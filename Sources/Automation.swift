import Foundation

struct Arrival: Codable {
    var firstSeen: Date; var changedAt: Date; var size: Int64; var modified: Date; var identity: String?; var eligible: Bool
}
func observedArrival(previous: Arrival?, size: Int64, modified: Date, identity: String?, now: Date, baseline: Bool) -> Arrival {
    if let previous, previous.size == size, previous.modified == modified, previous.identity == identity { return previous }
    return Arrival(firstSeen:now,changedAt:now,size:size,modified:modified,identity:identity,eligible:baseline ? false : (previous != nil && previous?.identity == identity ? previous!.eligible : true))
}
func stableForArchive(_ f: FileItem, arrival: Arrival, now: Date) -> Bool {
    arrival.eligible && now.timeIntervalSince(arrival.changedAt) >= 15 && now.timeIntervalSince(f.date) >= 15 && arrival.size == f.size && arrival.modified == f.date && arrival.identity == fileIdentity(f.path)
}
struct AutoMatch { var project: Project; var evidence: String }
func confidentMatch(_ file: FileItem, projects: [Project], references: [FileItem]) -> AutoMatch? {
    let content = (file.url.deletingPathExtension().lastPathComponent + "\n" + file.text).lowercased()
    let generic: Set<String> = ["建设项目","采购项目","信息化建设项目","合同项目","项目说明","采购工程","系统建设项目"]
    var matches: [AutoMatch] = []
    for p in projects where p.shallow != true {
        var terms = [p.name,URL(fileURLWithPath:p.path).lastPathComponent] + recommendations(p,files:references).map(\.name)
        let keywords = p.keywords.components(separatedBy:CharacterSet(charactersIn:",，;；\n")).map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
        let idPattern = "(?:项目编号|合同编号|招标编号|采购编号)[：:\\s]*([A-Za-z0-9][A-Za-z0-9_./—-]{3,})"
        if let regex = try? NSRegularExpression(pattern:idPattern) {
            for ref in references.filter({ $0.project == p.path }).prefix(30) {
                let text = ref.text as NSString
                terms += regex.matches(in:ref.text,range:NSRange(location:0,length:text.length)).map { text.substring(with:$0.range(at:1)) }
            }
        }
        terms += keywords
        let hits = Set(terms).filter { term in
            guard !generic.contains(term), content.contains(term.lowercased()) else { return false }
            let identifier = term.count >= 5 && term.rangeOfCharacter(from:.decimalDigits) != nil && term.range(of:"[A-Za-z]",options:.regularExpression) != nil
            let title = term.count >= 8 && (term.hasSuffix("项目") || term.hasSuffix("工程"))
            if identifier {
                let pattern = "(?<![A-Za-z0-9_./—-])" + NSRegularExpression.escapedPattern(for:term) + "(?![A-Za-z0-9_./—-])"
                return content.range(of:pattern,options:[.regularExpression,.caseInsensitive]) != nil
            }
            return title
        }
        if !hits.isEmpty { matches.append(AutoMatch(project:p,evidence:hits.sorted().joined(separator:"、"))) }
    }
    return matches.count == 1 ? matches[0] : nil
}

func fileTime(_ file: FileItem, by order: String, settings: Settings) -> Date {
    guard order == "最近到达" else { return file.date }
    if let record = settings.moves.first(where:{ !$0.undone && $0.destination == file.path }) { return record.arrivedAt ?? record.date }
    return settings.arrivals?[file.path]?.firstSeen ?? file.date
}
func sortedFiles(_ files: [FileItem], by order: String, settings: Settings) -> [FileItem] {
    files.sorted { a,b in
        if order == "名称 A–Z" { return a.name == b.name ? a.path < b.path : a.name.localizedStandardCompare(b.name) == .orderedAscending }
        let x = fileTime(a,by:order,settings:settings), y = fileTime(b,by:order,settings:settings)
        if x == y { return a.path < b.path }
        return order == "最早修改" ? x < y : x > y
    }
}

