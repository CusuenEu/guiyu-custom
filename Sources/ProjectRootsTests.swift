import Foundation

@MainActor func projectRootsTest(root: URL) throws {
    let base = root.appendingPathComponent("multiple-roots")
    let a = base.appendingPathComponent("甲总目录"), b = base.appendingPathComponent("乙总目录")
    let pa = a.appendingPathComponent("2026/10月 甲园区项目"), pb = b.appendingPathComponent("2026/10月 乙园区项目")
    for folder in [pa,pb,a.appendingPathComponent("2025"),b.appendingPathComponent("2025")] { try fm.createDirectory(at:folder,withIntermediateDirectories:true) }
    for folder in [pa,pb] { try "同名文档，正文不应在浏览时读取".write(to:folder.appendingPathComponent("验收资料.txt"),atomically:true,encoding:.utf8) }
    let state = base.appendingPathComponent("settings.json")
    var legacy = Settings(); legacy.root = a.path
    legacy.projects = try discoverProjects(root:a.path,saved:[])
    legacy.directoryOrders = [a.path:[a.appendingPathComponent("2025").path,a.appendingPathComponent("2026").path]]
    try JSONEncoder().encode(legacy).write(to:state)
    let store = Store(stateURL:state,loadOnLaunch:false)
    try verify(store.settings.activeProjectRoots == [a.path],"Legacy single-root settings must load without losing the original root")
    try verify(store.addProjectRoots([b.path],refreshAfter:false))
    try verify(store.settings.root == a.path && store.settings.activeProjectRoots == [a.path,b.path],"Adding roots must append rather than replace")
    let snapshot = try discoverProjectRoots(store.settings.activeProjectRoots,saved:store.settings.projects)
    store.settings.projects = snapshot.projects
    store.save() // Store.refresh persists published directory metadata before a later restart.
    try verify(snapshot.projects.filter{$0.shallow == true && $0.name == "2026"}.count == 2,"Both roots' same-name child directories must be visible")
    let sa = a.appendingPathComponent("2026").path, sb = b.appendingPathComponent("2026").path
    try verify(snapshot.projects.first{$0.path == pa.path}?.scopeID == sa && snapshot.projects.first{$0.path == pb.path}?.scopeID == sb,"Search and selection scopes use absolute paths, never ambiguous folder names")
    try verify(store.directories(in:a.path).first?.name == "2025","The original root's manual order survives adding another root")
    var alternate = store.settings
    alternate.root = a.path.replacingOccurrences(of:"/private/var/",with:"/var/")
    let alternateStore = Store(stateURL:base.appendingPathComponent("alias-settings.json"),loadOnLaunch:false)
    alternateStore.settings = alternate
    try verify(alternateStore.directories(in:alternate.root).map(\.path).allSatisfy { $0.hasPrefix(a.path+"/") } && alternateStore.directories(in:b.path).count == 2,"Equivalent macOS path spellings must not mix root groups")
    let prior = store.settings.activeProjectRoots
    try verify(store.addProjectRoots([b.path,b.path],refreshAfter:false) && store.settings.activeProjectRoots == prior,"Repeated linking is idempotent")
    try verify(!store.addProjectRoots([a.appendingPathComponent("2026").path],refreshAfter:false) && store.settings.activeProjectRoots == prior,"Nested roots are rejected without partial configuration writes")
    store.error = ""
    try verify(!store.reorderDirectory(DirectoryOrderPayload(root:a.path,path:sa),relativeTo:sb,after:true),"Dragging must not move a directory across root groups")
    let b25 = b.appendingPathComponent("2025").path
    try verify(store.reorderDirectory(DirectoryOrderPayload(root:b.path,path:b25),relativeTo:sb,after:false))
    try verify(store.settings.directoryOrders?[a.path] == legacy.directoryOrders?[a.path],"Reordering the second root does not alter the first root's saved order")
    let loaded = Store(stateURL:state,loadOnLaunch:false)
    try verify(loaded.settings.activeProjectRoots == prior && loaded.directories(in:b.path).first?.path == b25,"Roots and per-root order persist across restart")
    let index = FilenameSearchIndex(databaseURL:base.appendingPathComponent("names.sqlite"))
    let files = snapshot.projects.flatMap { metadataFiles($0.path,project:$0.path,recursive:$0.shallow != true,cache:[:]) }
    index.synchronize(root:store.settings.workspaceIdentity,projects:snapshot.projects,files:files)
    let ahits = index.lookupSync("验收",scope:sa), bhits = index.lookupSync("验收",scope:sb)
    try verify(Set(ahits.projectRanks.keys) == [pa.path] && Set(bhits.projectRanks.keys) == [pb.path],"Name-index matches remain isolated between identically named directories")
    let controller = WorkspaceSearchController()
    controller.submit(index:index,query:"验收",scope:sb,projects:snapshot.projects,files:files,sourceRows:[],byMonth:true,aggregateThirdLevel:true)
    let deadline = Date().addingTimeInterval(3)
    while controller.isSearching && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
    try verify(controller.output.searchEntries.map(\.id) == [pb.appendingPathComponent("验收资料.txt").path],"Aggregate search also isolates same-name directories across roots")
    let inbox = base.appendingPathComponent("external.txt"); try "外部资料".write(to:inbox,atomically:true,encoding:.utf8)
    let project = snapshot.projects.first{$0.path == pb.path}!
    let result = store.confirmQuickArchive(QuickArchiveRequest(rows:[browserEntry(inbox.path)!]),to:project)
    try verify(result.failure == nil && result.completed.count == 1,"Quick archive may target a project in the second root")
    store.scanCancellation?.cancel(); store.busy = false; store.undo(store.settings.moves[0],refreshAfter:false)
    try verify(fm.fileExists(atPath:inbox.path),"Cross-root archive remains undoable")
    for path in [a.path,b.path,sa,sb] {
        do { _ = try finderServiceRows([URL(fileURLWithPath:path)],settings:store.settings); throw namingError("Expected protected directory rejection") }
        catch { try verify(error.localizedDescription.contains("项目总目录"),"All linked roots and navigation directories are protected") }
    }
    let disconnected = base.appendingPathComponent("离线目录")
    try fm.moveItem(at:b,to:disconnected)
    let partial = try discoverProjectRoots([a.path,b.path],saved:snapshot.projects)
    try verify(partial.unavailable == [b.path] && partial.projects.contains{$0.path == pa.path} && partial.projects.contains{$0.path == pb.path},"One disconnected root preserves its cached navigation and leaves other roots available")
    try fm.moveItem(at:disconnected,to:b)
    try verify(store.removeProjectRoot(a.path,refreshAfter:false) && store.settings.root == b.path && store.settings.activeProjectRoots == [b.path],"Removing the primary root promotes the remaining root")
    try verify(fm.fileExists(atPath:pa.appendingPathComponent("验收资料.txt").path),"Removing a link never deletes files or folders")
    try verify(store.removeProjectRoot(b.path,refreshAfter:false) && !store.settings.hasProjectRoots,"Removing all links leaves a valid empty workspace")
    print("PASS: single-root migration, multiple-root append/dedup/persistence, same-name path scopes, independent ordering, filename/aggregate search isolation, second-root archive/undo, protected roots, partial offline discovery and unlink without file changes")
}
