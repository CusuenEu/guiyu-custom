import SwiftUI
import AppKit

// Exercise the production views against isolated temporary documents, never user data.
@MainActor func smartDialogsUIReview() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let root = fm.temporaryDirectory.appendingPathComponent("guiyu-smart-dialogs-"+UUID().uuidString)
    try fm.createDirectory(at:root,withIntermediateDirectories:true)
    defer { try? fm.removeItem(at:root) }
    let workspace = root.appendingPathComponent("Workspace"), project = workspace.appendingPathComponent("2026/10月 民政厅机关网络运维及网络安全运维项目")
    let inbox = root.appendingPathComponent("Inbox")
    for dir in [project,inbox] { try fm.createDirectory(at:dir,withIntermediateDirectories:true) }
    let file = inbox.appendingPathComponent("民政厅机关网络运维服务方案.txt")
    try "民政厅机关网络运维服务方案\n项目名称：民政厅机关网络运维及网络安全运维项目\n方案名称：民政厅机关网络运维服务方案".write(to:file,atomically:true,encoding:.utf8)
    let store = Store(stateURL:root.appendingPathComponent("State/settings.json"),loadOnLaunch:false)
    defer { store.scanCancellation?.cancel() }
    store.settings.root = workspace.path
    let destination = Project(path:project.path,name:project.lastPathComponent,group:"2026")
    store.settings.projects = [destination,Project(path:workspace.appendingPathComponent("CD类项目/惠水加油站").path,name:"惠水加油站",group:"CD类项目")]
    let out = URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent(".impeccable/review/smart-dialogs")
    try fm.createDirectory(at:out,withIntermediateDirectories:true)
    func check(_ condition:Bool,_ message:String) throws { try verify(condition,message) }
    func settle(_ seconds:Double = 0.15) { RunLoop.current.run(until:Date().addingTimeInterval(seconds)) }
    func mount<V:View>(_ view:V, height:CGFloat) -> NSWindow {
        let host = NSHostingView(rootView:view.preferredColorScheme(.light))
        host.frame = NSRect(x:0,y:0,width:700,height:height)
        let window = NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:700,height:height),styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView = host; window.orderBack(nil); settle(0.4)
        return window
    }
    func field(_ view:NSView) -> NSTextField? {
        if let value = view as? SidebarNativeTextField { return value }
        return view.subviews.lazy.compactMap(field).first
    }
    func waitFor(_ predicate:() -> Bool) throws {
        let deadline = Date().addingTimeInterval(8)
        while !predicate() && Date() < deadline { settle(0.05) }
        try check(predicate(),"Production dialog state did not settle")
    }
    func capture(_ window:NSWindow,_ name:String) throws {
        let host = window.contentView!; host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw namingError("原生截图失败") }
        host.cacheDisplay(in:host.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(name))
    }
    func edit(_ field:NSTextField,_ text:String) {
        field.stringValue = text
        field.delegate?.controlTextDidChange?(Notification(name:NSControl.textDidChangeNotification,object:field))
        settle()
    }

    var closed = false
    let target = NamingTarget(path:file.path,folder:false,projectPath:"")
    let naming = mount(RenameDialog(store:store,target:target,onClose:{closed=true}),height:460)
    try waitFor { !(field(naming.contentView!)?.stringValue ?? "").isEmpty }
    guard let input = field(naming.contentView!) else { throw namingError("缺少命名输入框") }
    try check(input.stringValue.contains("民政厅"),"Document suggestion fills the upper native input")
    try capture(naming,"smart-naming.png")
    edit(input,"解决方案-")
    guard let emptyCoordinator = input.delegate as? SmartDialogTextField.Coordinator else { throw namingError("缺少命名输入事件") }
    try check(emptyCoordinator.control(input,textView:NSTextView(),doCommandBy:#selector(NSResponder.insertNewline(_:))),"Prefix-only input is handled")
    try check(!closed && store.error.isEmpty && fm.fileExists(atPath:file.path),"A type prefix without a recognized name cannot confirm or open an error alert")
    edit(input,"人工确认名称")
    try check(fm.fileExists(atPath:file.path) && (store.settings.renames ?? []).isEmpty,"Editing the suggestion does not rename files")
    guard let nameCoordinator = input.delegate as? SmartDialogTextField.Coordinator else { throw namingError("命名输入事件未接通") }
    try check(nameCoordinator.control(input,textView:NSTextView(),doCommandBy:#selector(NSResponder.insertNewline(_:))),"Native Return invokes confirmed naming")
    settle()
    let renamed = inbox.appendingPathComponent(store.smartProposedName(base:"人工确认名称",target:target))
    try check(closed && fm.fileExists(atPath:renamed.path) && !fm.fileExists(atPath:file.path),"Upper edited name and original extension reach the confirmed rename")
    naming.orderOut(nil); naming.contentView = nil

    let folder = inbox.appendingPathComponent("10月 待整理项目")
    try fm.createDirectory(at:folder,withIntermediateDirectories:true)
    try "招标文件\n项目名称：民政厅机关网络运维及网络安全运维项目".write(to:folder.appendingPathComponent("招标文件.txt"),atomically:true,encoding:.utf8)
    let folderTarget = NamingTarget(path:folder.path,folder:true,projectPath:"")
    let folderWindow = mount(RenameDialog(store:store,target:folderTarget),height:460)
    try waitFor { !(field(folderWindow.contentView!)?.stringValue ?? "").isEmpty }
    try capture(folderWindow,"smart-naming-folder.png")
    try check(smartNamingEditableBase("10月 测试项目",target:folderTarget) == "测试项目","Folder composer separates the editable month from the name")
    
    folderWindow.orderOut(nil); folderWindow.contentView = nil
    try check(fm.fileExists(atPath:folder.path),"Cancelling folder naming leaves hierarchy intact")

    // A source with a matching filename is never selected or moved automatically.
    let archiveFile = inbox.appendingPathComponent("民政厅机关网络运维及网络安全运维项目.txt")
    try "归档验收资料".write(to:archiveFile,atomically:true,encoding:.utf8)
    let request = QuickArchiveRequest(rows:[browserEntry(archiveFile.path)!])
    var archivedClosed = false
    let archive = mount(QuickArchiveDialog(store:store,request:request,onClose:{archivedClosed=true}),height:620)
    settle(0.6)
    try capture(archive,"smart-archive-matched.png")
    guard let search = field(archive.contentView!) else { throw namingError("缺少归档搜索框") }
    guard let searchCoordinator = search.delegate as? SmartDialogTextField.Coordinator else { throw namingError("搜索输入事件未接通") }
    try check(searchCoordinator.control(search,textView:NSTextView(),doCommandBy:#selector(NSResponder.insertNewline(_:))),"Native Return is handled")
    try check(!archivedClosed && store.settings.moves.isEmpty && fm.fileExists(atPath:archiveFile.path),"Matched project is not automatically selected or moved by Return")
    edit(search,"惠水")
    try check(searchCoordinator.parent.text == "惠水","Native search publishes the query to its SwiftUI binding")
    try capture(archive,"smart-archive-search.png")
    edit(search,"没有这个项目XYZ")
    try capture(archive,"smart-archive-empty.png")
    edit(search,"")
    archive.orderOut(nil); archive.contentView = nil
    let selectedArchive = mount(QuickArchiveDialog(store:store,request:request,selected:destination.path,onClose:{archivedClosed=true}),height:620)
    settle(0.6)
    try capture(selectedArchive,"smart-archive-selected.png")
    try check(fm.fileExists(atPath:archiveFile.path) && store.settings.moves.isEmpty,"Selected destination alone never moves the source")
    guard let selectedSearch = field(selectedArchive.contentView!), let selectedCoordinator = selectedSearch.delegate as? SmartDialogTextField.Coordinator else { throw namingError("缺少选中后的搜索框") }
    edit(selectedSearch,"惠水")
    try check(selectedCoordinator.control(selectedSearch,textView:NSTextView(),doCommandBy:#selector(NSResponder.insertNewline(_:))),"Return after changing search is handled")
    try check(!archivedClosed && store.settings.moves.isEmpty && fm.fileExists(atPath:archiveFile.path),"Searching B after selecting A cannot archive to hidden A")
    selectedArchive.orderOut(nil); selectedArchive.contentView = nil
    let confirmedArchive = mount(QuickArchiveDialog(store:store,request:request,selected:destination.path,onClose:{archivedClosed=true}),height:620)
    guard let confirmedSearch = field(confirmedArchive.contentView!), let confirmedCoordinator = confirmedSearch.delegate as? SmartDialogTextField.Coordinator else { throw namingError("缺少确认目标的搜索框") }
    try check(confirmedCoordinator.control(confirmedSearch,textView:NSTextView(),doCommandBy:#selector(NSResponder.insertNewline(_:))),"Native Return invokes selected archive")
    settle()
    try check(archivedClosed && fm.fileExists(atPath:project.appendingPathComponent(archiveFile.lastPathComponent).path) && store.settings.moves.count == 1,"Selected destination reaches confirmed archive")
    confirmedArchive.orderOut(nil); confirmedArchive.contentView = nil
    store.scanCancellation?.cancel(); store.busy = false
    store.undo(store.settings.moves[0],refreshAfter:false)
    try check(fm.fileExists(atPath:archiveFile.path),"Native-dialog archive remains undoable")
    print("PASS: production views; initial suggestion binding; edited name/extension via native Return handler; folder month and dismissal; no selection means no archive; native query binding; search clears hidden prior destination; selected archive via Return and undo. Pointer selection and physical keystrokes not exercised.")
}
