import Foundation

func discoverProjects(root: String, saved: [Project]) throws -> [Project] {
    guard !root.isEmpty else { return [] }
    let rootURL = URL(fileURLWithPath:root)
    let children = try fm.contentsOfDirectory(at:rootURL,includingPropertiesForKeys:[.isDirectoryKey],options:.skipsHiddenFiles)
    var result: [Project] = []
    // Root folders are physical navigation directories, regardless of their names.
    // Each direct subfolder is a project; no synthetic year or ungrouped buckets.
    for child in children where (try? child.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true {
        var directory = saved.first { $0.path == child.path } ?? Project(path:child.path,name:child.lastPathComponent)
        directory.shallow = true; directory.group = child.lastPathComponent; result.append(directory)
        let nested = try fm.contentsOfDirectory(at:child,includingPropertiesForKeys:[.isDirectoryKey],options:.skipsHiddenFiles)
        for folder in nested where (try? folder.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true {
            var project = saved.first { $0.path == folder.path } ?? Project(path:folder.path,name:folder.lastPathComponent)
            project.group = child.lastPathComponent; project.shallow = false; result.append(project)
        }
    }
    for i in result.indices { result[i].modifiedAt = try? URL(fileURLWithPath:result[i].path).resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate }
    return result.sorted { a,b in
        if (a.group ?? "") != (b.group ?? "") { return (a.group ?? "") > (b.group ?? "") }
        if a.shallow == true && b.shallow != true { return true }
        if b.shallow == true && a.shallow != true { return false }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}
func metadataFiles(_ path: String, project: String, recursive: Bool, cache: [String:FileItem]) -> [FileItem] {
    guard !path.isEmpty else { return [] }
    let base = URL(fileURLWithPath:path)
    let urls: [URL]
    if recursive, let e = fm.enumerator(at:base,includingPropertiesForKeys:[.isRegularFileKey,.fileSizeKey,.contentModificationDateKey],options:[.skipsHiddenFiles,.skipsPackageDescendants]) { urls = e.compactMap { $0 as? URL } }
    else { urls = (try? fm.contentsOfDirectory(at:base,includingPropertiesForKeys:nil,options:.skipsHiddenFiles)) ?? [] }
    return urls.compactMap { u in
        guard supported.contains(u.pathExtension.lowercased()), !u.lastPathComponent.hasPrefix("~$"), let v = try? u.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey,.contentModificationDateKey]), v.isRegularFile == true else { return nil }
        let date = v.contentModificationDate ?? .distantPast, size = Int64(v.fileSize ?? 0)
        if project.isEmpty && Date().timeIntervalSince(date) < 15 { return nil }
        if var old = cache[u.path], old.date == date, old.size == size { old.project = project; return old }
        return FileItem(path:u.path,project:project,text:"",size:size,date:date)
    }
}

final class IndexCancellation: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}
func indexingTest(root: URL) throws {
    let base = root.appendingPathComponent("YearGroups")
    let nested = base.appendingPathComponent("2026/A")
    try fm.createDirectory(at:nested,withIntermediateDirectories:true)
    try "项目名称：测试分层建设项目".write(to:nested.appendingPathComponent("说明.txt"),atomically:true,encoding:.utf8)
    try "散放资料".write(to:base.appendingPathComponent("2026/散放.txt"),atomically:true,encoding:.utf8)
    let saved = Project(path:nested.path,name:"已确认的项目名",keywords:"TEST-2026")
    let projects = try discoverProjects(root:base.path,saved:[saved])
    try verify(projects.count == 2)
    try verify(projects.first(where: { $0.path == nested.path })?.name == saved.name)
    try verify(projects.first(where: { $0.path == nested.path })?.group == "2026")
    let files = projects.flatMap { metadataFiles($0.path,project:$0.path,recursive:$0.shallow != true,cache:[:]) }
    try verify(files.count == 2 && Set(files.map(\.path)).count == 2,"Year groups must not duplicate or omit documents")
    try verify(files.allSatisfy { $0.text.isEmpty },"Listing files must not wait for document extraction")
    let cd = base.appendingPathComponent("CD类项目"), cdProject = cd.appendingPathComponent("青秀2046")
    try fm.createDirectory(at:cdProject,withIntermediateDirectories:true)
    let cdFile = cdProject.appendingPathComponent("方案.txt"); try "项目资料".write(to:cdFile,atomically:true,encoding:.utf8)
    try "目录内散放文档".write(to:cd.appendingPathComponent("说明.txt"),atomically:true,encoding:.utf8)
    let discovered = try discoverProjects(root:base.path,saved:[])
    try verify(discovered.first(where:{$0.path == cd.path})?.shallow == true)
    try verify(discovered.first(where:{$0.path == cdProject.path})?.group == "CD类项目","Non-year names must be physical navigation labels")
    var legacy = metadataFiles(cdProject.path,project:cd.path,recursive:true,cache:[:])[0]; legacy.text = "cached text"
    let migrated = metadataFiles(cdProject.path,project:cdProject.path,recursive:true,cache:[legacy.path:legacy])
    try verify(migrated[0].project == cdProject.path && migrated[0].text == "cached text","Reparent cached entries without extracting text")
    let matched = versionMatched(migrated[0],cached:legacy)
    try verify(matched.project == cdProject.path,"Text-cache reuse must preserve the new project ownership")
    let all = discovered.flatMap { metadataFiles($0.path,project:$0.path,recursive:$0.shallow != true,cache:[:]) }
    try verify(all.count == 4 && Set(all.map(\.path)).count == 4,"Physical navigation must not flatten or duplicate nested documents")
    let token = IndexCancellation(); try verify(!token.isCancelled); token.cancel(); try verify(token.isCancelled)
}

