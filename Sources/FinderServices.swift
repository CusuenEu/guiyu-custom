import AppKit
import SwiftUI

// System Services passes selected file URLs, never shell commands or clipboard text.
func finderServiceURLs(_ pasteboard: NSPasteboard) -> [URL] {
    let urls = (pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]) ?? []
    if !urls.isEmpty { return urls }
    let paths = pasteboard.propertyList(forType:NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] ?? []
    return paths.map { URL(fileURLWithPath:$0) }
}
func finderServiceRows(_ urls: [URL], settings: Settings) throws -> [BrowserRow] {
    guard !urls.isEmpty else { throw namingError("请在 Finder 中选中文件或文件夹后重试。") }
    var seen = Set<String>(); var rows: [BrowserRow] = []
    let protected = settings.protectedProjectPaths.filter { !$0.isEmpty }.map(canonicalPath)
    for url in urls {
        guard url.isFileURL else { throw namingError("仅支持本机可访问的文件或文件夹。") }
        let path = canonicalPath(url.path)
        let values = try url.resourceValues(forKeys:[.isSymbolicLinkKey,.isAliasFileKey,.isPackageKey])
        guard values.isSymbolicLink != true, values.isAliasFile != true, values.isPackage != true, let row = browserEntry(path) else { throw namingError("无法处理「"+url.lastPathComponent+"」：请确认文件存在且可访问；不处理替身、符号链接、应用包或隐藏项。") }
        let resolved = canonicalPath(path)
        guard !protected.contains(where: { $0 == resolved || $0.hasPrefix(resolved+"/") }), resolved != "/" else { throw namingError("项目总目录、导航目录及其上层不能在此命名或归档，请选择具体文件或项目文件夹。") }
        if seen.insert(resolved).inserted { rows.append(row) }
    }
    guard !rows.contains(where: { row in rows.contains(where: { $0.folder && $0.id != row.id && canonicalPath(row.id).hasPrefix(canonicalPath($0.id)+"/") }) }) else { throw namingError("请只选择外层文件夹，不要同时选择其内部条目。") }
    return rows
}

@MainActor final class FinderServices: NSObject, NSWindowDelegate {
    let store: Store
    private var window: NSWindow?
    init(store: Store) { self.store = store }

    @objc func smartNaming(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        receive(pasteboard,archive:false,error:error)
    }
    @objc func quickArchive(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        receive(pasteboard,archive:true,error:error)
    }
    private func receive(_ pasteboard: NSPasteboard, archive: Bool, error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>) {
        do {
            guard window == nil else {
                NSApp.activate(ignoringOtherApps:true); window?.makeKeyAndOrderFront(nil)
                throw namingError("请先完成或取消当前归屿右键操作，再处理新的选择。")
            }
            let rows = try finderServiceRows(finderServiceURLs(pasteboard),settings:store.settings)
            store.error = ""
            if archive && !store.settings.hasProjectRoots {
                throw namingError("请先在归屿「设置 → 工作空间」关联项目总目录，然后再次使用智能归档。")
            }
            let close: () -> Void = { [weak self] in self?.window?.close() }
            let content: AnyView
            if archive {
                content = AnyView(QuickArchiveDialog(store:store,request:QuickArchiveRequest(rows:rows),onClose:close))
            } else if rows.count == 1, let row = rows.first {
                let project = store.settings.projects.filter { $0.shallow != true && (row.id == $0.path || row.id.hasPrefix($0.path+"/")) }.max { $0.path.count < $1.path.count }
                content = AnyView(RenameDialog(store:store,target:NamingTarget(path:row.id,folder:row.folder,projectPath:project?.path ?? ""),onClose:close))
            } else {
                content = AnyView(BatchRenameDialog(store:store,request:BatchNamingRequest(rows:rows,projectPath:"",recommended:true),onClose:close))
            }
            let controller = NSHostingController(rootView:content.background(Color(nsColor:.windowBackgroundColor)).preferredColorScheme(.light))
            let panel = NSWindow(contentViewController:controller)
            panel.title = archive ? "归屿-智能归档" : "归屿-智能命名"
            panel.styleMask = [.titled,.closable]; panel.isReleasedWhenClosed = false
            panel.delegate = self; window = panel
            panel.center(); NSApp.activate(ignoringOtherApps:true); panel.makeKeyAndOrderFront(nil)
        } catch { errorPointer.pointee = error.localizedDescription as NSString }
    }
    func windowWillClose(_ notification: Notification) {
        // Releasing the host cancels asynchronous reads through the dialogs' onDisappear.
        window?.contentViewController = nil; window = nil
    }
}

