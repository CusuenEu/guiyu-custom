import SwiftUI
import AppKit
import PDFKit
import QuickLookUI
import Vision
import Darwin

struct Project: Identifiable, Codable, Hashable {
    var id: String { path }; var path: String; var name: String; var keywords: String = ""; var group: String? = nil; var shallow: Bool? = nil; var modifiedAt: Date? = nil; var directoryPath: String? = nil
    var scopeID: String { directoryPath ?? group ?? "" }
}
struct FileItem: Identifiable, Hashable, Codable {
    var id: String { path }; var path: String; var project: String; var text: String; var size: Int64; var date: Date
    var url: URL { URL(fileURLWithPath: path) }; var name: String { url.lastPathComponent }
    var ext: String { url.pathExtension.lowercased() }
    var symbol: String { ["pdf":"doc.richtext", "docx":"doc.text", "doc":"doc.text", "xlsx":"tablecells", "xls":"tablecells", "png":"photo", "jpg":"photo", "jpeg":"photo" ][ext] ?? "doc.plaintext" }
    var tint: Color { ["pdf":Color(red:0.76,green:0.30,blue:0.25),"docx":.blue,"doc":.blue,"xlsx":.green,"xls":.green][ext] ?? .secondary }
}
struct MoveRecord: Identifiable, Codable { var id = UUID(); var source: String; var destination: String; var date = Date(); var undone = false; var identity: String? = nil; var arrivedAt: Date? = nil; var automatic: Bool? = nil; var evidence: String? = nil; var folder: Bool? = nil }
struct Settings: Codable { var root = ""; var projectRoots: [String]? = nil; var inbox = ""; var projects: [Project] = []; var moves: [MoveRecord] = []; var autoArchive = true; var automationVersion: Int? = nil; var baselineInbox: String? = nil; var arrivals: [String:Arrival]? = nil; var suppressed: [String]? = nil; var renames: [RenameRecord]? = nil; var categories: [WorkspaceCategory]? = nil; var namingRules: NamingRuleSettings? = nil; var categoryAssignments: [String:CategoryAssignment]? = nil; var archiveSources: [ArchiveSource]? = nil; var directoryOrders: [String:[String]]? = nil; var sidebarProjectsFraction: Double? = nil }
struct Suggestion: Identifiable { var id: String { name }; var name: String; var evidence: String }

