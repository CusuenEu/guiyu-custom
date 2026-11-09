import AppKit
import QuickLookUI

// File shortcuts live on the focused native table, never on a global event monitor.
enum FileShortcut: Equatable { case preview, trash, rename, open, copy, paste }
func fileShortcut(for event: NSEvent) -> FileShortcut? {
    guard event.type == .keyDown else { return nil }
    let modifiers = event.modifierFlags.intersection([.command,.option,.control,.shift])
    if modifiers.isEmpty && event.keyCode == 49 { return .preview }
    if modifiers == .command && [51,117].contains(event.keyCode) { return .trash }
    if modifiers.isEmpty && [36,76].contains(event.keyCode) { return .rename }
    if modifiers == .command && event.keyCode == 31 { return .open }
    let character = event.charactersIgnoringModifiers?.lowercased() ?? ""
    if modifiers == .command && (character == "c" || (character.isEmpty && event.keyCode == 8)) { return .copy }
    if modifiers == .command && (character == "v" || (character.isEmpty && event.keyCode == 9)) { return .paste }
    return nil
}
final class FileQuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var urls: [URL] = []
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { urls.indices.contains(index) ? urls[index] as NSURL : nil }
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard !(panel.firstResponder is NSTextView), fileShortcut(for:event) == .preview else { return false }
        panel.orderOut(nil); return true
    }
}
struct TrashedEntry {
    let original: URL; let trashed: URL; let identity: String
}
@MainActor extension Store {
    @discardableResult func moveToTrash(_ rows: [BrowserRow], undoManager: UndoManager? = nil) -> [TrashedEntry] {
        guard !busy else { error = "归档或目录读取尚未完成，请稍后重试。"; return [] }
        var moved: [TrashedEntry] = []
        do {
            let targets = rows.filter { !$0.header }.map { NamingTarget(path:$0.id,folder:$0.folder,projectPath:"") }
            guard !targets.isEmpty, Set(targets.map(\.path)).count == targets.count else { return [] }
            let protected = Set(settings.protectedProjectPaths.filter { !$0.isEmpty }.map(canonicalPath))
            for target in targets {
                guard !protected.contains(canonicalPath(target.path)) else { throw namingError("项目总目录和左侧导航目录不能在此移到废纸篓，请选择具体项目或文件。") }
                guard target.identity != nil, target.identity == fileIdentity(target.path) else { throw namingError("部分条目已被移动或替换，请刷新后重新选择。") }
                guard !targets.contains(where:{$0.path != target.path && target.path.hasPrefix($0.path+"/")}) else { throw namingError("请只选择外层文件夹，不要同时选择其内部条目。") }
            }
            for target in targets {
                guard let identity = target.identity, identity == fileIdentity(target.path) else { throw namingError("源条目发生变化，剩余条目未删除。") }
                var destination: NSURL?
                try fm.trashItem(at:URL(fileURLWithPath:target.path),resultingItemURL:&destination)
                guard let url = destination as URL? else { throw namingError("系统已处理废纸篓操作，但未返回恢复位置；请到 Finder 废纸篓中核对。") }
                moved.append(TrashedEntry(original:URL(fileURLWithPath:target.path),trashed:url,identity:identity))
                let matches: (String) -> Bool = { $0 == target.path || (target.folder && $0.hasPrefix(target.path+"/")) }
                files.removeAll { matches($0.path) }; incoming.removeAll { matches($0.path) }; cache = cache.filter { !matches($0.key) }
                settings.projects.removeAll { matches($0.path) }
            }
        } catch { self.error = "已移到废纸篓 \(moved.count) 项；"+error.localizedDescription }
        if !moved.isEmpty {
            let records = moved
            undoManager?.registerUndo(withTarget:self) { store in store.restoreFromTrash(records) }
            undoManager?.setActionName("移到废纸篓")
            projectCounts = Dictionary(files.map { ($0.project,1) },uniquingKeysWith:+)
            fileOperationRevision += 1; save(); message = "已将 \(moved.count) 项移到废纸篓"
        }
        return moved
    }
    func restoreFromTrash(_ entries: [TrashedEntry]) {
        do {
            for entry in entries {
                guard fileIdentity(entry.trashed.path) == entry.identity, !fm.fileExists(atPath:entry.original.path) else { throw namingError("原位置已被占用，或废纸篓中的条目已变化；请在 Finder 中核对，现有文件不会被覆盖。") }
            }
            for entry in entries { try fm.moveItem(at:entry.trashed,to:entry.original) }
            fileOperationRevision += 1; message = "已撤销移到废纸篓"; refresh()
        } catch { self.error = error.localizedDescription; fileOperationRevision += 1 }
    }
}
@MainActor func finderShortcutTest(root: URL) throws {
    func event(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent { NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)! }
    try verify(fileShortcut(for:event(49)) == .preview)
    try verify(fileShortcut(for:event(51,.command)) == .trash)
    try verify(fileShortcut(for:event(117,.command)) == .trash)
    try verify(fileShortcut(for:event(51)) == nil && fileShortcut(for:event(51,[.command,.option])) == nil && fileShortcut(for:event(51,[.command,.shift])) == nil,"Do not turn plain delete or permanent-delete combinations into trash")
    var previews = 0; var deletes = 0
    let table = BrowserNSTable(); table.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier("name"))); table.onSpace = { previews += 1 }; table.onTrash = { deletes += 1 }
    let host = NSView(frame:NSRect(x:0,y:0,width:300,height:100)); table.frame = host.bounds; host.addSubview(table)
    let window = NSWindow(contentRect:host.bounds,styleMask:.borderless,backing:.buffered,defer:false); window.contentView = host
    window.makeFirstResponder(table)
    try verify(table.performFileShortcut(event(49)) && previews == 1)
    try verify(table.performFileShortcut(event(51,.command)) && deletes == 1)
    let field = NSTextView(frame:NSRect(x:0,y:0,width:100,height:30)); host.addSubview(field); window.makeFirstResponder(field)
    try verify(!table.performFileShortcut(event(51,.command)) && !table.performFileShortcut(event(49)) && deletes == 1 && previews == 1,"Text input must keep its own keyboard behavior")
    let dir = root.appendingPathComponent("ShortcutTrash"); let folder = dir.appendingPathComponent("资料文件夹")
    try fm.createDirectory(at:folder,withIntermediateDirectories:true)
    let file = dir.appendingPathComponent("快捷键临时文件.txt"); try "temporary fixture".write(to:file,atomically:true,encoding:.utf8)
    try "nested fixture".write(to:folder.appendingPathComponent("内部.txt"),atomically:true,encoding:.utf8)
    let store = Store(stateURL:root.appendingPathComponent("ShortcutState/settings.json"),loadOnLaunch:false)
    store.settings.categories = WorkspaceCategory.defaults // Existing configured-user fixture.
    let rows = try directoryEntries(path:dir.path,project:dir.path)
    let trash = store.moveToTrash(rows)
    defer { for entry in trash where fileIdentity(entry.trashed.path) == entry.identity && !fm.fileExists(atPath:entry.original.path) { try? fm.moveItem(at:entry.trashed,to:entry.original) } }
    try verify(trash.count == 2 && trash.allSatisfy { fileIdentity($0.trashed.path) == $0.identity && !fm.fileExists(atPath:$0.original.path) },"Only isolated fixtures move to actual system Trash")
    store.restoreFromTrash(trash); store.scanCancellation?.cancel(); store.busy = false
    try verify(fm.fileExists(atPath:file.path) && fm.fileExists(atPath:folder.appendingPathComponent("内部.txt").path),"Trash restore preserves folder hierarchy")
    let preview = FileQuickLook(); preview.urls = [file,folder]
    try verify(preview.numberOfPreviewItems(in:nil) == 2 && (preview.previewPanel(nil,previewItemAt:0)?.previewItemURL ?? nil) == file)
    print("PASS: focused-table Finder shortcuts, text-editor exclusion, native Quick Look multi-item data source, actual temporary-fixture Trash and safe restore")
}
