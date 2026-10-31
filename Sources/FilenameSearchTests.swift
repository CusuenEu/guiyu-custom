import Foundation
import GRDB

@MainActor func filenameSearchTest(root:URL) throws {
    let state = root.appendingPathComponent("filename-search")
    let dbURL = state.appendingPathComponent("search.sqlite")
    let index = FilenameSearchIndex(databaseURL:dbURL)
    let base = state.appendingPathComponent("projects").path
    let p = Project(path:base+"/2026/10月 机关项目",name:"10月 机关项目",group:"2026")
    let other = Project(path:base+"/2026/9月 第二项目",name:"9月 第二项目",group:"2026")
    let previous = Project(path:base+"/2025/旧项目",name:"旧项目",group:"2025")
    let directory = Project(path:base+"/2026",name:"2026",group:"2026",shallow:true)
    let projects = [directory,p,other,previous]
    func file(_ owner:Project,_ name:String) -> FileItem {
        FileItem(path:owner.path+"/"+name,project:owner.path,text:"正文专属暗号不得入索引",size:1,date:Date())
    }
    var files = [file(p,"民政厅网络运维方案.docx"),file(other,"民政厅网络运维方案.docx.bak"),file(p,"CAFE\u{301}全角ＡＢＣ.docx"),file(p,"合同_%'报价.xlsx"),file(previous,"民政厅网络运维方案.docx"),file(directory,"散放采购说明.pdf")]
    index.synchronize(root:base,projects:projects,files:files)
    let multi = index.lookupSync("民政 运维",scope:"2026")
    try verify(multi.usedDatabase && multi.fileRanks.count == 2,"Chinese multi-term queries must use the database and stay in the directory scope")
    try verify(index.lookupSync("民",scope:"2026").fileRanks.count == 2,"Single Chinese characters must not disappear")
    try verify(index.lookupSync("政厅",scope:"2026").fileRanks.count == 2,"Two-character Chinese terms must be indexed")
    try verify(index.lookupSync("cafe abc",scope:"2026").fileRanks[files[2].path] != nil,"Canonical Unicode, width and case normalization")
    try verify(index.lookupSync("_%'",scope:"2026").fileRanks[files[3].path] != nil,"SQL metacharacters must be literal, parameter-bound text")
    try verify(index.lookupSync("' OR 1=1",scope:"2026").fileRanks.isEmpty,"Search text must never become SQL")
    try verify(index.lookupSync("正文专属暗号",scope:"2026").fileRanks.isEmpty,"Body text must never enter the name index")
    let exact = index.lookupSync("民政厅网络运维方案.docx",scope:"2026")
    try verify(exact.projectRanks[p.path]! < exact.projectRanks[other.path]!,"Exact names rank before substring matches")
    try verify(index.lookupSync("散放",scope:"2026").fileRanks[files[5].path] != nil,"Loose directory files must remain searchable")

    let oldPath = files[0].path
    files[0].path = p.path+"/已更名安全服务.docx"
    index.synchronize(root:base,projects:projects,files:files)
    try verify(index.lookupSync("民政 运维",scope:"2026").fileRanks[oldPath] == nil,"Renaming removes the old name")
    try verify(index.lookupSync("已更名",scope:"2026").fileRanks[files[0].path] != nil,"Renaming inserts the new name")
    files.removeFirst()
    index.synchronize(root:base,projects:projects,files:files)
    try verify(index.lookupSync("已更名",scope:"2026").fileRanks.isEmpty,"Deleted/trashed files must leave the index")
    let reopened = FilenameSearchIndex(databaseURL:dbURL)
    reopened.synchronize(root:base,projects:projects,files:files)
    try verify(reopened.lookupSync("cafe abc",scope:"2026").usedDatabase,"Persisted cache must reopen with revalidated metadata")
    index.synchronize(root:"/different-project-root",projects:[],files:[])
    try verify(index.lookupSync("民政",scope:"2026").fileRanks.isEmpty,"Changing project roots must remove the previous scope")

    let corrupt = state.appendingPathComponent("corrupt.sqlite")
    try Data("not a sqlite database".utf8).write(to:corrupt)
    let recovered = FilenameSearchIndex(databaseURL:corrupt)
    recovered.synchronize(root:base,projects:projects,files:files)
    try verify(recovered.lookupSync("cafe abc",scope:"2026").usedDatabase,"A corrupt disposable cache must rebuild")
    let blocked = state.appendingPathComponent("directory-not-a-cache.sqlite")
    try fm.createDirectory(at:blocked,withIntermediateDirectories:true)
    let marker = blocked.appendingPathComponent("keep.txt"); try Data("keep".utf8).write(to:marker)
    let fallback = FilenameSearchIndex(databaseURL:blocked)
    fallback.synchronize(root:base,projects:projects,files:files)
    let fallbackResult = fallback.lookupSync("cafe abc",scope:"2026")
    try verify(!fallbackResult.usedDatabase && fallbackResult.fileRanks.count == 1 && fm.fileExists(atPath:marker.path),"An unavailable cache falls back without deleting unrelated files")

    // A second client changed this shared cache's root above; revalidate this client's snapshot.
    reopened.synchronize(root:base,projects:projects,files:files)
    let disk = try Data(contentsOf:dbURL)
    try verify(disk.range(of:Data("正文专属暗号不得入索引".utf8)) == nil,"Document bodies must not be persisted in the SQLite cache")
    let localRows = files.filter { $0.project == p.path }.map { BrowserRow(id:$0.path,title:$0.name,file:$0) }
    let warmFolder = state.appendingPathComponent("warm-store")
    let warmURL = warmFolder.appendingPathComponent("search-index-v1.sqlite")
    let seed = FilenameSearchIndex(databaseURL:warmURL)
    seed.synchronize(root:base,projects:projects,files:files)
    var saved = Settings(); saved.root = base; saved.projects = projects
    let settingsURL = warmFolder.appendingPathComponent("settings.json")
    try JSONEncoder().encode(saved).write(to:settingsURL)
    let coldStore = Store(stateURL:settingsURL,loadOnLaunch:false)
    _ = coldStore.filenameIndex.lookupSync("cafe abc",scope:"2026")
    let inspected = try DatabaseQueue(path:warmURL.path)
    let preserved = try inspected.read { try Int.fetchOne($0,sql:"SELECT COUNT(*) FROM search_documents WHERE kind=1") ?? 0 }
    try verify(preserved == files.count,"Startup's temporary empty file array must not erase the persisted index")
    coldStore.files = files
    try verify(coldStore.filenameIndex.lookupSync("cafe abc",scope:"2026").usedDatabase,"Publishing metadata revalidates the warm cache")

    let controller = WorkspaceSearchController()
    controller.submit(index:reopened,query:"民政",scope:"2026",projects:projects,files:files,sourceRows:[],byMonth:true)
    controller.submit(index:reopened,query:"cafe abc",scope:"2026",projects:projects,files:files,sourceRows:localRows,byMonth:true)
    let until = Date().addingTimeInterval(3)
    while controller.output.query != "cafe abc" && Date() < until { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
    try verify(controller.output.query == "cafe abc" && controller.output.projectRows.map(\.id) == [p.path],"Only the latest debounced query may publish results; got \(controller.output.query), \(controller.output.projectRows.map(\.id))")
    try verify(controller.output.sourceIDs == Set(localRows.filter { FilenameQuery("cafe abc").matches($0.title) }.map(\.id)),"The file pane may match only its explicit immediate entries")
    controller.submit(index:reopened,query:"",scope:"2025",projects:projects,files:files,sourceRows:[],byMonth:true)
    let cleared = Date().addingTimeInterval(3)
    while controller.output.projectRows.map(\.id) != [previous.path] && Date() < cleared { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
    try verify(controller.output.query.isEmpty && controller.output.projectRows.map(\.id) == [previous.path],"Clearing search restores the selected scope, not stale results")
    print("PASS: GRDB name-only index, Chinese short/multi-term queries, normalization, literal SQL input, exact ranking, scope/rename/delete/reopen/corrupt-cache/fallback, latest-query publication")

    let benchmark = FilenameSearchIndex(databaseURL:state.appendingPathComponent("benchmark.sqlite"))
    let bp = (0..<100).map { Project(path:"/synthetic/2026/P\($0)",name:"10月 示例项目\($0)",group:"2026") }
    let sample = (0..<10000).map { i in file(bp[i % bp.count],"网络运维服务方案-"+String(format:"%05d",i)+".docx") }
    let started = Date(); benchmark.synchronize(root:"/synthetic",projects:bp,files:sample)
    let buildMS = Date().timeIntervalSince(started)*1000
    let revalidate = Date(); benchmark.synchronize(root:"/synthetic",projects:bp,files:sample)
    let warmIndexMS = Date().timeIntervalSince(revalidate)*1000
    var narrow: [Double] = []
    for _ in 0..<15 {
        let start = Date(); let result = benchmark.lookupSync("运维 09999",scope:"2026")
        narrow.append(Date().timeIntervalSince(start)*1000)
        try verify(result.usedDatabase && result.fileRanks.count == 1)
    }
    let broadStart = Date(); let broad = benchmark.lookupSync("网络 运维",scope:"2026")
    let broadMS = Date().timeIntervalSince(broadStart)*1000
    try verify(broad.usedDatabase && broad.fileRanks.count == 10000)
    print(String(format:"SEARCH BENCHMARK (synthetic 100 projects / 10000 names): initial index %.1f ms; unchanged metadata revalidation %.1f ms; warm narrow median %.2f ms, max %.2f ms; broad 10000-hit query %.2f ms. Backend only; UI debounce adds 50 ms.",buildMS,warmIndexMS,narrow.sorted()[narrow.count/2],narrow.max()!,broadMS))
}