let accent = Color(red:0.14,green:0.38,blue:0.30)
let fm = FileManager.default
let supported: Set<String> = ["pdf","docx","doc","xlsx","xls","txt","md","csv","rtf","png","jpg","jpeg","heic","tiff"]
func run(_ executable: String, _ arguments: [String]) -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = arguments
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    do {
        p.standardInput = FileHandle.nullDevice; try p.run()
        let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+20,execute:timeout)
        defer { timeout.cancel() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(data:data,encoding:.utf8) ?? ""
    } catch { return "" }
}
func ocr(_ image: CGImage) -> String {
    let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "en-US"]; request.usesLanguageCorrection = true
    do { try VNImageRequestHandler(cgImage:image).perform([request]); return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator:"\n") } catch { return "" }
}
func extract(_ url: URL) -> String {
    let ext = url.pathExtension.lowercased()
    if ext == "pdf", let document = PDFDocument(url:url) {
        let text = document.string ?? ""
        if text.trimmingCharacters(in:.whitespacesAndNewlines).count > 30 { return String(text.prefix(100000)) }
        return (0..<min(document.pageCount,8)).compactMap { i -> String? in
            guard let page = document.page(at:i) else { return nil }
            let image = page.thumbnail(of:NSSize(width:1400,height:1800),for:.mediaBox)
            guard let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return nil }; return ocr(cg)
        }.joined(separator:"\n")
    }
    if ["png","jpg","jpeg","heic","tiff"].contains(ext), let image = NSImage(contentsOf:url), let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) { return ocr(cg) }
    if ["docx","doc","rtf"].contains(ext) { return String(run("/usr/bin/textutil",["-convert","txt","-stdout",url.path]).prefix(100000)) }
    if ext == "xlsx" {
        let xml = run("/usr/bin/unzip",["-p",url.path,"xl/sharedStrings.xml"]) + run("/usr/bin/unzip",["-p",url.path,"xl/worksheets/sheet1.xml"])
        return String(xml.replacingOccurrences(of:"<[^>]+>",with:" ",options:.regularExpression).prefix(100000))
    }
    if ["txt","md","csv"].contains(ext) { return String(((try? String(contentsOf:url,encoding:.utf8)) ?? "").prefix(100000)) }
    return ""
}
func scan(_ folder: String, project: String, recursive: Bool) -> [FileItem] {
    guard !folder.isEmpty else { return [] }; let base = URL(fileURLWithPath:folder)
    var urls: [URL] = []
    if recursive, let e = fm.enumerator(at:base,includingPropertiesForKeys:[.isRegularFileKey,.fileSizeKey,.contentModificationDateKey],options:[.skipsHiddenFiles,.skipsPackageDescendants]) { for case let u as URL in e { urls.append(u) } }
    else { urls = (try? fm.contentsOfDirectory(at:base,includingPropertiesForKeys:[.isRegularFileKey],options:.skipsHiddenFiles)) ?? [] }
    return urls.compactMap { u in
        guard supported.contains(u.pathExtension.lowercased()), !u.lastPathComponent.hasPrefix("~$"), let v = try? u.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey,.contentModificationDateKey]), v.isRegularFile == true else { return nil }
        return FileItem(path:u.path,project:project,text:extract(u),size:Int64(v.fileSize ?? 0),date:v.contentModificationDate ?? .distantPast)
    }
}
func recommendations(_ project: Project, files: [FileItem]) -> [Suggestion] {
    var votes: [String:(Int,String)] = [:]
    for f in files.filter({ $0.project == project.path }).prefix(30) {
        let lines = Array(f.text.components(separatedBy:.newlines).prefix(60)) + [f.url.deletingPathExtension().lastPathComponent]
        var seen = Set<String>()
        for raw in lines {
            var s = raw.trimmingCharacters(in:.whitespacesAndNewlines)
            s = s.replacingOccurrences(of:"^(项目名称|工程名称|合同名称|项目全称)[：:\\s]*",with:"",options:.regularExpression)
            guard s.count >= 5, s.count <= 55,
                (s.hasSuffix("项目") || s.hasSuffix("工程") || raw.hasPrefix("项目名称") || raw.hasPrefix("工程名称") || raw.hasPrefix("合同名称")),
                !s.contains("。"), !s.contains("项目编号"), !s.contains("项目经理"), !s.contains("项目负责人"), !seen.contains(s) else { continue }
            seen.insert(s); let old = votes[s] ?? (0,f.name); votes[s] = (old.0+1,old.1)
        }
    }
    return votes.sorted { $0.value.0 == $1.value.0 ? $0.key < $1.key : $0.value.0 > $1.value.0 }.prefix(5).map { Suggestion(name:$0.key,evidence:"见于 \($0.value.0) 份文档 · \($0.value.1)") }
}
func score(_ file: FileItem, project: Project) -> (Int,String) {
    let content = (file.name + "\n" + file.text).lowercased()
    let words = ([project.name,URL(fileURLWithPath:project.path).lastPathComponent] + project.keywords.components(separatedBy:CharacterSet(charactersIn:",，;；\n"))).map { $0.trimmingCharacters(in:.whitespaces) }.filter { $0.count >= 3 }
    let hits = Set(words).filter { content.contains($0.lowercased()) }
    return (hits.reduce(0){$0 + min($1.count,20)}, hits.joined(separator:"、"))
}