@MainActor func automationTest(root: URL) throws {
    let projectDir = root.appendingPathComponent("AutoProject"); let inbox = root.appendingPathComponent("AutoInbox")
    try fm.createDirectory(at:projectDir,withIntermediateDirectories:true); try fm.createDirectory(at:inbox,withIntermediateDirectories:true)
    let project = Project(path:projectDir.path,name:"A")
    let referenceURL = projectDir.appendingPathComponent("说明.txt")
    try "项目名称：南山智慧园区建设项目\n项目编号：NS-2026-001".write(to:referenceURL,atomically:true,encoding:.utf8)
    let refs = scan(projectDir.path,project:project.path,recursive:true)
    let store = Store(stateURL:root.appendingPathComponent("isolated/settings.json"),loadOnLaunch:false)
    store.settings.root = root.path; store.settings.inbox = inbox.path; store.settings.projects = [project]; store.files = refs
    let baselineURL = inbox.appendingPathComponent("旧资料.txt")
    try "南山智慧园区建设项目".write(to:baselineURL,atomically:true,encoding:.utf8)
    try fm.setAttributes([.modificationDate:Date().addingTimeInterval(-60)],ofItemAtPath:baselineURL.path)
    store.observeInbox(); try verify(store.settings.arrivals?[baselineURL.path]?.eligible == false, "baseline keys \(Array((store.settings.arrivals ?? [:]).keys)) expected \(baselineURL.path)")
    let newURL = inbox.appendingPathComponent("新下载.txt")
    try "南山智慧园区建设项目\n本次进度更新".write(to:newURL,atomically:true,encoding:.utf8)
    try fm.setAttributes([.modificationDate:Date().addingTimeInterval(-60)],ofItemAtPath:newURL.path)
    store.observeInbox(); store.incoming = scan(inbox.path,project:"",recursive:false)
    let oldFile = store.incoming.first { $0.path == baselineURL.path }!
    try verify(readyForManualArchive(oldFile,arrival:store.settings.arrivals![baselineURL.path]!,now:Date()),"Explicit click may process existing stable files")
    let newFile = store.incoming.first { $0.path == newURL.path }!
    try verify(confidentMatch(newFile,projects:[project],references:refs)?.project.path == project.path)
    let conflicting = Project(path:root.appendingPathComponent("Other").path,name:"南山智慧园区建设项目")
    try verify(confidentMatch(newFile,projects:[project,conflicting],references:refs) == nil)
    var unknown = newFile; unknown.text = "没有项目标识的普通文件"; unknown.path = inbox.appendingPathComponent("unknown.txt").path
    try verify(confidentMatch(unknown,projects:[project],references:refs) == nil)
    var prefixFile = newFile; prefixFile.text = "项目编号：NS-2026-0012"; prefixFile.path = inbox.appendingPathComponent("prefix.txt").path
    try verify(confidentMatch(prefixFile,projects:[project],references:refs) == nil)
    prefixFile.text = "项目编号：NS-2026-001-A"
    try verify(confidentMatch(prefixFile,projects:[project],references:refs) == nil)
    let oldArrival = store.settings.arrivals![baselineURL.path]!
    let editedOld = observedArrival(previous:oldArrival,size:oldArrival.size+1,modified:Date(),identity:oldArrival.identity,now:Date(),baseline:false)
    try verify(!editedOld.eligible)
    store.processAutomatic(); try verify(fm.fileExists(atPath:newURL.path),"No archive may run without an explicit click")
    store.settings.arrivals?[newURL.path]?.changedAt = Date().addingTimeInterval(-20)
    let arrival = store.settings.arrivals![newURL.path]!
    try verify(stableForArchive(newFile,arrival:arrival,now:Date()))
    var changed = arrival; changed.size += 1; try verify(!stableForArchive(newFile,arrival:changed,now:Date()))
    let restarted = try JSONDecoder().decode(Settings.self,from:JSONEncoder().encode(store.settings)); try verify(!restarted.autoArchive && restarted.baselineInbox == inbox.path)
    store.incoming.removeAll { $0.path == baselineURL.path }; store.processAutomatic(manualRun:true); try verify(!fm.fileExists(atPath:newURL.path)); try verify(fm.fileExists(atPath:baselineURL.path))
    let move = store.settings.moves[0]; try verify(move.automatic == true && move.arrivedAt != nil && move.evidence?.contains("南山") == true)
    try verify(fm.fileExists(atPath:move.destination)); try verify(store.files.contains { $0.path == move.destination })
    let newest = sortedFiles(store.files,by:"最近到达",settings:store.settings)[0]; try verify(newest.path == move.destination)
    store.undo(move,refreshAfter:false); try verify(fm.fileExists(atPath:newURL.path)); try verify(store.settings.moves[0].undone)
    store.incoming = scan(inbox.path,project:"",recursive:false); store.processAutomatic(manualRun:true); try verify(fm.fileExists(atPath:newURL.path),"Undo must prevent immediate automatic re-archive")
    let persisted = try JSONDecoder().decode(Settings.self,from:Data(contentsOf:store.stateURL)); try verify(persisted.moves.first(where: { $0.id == move.id })?.undone == true && !(persisted.suppressed ?? []).isEmpty)
    try verify(!fm.fileExists(atPath:baselineURL.path),"An explicit click also archives matching existing files")
    let legacy = Data("{\"root\":\"\",\"inbox\":\"\",\"projects\":[],\"moves\":[],\"autoArchive\":false}".utf8)
    let decodedLegacy = try JSONDecoder().decode(Settings.self,from:legacy); try verify(decodedLegacy.arrivals == nil)
}

func verify(_ condition: @autoclosure () -> Bool, _ message: String = "", line: Int = #line) throws {
    if !condition() { throw NSError(domain:"AutomationTest",code:line,userInfo:[NSLocalizedDescriptionKey:"line \(line): \(message)"]) }
}

func readyForManualArchive(_ file: FileItem, arrival: Arrival, now: Date) -> Bool {
    now.timeIntervalSince(file.date) >= 15 && arrival.size == file.size && arrival.modified == file.date && arrival.identity == fileIdentity(file.path)
}
