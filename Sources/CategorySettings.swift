import SwiftUI

struct DirectRenameDialog: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store: Store; let target: NamingTarget
    @State private var name = ""
    var finalName: String { target.folder ? name : proposedName(base:name,month:1,folder:false,original:target.path) }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("更改名称").font(.title2.bold())
            Text(URL(fileURLWithPath:target.path).lastPathComponent).font(.callout).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
            TextField("新名称",text:$name).textFieldStyle(.roundedBorder).onSubmit { confirm() }
            Text("更改后："+finalName).font(.callout).textSelection(.enabled)
            Text(target.folder ? "确认后同步更改 Finder 中的文件夹名称，内部层级保持不变。" : "保留原扩展名。确认后同步更改 Finder 中的文件名，同名不覆盖。").font(.caption).foregroundStyle(.secondary)
            HStack { Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("确认更改") { confirm() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
        }.padding(26).frame(width:530)
        .onAppear { let url = URL(fileURLWithPath:target.path); name = target.folder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent }
        .alert("更改名称未完成",isPresented:Binding(get:{!store.error.isEmpty},set:{if !$0 { store.error = "" }})) { Button("知道了") { store.error = "" } } message: { Text(store.error) }
    }
    func confirm() { if store.confirmRename(target,newName:finalName,requireMonth:false) { dismiss() } }
}

struct CategorySettingsView: View {
    @ObservedObject var store: Store
    @State private var query = ""; @State private var name = ""; @State private var editing: String?
    @State private var deleting: WorkspaceCategory?
    var filtered: [WorkspaceCategory] { store.workspaceCategories.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(WorkspaceTheme.secondary)
                TextField("搜索分类",text:$query).textFieldStyle(.plain)
                Spacer(minLength:0)
                Text("\(store.workspaceCategories.count) 个分类").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary)
            }.padding(12).background(WorkspaceTheme.rail.opacity(0.65),in:RoundedRectangle(cornerRadius:10))
            ScrollView {
                VStack(spacing:0) {
                    ForEach(filtered) { category in
                        HStack(spacing:12) {
                            Image(systemName:"tag").foregroundStyle(accent).frame(width:20)
                            Text(category.name).font(.system(size:14,weight:.medium)).lineLimit(1); Spacer()
                            Button("更名") { editing = category.id; name = category.name }.buttonStyle(SoftWorkspaceButton())
                            Button { deleting = category } label: { Image(systemName:"trash").frame(width:28,height:30) }.buttonStyle(.plain).foregroundStyle(Color(red:0.65,green:0.23,blue:0.20)).help("删除「"+category.name+"」").accessibilityLabel("删除「"+category.name+"」").disabled(store.workspaceCategories.count <= 1)
                        }.padding(.horizontal,4).frame(minHeight:52)
                        Divider()
                    }
                    if filtered.isEmpty { Text("没有匹配的分类").foregroundStyle(WorkspaceTheme.secondary).padding(24) }
                }
            }.frame(height:236)
            VStack(alignment:.leading,spacing:10) {
                Text(editing == nil ? "添加一个新分类" : "更改分类名称").font(.system(size:13,weight:.semibold))
                HStack(spacing:10) {
                    TextField("分类名称",text:$name).textFieldStyle(.plain).padding(10).background(Color.white,in:RoundedRectangle(cornerRadius:9)).overlay(RoundedRectangle(cornerRadius:9).stroke(WorkspaceTheme.line,lineWidth:1))
                    if editing != nil { Button("取消") { editing = nil; name = "" }.buttonStyle(SoftWorkspaceButton()) }
                    Button(editing == nil ? "添加" : "保存") {
                        if store.saveCategory(id:editing,name:name) { editing = nil; name = "" }
                    }.buttonStyle(SoftWorkspaceButton(peach:true)).disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                }
            }
            Text("右键文件或文件夹即可更改分类。自建分类用于手动整理；默认分类更名后仍会自动识别。").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary).fixedSize(horizontal:false,vertical:true)
        }

        .alert("删除分类？",isPresented:Binding(get:{deleting != nil},set:{if !$0 { deleting = nil }})) {
            Button("取消",role:.cancel) { deleting = nil }
            Button("删除分类",role:.destructive) {
                if let category = deleting { _ = store.deleteCategory(category.id); if editing == category.id { editing = nil; name = "" } }; deleting = nil
            }
        } message: {
            let fallback = store.workspaceCategories.first(where:{$0.id == "其他" && $0.id != deleting?.id}) ?? store.workspaceCategories.first(where:{$0.id != deleting?.id})
            Text("删除「\(deleting?.name ?? "")」后，其中的条目显示在「\(fallback?.name ?? "其他")」。源文件和文件夹保留。")
        }
        .alert("分类未保存",isPresented:Binding(get:{!store.error.isEmpty},set:{if !$0 { store.error = "" }})) { Button("知道了") { store.error = "" } } message: { Text(store.error) }
    }
}