@MainActor final class Store: ObservableObject {
    @Published var settings = Settings() {
        didSet { if oldValue.workspaceIdentity != settings.workspaceIdentity || oldValue.projects != settings.projects { rebuildFilenameIndex() } }
    }
    @Published var files: [FileItem] = [] { didSet { searchMetadataLoaded = true; rebuildFilenameIndex() } }
    @Published var incoming: [FileItem] = []
    @Published var searchRevision = 0
    let filenameIndex: FilenameSearchIndex
    private var searchMetadataLoaded = false
    @Published var projectCounts: [String:Int] = [:]
    @Published var unavailableProjectRoots: [String] = []
    @Published var metadataReady = false
    @Published var globalRefreshRevision = 0
    @Published var fileOperationRevision = 0
    let progress = IndexProgress()
    var message: String { get { progress.message } set { progress.message = newValue } }
    @Published var busy = false; @Published var error = ""; @Published var selected = "all"
    var cache: [String:FileItem] = [:]; var scanCancellation: IndexCancellation?
    let stateURL: URL
    init(stateURL override: URL? = nil, loadOnLaunch: Bool = true) {
        stateURL = override ?? fm.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Guiyu/settings.json")
        filenameIndex = FilenameSearchIndex(databaseURL:stateURL.deletingLastPathComponent().appendingPathComponent("search-index-v1.sqlite"))
        if let data = try? Data(contentsOf:stateURL), var saved = try? JSONDecoder().decode(Settings.self,from:data) {
            if !saved.root.isEmpty { saved.root = canonicalPath(saved.root) }
            if let roots = saved.projectRoots { saved.projectRoots = roots.map(canonicalPath) }
            settings = saved
        }
        if !fm.fileExists(atPath:stateURL.path) { settings.categories = [] }
        settings.autoArchive = false; settings.automationVersion = 2; save()
        rebuildFilenameIndex()
        if loadOnLaunch { refresh() }
    }
    func rebuildFilenameIndex() {
        // Do not replace a warm disk cache with the temporary empty file array during startup.
        guard searchMetadataLoaded else { return }
        guard searchRevision > 0 || settings.hasProjectRoots || !settings.projects.isEmpty || !files.isEmpty else { return }
        filenameIndex.replace(root:settings.workspaceIdentity,projects:settings.projects,files:files)
        searchRevision += 1
    }
    func save() { do { try fm.createDirectory(at:stateURL.deletingLastPathComponent(),withIntermediateDirectories:true); try JSONEncoder().encode(settings).write(to:stateURL,options:.atomic) } catch { self.error = error.localizedDescription } }
    func choose(_ kind: String) {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.message = kind == "root" ? "选择项目总目录，按磁盘上的真实文件夹显示" : "选择点击检查时需要处理的下载或待归档文件夹"
        guard p.runModal() == .OK, let url = p.url else { return }
        let resolved = canonicalPath(url.path)
        let others = kind == "root" ? [settings.inbox] : settings.activeProjectRoots
        if others.contains(where:{ !$0.isEmpty && (resolved == $0 || resolved.hasPrefix($0+"/") || $0.hasPrefix(resolved+"/")) }) { error = "项目目录与待归档目录不能重叠，请选择独立的文件夹。"; return }
        if kind == "root" {
            let oldRoot = settings.root; var roots = settings.activeProjectRoots.filter { $0 != oldRoot && $0 != resolved }; roots.insert(resolved,at:0)
            if roots.dropFirst().contains(where:{ $0.hasPrefix(resolved+"/") || resolved.hasPrefix($0+"/") }) { error = "项目总目录不能互相嵌套。"; return }
            settings.root = resolved; settings.projectRoots = roots; settings.projects = []; files = []; cache = [:]
        } else { settings.inbox = resolved; incoming = [] }
        scanCancellation?.cancel(); busy = false; save(); refresh()
    }
    func refresh(includeInbox: Bool = false, archiveRequested: Bool = false) {
        guard !busy else { return }; busy = true; metadataReady = false
        let token = IndexCancellation(); scanCancellation = token
        let roots = settings.activeProjectRoots; let workspaceID = settings.workspaceIdentity; let inbox = settings.inbox; let old = settings.projects; let previous = cache
        if includeInbox { observeInbox() }
        DispatchQueue.global(qos:.utility).async {
            let snapshot: ProjectRootsSnapshot
            do { snapshot = try discoverProjectRoots(roots,saved:old) }
            catch {
                DispatchQueue.main.async {
                    guard !token.isCancelled else { return }; guard self.settings.workspaceIdentity == workspaceID else { self.busy = false; self.refresh(); return }
                    self.busy = false; self.message = "无法读取项目目录，请检查磁盘连接与访问权限；已有配置已保留。"
                    self.error = "无法读取项目目录：\(error.localizedDescription)"
                }; return
            }
            let projects = snapshot.projects
            // Publish folders before enumerating or parsing any document.
            DispatchQueue.main.async {
                guard !token.isCancelled else { return }; guard self.settings.workspaceIdentity == workspaceID else { return }
                self.unavailableProjectRoots = snapshot.unavailable
                self.settings.projects = projects.map { candidate in
                    var p = self.settings.projects.first(where: { $0.path == candidate.path }) ?? candidate
                    p.directoryPath = candidate.directoryPath; p.group = candidate.group; p.shallow = candidate.shallow; p.modifiedAt = candidate.modifiedAt; return p
                }
                self.message = "已读取 \(projects.count) 个目录，正在列出文件…"; self.save()
            }
            let files = projects.flatMap { metadataFiles($0.path,project:$0.path,recursive:$0.shallow != true,cache:previous) }.sorted { $0.date > $1.date }
            let incoming = includeInbox ? metadataFiles(inbox,project:"",recursive:false,cache:previous) : []
            DispatchQueue.main.async {
                guard !token.isCancelled else { return }; guard self.settings.workspaceIdentity == workspaceID && self.settings.inbox == inbox else { return }
                self.projectCounts = Dictionary(files.map { ($0.project,1) },uniquingKeysWith:+)
                self.files = files; if includeInbox { self.incoming = incoming }; self.metadataReady = true
                self.message = "文件列表已就绪 · 未读取文档正文"
                if !archiveRequested { self.busy = false; self.cache.merge(Dictionary((files+incoming).map { ($0.path,$0) },uniquingKeysWith:{a,_ in a}),uniquingKeysWith:{_,b in b}) }
            }
            guard archiveRequested else { return }
            var indexed: [FileItem] = []; var batch: [FileItem] = []; var lastUpdate = Date()
            let all = archiveWorkset(projects:projects,files:files,incoming:incoming)
            for (index,item) in all.enumerated() {
                guard !token.isCancelled else { return }
                var file = item
                if file.text.isEmpty { file.text = autoreleasepool { extract(file.url) } }
                indexed.append(file); batch.append(file)
                if (batch.count >= 25 && Date().timeIntervalSince(lastUpdate) > 0.8) || Date().timeIntervalSince(lastUpdate) > 2 || index == all.count-1 {
                    let update = batch; let progress = index+1; batch = []; lastUpdate = Date()
                    DispatchQueue.main.async {
                        guard !token.isCancelled else { return }; guard self.settings.workspaceIdentity == workspaceID && self.settings.inbox == inbox else { return }
                        let lookup = Dictionary(update.map { ($0.path,$0) },uniquingKeysWith: { a,_ in a })
                        for (path,file) in lookup { self.cache[path] = file }
                        self.message = "正在解析归档所需文档（\(progress)/\(all.count)）"
                    }
                }
            }
            DispatchQueue.main.async {
                guard !token.isCancelled else { return }; guard self.settings.workspaceIdentity == workspaceID && self.settings.inbox == inbox else { self.busy = false; self.refresh(); return }
                self.cache.merge(Dictionary(indexed.map { ($0.path,$0) },uniquingKeysWith: { a,_ in a }),uniquingKeysWith:{_,b in b})
                self.files = self.files.map { versionMatched($0,cached:self.cache[$0.path]) }; if includeInbox { self.incoming = self.incoming.map { versionMatched($0,cached:self.cache[$0.path]) } }
                self.busy = false; self.save()
                self.message = "归档文档解析完成 · " + Date().formatted(date:.omitted,time:.shortened)
                if archiveRequested { self.processAutomatic(manualRun:true) }
            }
        }
    }

