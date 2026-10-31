import Foundation

func directoryEntries(path: String, project: String) throws -> [BrowserRow] {
    let urls = try fm.contentsOfDirectory(at:URL(fileURLWithPath:path),includingPropertiesForKeys:[.isDirectoryKey,.isRegularFileKey,.fileSizeKey,.contentModificationDateKey],options:.skipsHiddenFiles)
    return urls.compactMap { url in
        guard !url.lastPathComponent.hasPrefix("~$"), let value = try? url.resourceValues(forKeys:[.isDirectoryKey,.isRegularFileKey,.fileSizeKey,.contentModificationDateKey]) else { return nil }
        let folder = value.isDirectory == true
        let file = folder ? nil : FileItem(path:url.path,project:project,text:"",size:Int64(value.fileSize ?? 0),date:value.contentModificationDate ?? .distantPast)
        return BrowserRow(id:url.path,title:url.lastPathComponent,date:value.contentModificationDate,file:file,folder:folder)
    }.sorted { a,b in a.folder == b.folder ? a.title.localizedStandardCompare(b.title) == .orderedAscending : a.folder }
}
func categoryForEntry(_ row: BrowserRow) -> DocumentCategory {
    // Classification inspects this entry's own name only; folders remain folders.
    let parent = URL(fileURLWithPath:row.id).deletingLastPathComponent().path
    return documentCategory(FileItem(path:row.id,project:parent,text:"",size:row.file?.size ?? 0,date:row.date ?? .distantPast))
}
func presentDirectory(_ entries: [BrowserRow], mode: String, query: String, collapsed: Set<String>, categories: [WorkspaceCategory] = WorkspaceCategory.defaults, assignments: [String:CategoryAssignment] = [:]) -> [BrowserRow] {
    let entries = entries.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    if mode == "源文档" { return entries }
    func newest(_ values: [BrowserRow]) -> [BrowserRow] {
        values.sorted { a,b in let x = a.date ?? .distantPast, y = b.date ?? .distantPast; return x == y ? a.title.localizedStandardCompare(b.title) == .orderedAscending : x > y }
    }
    if mode == "按时间" {
        let calendar = Calendar(identifier:.gregorian)
        func key(_ row: BrowserRow) -> String {
            guard let date = row.date else { return "日期未知" }
            let parts = calendar.dateComponents([.year,.month],from:date); return String(format:"%04d-%02d",parts.year ?? 0,parts.month ?? 0)
        }
        let groups = Dictionary(grouping:entries,by:key)
        return groups.keys.sorted(by:>).flatMap { label -> [BrowserRow] in
            let values = newest(groups[label] ?? []); let id = "date:"+label
            return [BrowserRow(id:id,title:label,header:true,count:values.count,expanded:!collapsed.contains(id))] + (collapsed.contains(id) ? [] : values)
        }
    }
    let classifier = CategoryClassifier(categories:categories)
    let grouped = Dictionary(grouping:entries,by:{ classifier.resolve($0,assignments:assignments)?.id ?? "" })
    return categories.flatMap { category -> [BrowserRow] in
        let values = newest(grouped[category.id] ?? []).map { row -> BrowserRow in var row = row; row.categoryID = category.id; return row }
        guard !values.isEmpty else { return [] }
        let id = "category:"+category.id
        return [BrowserRow(id:id,title:category.name,header:true,count:values.count,expanded:!collapsed.contains(id),categoryID:category.id)] + (collapsed.contains(id) ? [] : values)
    }
}
func projectMonth(_ name: String) -> Int? {
    guard let range = name.range(of:"^(1[0-2]|[1-9])(?=月|\\s|[^0-9]|$)",options:.regularExpression) else { return nil }
    return Int(name[range])
}
func newestProjects(_ projects: [Project], byMonth: Bool) -> [Project] {
    projects.sorted { a,b in
        if byMonth {
            let x = projectMonth(a.name) ?? projectMonth(URL(fileURLWithPath:a.path).lastPathComponent) ?? 0
            let y = projectMonth(b.name) ?? projectMonth(URL(fileURLWithPath:b.path).lastPathComponent) ?? 0
            if x != y { return x > y }
        }
        let x = a.modifiedAt ?? .distantPast, y = b.modifiedAt ?? .distantPast
        return x == y ? a.name.localizedStandardCompare(b.name) == .orderedDescending : x > y
    }
}
func directoryPresentationTest(root: URL) throws {
    let dir = root.appendingPathComponent("Presentation"); let nested = dir.appendingPathComponent("投标文件B")
    try fm.createDirectory(at:nested,withIntermediateDirectories:true)
    try "root".write(to:dir.appendingPathComponent("方案A.txt"),atomically:true,encoding:.utf8)
    try "nested".write(to:nested.appendingPathComponent("内部招标文件.txt"),atomically:true,encoding:.utf8)
    let entries = try directoryEntries(path:dir.path,project:dir.path)
    try verify(entries.count == 2 && entries.contains { $0.folder && $0.title == "投标文件B" })
    let paths = Set(entries.map(\.id))
    for mode in ["按类别","按时间","源文档"] {
        let rows = presentDirectory(entries,mode:mode,query:"",collapsed:[])
        try verify(Set(rows.filter{!$0.header}.map(\.id)) == paths,"All modes must preserve exactly the immediate children")
        try verify(!rows.contains { $0.title == "内部招标文件.txt" },"Never flatten folder contents")
        try verify(rows.first(where:{$0.title == "投标文件B"})?.folder == true)
        try verify(rows.filter(\.header).allSatisfy { $0.count > 0 })
    }
    let rows = presentDirectory(entries,mode:"按类别",query:"",collapsed:[])
    try verify(!rows.contains { $0.header && ($0.title == "招标文件" || $0.title == "其他") })
    let inside = try directoryEntries(path:nested.path,project:dir.path); try verify(inside.count == 1 && inside[0].title == "内部招标文件.txt")
    let jan = Project(path:"/projects/1 A",name:"1 A",modifiedAt:Date(timeIntervalSince1970:200))
    let oct = Project(path:"/projects/10 B",name:"10 B",modifiedAt:Date(timeIntervalSince1970:100))
    try verify(newestProjects([jan,oct],byMonth:true)[0].id == oct.id)
    try verify(newestProjects([jan,oct],byMonth:false)[0].id == jan.id)
    let rfpName = "抖音集团2026年中国区贵州+新疆 (乌鲁木齐、昌吉) 机房租赁招采项目-RFP文件"
    let rfp = BrowserRow(id:dir.appendingPathComponent(rfpName).path,title:rfpName,folder:true)
    try verify(categoryForEntry(rfp) == .tender,"User's exact RFP folder must classify as tender")
    let groupedRFP = presentDirectory([rfp],mode:"按类别",query:"",collapsed:[])
    try verify(groupedRFP.count == 2 && groupedRFP[0].title == "招标文件" && groupedRFP[1].folder,"RFP folder must remain a single folder")
    func fileCategory(_ name: String) -> DocumentCategory { documentCategory(FileItem(path:dir.appendingPathComponent(name).path,project:dir.path,text:"",size:1,date:Date())) }
    try verify(fileCategory(rfpName+".pdf") == .tender)
    try verify(fileCategory("项目-rfp文件.docx") == .tender)
    try verify(fileCategory("项目RFP2026.pdf") == .tender)
    try verify(fileCategory("REQUEST_FOR_PROPOSAL.pdf") == .tender)
    try verify(fileCategory("RFQ采购要求.xlsx") == .tender)
    try verify(fileCategory("招采需求说明.docx") == .tender)
    try verify(fileCategory("RFP投标邀请.pdf") == .tender)
    try verify(fileCategory("RFP响应要求.pdf") == .tender)
    try verify(fileCategory("RFP响应文件.docx") == .bid)
    try verify(fileCategory("rfp-response.docx") == .bid)
    try verify(fileCategory("RFQ报价清单.xlsx") == .bid)
    try verify(fileCategory("IRFPbackup.txt") == .other)
    try verify(fileCategory("RFPAbase.txt") == .other)
    print("PASS: exact RFP folder/file, case-insensitive procurement codes, response-vs-request distinction, no embedded-word false matches")
    print("PASS: all views preserve immediate file/folder entries, no descendant flattening, empty categories hidden, project time/month descending")
}
