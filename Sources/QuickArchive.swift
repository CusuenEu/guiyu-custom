import SwiftUI

struct QuickArchiveRequest: Identifiable {
    let id = UUID(); let rows: [BrowserRow]; let targets: [NamingTarget]
    init(rows: [BrowserRow]) { self.rows = rows.filter { !$0.header }; targets = self.rows.map { NamingTarget(path:$0.id,folder:$0.folder,projectPath:"") } }
}
struct ProjectArchiveChoice: Identifiable {
    var id: String { project.path }; let project: Project; let score: Int; let evidence: String
}
func archiveProjectAccepts(_ project: Project, request: QuickArchiveRequest) -> Bool {
    let destination = canonicalPath(project.path)
    return project.shallow != true && request.targets.allSatisfy { target in
        let source = canonicalPath(target.path)
        return destination != source && !destination.hasPrefix(source+"/") && URL(fileURLWithPath:source).deletingLastPathComponent().path != destination
    }
}
func archiveNormal(_ text: String) -> String {
    text.lowercased().replacingOccurrences(of:"[^\\p{L}\\p{N}]",with:"",options:.regularExpression)
}
func archiveProjectStem(_ name: String) -> String {
    var text = name.replacingOccurrences(of:"^(?:1[0-2]|[1-9])(?=月|\\s|[^0-9]|$)月?\\s*",with:"",options:.regularExpression)
    for word in ["股份有限公司","有限责任公司","有限公司","投标响应文件","招标文件","投标文件","采购文件","解决方案","服务项目","建设项目","项目","方案"] { text = text.replacingOccurrences(of:word,with:"") }
    return archiveNormal(text)
}
func projectArchiveChoices(input: String, projects: [Project], references: [FileItem]) -> [ProjectArchiveChoice] {
    let normalized = archiveNormal(input)
    let generic: Set<String> = ["建设","采购","项目","文件","公司","服务","技术","方案","响应","中国","贵州","要求","系统","信息","有限","集团","20","2026","xx"]
    return projects.filter { $0.shallow != true }.compactMap { project in
        var points = 0; var evidence: [String] = []
        let own = archiveProjectStem(project.name)
        if own.count >= 2, !generic.contains(own), normalized.contains(own) { points += min(65,own.count*5); evidence.append("文件内容包含项目名称中的“"+own+"”") }
        let refs = references.filter { $0.project == project.path }
        let names = refs.flatMap(projectNames)
        for name in Set(names) where archiveNormal(name).count >= 6 && normalized.contains(archiveNormal(name)) { points += 70; evidence.append("项目名称匹配："+name) }
        let idPattern = "(?:项目编号|合同编号|招标编号|采购编号)[：:\\s]*([A-Za-z0-9][A-Za-z0-9_./—-]{3,})"
        let corpus = refs.map(\.text).joined(separator:"\n")
        if let regex = try? NSRegularExpression(pattern:idPattern) {
            let value = corpus as NSString
            for match in regex.matches(in:corpus,range:NSRange(location:0,length:value.length)) {
                let code = value.substring(with:match.range(at:1))
                let pattern = "(?<![A-Za-z0-9_./—-])"+NSRegularExpression.escapedPattern(for:code)+"(?![A-Za-z0-9_./—-])"
                if input.range(of:pattern,options:[.regularExpression,.caseInsensitive]) != nil { points += 120; evidence.append("项目编号匹配："+code) }
            }
        }
        for keyword in project.keywords.components(separatedBy:CharacterSet(charactersIn:",，;；\n")) {
            let key = keyword.trimmingCharacters(in:.whitespacesAndNewlines)
            if key.count >= 2, !generic.contains(archiveNormal(key)), normalized.contains(archiveNormal(key)) { points += 40; evidence.append("关键词匹配："+key) }
        }
        if points == 0, own.count >= 6 {
            let chars = Array(own)
            let pairs = Set((0..<chars.count-1).map { String(chars[$0...$0+1]) }).subtracting(generic)
            let hits = pairs.filter { normalized.contains($0) }
            if hits.count >= 3, Double(hits.count)/Double(max(pairs.count,1)) >= 0.35 { points = min(35,hits.count*3); evidence.append("部分名称相似，请核对："+hits.sorted().prefix(6).joined(separator:"、")) }
        }
        guard points > 0 else { return nil }
        return ProjectArchiveChoice(project:project,score:points,evidence:Array(Set(evidence)).sorted().prefix(3).joined(separator:"；"))
    }.sorted { $0.score == $1.score ? $0.project.name.localizedStandardCompare($1.project.name) == .orderedAscending : $0.score > $1.score }
}
@MainActor extension Store {
    func suggestArchiveProjects(_ request: QuickArchiveRequest, token: IndexCancellation, update: @escaping ([ProjectArchiveChoice],Bool,String) -> Void) {
        let root = settings.root; let saved = settings.projects; let known = files
        DispatchQueue.global(qos:.utility).async {
            do {
                let discovered = try discoverProjects(root:root,saved:saved)
                let projects = discovered.filter { archiveProjectAccepts($0,request:request) }
                var inputs: [FileItem] = []
                for row in request.rows {
                    guard !token.isCancelled else { return }
                    let candidates = row.folder ? representativeFiles(metadataFiles(row.id,project:row.id,recursive:true,cache:[:]),limit:2) : [browserEntry(row.id)?.file].compactMap { $0 }
                    for var file in candidates { guard !token.isCancelled else { return }; file.text = autoreleasepool { extractForNaming(file,token:token) }; inputs.append(file) }
                }
                let input = request.rows.map(\.title).joined(separator:"\n")+"\n"+inputs.map(\.text).joined(separator:"\n")
                var references: [FileItem] = []
                func publish(_ done: Bool, _ message: String) {
                    let choices = projectArchiveChoices(input:input,projects:projects,references:references)
                    DispatchQueue.main.async { guard !token.isCancelled, self.settings.root == root else { return }; update(choices,done,message) }
                }
                publish(false,"已读取待归档文档，正在比对项目…")
                // Titles provide immediate recommendations; short names need sampled document evidence.
                for (index,project) in projects.enumerated() {
                    guard !token.isCancelled else { return }
                    let hasSpecificName = archiveProjectStem(project.name).count >= 8
                    if !hasSpecificName {
                        let indexed = known.filter { $0.project == project.path }
                        let metadata = indexed.isEmpty ? metadataFiles(project.path,project:project.path,recursive:true,cache:[:]) : indexed
                        for var file in representativeFiles(metadata,limit:2) {
                            guard !token.isCancelled else { return }
                            file.text = autoreleasepool { extractForNaming(file,token:token) }; references.append(file)
                        }
                    }
                    if index % 8 == 0 { publish(false,"正在比对项目（\(index+1)/\(projects.count)），可随时手动选择") }
                }
                DispatchQueue.main.async { guard !token.isCancelled, self.settings.root == root else { return }; self.settings.projects = discovered; self.save() }
                publish(true,"推荐仅供选择，确认后才移动文件")
            } catch { DispatchQueue.main.async { guard !token.isCancelled else { return }; update([],true,"项目读取未完成："+error.localizedDescription+"；仍可手动选择已有项目") } }
        }
    }
    func confirmQuickArchive(_ request: QuickArchiveRequest, to project: Project) -> (completed: Set<String>, failure: String?) {
        var completed = Set<String>(); error = ""
        do {
            guard !busy, settings.projects.contains(where:{$0.path == project.path && $0.shallow != true}), !settings.root.isEmpty else { throw namingError("项目已变化或仍在读取，请刷新后重试。") }
            let destinationRoot = canonicalPath(project.path), workspaceRoot = canonicalPath(settings.root)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath:destinationRoot,isDirectory:&isDirectory), isDirectory.boolValue, destinationRoot.hasPrefix(workspaceRoot+"/") else { throw namingError("目标项目文件夹不存在或不在项目总目录中。") }
            var reserved = Set<String>(); var plans: [(NamingTarget,URL)] = []; var sources = Set<String>()
            for target in request.targets {
                guard sources.insert(target.path).inserted, target.identity != nil, target.identity == fileIdentity(target.path), (try? URL(fileURLWithPath:target.path).resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) == target.modified else { throw namingError("部分源文件已更新或被替换，请重新选择；本次尚未移动。") }
                let source = canonicalPath(target.path)
                guard destinationRoot != source, !destinationRoot.hasPrefix(source+"/"), URL(fileURLWithPath:source).deletingLastPathComponent().path != destinationRoot else { throw namingError("文件已在目标项目中，或目标位于源文件夹内部，请选择其他项目。") }
                guard !request.targets.contains(where:{$0.path != target.path && target.path.hasPrefix($0.path+"/")}) else { throw namingError("不能同时归档文件夹及其内部文件，请只选择外层文件夹。") }
                let original = URL(fileURLWithPath:target.path); let ext = target.folder ? "" : original.pathExtension
                let stem = target.folder ? original.lastPathComponent : original.deletingPathExtension().lastPathComponent
                var number = 1; var name = original.lastPathComponent
                while fm.fileExists(atPath:URL(fileURLWithPath:destinationRoot).appendingPathComponent(name).path) || reserved.contains(name.precomposedStringWithCanonicalMapping.lowercased()) {
                    number += 1; name = stem+" (\(number))"+(ext.isEmpty ? "" : "."+ext)
                }
                reserved.insert(name.precomposedStringWithCanonicalMapping.lowercased()); plans.append((target,URL(fileURLWithPath:destinationRoot).appendingPathComponent(name)))
            }
            for (target,destination) in plans {
                guard target.identity == fileIdentity(target.path), !fm.fileExists(atPath:destination.path) else { throw namingError("执行时文件或目标发生变化，已停止剩余操作。") }
                try fm.moveItem(atPath:target.path,toPath:destination.path)
                remapCategoryAssignments(source:target.path,destination:destination.path,folder:target.folder)
                for i in settings.moves.indices { settings.moves[i].destination = remapPath(settings.moves[i].destination,source:target.path,destination:destination.path,folder:target.folder) }
                settings.moves.insert(MoveRecord(source:target.path,destination:destination.path,identity:fileIdentity(destination.path),automatic:false,evidence:"快速归类 · 用户确认项目",folder:target.folder),at:0)
                incoming.removeAll { $0.path == target.path }; completed.insert(target.path); save()
                if !error.isEmpty { throw namingError("文件已移动，归档记录保存失败："+error) }
            }
            message = "已归档 \(completed.count) 项至 "+project.name; refresh(); return (completed,nil)
        } catch { if !completed.isEmpty { refresh() }; return (completed,"已完成 \(completed.count) 项；"+error.localizedDescription) }
    }
}

