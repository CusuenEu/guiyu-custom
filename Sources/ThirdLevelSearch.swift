import Foundation

// Cached metadata only: immediate children of second-level projects, including empty folders.
// This queue never reads document bodies and never descends into third-level folders.
final class ThirdLevelSearchCache: @unchecked Sendable {
    struct Snapshot { var rows: [BrowserRow] = []; var unavailable: [String] = [] }
    private struct Key: Equatable { let scope: String; let projects: [Project]; let revision: Int }
    private let queue = DispatchQueue(label:"local.guiyu.third-level-search",qos:.userInitiated)
    private var key: Key?
    private var snapshot = Snapshot()
    func load(scope:String,projects:[Project],revision:Int,token:IndexCancellation,completion:@escaping (Snapshot) -> Void) {
        let owners = projects.filter { $0.shallow != true && $0.scopeID == scope }
        let requested = Key(scope:scope,projects:owners,revision:revision)
        queue.async { [self] in
            guard !token.isCancelled else { return }
            if key != requested {
                var next = Snapshot()
                for owner in owners {
                    guard !token.isCancelled else { return }
                    do {
                        next.rows += try directoryEntries(path:owner.path,project:owner.path).map { entry in
                            var row = entry; row.subtitle = owner.name; return row
                        }
                    } catch { next.unavailable.append(owner.name) }
                }
                key = requested; snapshot = next
            }
            guard !token.isCancelled else { return }
            completion(snapshot)
        }
    }
}

func projectOwnerPath(_ path:String,projects:[Project]) -> String? {
    projects.filter { $0.shallow != true && (path == $0.path || path.hasPrefix($0.path+"/")) }.max { $0.path.count < $1.path.count }?.path
}

@MainActor func thirdLevelSearchTest(root:URL) throws {
    let base = root.appendingPathComponent("third-level-search")
    let a = base.appendingPathComponent("2026/甲项目"), b = base.appendingPathComponent("2026/乙项目"), old = base.appendingPathComponent("2025/旧项目")
    for folder in [a.appendingPathComponent("民政空目录"),b,old,a.appendingPathComponent("参考资料")] { try fm.createDirectory(at:folder,withIntermediateDirectories:true) }
    let wanted = [a.appendingPathComponent("民政资料.txt"),b.appendingPathComponent("民政资料.txt")]
    for file in wanted + [old.appendingPathComponent("民政资料.txt"),a.appendingPathComponent("参考资料/民政深层.txt")] { try "正文不应被读取".write(to:file,atomically:true,encoding:.utf8) }
    let projects = [Project(path:a.path,name:"甲项目",group:"2026"),Project(path:b.path,name:"乙项目",group:"2026"),Project(path:old.path,name:"旧项目",group:"2025")]
    let index = FilenameSearchIndex(databaseURL:base.appendingPathComponent("index.sqlite"))
    index.synchronize(root:base.path,projects:projects,files:[])
    let controller = WorkspaceSearchController()
    func submit(_ query:String,scope:String = "2026",revision:Int = 0,source:[BrowserRow] = [],owners:[Project]? = nil) throws {
        controller.submit(index:index,query:query,scope:scope,projects:owners ?? projects,files:[],sourceRows:source,byMonth:true,aggregateThirdLevel:true,metadataRevision:revision)
        let deadline = Date().addingTimeInterval(3)
        while controller.isSearching && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
        try verify(!controller.isSearching && controller.output.query == query,"Aggregate search must finish and publish the requested query")
    }
    try submit("民政")
    let expected = Set(wanted.map(\.path)+[a.appendingPathComponent("民政空目录").path])
    try verify(Set(controller.output.searchEntries.map(\.id)) == expected,"Right pane must aggregate exactly the third-level entries across all projects, including empty folders, without a selection or deeper descendants")
    try verify(Set(controller.output.projectRows.map(\.id)) == Set([a.path,b.path]),"A matching third-level folder must make its owning project discoverable")
    try verify(Set(controller.output.searchEntries.compactMap(\.subtitle)) == Set(["甲项目","乙项目"]),"Same-name hits must identify their owning project")
    try verify(controller.output.searchEntries.allSatisfy { $0.folder || $0.file?.text.isEmpty == true },"Aggregate listing must never read document bodies")
    try verify(projectOwnerPath(wanted[1].path,projects:projects) == b.path,"Result actions must resolve the result's owner, independent of current selection")
    try submit("民政",scope:"2025")
    try verify(controller.output.searchEntries.map(\.id) == [old.appendingPathComponent("民政资料.txt").path],"Changing left directory must isolate all third-level hits")
    try submit("民政")
    let added = b.appendingPathComponent("民政新增.bin"); try Data().write(to:added)
    try submit("民政新增")
    try verify(controller.output.searchEntries.isEmpty,"Typing should reuse metadata rather than re-enumerating directories")
    try submit("民政新增",revision:1)
    try verify(controller.output.searchEntries.map(\.id) == [added.path],"Refresh must invalidate metadata, including unsupported filename extensions")
    let source = try directoryEntries(path:a.path,project:a.path)
    try submit("",source:source)
    try verify(controller.output.searchEntries.isEmpty && controller.output.sourceIDs == nil && Set(controller.output.fileRows.filter{!$0.header}.map(\.id)) == Set(source.map(\.id)),"Clearing search restores ordinary immediate-directory browsing")
    let missing = Project(path:base.appendingPathComponent("missing").path,name:"不可读项目",group:"2026")
    try submit("民政",revision:2,owners:projects+[missing])
    try verify(controller.output.unavailableProjects == ["不可读项目"] && !controller.output.searchEntries.isEmpty,"Unreadable projects must be reported without hiding accessible results")
    print("PASS: no-selection third-level aggregate search, folder/file boundaries, owning-project labels/actions, directory isolation, metadata-only caching and invalidation, clearing search and partial-read errors")
}
