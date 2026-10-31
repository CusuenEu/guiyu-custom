import SwiftUI

struct BatchNamingRequest: Identifiable {
    let id = UUID(); let rows: [BrowserRow]; let projectPath: String; let recommended: Bool
}
struct BatchNameEdit: Identifiable {
    var id: String { target.path }; let target: NamingTarget
    var name: String; var included = true; var evidence = ""; var candidates: [Suggestion] = []; var userEdited = false
}
@MainActor extension Store {
    func validateBatchRenames(_ edits: [BatchNameEdit], requireMonth: Bool) throws {
        guard !edits.isEmpty else { throw namingError("请至少选择一项。") }
        var destinations = Set<String>(); var sources = Set<String>()
        for edit in edits {
            guard sources.insert(edit.target.path).inserted else { throw namingError("同一条目不能重复命名。") }
            let path = try validateRename(edit.target,newName:edit.name,requireMonth:requireMonth)
            guard destinations.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw namingError("多个条目将使用相同名称，请先修改，尚未更改任何文件。") }
        }
    }
    func confirmBatchRenames(_ edits: [BatchNameEdit], requireMonth: Bool) -> (completed: Set<String>, failed: String?) {
        do { try validateBatchRenames(edits,requireMonth:requireMonth) }
        catch { self.error = error.localizedDescription; return ([],error.localizedDescription) }
        var completed = Set<String>()
        for edit in edits {
            if confirmRename(edit.target,newName:edit.name,requireMonth:requireMonth) { completed.insert(edit.id) }
            else { return (completed,"已完成 \(completed.count) 项，剩余项目未更改："+error) }
        }
        return (completed,nil)
    }
}
struct BatchRenameDialog: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store: Store; let request: BatchNamingRequest
    @State private var edits: [BatchNameEdit] = []; @State private var loading = false; @State private var progress = 0
    @State private var prefix = ""; @State private var find = ""; @State private var replacement = ""; @State private var notice = ""
    @State private var token = IndexCancellation()
    var onClose: (() -> Void)? = nil
    private func close() { if let onClose { onClose() } else { dismiss() } }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text(request.recommended ? "批量推荐命名" : "批量更改名称").font(.title2.bold()); Spacer(); Text("\(edits.filter(\.included).count) / \(edits.count) 项").foregroundStyle(.secondary) }
            Text("逐项核对并修改新名称；取消勾选可跳过。确认后同步更改 Finder 中的名称，同名不覆盖。").font(.caption).foregroundStyle(.secondary)
            if loading { HStack { ProgressView().controlSize(.small); Text("正在读取第 \(min(progress+1,edits.count)) / \(edits.count) 项，优先前两页…").font(.caption) } }
            if !request.recommended {
                HStack {
                    TextField("查找文字",text:$find).textFieldStyle(.roundedBorder)
                    TextField("替换为",text:$replacement).textFieldStyle(.roundedBorder)
                    TextField("添加前缀",text:$prefix).textFieldStyle(.roundedBorder)
                    Button("应用到勾选项") { applyRule() }
                }
            }
            ScrollView {
                LazyVStack(alignment:.leading,spacing:14) {
                    ForEach($edits) { $edit in
                        HStack(alignment:.top,spacing:12) {
                            Toggle("",isOn:$edit.included).labelsHidden().padding(.top,4)
                            VStack(alignment:.leading,spacing:6) {
                                Text(URL(fileURLWithPath:edit.id).lastPathComponent).font(.callout).lineLimit(2)
                                TextField("新名称（文件须含扩展名）",text:Binding(get:{edit.name},set:{edit.name=$0;edit.userEdited=true})).textFieldStyle(.roundedBorder)
                                if !edit.candidates.isEmpty {
                                    Menu("其他候选") { ForEach(edit.candidates) { candidate in Button(candidate.name) {
                                        edit.name = proposedName(base:candidate.name,month:suggestedMonth(edit.id),folder:edit.target.folder,original:edit.id); edit.evidence = candidate.evidence; edit.userEdited = true
                                    } } }.fixedSize()
                                }
                                if !edit.evidence.isEmpty { Text(edit.evidence).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                            }
                        }; Divider()
                    }
                }.padding(2)
            }.frame(minHeight:220,maxHeight:390)
            if !notice.isEmpty { Text(notice).font(.callout).foregroundStyle(.red) }
            HStack {
                Button("取消") { token.cancel(); close() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("确认批量更改") { confirm() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(loading || !edits.contains(where:{$0.included}))
            }
        }.padding(24).frame(width:760)
        .onAppear {
            edits = request.rows.map { row in BatchNameEdit(target:NamingTarget(path:row.id,folder:row.folder,projectPath:request.projectPath),name:row.title) }
            if request.recommended { loading = true; loadNext(0) }
        }.onDisappear { token.cancel() }
    }
    func loadNext(_ index: Int) {
        guard !token.isCancelled else { return }
        guard edits.indices.contains(index) else { loading = false; return }
        progress = index; let target = edits[index].target
        store.loadSuggestions(target,token:token) { values in
            guard !token.isCancelled, edits.indices.contains(index), edits[index].id == target.path else { return }
            edits[index].candidates = values
            if !edits[index].userEdited {
                if let first = values.first {
                    edits[index].name = proposedName(base:first.name,month:suggestedMonth(target.path),folder:target.folder,original:target.path)
                    edits[index].evidence = first.evidence
                } else { edits[index].included = false; edits[index].evidence = "未找到明确名称，已跳过；可填写后勾选。" }
            }
            loadNext(index+1)
        }
    }
    func applyRule() {
        for i in edits.indices where edits[i].included {
            let url = URL(fileURLWithPath:edits[i].id)
            let stem = edits[i].target.folder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
            let base = prefix + (find.isEmpty ? stem : stem.replacingOccurrences(of:find,with:replacement))
            edits[i].name = edits[i].target.folder ? base : proposedName(base:base,month:1,folder:false,original:edits[i].id)
            edits[i].userEdited = true
        }
    }
    func confirm() {
        let result = store.confirmBatchRenames(edits.filter(\.included),requireMonth:request.recommended)
        if result.failed == nil { close() }
        else {
            notice = result.failed ?? "更改未完成"; store.error = ""
            edits.removeAll { result.completed.contains($0.id) }
        }
    }
}

