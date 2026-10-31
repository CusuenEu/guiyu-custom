import Foundation

struct NamingTarget: Identifiable {
    var id: String { path }; let path: String; let folder: Bool; let projectPath: String
    let identity: String?; let modified: Date?
    init(path: String, folder: Bool, projectPath: String) {
        self.path = path; self.folder = folder; self.projectPath = projectPath; identity = fileIdentity(path)
        modified = try? URL(fileURLWithPath:path).resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate
    }
}
struct RenameRecord: Codable, Identifiable {
    var id = UUID(); var source: String; var destination: String; var folder: Bool; var date = Date(); var identity: String?
}
enum DocumentCategory: String, CaseIterable {
    case proposal = "方案", tender = "招标文件", bid = "投标文件", other = "其他"
}
func documentCategory(_ file: FileItem) -> DocumentCategory {
    func classify(_ text: String) -> DocumentCategory? {
        func procurementCode(_ value: String) -> Bool {
            value.range(of:"(?<![A-Za-z])(?:RFP|RFQ)(?![A-Za-z])|REQUEST[ _-]+FOR[ _-]+(?:PROPOSALS?|QUOTATIONS?)",options:[.regularExpression,.caseInsensitive]) != nil
        }
        // A supplier response to an RFP/RFQ is a bid, rather than the request itself.
        if procurementCode(text), ["响应文件","应答文件","投标文件","投标响应","投标应答","响应书","应答书","报价清单","报价文件","报价表","商务响应","技术响应","response","proposal submission","quotation submission"].contains(where:{ text.localizedCaseInsensitiveContains($0) }) { return .bid }
        if procurementCode(text) || ["招采文件","招采需求","招标需求","投标邀请","采购邀请","招标邀请","征求建议书"].contains(where:text.contains) { return .tender }
        if ["招标文件","采购文件","采购需求","磋商文件","谈判文件","比选文件","询价文件","征集文件","招标公告","采购公告","招标答疑","招标澄清","招标补遗","竞争性磋商"].contains(where:text.contains) { return .tender }
        if ["投标","响应文件","应答文件","报价","商务响应","技术响应","商务标","技术标"].contains(where:text.contains) { return .bid }
        if ["方案","建议书","解决方案"].contains(where:text.contains) { return .proposal }
        return nil
    }
    if let category = classify(file.name) { return category }
    let parent = URL(fileURLWithPath:file.path).deletingLastPathComponent().path
    let relative = parent.hasPrefix(file.project+"/") ? String(parent.dropFirst(file.project.count+1)) : ""
    return classify(relative) ?? .other
}
func cleanName(_ raw: String) -> String {
    raw.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"[\\r\\n\\t]+",with:" ",options:.regularExpression)
        .replacingOccurrences(of:"[/：:]",with:"-",options:.regularExpression)
        .replacingOccurrences(of:"[《》“”]",with:"",options:.regularExpression)
        .trimmingCharacters(in:CharacterSet(charactersIn:" .-"))
}
func linesOf(_ file: FileItem) -> [String] {
    file.text.components(separatedBy:.newlines).map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }.filter { !$0.isEmpty }
}
func fieldValues(_ lines: [String], labels: [String]) -> [String] {
    var values: [String] = []
    for (i,line) in lines.prefix(3000).enumerated() {
        for label in labels {
            let spaced = label.map { NSRegularExpression.escapedPattern(for:String($0)) }.joined(separator:"\\s*")
            guard let range = line.range(of:"^"+spaced+"\\s*[：:]\\s*",options:.regularExpression) else { continue }
            let tail = String(line[range.upperBound...]).trimmingCharacters(in:.whitespaces)
            let value = tail.isEmpty && i+1 < lines.count ? lines[i+1] : tail
            let clean = cleanName(value)
            if clean.count >= 4 && clean.count <= 120 && !clean.contains("：") && !clean.contains(":") { values.append(clean) }
        }
    }
    return values
}
func projectIdentity(_ raw: String) -> String {
    var value = cleanName(raw)
    value = value.replacingOccurrences(of:"^(?:投标文件|响应文件|应答文件|解决方案|技术方案|建设方案|招标文件|采购文件)[\\s—_-]+",with:"",options:.regularExpression)
    value = value.replacingOccurrences(of:"[\\s—_（(]*(?:投标文件|响应文件|应答文件)[\\s—_-]*[（(](?:商务|技术|报价)(?:部分|文件|标)?[）)]$",with:"",options:.regularExpression)
    value = value.replacingOccurrences(of:"[\\s—_（(]*(?:投标文件|响应文件|应答文件|招标文件|采购文件|解决方案|技术方案|建设方案|方案|建议书|RFP文件|RFP)[）)]*$",with:"",options:[.regularExpression,.caseInsensitive])
    return cleanName(value)
}
func validProjectIdentity(_ name: String) -> Bool {
    let generic: Set<String> = ["招标文件","投标文件","响应文件","应答文件","解决方案","技术方案","建设方案","项目名称","采购项目名称","技术部分","商务部分","报价清单","目录","项目","采购需求说明"]
    return name.count >= 4 && name.count <= 120 && !generic.contains(name) && !name.contains("：") && !name.contains(":") && !name.contains("。") && !name.contains("……") && name.range(of:"^(?:第[一二三四五六七八九十0-9]+[章节条]|项目编号|采购编号|招标编号|采购人|投标人|法定代表人|供应商|编制单位|日期|根据|本项目|本文件|本方案|本次|投标须知|供应商须知|招标范围|服务要求|资格要求)",options:.regularExpression) == nil
}
func namingHeadingLines(_ file: FileItem) -> [String] {
    file.text.components(separatedBy:"\u{000C}").flatMap { page in
        page.components(separatedBy:.newlines).map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(30)
    }
}
func projectNames(_ file: FileItem) -> [String] {
    let lines = linesOf(file)
    var names = fieldValues(lines,labels:["项目名称","工程名称","采购项目名称","招标项目名称","项目全称"])
    names += fieldValues(lines,labels:["方案名称","文件标题","文档标题","标题"]).map(projectIdentity)
    let headings = namingHeadingLines(file)
    for (i,line) in headings.enumerated() {
        if line.contains("：") || line.contains(":") { continue }
        let value = projectIdentity(line)
        if validProjectIdentity(value), line.contains("项目") || line.contains("工程") || line.hasSuffix("方案") || line.hasSuffix("建议书") {
            names.append(value)
        }
        // Common cover layout: project name and document type occupy separate lines.
        if ["投标文件","响应文件","应答文件","招标文件","采购文件","解决方案","技术方案"].contains(line), i > 0 {
            let previous = projectIdentity(headings[i-1])
            if validProjectIdentity(previous), !previous.hasSuffix("公司"), !previous.hasSuffix("委员会"), previous.range(of:"^[0-9年月日 .-]+$",options:.regularExpression) == nil { names.append(previous) }
        }
    }
    var seen = Set<String>()
    return names.map(projectIdentity).filter { validProjectIdentity($0) && seen.insert($0).inserted }
}
func hasNamingIdentity(_ file: FileItem) -> Bool {
    if !projectNames(file).isEmpty { return true }
    // A generic document needs its own explicit title; generic cover labels never suffice.
    if namingCategory(file) == .other {
        return !fieldValues(linesOf(file),labels:["文件标题","文档标题","标题"]).isEmpty
    }
    return false
}
func titleCandidates(_ file: FileItem) -> [String] {
    let lines = linesOf(file)
    let fields = fieldValues(lines,labels:["文件标题","文档标题","标题","方案名称"])
    let ignored: Set<String> = ["目录","目 录","正文","封面","技术方案","招标文件","投标文件","商务部分","技术部分","方案","项目名称","采购人","供应商"]
    let headings = lines.prefix(20).filter { line in
        line.count >= 5 && line.count <= 100 && !ignored.contains(line) && !line.contains("：") && !line.contains(":") && !line.contains("……") && !line.contains("。") &&
        line.range(of:"^(第[一二三四五六七八九十0-9]+[章节条]|[0-9]{4}[年./-]|法定代表人|编制单位|联系人|联系电话)",options:.regularExpression) == nil &&
        !(line.hasSuffix("公司") || line.hasSuffix("有限公司"))
    }.map(cleanName)
    return Array((fields + headings).prefix(5))
}
func namingCategory(_ file: FileItem) -> DocumentCategory {
    let category = documentCategory(file)
    if category != .other { return category }
    let headings = namingHeadingLines(file).filter { $0.count <= 100 && !$0.contains("。") && !$0.contains("：") && !$0.contains(":") }
    // Cover headings beat references to another document later in the body.
    if headings.contains(where:{ $0.hasSuffix("投标文件") || $0.hasSuffix("响应文件") || $0.hasSuffix("应答文件") }) { return .bid }
    if headings.contains(where:{ $0.hasSuffix("方案") || $0.hasSuffix("建议书") }) { return .proposal }
    if headings.contains(where:{ $0.hasSuffix("招标文件") || $0.hasSuffix("采购文件") || $0.hasSuffix("磋商文件") }) { return .tender }
    return .other
}
func folderSuggestions(files: [FileItem]) -> [Suggestion] {
    var ranked: [(String,String,Int)] = []
    let sorted = files.sorted { a,b in
        let x = namingCategory(a) == .tender ? 0 : namingCategory(a) == .proposal ? 1 : 2
        let y = namingCategory(b) == .tender ? 0 : namingCategory(b) == .proposal ? 1 : 2
        return x == y ? a.path < b.path : x < y
    }
    for file in sorted {
        let lines = linesOf(file)
        if namingCategory(file) == .tender {
            for name in fieldValues(lines,labels:["项目名称","工程名称","采购项目名称","招标项目名称","项目全称"]) { ranked.append((projectIdentity(name),"招标文件中的项目名称 · "+file.name,0)) }
            for name in projectNames(file) { ranked.append((name,"招标文件封面项目名称 · "+file.name,1)) }
            for title in titleCandidates(file) where title.contains("项目") || title.contains("工程") {
                let value = title.replacingOccurrences(of:"[（(]?招标文件[）)]?$",with:"",options:.regularExpression)
                ranked.append((cleanName(value),"招标文件标题 · "+file.name,1))
            }
        }
        if namingCategory(file) == .proposal {
            for title in titleCandidates(file) { ranked.append((title,"方案标题 · "+file.name,2)) }
            let stem = file.url.deletingPathExtension().lastPathComponent
            if stem.count >= 5 { ranked.append((cleanName(stem),"方案文件名称 · "+file.name,3)) }
        }
        let units = fieldValues(lines,labels:["建设单位","采购人","招标人","客户名称","单位名称","业主单位"]) + lines.prefix(60).filter { $0.count >= 5 && $0.count <= 50 && ($0.hasSuffix("有限公司") || $0.hasSuffix("委员会") || $0.hasSuffix("管理局")) }
        let key = fieldValues(lines,labels:["方案名称","关键方案名称","建设内容"]).first ?? titleCandidates(file).first { $0.contains("方案") || $0.contains("建设") || $0.contains("系统") || $0.contains("服务") }
        if let unit = units.first, let key {
            ranked.append((cleanName(key.contains(unit) ? key : unit+" "+key),"单位名称＋关键方案名称 · "+file.name,4))
        }
    }
    var seen = Set<String>()
    return ranked.sorted { $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 < $1.2 }.compactMap { name,evidence,_ in
        let name = cleanName(name); guard name.count >= 4, !seen.contains(name) else { return nil }; seen.insert(name)
        return Suggestion(name:name,evidence:evidence)
    }.prefix(8).map { $0 }
}
func fileSuggestions(file: FileItem, context: [Suggestion] = []) -> [Suggestion] {
    let category = namingCategory(file)
    let prefix: String? = category == .bid ? "投标文件-" : category == .proposal ? "解决方案-" : category == .tender ? "招标文件-" : nil
    var values: [Suggestion] = []
    if let prefix {
        for name in projectNames(file) { values.append(Suggestion(name:prefix+name,evidence:"前页项目名称／标题 · "+file.name)) }
        if values.isEmpty {
            for suggestion in context {
                let name = projectIdentity(suggestion.name)
                if validProjectIdentity(name) { values.append(Suggestion(name:prefix+name,evidence:"同项目参考 · "+suggestion.evidence)) }
            }
            let stem = projectIdentity(file.url.deletingPathExtension().lastPathComponent)
            if validProjectIdentity(stem), stem.contains("项目") || stem.contains("工程") || stem.contains("服务") || stem.contains("系统") {
                values.append(Suggestion(name:prefix+stem,evidence:"原文件名中的项目名称（请核对） · "+file.name))
            }
        }
    }
    for title in titleCandidates(file) {
        let name = projectIdentity(title)
        guard validProjectIdentity(name) else { continue }
        if prefix != nil && !["项目","工程","系统","服务","建设","改造","升级","平台"].contains(where:name.contains) { continue }
        values.append(Suggestion(name:prefix.map { $0+name } ?? title,evidence:"文档自身标题 · "+file.name))
    }
    var seen = Set<String>()
    return values.filter { seen.insert($0.name).inserted }.prefix(8).map { $0 }
}
func suggestedMonth(_ path: String) -> Int {
    let name = URL(fileURLWithPath:path).lastPathComponent
    if let match = name.range(of:"^(1[0-2]|[1-9])(?=月|\\s|[^0-9]|$)",options:.regularExpression), let n = Int(name[match]) { return n }
    let date = (try? URL(fileURLWithPath:path).resourceValues(forKeys:[.creationDateKey]).creationDate) ?? Date()
    var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(identifier:"Asia/Shanghai")!
    return calendar.component(.month,from:date)
}
func proposedName(base: String, month: Int, folder: Bool, original: String) -> String {
    if folder {
        let stem = base.replacingOccurrences(of:"^\\s*(1[0-2]|[1-9])月\\s*",with:"",options:.regularExpression).trimmingCharacters(in:.whitespaces)
        return "\(month)月 "+stem
    }
    let ext = URL(fileURLWithPath:original).pathExtension
    let stem = base.hasSuffix("."+ext) && !ext.isEmpty ? String(base.dropLast(ext.count+1)) : base
    return stem + (ext.isEmpty ? "" : "."+ext)
}
func remapPath(_ path: String, source: String, destination: String, folder: Bool) -> String {
    if path == source { return destination }
    if folder && path.hasPrefix(source+"/") { return destination+path.dropFirst(source.count) }
    return path
}
@MainActor extension Store {
    func loadSuggestions(_ target: NamingTarget, token: IndexCancellation, completion: @escaping ([Suggestion]) -> Void) {
        let root = settings.root
        let candidates: [FileItem]
        if target.folder {
            let indexed = namingFiles.filter { $0.path.hasPrefix(target.path+"/") }
            let matching = indexed.isEmpty ? metadataFiles(target.path,project:target.path,recursive:true,cache:[:]) : indexed
            let priority = matching.sorted { a,b in
                let x = namingCategory(a) == .tender ? 0 : namingCategory(a) == .proposal ? 1 : 2
                let y = namingCategory(b) == .tender ? 0 : namingCategory(b) == .proposal ? 1 : 2
                return x == y ? a.size < b.size : x < y
            }
            // Include tender, proposal and fallback evidence without parsing the whole project library.
            let tenderFiles = Array(priority.filter { documentCategory($0) == .tender }.prefix(5))
            let proposalFiles = Array(priority.filter { documentCategory($0) == .proposal }.prefix(3))
            let otherFiles = Array(priority.filter { documentCategory($0) == .other }.prefix(2))
            let bidFiles = Array(priority.filter { documentCategory($0) == .bid }.prefix(2))
            candidates = tenderFiles + proposalFiles + otherFiles + bidFiles
        } else {
            let existing = (files+incoming).first { $0.path == target.path }
            candidates = [existing ?? browserEntry(target.path)?.file].compactMap { $0 }
        }
        let references = target.folder ? [] : namingFiles.filter { $0.project == target.projectPath && $0.path != target.path }
        DispatchQueue.global(qos:.utility).async {
            var parsed: [FileItem] = []
            for var file in candidates {
                guard !token.isCancelled else { return }
                file.text = autoreleasepool { extractForNaming(file,token:token) }; parsed.append(file)
            }
            var context: [Suggestion] = []
            if !target.folder, let file = parsed.first, projectNames(file).isEmpty, [.bid,.proposal].contains(namingCategory(file)) {
                let tenders = references.filter { documentCategory($0) == .tender }.sorted { $0.size < $1.size }.prefix(3)
                let plans = references.filter { documentCategory($0) == .proposal }.sorted { $0.size < $1.size }.prefix(2)
                for var reference in Array(tenders) + Array(plans) {
                    guard !token.isCancelled else { return }
                    reference.text = autoreleasepool { extractForNaming(reference,token:token) }
                    let found = folderSuggestions(files:[reference])
                    if !found.isEmpty { context = found; break }
                }
            }
            let suggestions = target.folder ? folderSuggestions(files:parsed) : parsed.first.map { fileSuggestions(file:$0,context:context) } ?? []
            DispatchQueue.main.async {
                guard !token.isCancelled else { return }; guard self.settings.root == root else { completion([]); return }
                completion(suggestions)
            }
        }
    }
    func validateRename(_ target: NamingTarget, newName: String, requireMonth: Bool) throws -> String {
        let source = target.path; let trimmed = newName.trimmingCharacters(in:.whitespacesAndNewlines)
            if target.folder && settings.projects.contains(where: { $0.path == source && $0.shallow == true }) { throw namingError("左侧目录不参与项目命名，请选择其中的具体项目文件夹。") }
            if target.folder && requireMonth, trimmed.range(of:"^(1[0-2]|[1-9])月\\s*.+$",options:.regularExpression) == nil { throw namingError("文件夹名称必须以 1月 至 12月 开头。") }
            guard !busy else { throw namingError("当前归档尚未完成，请完成后再确认命名。") }
            guard !trimmed.isEmpty, trimmed != ".", trimmed != "..", !trimmed.contains("/"), !trimmed.contains(":"), !trimmed.contains("\0"), !trimmed.contains("\n") else { throw namingError("名称不能包含斜杠、冒号或换行，请修改后重试。") }
            guard target.identity != nil, target.identity == fileIdentity(source) else { throw namingError("源文件或文件夹已被替换，请关闭窗口重新选择。") }
            if !target.folder, let modified = target.modified, (try? URL(fileURLWithPath:source).resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) != modified { throw namingError("文档已更新，请重新读取标题后命名。") }
            let destination = URL(fileURLWithPath:source).deletingLastPathComponent().appendingPathComponent(trimmed).path
            if destination == source { return destination }
            guard !fm.fileExists(atPath:destination) else { throw namingError("同目录已有这个名称，请修改名称；现有文件不会被覆盖。") }
        return destination
    }
    @discardableResult func confirmRename(_ target: NamingTarget, newName: String, requireMonth: Bool = true) -> Bool {
        let source = target.path; let trimmed = newName.trimmingCharacters(in:.whitespacesAndNewlines)
        do {
            let destination = try validateRename(target,newName:newName,requireMonth:requireMonth)
            if destination == source { return true }
            try fm.moveItem(atPath:source,toPath:destination)
            func map(_ path: String) -> String { remapPath(path,source:source,destination:destination,folder:target.folder) }
            settings.projects = settings.projects.map { p in var p = p; p.path = map(p.path); if p.path == destination { p.name = trimmed }; return p }
            for i in settings.moves.indices { settings.moves[i].source = map(settings.moves[i].source); settings.moves[i].destination = map(settings.moves[i].destination) }
            if let arrivals = settings.arrivals { settings.arrivals = Dictionary(arrivals.map { (map($0.key),$0.value) },uniquingKeysWith:{a,_ in a}) }
            remapCategoryAssignments(source:source,destination:destination,folder:target.folder)
            settings.renames = (settings.renames ?? []) + [RenameRecord(source:source,destination:destination,folder:target.folder,identity:fileIdentity(destination))]
            func mapFile(_ file: FileItem) -> FileItem { var f = file; f.path = map(f.path); f.project = map(f.project); return f }
            files = files.map(mapFile); incoming = incoming.map(mapFile)
            cache = Dictionary(cache.values.map(mapFile).map { ($0.path,$0) },uniquingKeysWith:{a,_ in a})
            projectCounts = Dictionary(files.map { ($0.project,1) },uniquingKeysWith:+)
            selected = map(selected); save(); message = "已确认命名："+trimmed
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
func namingError(_ message: String) -> NSError { NSError(domain:"命名",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }

@MainActor func namingTest(root: URL) throws {
    let dir = root.appendingPathComponent("Naming/10 A"); try fm.createDirectory(at:dir,withIntermediateDirectories:true)
    let tenderPath = dir.appendingPathComponent("招标文件.txt")
    let tender = "招标文件\n项目名称：贵阳智慧园区建设项目\n采购人：贵阳园区管理有限公司"
    try tender.write(to:tenderPath,atomically:true,encoding:.utf8)
    let planPath = dir.appendingPathComponent("网络建设方案.txt")
    try "园区网络升级建设方案\n\n建设单位：某某园区管理有限公司".write(to:planPath,atomically:true,encoding:.utf8)
    let parsed = scan(dir.path,project:dir.path,recursive:true)
    try verify(folderSuggestions(files:parsed).first?.name == "贵阳智慧园区建设项目","Tender project name must win over proposal title")
    let proposal = parsed.filter { $0.path == planPath.path }
    try verify(folderSuggestions(files:proposal).first?.name == "园区网络升级建设方案","Proposal title is the next fallback")
    var fallback = parsed[0]; fallback.path = dir.appendingPathComponent("说明.txt").path; fallback.text = "单位名称：贵阳园区管理有限公司\n方案名称：网络安全改造"
    // Explicit proposal-name data without a proposal file is combined with the customer name.
    try verify(folderSuggestions(files:[fallback]).first?.name == "贵阳园区管理有限公司 网络安全改造")
    try verify(fileSuggestions(file:proposal[0]).first?.name == "解决方案-园区网络升级")
    try verify(suggestedMonth(dir.path) == 10)
    try verify(proposedName(base:"10月 贵阳智慧园区建设项目",month:5,folder:true,original:dir.path) == "5月 贵阳智慧园区建设项目")
    try verify(proposedName(base:"园区网络升级建设方案",month:5,folder:false,original:planPath.path) == "园区网络升级建设方案.txt")
    var response = FileItem(path:dir.appendingPathComponent("附件3响应文件.docx").path,project:dir.path,text:"响应文件\n项 目 名 称 ： 贵阳智慧园区建设项目\n根据招标文件要求编制",size:1,date:Date())
    try verify(fileSuggestions(file:response).first?.name == "投标文件-贵阳智慧园区建设项目","Response uses standardized bid name and spaced project label")
    response.text = "响应文件\n项目名称：\n贵阳智慧园区建设项目\n采购人：测试单位"
    try verify(fileSuggestions(file:response).first?.name == "投标文件-贵阳智慧园区建设项目","Multiline project fields are supported")
    response.path = dir.appendingPathComponent("附件3.docx").path
    response.text = "贵阳智慧园区建设项目\n响应文件\n根据招标文件要求编制"
    try verify(namingCategory(response) == .bid && fileSuggestions(file:response).first?.name == "投标文件-贵阳智慧园区建设项目","Own response cover must beat references to tender")
    response.text = "响应文件\n技术部分\n目录"
    try verify(!hasNamingIdentity(response),"Generic cover and section labels must trigger further reading")
    response.text = "解决方案-园区网络升级\n方案名称：解决方案-园区网络升级"
    response.path = dir.appendingPathComponent("解决方案-园区网络升级.docx").path
    try verify(fileSuggestions(file:response).first?.name == "解决方案-园区网络升级","Repeated naming must not duplicate the type prefix")
    response.path = dir.appendingPathComponent("响应文件.docx").path; response.text = "响应文件\n技术部分"
    try verify(fileSuggestions(file:response,context:[Suggestion(name:"贵阳智慧园区建设项目",evidence:"招标文件中的项目名称")]).first?.name == "投标文件-贵阳智慧园区建设项目","Missing own name can use tender identity from same project")
    try namingReadingTest(root:root)
    let store = Store(stateURL:root.appendingPathComponent("NamingState/settings.json"),loadOnLaunch:false)
    store.settings.root = dir.deletingLastPathComponent().path; store.settings.projects = [Project(path:dir.path,name:"10 A")]; store.files = parsed
    let target = NamingTarget(path:dir.path,folder:true,projectPath:dir.path)
    _ = folderSuggestions(files:parsed); try verify(fm.fileExists(atPath:dir.path),"Suggestions must not rename without confirmation")
    try verify(!store.confirmRename(target,newName:"无月份名称")); store.error = ""
    let name = "10月 贵阳智慧园区建设项目"
    try verify(store.confirmRename(target,newName:name))
    let newDir = dir.deletingLastPathComponent().appendingPathComponent(name)
    try verify(!fm.fileExists(atPath:dir.path) && fm.fileExists(atPath:newDir.path))
    try verify(store.files.allSatisfy { $0.path.hasPrefix(newDir.path+"/") && $0.project == newDir.path })
    let doc = newDir.appendingPathComponent("网络建设方案.txt")
    let document = NamingTarget(path:doc.path,folder:false,projectPath:newDir.path)
    try verify(!store.confirmRename(document,newName:"招标文件.txt"),"Existing files must not be overwritten"); store.error = ""
    try verify(store.confirmRename(document,newName:"园区网络升级建设方案.txt"))
    try verify(fm.fileExists(atPath:newDir.appendingPathComponent("园区网络升级建设方案.txt").path))
    try verify(store.settings.renames?.count == 2)
    try verify(remapPath("/x/AB/f.txt",source:"/x/A",destination:"/x/B",folder:true) == "/x/AB/f.txt")
    let file = FileItem(path:"/project/投标文件/方案.docx",project:"/project",text:"",size:1,date:Date())
    try verify(documentCategory(file) == .proposal)
    var bid = file; bid.path = "/project/投标文件/技术响应.docx"; try verify(documentCategory(bid) == .bid)
    var notice = file; notice.path = "/project/采购公告.pdf"; try verify(documentCategory(notice) == .tender)
    print("PASS: naming priorities, month prefix, editable-title extension preservation, confirmation-only physical rename, collision protection, path remapping")
}