    var namingFiles: [FileItem] { files.map { versionMatched($0,cached:cache[$0.path]) } }
    func observeInbox() {
        guard !settings.inbox.isEmpty, let urls = try? fm.contentsOfDirectory(at:URL(fileURLWithPath:settings.inbox),includingPropertiesForKeys:[.isRegularFileKey,.fileSizeKey,.contentModificationDateKey],options:.skipsHiddenFiles) else { return }
        let baseline = settings.baselineInbox != settings.inbox; let now = Date()
        var observations = baseline ? [:] : (settings.arrivals ?? [:])
        for u in urls where supported.contains(u.pathExtension.lowercased()) && !u.lastPathComponent.hasPrefix("~$") {
            guard let v = try? u.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey,.contentModificationDateKey]), v.isRegularFile == true else { continue }
            observations[u.path] = observedArrival(previous:observations[u.path],size:Int64(v.fileSize ?? 0),modified:v.contentModificationDate ?? now,identity:fileIdentity(u.path),now:now,baseline:baseline)
        }
        settings.arrivals = observations; settings.baselineInbox = settings.inbox; save()
    }
    func checkDownloads() {
        guard !settings.inbox.isEmpty else { error = "请先在工作空间设置中选择下载或待归档目录。"; return }
        refresh(includeInbox:true,archiveRequested:true)
    }
    func processAutomatic(manualRun: Bool = false) {
        guard manualRun else { return }
        var moved = 0
        for file in incoming {
            guard let arrival = settings.arrivals?[file.path], readyForManualArchive(file,arrival:arrival,now:Date()),
                  !(settings.suppressed ?? []).contains(fileIdentity(file.path) ?? ""),
                  let match = confidentMatch(file,projects:settings.projects,references:files) else { continue }
            do { try performArchive(file,to:match.project,automatic:true,evidence:match.evidence); moved += 1 }
            catch { message = "自动归档未完成：\(error.localizedDescription)；文件保留待确认。" }
        }
        message = "本次归档 \(moved) 份，待确认 \(incoming.count) 份。可在归档记录中查看或撤销。"
    }
    func performArchive(_ file: FileItem, to project: Project, automatic: Bool, evidence: String) throws {
        guard incoming.contains(where:{$0.path == file.path}), fm.fileExists(atPath:project.path),
              let v = try? file.url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey]),
              Int64(v.fileSize ?? -1) == file.size, v.contentModificationDate == file.date else {
            throw NSError(domain:"归档",code:1,userInfo:[NSLocalizedDescriptionKey:"文件或目标目录已变化，请刷新后重试。"])
        }
        let destination = try safeMove(file.url,into:URL(fileURLWithPath:project.path))
        remapCategoryAssignments(source:file.path,destination:destination.path,folder:false)
        settings.moves.insert(MoveRecord(source:file.path,destination:destination.path,identity:fileIdentity(destination.path),arrivedAt:settings.arrivals?[file.path]?.firstSeen,automatic:automatic,evidence:evidence),at:0)
        // Persist the recovery record before updating the view.
        save()
        incoming.removeAll { $0.path == file.path }
        files.insert(FileItem(path:destination.path,project:project.path,text:file.text,size:file.size,date:file.date),at:0)
        projectCounts[project.path,default:0] += 1
        cache[destination.path] = files[0]; cache.removeValue(forKey:file.path)
    }
    func archive(_ file: FileItem, to project: Project) {
        do { try performArchive(file,to:project,automatic:false,evidence:"手动选择项目"); message = "已归入 \(project.name)"; refresh() }
        catch { self.error = error.localizedDescription }
    }
    func undo(_ move: MoveRecord, refreshAfter: Bool = true) {
        do {
            guard !fm.fileExists(atPath:move.source) else { throw NSError(domain:"撤销",code:1,userInfo:[NSLocalizedDescriptionKey:"原位置已有同名文件，请先处理该文件，避免覆盖。"]) }
            guard let identity = move.identity, identity == fileIdentity(move.destination) else { throw NSError(domain:"撤销",code:2,userInfo:[NSLocalizedDescriptionKey:"归档文件已被移走或替换，无法安全撤销。请在 Finder 中核对文件。"]) }
            try fm.moveItem(atPath:move.destination,toPath:move.source)
            remapCategoryAssignments(source:move.destination,destination:move.source,folder:move.folder == true)
            settings.suppressed = Array(Set((settings.suppressed ?? []) + [fileIdentity(move.source) ?? identity]))
            if let i = settings.moves.firstIndex(where:{$0.id == move.id}) { settings.moves[i].undone = true }; save(); if refreshAfter { refresh() }
        } catch { self.error = error.localizedDescription }
    }
    func demo() {
        do {
            let root = stateURL.deletingLastPathComponent().appendingPathComponent("示例空间")
            let projects = root.appendingPathComponent("项目"); let inbox = root.appendingPathComponent("待归档")
            for name in ["A","B"] { try fm.createDirectory(at:projects.appendingPathComponent(name),withIntermediateDirectories:true) }
            try fm.createDirectory(at:inbox,withIntermediateDirectories:true)
            let samples = [("项目/A/项目说明.txt","项目名称：南山智慧园区建设项目\n\n建设单位：南山产业园\n项目编号：NS-2026-001\n\n本项目包含园区网络、安防和数字化管理系统建设。\n项目资料在本机保存，通过原有软件继续编辑。"),("项目/B/需求记录.txt","项目名称：滨江数据中心改造工程\n\n项目编号：BJ-2026-008\n\n工作内容：机房网络与供配电系统改造。"),("待归档/会议纪要.txt","南山智慧园区建设项目\n项目编号：NS-2026-001\n\n会议纪要\n本次会议确认园区网络施工安排，下周提交深化设计。")]
            for (path,text) in samples { let u = root.appendingPathComponent(path); if !fm.fileExists(atPath:u.path) { try text.write(to:u,atomically:true,encoding:.utf8); try fm.setAttributes([.modificationDate:Date().addingTimeInterval(-60)],ofItemAtPath:u.path) } }
            settings.root = projects.path; settings.inbox = inbox.path; settings.projects = []; save(); refresh()
        } catch { self.error = error.localizedDescription }
    }
}
func canonicalPath(_ path: String) -> String {
    guard let resolved = realpath(path,nil) else { return path }
    defer { free(resolved) }; return String(cString:resolved)
}
func fileIdentity(_ path: String) -> String? {
    guard let a = try? fm.attributesOfItem(atPath:path), let device = a[.systemNumber], let inode = a[.systemFileNumber] else { return nil }
    return "\(device):\(inode)"
}
func safeMove(_ source: URL, into folder: URL) throws -> URL {
    var target = folder.appendingPathComponent(source.lastPathComponent); var n = 2
    while fm.fileExists(atPath:target.path) {
        let ext = source.pathExtension; let suffix = ext.isEmpty ? "" : "."+ext
        target = folder.appendingPathComponent(source.deletingPathExtension().lastPathComponent+" (\(n))"+suffix); n += 1
    }
    try fm.moveItem(at:source,to:target); return target
}