@MainActor func finderServicesTest(root: URL) throws {
    let external = root.appendingPathComponent("Finder 外部位置 空格 # %"); try fm.createDirectory(at:external,withIntermediateDirectories:true)
    let folder = external.appendingPathComponent("任意文件夹"); try fm.createDirectory(at:folder,withIntermediateDirectories:true)
    let file = external.appendingPathComponent("资料 # %.txt"); try "项目名称：南山智慧园区建设项目".write(to:file,atomically:true,encoding:.utf8)
    let child = folder.appendingPathComponent("内部.txt"); try "内部资料".write(to:child,atomically:true,encoding:.utf8)
    let pb = NSPasteboard.withUniqueName(); defer { pb.releaseGlobally() }
    pb.writeObjects([file as NSURL,folder as NSURL])
    let urls = finderServiceURLs(pb)
    let rows = try finderServiceRows(urls,settings:Settings())
    try verify(rows.count == 2 && rows.contains { $0.id == file.path } && rows.contains { $0.folder },"File URLs preserve Unicode, spaces and URL metacharacters")
    let deduplicated = try finderServiceRows([file,file],settings:Settings())
    try verify(deduplicated.count == 1,"Duplicate selection is processed once")
    func rejected(_ urls: [URL], _ settings: Settings = Settings()) -> Bool { do { _ = try finderServiceRows(urls,settings:settings); return false } catch { return true } }
    try verify(rejected([folder,child]) && rejected([]) && rejected([URL(string:"https://example.com/a")!]),"Empty, non-file and overlapping selections are rejected before presenting")
    let link = external.appendingPathComponent("链接"); try fm.createSymbolicLink(at:link,withDestinationURL:file)
    try verify(rejected([link]),"Do not resolve symlinks into unintended write targets")
    let app = external.appendingPathComponent("测试.app"); try fm.createDirectory(at:app,withIntermediateDirectories:true)
    try verify(rejected([app]),"Application bundles are not document folders")
    var settings = Settings(); settings.root = folder.path
    try verify(rejected([folder],settings) && rejected([external],settings),"Protect workspace roots and ancestors")
    pb.clearContents(); pb.setPropertyList([file.path,folder.path],forType:NSPasteboard.PasteboardType("NSFilenamesPboardType"))
    try verify(finderServiceURLs(pb).count == 2,"Legacy Finder filename lists are accepted")
    let store = Store(stateURL:root.appendingPathComponent("FinderServiceState/settings.json"),loadOnLaunch:false)
    let project = root.appendingPathComponent("FinderDestination/2026/10 测试项目"); try fm.createDirectory(at:project,withIntermediateDirectories:true)
    store.settings.root = root.appendingPathComponent("FinderDestination").path
    let destination = Project(path:project.path,name:"10 测试项目",group:"2026"); store.settings.projects = [destination]
    try verify(fm.fileExists(atPath:file.path) && fm.fileExists(atPath:child.path),"Reading service selection changes no files")
    try verify(store.confirmRename(NamingTarget(path:file.path,folder:false,projectPath:""),newName:"归屿外部文档.txt"),"External documents use the existing confirmed rename")
    let updated = external.appendingPathComponent("归屿外部文档.txt")
    let result = store.confirmQuickArchive(QuickArchiveRequest(rows:[browserEntry(updated.path)!,browserEntry(folder.path)!]),to:destination)
    try verify(result.failure == nil && result.completed.count == 2 && fm.fileExists(atPath:project.appendingPathComponent("任意文件夹/内部.txt").path),"External files and folders use confirmed archive with hierarchy intact")
    store.scanCancellation?.cancel(); store.busy = false
    for move in store.settings.moves { store.undo(move,refreshAfter:false) }
    try verify(fm.fileExists(atPath:updated.path) && fm.fileExists(atPath:child.path),"Service-triggered archive remains undoable")
    print("PASS: system-service URL and legacy pasteboards, arbitrary external folders, Unicode paths, selection guards, confirmed rename/archive and undo")
}

@MainActor func finderServicesUIReview() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let root = fm.temporaryDirectory.appendingPathComponent("guiyu-service-ui-"+UUID().uuidString)
    try fm.createDirectory(at:root,withIntermediateDirectories:true)
    defer { try? fm.removeItem(at:root) }
    let file = root.appendingPathComponent("验收资料.txt"), other = root.appendingPathComponent("第二份资料.txt")
    let text = "招标文件\n项目名称：南山智慧园区建设项目\n"
    try text.write(to:file,atomically:true,encoding:.utf8); try text.write(to:other,atomically:true,encoding:.utf8)
    let project = root.appendingPathComponent("Workspace/2026/10 南山智慧园区建设项目")
    try fm.createDirectory(at:project,withIntermediateDirectories:true)
    let store = Store(stateURL:root.appendingPathComponent("State/settings.json"),loadOnLaunch:false)
    store.settings.root = root.appendingPathComponent("Workspace").path
    store.settings.projects = [Project(path:project.path,name:project.lastPathComponent,group:"2026")]
    let provider = FinderServices(store:store)
    let pb = NSPasteboard.withUniqueName(); defer { pb.releaseGlobally() }
    let output = URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent("Design/FinderServices-review")
    try fm.createDirectory(at:output,withIntermediateDirectories:true)
    func capture(_ title: String, _ filename: String) throws {
        RunLoop.main.run(until:Date().addingTimeInterval(1))
        guard let window = NSApp.windows.first(where:{$0.title == title && $0.isVisible}), let view = window.contentView else { throw namingError("系统服务确认窗口未显示："+title) }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { throw namingError("无法渲染服务窗口") }
        view.cacheDisplay(in:view.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(filename))
        window.performClose(nil)
        RunLoop.main.run(until:Date().addingTimeInterval(0.1))
    }
    var failure: NSString?
    pb.writeObjects([file as NSURL]); provider.smartNaming(pb,userData:nil,error:&failure)
    try verify(failure == nil,"Single-selection service dispatch succeeds")
    try capture("归屿-智能命名","smart-naming.png")
    pb.clearContents(); pb.writeObjects([file as NSURL,other as NSURL]); provider.smartNaming(pb,userData:nil,error:&failure)
    try verify(failure == nil,"Batch service can open after the previous window closes")
    try capture("归屿-智能命名","batch-naming.png")
    provider.quickArchive(pb,userData:nil,error:&failure)
    try verify(failure == nil,"Quick archive service dispatch succeeds")
    try capture("归屿-智能归档","quick-archive.png")
    try verify(fm.fileExists(atPath:file.path) && fm.fileExists(atPath:other.path) && store.settings.moves.isEmpty && (store.settings.renames ?? []).isEmpty,"Closing service dialogs changes no files or operation records")
    print("PASS: single and batch naming / quick archive service windows render; close and reopen work; cancellation changes no files")
}