struct QuickArchiveDialog: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store: Store; let request: QuickArchiveRequest
    @State private var query = ""; @State private var selected: String?; @State private var choices: [ProjectArchiveChoice] = []; @State private var loading = true; @State private var status = ""; @State private var failure = ""
    @State private var token = IndexCancellation()
    var projects: [Project] { store.settings.projects.filter { archiveProjectAccepts($0,request:request) && (query.isEmpty || (($0.group ?? "")+" "+$0.name+" "+$0.keywords).localizedCaseInsensitiveContains(query)) }.sorted { ($0.group ?? "") == ($1.group ?? "") ? $0.name.localizedStandardCompare($1.name) == .orderedDescending : ($0.group ?? "") > ($1.group ?? "") } }
    var destination: Project? { store.settings.projects.first { $0.path == selected && $0.shallow != true } }
    var onClose: (() -> Void)? = nil
    private func close() { if let onClose { onClose() } else { dismiss() } }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("快速归类").font(.title2.bold()); Spacer(); Text("\(request.rows.count) 项待归档").foregroundStyle(.secondary) }
            Text(request.rows.map(\.title).joined(separator:"、")).font(.callout).lineLimit(2).help(request.rows.map(\.id).joined(separator:"\n"))
            HStack { Image(systemName:"magnifyingglass").foregroundStyle(.secondary); TextField("输入项目名、单位或关键词，手动查找目标项目",text:$query).textFieldStyle(.plain) }.padding(10).background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:7))
            HStack { if loading { ProgressView().controlSize(.small) }; Text(status.isEmpty ? "正在读取文档并比对项目，也可直接手动选择" : status).font(.caption).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment:.leading,spacing:0) {
                    if query.isEmpty && !choices.isEmpty {
                        Text("推荐项目").font(.headline).padding(.vertical,10)
                        ForEach(Array(choices.prefix(5))) { choice in projectButton(choice.project,evidence:choice.evidence) }
                        Divider().padding(.vertical,8)
                    }
                    Text(query.isEmpty ? "全部项目 · 手动选择" : "搜索结果（\(projects.count)）").font(.headline).padding(.vertical,10)
                    ForEach(projects) { project in projectButton(project,evidence:nil) }
                    if projects.isEmpty { Text("没有匹配项目，请更换关键词或先关联项目总目录。").foregroundStyle(.secondary).padding(.vertical,16) }
                }
            }.frame(height:290)
            if let project = destination { Text("归档至："+project.path).font(.caption).textSelection(.enabled) }
            Text("确认后将文件移动到项目文件夹，同名自动编号、不覆盖；可在最近归档中撤销。").font(.caption).foregroundStyle(.secondary)
            if !failure.isEmpty { Text(failure).foregroundStyle(.red).font(.callout) }
            HStack { Button("取消") { token.cancel(); close() }.keyboardShortcut(.cancelAction); Spacer(); Button("确认归档（移动）") { confirm() }.buttonStyle(.borderedProminent).disabled(destination == nil || store.busy) }
        }.padding(24).frame(width:720)
        .onAppear { store.suggestArchiveProjects(request,token:token) { values,done,message in choices = values; loading = !done; status = message } }.onDisappear { token.cancel() }
    }
    func projectButton(_ project: Project, evidence: String?) -> some View {
        Button { selected = project.path } label: {
            HStack(alignment:.top,spacing:10) {
                Image(systemName:selected == project.path ? "largecircle.fill.circle" : "circle").foregroundStyle(accent).padding(.top,2)
                VStack(alignment:.leading,spacing:4) { Text((project.group.map{$0+" / "} ?? "")+project.name).foregroundStyle(.primary).multilineTextAlignment(.leading); if let evidence { Text(evidence).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading) } }; Spacer()
            }.padding(10).background(selected == project.path ? accent.opacity(0.08) : .clear,in:RoundedRectangle(cornerRadius:6))
        }.buttonStyle(.plain)
    }
    func confirm() {
        guard let project = destination else { return }; token.cancel()
        let result = store.confirmQuickArchive(request,to:project)
        if result.failure == nil { close() } else { failure = (result.failure ?? "归档未完成") + (result.completed.isEmpty ? "" : "。请关闭窗口，重新选择未完成的条目。"); loading = false }
    }
}