struct Preview: NSViewRepresentable {
    let url: URL; let version: Date
    final class Coordinator { let gate = PreviewLoadGate() }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context:Context) -> QLPreviewView { QLPreviewView(frame:.zero,style:.normal)! }
    func updateNSView(_ view:QLPreviewView,context:Context) {
        guard context.coordinator.gate.shouldLoad(url: url, version: version) else { return }
        view.previewItem = url as NSURL
    }
}
@MainActor func selfTest() throws {
    var root = fm.temporaryDirectory.appendingPathComponent("guiyu-test-"+UUID().uuidString)
    try fm.createDirectory(at:root,withIntermediateDirectories:true); root = URL(fileURLWithPath:canonicalPath(root.path)); defer { try? fm.removeItem(at:root) }
    let a = root.appendingPathComponent("A"); let inbox = root.appendingPathComponent("inbox")
    try fm.createDirectory(at:a,withIntermediateDirectories:true); try fm.createDirectory(at:inbox,withIntermediateDirectories:true)
    let first = a.appendingPathComponent("测试.txt"); try "项目名称：南山智慧园区建设项目\n项目编号：NS-2026-001".write(to:first,atomically:true,encoding:.utf8)
    let files = scan(a.path,project:a.path,recursive:true); precondition(files.count == 1 && files[0].text.contains("NS-2026"))
    let p = Project(path:a.path,name:"A",keywords:"NS-2026-001")
    precondition(recommendations(p,files:files).first?.name == "南山智慧园区建设项目"); precondition(score(files[0],project:p).0 > 0)
    let incoming = inbox.appendingPathComponent("测试.txt"); try "新版内容".write(to:incoming,atomically:true,encoding:.utf8)
    let originalIdentity = fileIdentity(incoming.path); let moved = try safeMove(incoming,into:a); precondition(fileIdentity(moved.path) == originalIdentity); precondition(moved.lastPathComponent == "测试 (2).txt"); precondition(extract(first).contains("NS-2026")); precondition(extract(moved) == "新版内容")
    try fm.moveItem(at:moved,to:incoming); precondition(fm.fileExists(atPath:incoming.path))
    try "替代文件".write(to:moved,atomically:true,encoding:.utf8); precondition(fileIdentity(moved.path) != originalIdentity)
    let docx = root.appendingPathComponent("sample.docx")
    _ = run("/usr/bin/textutil",["-convert","docx","-output",docx.path,first.path])
    precondition(extract(docx).contains("NS-2026-001"))
    let xl = root.appendingPathComponent("xl"); try fm.createDirectory(at:xl,withIntermediateDirectories:true)
    try "<sst><si><t>NS-2026-001</t></si></sst>".write(to:xl.appendingPathComponent("sharedStrings.xml"),atomically:true,encoding:.utf8)
    let zipper = Process(); zipper.executableURL = URL(fileURLWithPath:"/usr/bin/zip"); zipper.arguments = ["-qr","sample.xlsx","xl"]; zipper.currentDirectoryURL = root; try zipper.run(); zipper.waitUntilExit()
    precondition(extract(root.appendingPathComponent("sample.xlsx")).contains("NS-2026-001"))
    let pdf = root.appendingPathComponent("sample.pdf"); var box = CGRect(x:0,y:0,width:600,height:400)
    if let context = CGContext(pdf as CFURL,mediaBox:&box,nil) {
        context.beginPDFPage(nil); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
        ("Project NS-2026-001 official documentation" as NSString).draw(at:NSPoint(x:30,y:200),withAttributes:[.font:NSFont.systemFont(ofSize:22)])
        NSGraphicsContext.restoreGraphicsState(); context.endPDFPage(); context.closePDF()
    }
    precondition(extract(pdf).contains("NS-2026-001"))
    let image = NSImage(size:NSSize(width:1200,height:200)); image.lockFocus(); NSColor.white.setFill(); NSRect(x:0,y:0,width:1200,height:200).fill()
    ("PROJECT ALPHA 2026" as NSString).draw(at:NSPoint(x:40,y:75),withAttributes:[.font:NSFont.systemFont(ofSize:64),.foregroundColor:NSColor.black]); image.unlockFocus()
    let png = root.appendingPathComponent("ocr.png"); try NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:png)
    precondition(extract(png).contains("ALPHA"))
    try directoryPresentationTest(root:root)
    try namingTest(root:root)
    try namingRulesTest(root:root)
    try categoryManagementTest(root:root)
    try categoryRulesTest(root:root)
    try categoryRuleExchangeTest(root:root)
    try categoryWorkflowTest(root:root)
    try batchOperationsTest(root:root)
    try quickArchiveTest(root:root)
    try archiveMatchingTest(root:root)
    try finderServicesTest(root:root)
    try filenameSearchTest(root:root)
    try lightweightTest(root:root)
    try interactionTest()
    try finderShortcutTest(root:root)
    try indexingTest(root:root)
    try directoryOrderingTest(root:root)
    try sidebarSectionsTest(root:root)
    try projectRootsTest(root:root)
    try AppUpdater.selfTest()
    try automationTest(root:root)
    print("PASS: extraction + OCR; explicit-click routing, no unrequested moves, ambiguity, stable downloads, undo suppression, time sorting, persisted records")
}
if CommandLine.arguments.contains("--self-test") { do { try MainActor.assumeIsolated { try selfTest() } } catch { fputs("FAIL: \(error)\n",stderr); exit(1) } }
else if CommandLine.arguments.contains("--project-roots-review") { do { try MainActor.assumeIsolated { try projectRootsUIReview() } } catch { fputs("FAIL: \(error)\n",stderr); exit(1) } }
else if CommandLine.arguments.contains("--finder-services-review") { do { try MainActor.assumeIsolated { try finderServicesUIReview() } } catch { fputs("FAIL: \(error)\n",stderr); exit(1) } }
else if CommandLine.arguments.contains("--update-probe") { do { try MainActor.assumeIsolated { try AppUpdater.probeDiagnostic() } } catch { fputs("FAIL: \(error)\n",stderr); exit(1) } }
else if CommandLine.arguments.contains("--smart-dialogs-review") { do { try MainActor.assumeIsolated { try smartDialogsUIReview() } } catch { fputs("FAIL: \(error)\n",stderr); exit(1) } }
else if CommandLine.arguments.contains("--category-flow-review") { do { try MainActor.assumeIsolated { try categoryWorkflowUIReview() } } catch { fputs("FAIL: \(error)\n",stderr); exit(1) } }
else if CommandLine.arguments.contains("--naming-rules-review") { do { try MainActor.assumeIsolated { try namingRulesUIReview() } } catch { fputs("FAIL: \(error)\n",stderr); exit(1) } }
else if CommandLine.arguments.contains("--ui-review") { do { try MainActor.assumeIsolated { try batchUIReview() } } catch { fputs("FAIL: \(error)\n",stderr); exit(1) } }
else { GuiyuApp.main() }
@MainActor final class GuiyuAppDelegate: NSObject, NSApplicationDelegate {
    lazy var store = Store()
    lazy var finderServices = FinderServices(store:store)
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = finderServices
        NSUpdateDynamicServices()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = finderServices
        applyGuiyuApplicationIcon()
        AppUpdater.shared.start()
    }
}
@MainActor @discardableResult func applyGuiyuApplicationIcon() -> Bool {
    guard let url = Bundle.main.url(forResource:"AppIcon",withExtension:"icns"), let icon = NSImage(contentsOf:url), icon.isValid else { return false }
    NSApplication.shared.applicationIconImage = icon
    return true
}
struct GuiyuApp: App {
    @NSApplicationDelegateAdaptor(GuiyuAppDelegate.self) var delegate
    var body: some Scene { WindowGroup("归屿") { ProjectWorkspace(store:delegate.store).preferredColorScheme(.light) }.defaultSize(width:1280,height:820).windowStyle(.hiddenTitleBar).commands { CommandGroup(replacing:.newItem) {}; CommandGroup(replacing:.appInfo) { Button("关于归屿") { NSApp.orderFrontStandardAboutPanel(options:[.applicationVersion:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "开发版本",.version:""]) } }; CommandGroup(after:.appInfo) { UpdateMenu() } } }
}