func representativeFiles(_ files: [FileItem], limit: Int) -> [FileItem] {
    files.sorted { a,b in
        func rank(_ file: FileItem) -> Int {
            let document = ["txt","md","docx","doc","pdf","rtf"].contains(file.ext) ? 0 : 10
            let title = ["项目说明","项目信息","需求","合同","采购","招标"].contains { file.name.contains($0) } ? 0 : 2
            return document + title
        }
        let x = rank(a), y = rank(b)
        return x == y ? a.size < b.size : x < y
    }.prefix(limit).map { $0 }
}
func archiveWorkset(projects: [Project], files: [FileItem], incoming: [FileItem]) -> [FileItem] {
    var references: [FileItem] = []
    for project in projects where project.shallow != true {
        let knownTitle = project.name.count >= 8 && (project.name.hasSuffix("项目") || project.name.hasSuffix("工程"))
        if knownTitle || !project.keywords.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { continue }
        references += representativeFiles(files.filter { $0.project == project.path },limit:3)
    }
    return references + incoming
}
func lightweightTest(root: URL) throws {
    let p = Project(path:"/sample/A",name:"A")
    let files = (0..<1000).map { FileItem(path:"/sample/A/\($0).txt",project:p.path,text:"",size:1,date:Date()) }
    let incoming = FileItem(path:"/sample/download.txt",project:"",text:"",size:1,date:Date())
    let work = archiveWorkset(projects:[p],files:files,incoming:[incoming])
    try verify(work.count == 4,"Archiving should sample references rather than parse the whole library")
    var stale = incoming; stale.text = "outdated"; stale.date = incoming.date.addingTimeInterval(-1)
    try verify(versionMatched(incoming,cached:stale).text.isEmpty,"Stale cache must not replace current metadata")
    stale.date = incoming.date; try verify(versionMatched(incoming,cached:stale).text == "outdated")
    let known = Project(path:p.path,name:"南山智慧园区建设项目")
    try verify(archiveWorkset(projects:[known],files:files,incoming:[incoming]).count == 1)
    print("Lightweight fixture: 1000 library files, 3 reference samples + 1 incoming; browsing metadata requires no extraction")
}

func versionMatched(_ file: FileItem, cached: FileItem?) -> FileItem {
    guard let cached, cached.path == file.path, cached.date == file.date, cached.size == file.size else { return file }
    var result = cached; result.project = file.project; return result
}