@MainActor func quickArchiveTest(root: URL) throws {
    let workspace = root.appendingPathComponent("QuickWorkspace"), projectDir = workspace.appendingPathComponent("2026/10 抖音")
    let inbox = root.appendingPathComponent("QuickInbox")
    try fm.createDirectory(at:projectDir,withIntermediateDirectories:true); try fm.createDirectory(at:inbox,withIntermediateDirectories:true)
    let first = inbox.appendingPathComponent("RFP.txt"); try "抖音集团机房租赁招采项目\n项目编号：DY-2026-001".write(to:first,atomically:true,encoding:.utf8)
    try "原有文件".write(to:projectDir.appendingPathComponent(first.lastPathComponent),atomically:true,encoding:.utf8)
    let store = Store(stateURL:root.appendingPathComponent("QuickState/settings.json"),loadOnLaunch:false)
    let project = Project(path:projectDir.path,name:"10 抖音",group:"2026")
    store.settings.root = workspace.path; store.settings.projects = [project]
    try verify(store.availableArchiveSources.prefix(2).map(\.id) == ["downloads","recent"],"Default archive sources are real Downloads and Finder Recents")
    let custom = ArchiveSource(id:"custom",name:"资料",kind:"folder",path:inbox.path)
    store.settings.archiveSources = store.availableArchiveSources+[custom]; store.save()
    let saved = try JSONDecoder().decode(Settings.self,from:Data(contentsOf:store.stateURL)); try verify(saved.archiveSources?.last?.path == inbox.path)
    let choices = projectArchiveChoices(input:"抖音集团机房租赁招采项目",projects:[project,Project(path:"/other",name:"9 水利投资")],references:[])
    try verify(choices.first?.project.path == project.path,"Short project name can yield a reviewable suggestion")
    let ambiguous = Project(path:"/other",name:"8 抖音")
    try verify(projectArchiveChoices(input:"抖音集团资料",projects:[project,ambiguous],references:[]).count == 2,"Ambiguous suggestions remain choices, never automatic moves")
    let coded = Project(path:projectDir.path,name:"A")
    let ref = FileItem(path:projectDir.appendingPathComponent("招标文件.txt").path,project:projectDir.path,text:"项目编号：DY-2026-001",size:1,date:Date())
    try verify(projectArchiveChoices(input:"项目编号：DY-2026-001",projects:[coded],references:[ref]).first?.score == 120)
    try verify(projectArchiveChoices(input:"项目编号：DY-2026-0012",projects:[coded],references:[ref]).isEmpty,"Identifier matching must honor boundaries")
    let row = browserEntry(first.path)!, request = QuickArchiveRequest(rows:[row])
    try verify(!archiveProjectAccepts(Project(path:inbox.path,name:"来源目录"),request:request),"Already-in-target source is excluded from recommendations and manual choices")
    let alias = root.appendingPathComponent("QuickInboxAlias"); try fm.createSymbolicLink(at:alias,withDestinationURL:inbox)
    try verify(!archiveProjectAccepts(Project(path:alias.path,name:"来源别名"),request:request),"Symlink aliases must not bypass target filtering")
    try verify(fm.fileExists(atPath:first.path),"Previewing suggestions must not move anything")
    let result = store.confirmQuickArchive(request,to:project)
    try verify(result.failure == nil && result.completed.count == 1)
    let move = store.settings.moves[0]; try verify(move.destination.hasSuffix("RFP (2).txt") && move.automatic == false)
    let retained = try String(contentsOf:projectDir.appendingPathComponent("RFP.txt"),encoding:.utf8); try verify(retained == "原有文件")
    store.scanCancellation?.cancel(); store.busy = false; store.undo(move,refreshAfter:false)
    try verify(fm.fileExists(atPath:first.path),"Quick archive is undoable")
    let changed = QuickArchiveRequest(rows:[browserEntry(first.path)!]); try "新内容，保持原位".write(to:first,atomically:true,encoding:.utf8)
    let rejected = store.confirmQuickArchive(changed,to:project); try verify(rejected.completed.isEmpty && rejected.failure != nil && fm.fileExists(atPath:first.path),"Modified source is rejected before moving")
    let nested = inbox.appendingPathComponent("资料文件夹"); try fm.createDirectory(at:nested,withIntermediateDirectories:true)
    let child = nested.appendingPathComponent("内部.txt"); try "child".write(to:child,atomically:true,encoding:.utf8)
    let folder = browserEntry(nested.path)!; try verify(store.assignCategory(browserEntry(child.path)!,to:"方案"))
    let folderResult = store.confirmQuickArchive(QuickArchiveRequest(rows:[folder]),to:project)
    try verify(folderResult.failure == nil && fm.fileExists(atPath:projectDir.appendingPathComponent("资料文件夹/内部.txt").path),"Folder archiving preserves internal hierarchy")
    let folderMove = store.settings.moves[0]; store.scanCancellation?.cancel(); store.busy = false; store.undo(folderMove,refreshAfter:false)
    try verify(fm.fileExists(atPath:child.path) && store.workspaceAssignments[child.path]?.categoryID == "方案","Folder undo preserves manual classifications")
    store.removeArchiveSource("custom"); try verify(fm.fileExists(atPath:inbox.path),"Removing a linked source does not delete its folder")
    print("PASS: Downloads/Recents defaults, linked-source persistence, short-name and identifier project suggestions, confirmation-only move, no overwrite, stale-source rejection, folder hierarchy and undo")
}
