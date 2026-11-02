import SwiftUI
import AppKit

struct ArchiveSource: Identifiable, Codable, Equatable {
    var id: String; var name: String; var kind: String; var path: String
    static var defaults: [ArchiveSource] {
        [ArchiveSource(id:"downloads",name:"下载",kind:"folder",path:fm.urls(for:.downloadsDirectory,in:.userDomainMask).first!.path),ArchiveSource(id:"recent",name:"最近使用",kind:"recent",path:"")]
    }
}
func browserEntry(_ path: String, used: Date? = nil) -> BrowserRow? {
    let url = URL(fileURLWithPath:path)
    guard !url.lastPathComponent.hasPrefix("."), !url.lastPathComponent.hasPrefix("~$"), let v = try? url.resourceValues(forKeys:[.isRegularFileKey,.isDirectoryKey,.isSymbolicLinkKey,.isAliasFileKey,.contentModificationDateKey,.fileSizeKey]), v.isSymbolicLink != true, v.isRegularFile == true || v.isDirectory == true else { return nil }
    let folder = v.isDirectory == true
    return BrowserRow(id:path,title:url.lastPathComponent,date:used ?? v.contentModificationDate,file:folder ? nil : FileItem(path:path,project:"",text:"",size:Int64(v.fileSize ?? 0),date:v.contentModificationDate ?? .distantPast),folder:folder,isAlias:v.isAliasFile == true)
}
@MainActor final class RecentFilesQuery {
    private let query = NSMetadataQuery(); private var observer: NSObjectProtocol?; private var timeout: DispatchWorkItem?; private var finished = false
    func start(completion: @escaping ([BrowserRow],String?) -> Void) {
        let url = URL(fileURLWithPath:"/System/Library/CoreServices/Finder.app/Contents/Resources/MyLibraries/myDocuments.cannedSearch/Resources/search.savedSearch")
        let plist = (try? Data(contentsOf:url)).flatMap { try? PropertyListSerialization.propertyList(from:$0,format:nil) } as? [String:Any]
        let raw = plist?["RawQuery"] as? String ?? "(kMDItemLastUsedDate = '*') && (kMDItemContentTypeTree = 'public.content')"
        query.predicate = NSPredicate(fromMetadataQueryString:raw)
        query.searchScopes = ["kMDQueryScopeMyFiles"]
        query.sortDescriptors = [NSSortDescriptor(key:"kMDItemLastUsedDate",ascending:false)]
        func finish(timedOut: Bool) {
            guard !self.finished else { return }; self.finished = true; self.query.disableUpdates()
            let rows = (0..<min(self.query.resultCount,500)).compactMap { index -> BrowserRow? in
                guard let item = self.query.result(at:index) as? NSMetadataItem, let path = item.value(forAttribute:NSMetadataItemPathKey) as? String else { return nil }
                return browserEntry(path,used:item.value(forAttribute:"kMDItemLastUsedDate") as? Date)
            }.filter { !$0.folder }
            self.stop()
            completion(rows,timedOut && rows.isEmpty ? "系统最近使用查询暂未返回结果，可刷新重试。" : nil)
        }
        observer = NotificationCenter.default.addObserver(forName:.NSMetadataQueryDidFinishGathering,object:query,queue:.main) { _ in finish(timedOut:false) }
        let work = DispatchWorkItem { finish(timedOut:true) }; timeout = work; DispatchQueue.main.asyncAfter(deadline:.now()+12,execute:work)
        if !query.start() { finish(timedOut:true) }
    }
    func stop() { finished = true; timeout?.cancel(); timeout = nil; query.stop(); if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil }
}
@MainActor extension Store {
    var availableArchiveSources: [ArchiveSource] {
        if let sources = settings.archiveSources { return sources }
        var sources = ArchiveSource.defaults
        if !settings.inbox.isEmpty, settings.inbox != sources[0].path, !settings.inbox.contains("/Guiyu/示例空间/") {
            sources.append(ArchiveSource(id:"legacy-inbox",name:URL(fileURLWithPath:settings.inbox).lastPathComponent,kind:"folder",path:settings.inbox))
        }
        return sources
    }
    func chooseArchiveSource(replacing id: String? = nil) -> String? {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false; panel.message = "选择在可归档目录中显示的文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let path = canonicalPath(url.path); var sources = availableArchiveSources
        if let duplicate = sources.first(where:{$0.kind == "folder" && canonicalPath($0.path) == path && $0.id != id}) { return duplicate.id }
        if let id, let i = sources.firstIndex(where:{$0.id == id && $0.kind == "folder"}) { sources[i].path = path; if id != "downloads" { sources[i].name = url.lastPathComponent } }
        else { sources.append(ArchiveSource(id:UUID().uuidString,name:url.lastPathComponent,kind:"folder",path:path)) }
        settings.archiveSources = sources; save(); return id ?? sources.last?.id
    }
    func restoreArchiveDefaults() {
        var sources = availableArchiveSources
        for source in ArchiveSource.defaults where !sources.contains(where:{$0.id == source.id}) { sources.append(source) }
        settings.archiveSources = sources; save()
    }
    func removeArchiveSource(_ id: String) { settings.archiveSources = availableArchiveSources.filter { $0.id != id }; save() }
}
struct ArchiveSourceSettingsView: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("可归档目录").font(.system(size:14,weight:.semibold)); Spacer()
                Button { _ = store.chooseArchiveSource() } label: { Label("关联文件夹",systemImage:"plus") }.buttonStyle(SoftWorkspaceButton())
            }
            VStack(spacing:0) {
                ForEach(store.availableArchiveSources) { source in
                    HStack(spacing:12) {
                        Image(systemName:source.kind == "recent" ? "clock" : "tray.and.arrow.down").font(.system(size:20)).foregroundStyle(accent).frame(width:28)
                        VStack(alignment:.leading,spacing:5) {
                            Text(source.name).font(.system(size:14,weight:.medium))
                            Text(source.kind == "recent" ? "Finder 最近使用 · 系统索引" : source.path).font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary).lineLimit(1).truncationMode(.middle).help(source.path)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                        if source.kind == "folder" { Button("更换…") { _ = store.chooseArchiveSource(replacing:source.id) }.buttonStyle(SoftWorkspaceButton()) }
                        Button { store.removeArchiveSource(source.id) } label: { Image(systemName:"minus.circle").font(.system(size:16)).frame(width:24,height:30) }.buttonStyle(.plain).foregroundStyle(WorkspaceTheme.secondary).help("移除「"+source.name+"」入口").accessibilityLabel("移除「"+source.name+"」入口")
                    }.padding(.vertical,13)
                    Divider()
                }
                if store.availableArchiveSources.isEmpty { Text("还没有关联目录").font(.system(size:13)).foregroundStyle(WorkspaceTheme.secondary).frame(maxWidth:.infinity).padding(.vertical,24) }
            }
            if !ArchiveSource.defaults.allSatisfy({ base in store.availableArchiveSources.contains(where:{$0.id == base.id}) }) { Button("恢复下载和最近使用入口") { store.restoreArchiveDefaults() }.buttonStyle(SoftWorkspaceButton()) }
            Text("点击入口时才读取列表；归档前由你确认。移除入口不会删除文件。").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }

}
struct ArchiveSourcePane: View {
    @ObservedObject var store: Store; let source: ArchiveSource
    @State private var rows: [BrowserRow] = []; @State private var selected: String?; @State private var selections = Set<String>()
    @State private var folder = ""; @State private var loading = false; @State private var error = ""; @State private var generation = UUID(); @State private var recent: RecentFilesQuery?
    @State private var quick: QuickArchiveRequest?; @State private var rename: NamingTarget?; @State private var manual: NamingTarget?; @State private var batch: BatchNamingRequest?
    @State private var archiveAfterNaming:QuickArchiveRequest?
    var filtered: [BrowserRow] { rows }
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            if source.kind == "folder", !folder.isEmpty, folder != source.path {
                DirectoryBreadcrumbBar(root:source.path,current:folder,rootTitle:source.name) { path in
                    guard let destination = DirectoryBreadcrumb.destination(path,root:source.path,current:folder) else { return }
                    folder = destination; load()
                }.padding(.horizontal,20).padding(.bottom,8)
            }
            if loading { Spacer(); ProgressView("正在读取文件列表…").frame(maxWidth:.infinity); Spacer() }
            else if !error.isEmpty { Spacer(); Text(error).foregroundStyle(.secondary).padding(); Button("重试") { load() }.padding(.horizontal); Spacer() }
            else if rows.isEmpty { Spacer(); Text("暂时没有可显示的文件").foregroundStyle(.secondary).frame(maxWidth:.infinity); Spacer() }
            else {
                BrowserTable(rows:filtered,selection:$selected,multipleSelection:$selections,batchRename:{ values,recommended in batch = BatchNamingRequest(rows:values,projectPath:"",recommended:recommended) },dataset:source.id+"|"+folder,activate:{ row in if row.folder { folder = row.id; load() } else { NSWorkspace.shared.open(URL(fileURLWithPath:row.id)) } },rename:{ row in rename = NamingTarget(path:row.id,folder:row.folder,projectPath:"") },directRename:{ row in manual = NamingTarget(path:row.id,folder:row.folder,projectPath:"") },quickArchive:{ quick = QuickArchiveRequest(rows:$0) },trash:{ _ = store.moveToTrash($0,undoManager:NSApplication.shared.keyWindow?.undoManager) })
            }
        }
        .onAppear { folder = source.path; load() }.onDisappear { generation = UUID(); recent?.stop() }
        .onChange(of:source.path) { _ in folder = source.path; load() }
        .onChange(of:store.fileOperationRevision) { _ in load() }
        .onChange(of:store.globalRefreshRevision) { _ in load() }
        .onChange(of:store.settings.moves.map { $0.id.uuidString+String($0.undone) }) { _ in load() }
        .onChange(of:store.settings.renames?.count) { _ in load() }
        .alert("操作未完成",isPresented:Binding(get:{!store.error.isEmpty && quick == nil && rename == nil && manual == nil && batch == nil},set:{if !$0 { store.error = "" }})) { Button("知道了") { store.error = "" } } message: { Text(store.error) }
        .sheet(item:$quick) { QuickArchiveDialog(store:store,request:$0) }
        .sheet(item:$rename,onDismiss:{
            if let request = archiveAfterNaming { archiveAfterNaming = nil;quick = request }
        }) { RenameDialog(store:store,target:$0,onArchive:{archiveAfterNaming = $0}) }
        .sheet(item:$manual) { DirectRenameDialog(store:store,target:$0) }
        .sheet(item:$batch) { BatchRenameDialog(store:store,request:$0) }
    }
    func load() {
        recent?.stop(); recent = nil; let ticket = UUID(); generation = ticket; selections = []; selected = nil; loading = true; error = ""
        if source.kind == "recent" {
            let query = RecentFilesQuery(); recent = query
            query.start { values,message in guard generation == ticket else { return }; rows = values; error = message ?? ""; loading = false }
        } else {
            let path = folder.isEmpty ? source.path : folder
            DispatchQueue.global(qos:.userInitiated).async {
                let result = Result { try directoryEntries(path:path,project:"") }
                DispatchQueue.main.async { guard generation == ticket else { return }; loading = false
                    switch result { case .success(let values): rows = values.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }; case .failure(let e): error = "无法读取关联文件夹："+e.localizedDescription; rows = [] }
                }
            }
        }
    }
}