@MainActor func batchOperationsTest(root: URL) throws {
    let dir = root.appendingPathComponent("BatchOperations"); try fm.createDirectory(at:dir,withIntermediateDirectories:true)
    let first = dir.appendingPathComponent("a.txt"), second = dir.appendingPathComponent("b.txt")
    try "first".write(to:first,atomically:true,encoding:.utf8); try "second".write(to:second,atomically:true,encoding:.utf8)
    let rows = try directoryEntries(path:dir.path,project:dir.path)
    let store = Store(stateURL:root.appendingPathComponent("BatchState/settings.json"),loadOnLaunch:false)
    let targets = rows.map { NamingTarget(path:$0.id,folder:false,projectPath:dir.path) }
    let conflict = targets.map { BatchNameEdit(target:$0,name:"同名.txt") }
    let rejected = store.confirmBatchRenames(conflict,requireMonth:false)
    try verify(rejected.completed.isEmpty && rejected.failed != nil && fm.fileExists(atPath:first.path) && fm.fileExists(atPath:second.path),"Batch collision preflight changes no files")
    store.error = ""
    try verify(store.assignCategories(rows,to:"方案"))
    try verify(rows.allSatisfy { store.workspaceAssignments[$0.id]?.categoryID == "方案" })
    try verify(!batchCategoryDestinations(rows,categories:store.workspaceCategories,assignments:store.workspaceAssignments).contains(where:{$0.id == "方案"}))
    let missing = BrowserRow(id:dir.appendingPathComponent("missing.txt").path,title:"missing.txt")
    try verify(!store.assignCategories(rows+[missing],to:"招标文件"))
    try verify(rows.allSatisfy { store.workspaceAssignments[$0.id]?.categoryID == "方案" },"Batch categories validate all items before committing")
    store.error = ""
    let pb = NSPasteboard.withUniqueName(); defer { pb.releaseGlobally() }
    func dragItems(scope: String) throws -> [NSPasteboardItem] { try rows.map { row in
        let item = NSPasteboardItem(); item.setData(try JSONEncoder().encode(CategoryDragItem(path:row.id,identity:fileIdentity(row.id)!,scope:scope)),forType:categoryDragType); return item
    } }
    pb.writeObjects(try dragItems(scope:dir.path))
    try verify(categoryDropRows(pb,scope:dir.path,rows:rows)?.count == 2,"Native multi-item drag payload is accepted")
    try verify(categoryDropRows(pb,scope:"/another-project",rows:rows) == nil,"Cross-directory or stale drag is rejected")
    try verify(categoryDropRows(pb,scope:dir.path,rows:[rows[0]]) == nil,"Missing drag entries reject the whole drop")
    let edited = targets.enumerated().map { BatchNameEdit(target:$0.element,name:"命名\($0.offset).txt") }
    let completed = store.confirmBatchRenames(edited,requireMonth:false)
    try verify(completed.completed.count == 2 && completed.failed == nil)
    try verify(edited.allSatisfy { fm.fileExists(atPath:dir.appendingPathComponent($0.name).path) && store.workspaceAssignments[dir.appendingPathComponent($0.name).path]?.categoryID == "方案" },"Batch rename preserves manual categories")
    var selected: String?; var multi = Set<String>()
    let parent = BrowserTable(rows:rows,selection:Binding(get:{selected},set:{selected=$0}),multipleSelection:Binding(get:{multi},set:{multi=$0}),activate:{_ in},rename:{_ in})
    let coordinator = parent.makeCoordinator(); coordinator.rows = rows
    let table = NSTableView(); table.allowsMultipleSelection = true; table.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier("name"))); table.dataSource = coordinator; table.reloadData()
    table.selectRowIndexes(IndexSet([0,1]),byExtendingSelection:false)
    coordinator.tableViewSelectionDidChange(Notification(name:NSTableView.selectionDidChangeNotification,object:table))
    try verify(multi == Set(rows.map(\.id)) && selected == nil,"Native multiselection reports whole set, disables single-file preview")
    print("PASS: native multiselect, multi-item local drag, scope guards, batch-category atomic validation, batch-name collision preflight and persisted category remapping")
}
