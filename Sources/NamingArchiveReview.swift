import SwiftUI
import AppKit

@MainActor func namingArchiveUIReview() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let root = fm.temporaryDirectory.appendingPathComponent("GuiyuNamingArchive-"+UUID().uuidString)
    try fm.createDirectory(at:root,withIntermediateDirectories:true)
    defer { try? fm.removeItem(at:root) }
    let out = URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent(".impeccable/review/naming-archive")
    try fm.createDirectory(at:out,withIntermediateDirectories:true)
    func settle(_ seconds:Double = 0.12) {RunLoop.current.run(until:Date().addingTimeInterval(seconds))}
    func find<T>(_ view:NSView,_ type:T.Type) -> T? { (view as? T) ?? view.subviews.lazy.compactMap{find($0,type)}.first }
    func button(_ view:NSView) -> NSButton? {
        if let b = view as? NSButton,b.identifier?.rawValue == "confirm-name-and-archive" {return b}
        return view.subviews.lazy.compactMap(button).first
    }
    func capture(_ window:NSWindow,_ name:String) throws {
        settle()
        let view = window.contentView!;view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else {throw namingError("命名归档截图失败")}
        view.cacheDisplay(in:view.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(name))
    }
    func mount<V:View>(_ view:V,_ size:NSSize) -> NSWindow {
        let host = NSHostingView(rootView:view.preferredColorScheme(.light));host.frame = NSRect(origin:.zero,size:size)
        let window = NSWindow(contentRect:NSRect(origin:NSPoint(x:-5000,y:-5000),size:size),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false;window.contentView = host;window.orderBack(nil);settle();return window
    }
    func dispose(_ window:NSWindow) {
        while let sheet = window.attachedSheet {window.endSheet(sheet);sheet.orderOut(nil)}
        window.orderOut(nil);window.contentView = nil;settle()
    }
    func fixture(_ name:String) throws -> (Store,URL,URL) {
        let directory = root.appendingPathComponent(name),inbox = directory.appendingPathComponent("inbox"),workspace = directory.appendingPathComponent("workspace")
        let destination = workspace.appendingPathComponent("2026/目标项目")
        try fm.createDirectory(at:inbox,withIntermediateDirectories:true);try fm.createDirectory(at:destination,withIntermediateDirectories:true)
        let pdf = try namingRegionFixture(inbox)
        let store = Store(stateURL:directory.appendingPathComponent("state/settings.json"),loadOnLaunch:false)
        store.settings.root = workspace.path;store.settings.inbox = inbox.path
        store.settings.archiveSources = [ArchiveSource(id:"fixture",name:"测试下载",kind:"folder",path:inbox.path)]
        store.settings.projects = [Project(path:workspace.appendingPathComponent("2026").path,name:"2026",group:"2026",shallow:true),Project(path:destination.path,name:"目标项目",group:"2026",shallow:false)]
        return (store,pdf,inbox)
    }
    func renameSheet(_ parent:NSWindow) throws -> NSWindow {
        try namingRegionWait({parent.attachedSheet.map{button($0.contentView!) != nil} == true},"Production naming sheet opens")
        let sheet = parent.attachedSheet!
        try namingRegionWait({button(sheet.contentView!)?.isEnabled == true},"Naming actions become available")
        return sheet
    }
    func edit(_ window:NSWindow,_ value:String) throws {
        guard let field = find(window.contentView!,SidebarNativeTextField.self) else {throw namingError("缺少名称编辑框")}
        field.stringValue = value;field.delegate?.controlTextDidChange?(Notification(name:NSControl.textDidChangeNotification,object:field));settle()
    }
    func transition(_ parent:NSWindow,_ naming:NSWindow,_ file:URL,_ inbox:URL,_ stem:String) throws {
        try edit(naming,stem)
        guard let action = button(naming.contentView!) else {throw namingError("缺少确认并归档按钮")}
        action.performClick(nil)
        try namingRegionWait({parent.attachedSheet != nil && parent.attachedSheet !== naming && button(parent.attachedSheet!.contentView!) == nil},"Naming dismissal is followed by a fresh archive sheet")
        try verify(!fm.fileExists(atPath:file.path) && fm.fileExists(atPath:inbox.appendingPathComponent(stem+".pdf").path),"The actual native action renames before the archive presentation")
    }

    let (mainStore,mainFile,mainInbox) = try fixture("workspace")
    let main = mount(ProjectWorkspace(store:mainStore,naming:NamingTarget(path:mainFile.path,folder:false,projectPath:"")),NSSize(width:1280,height:820))
    let mainNaming = try renameSheet(main)
    try capture(mainNaming,"workspace-file-actions.png")
    try edit(mainNaming,"");try verify(button(mainNaming.contentView!)?.isEnabled == false,"Empty final names disable the new action")
    try capture(mainNaming,"empty-name-disabled.png")
    try transition(main,mainNaming,mainFile,mainInbox,"主窗口确认标题")
    try verify(mainStore.settings.moves.isEmpty && mainStore.settings.renames?.count == 1,"Main-window handoff renames once and performs no automatic archive move")
    try capture(main.attachedSheet!,"workspace-archive.png");dispose(main)
    try verify(fm.fileExists(atPath:mainInbox.appendingPathComponent("主窗口确认标题.pdf").path),"Closing the archive flow keeps the successful rename")
    mainStore.scanCancellation?.cancel()

    let (sourceStore,sourceFile,sourceInbox) = try fixture("source")
    let source = mount(ArchiveSourcePane(store:sourceStore,source:ArchiveSource(id:"fixture",name:"测试下载",kind:"folder",path:sourceInbox.path)),NSSize(width:1100,height:800))
    try namingRegionWait({find(source.contentView!,BrowserNSTable.self).map{$0.numberOfRows>0} == true},"Production source list loads fixture rows")
    guard let coordinator = find(source.contentView!,BrowserNSTable.self)?.delegate as? BrowserTable.Coordinator else {throw namingError("缺少来源列表事件")}
    guard let row = coordinator.rows.first(where:{canonicalPath($0.id) == canonicalPath(sourceFile.path)}) else {throw namingError("来源测试文件不在原生列表中")}
    coordinator.contextRow = row;coordinator.renameClicked()
    let sourceNaming = try renameSheet(source)
    try transition(source,sourceNaming,sourceFile,sourceInbox,"下载确认标题")
    try verify(sourceStore.settings.moves.isEmpty && sourceStore.settings.renames?.count == 1,"Archive-source handoff uses the new path without moving it")
    try capture(source.attachedSheet!,"source-archive.png");dispose(source);sourceStore.scanCancellation?.cancel()

    let (finderStore,finderFile,finderInbox) = try fixture("finder")
    var windows:[NSWindow] = []
    let provider = FinderServices(store:finderStore,presentWindow:{window in
        if let view = window.contentView {view.layoutSubtreeIfNeeded();window.setContentSize(view.fittingSize)}
        window.setFrameOrigin(NSPoint(x:-5000,y:-5000));window.orderBack(nil);windows.append(window)
    })
    let pasteboard = NSPasteboard.withUniqueName();defer {pasteboard.releaseGlobally()}
    pasteboard.writeObjects([finderFile as NSURL]);var failure:NSString?
    provider.smartNaming(pasteboard,userData:nil,error:&failure)
    try verify(failure == nil && windows.count == 1,"Finder naming service opens an isolated real window")
    let finderNaming = windows[0]
    try namingRegionWait({button(finderNaming.contentView!)?.isEnabled == true},"Finder action becomes enabled")
    try edit(finderNaming,"服务确认标题");button(finderNaming.contentView!)!.performClick(nil)
    try namingRegionWait({windows.count==2},"Finder naming window closes before an archive window opens")
    try verify(windows[1].title == "归屿-智能归档" && fm.fileExists(atPath:finderInbox.appendingPathComponent("服务确认标题.pdf").path) && finderStore.settings.moves.isEmpty,"Finder handoff switches to archive with the renamed source and no move")
    try capture(windows[1],"finder-archive.png");windows[1].close();settle();finderStore.scanCancellation?.cancel()

    let (folderStore,_,folderInbox) = try fixture("folder")
    let folder = folderInbox.appendingPathComponent("原文件夹");try fm.createDirectory(at:folder,withIntermediateDirectories:true)
    var folderHandoff:QuickArchiveRequest?,folderClosed = false
    let compact = mount(RenameDialog(store:folderStore,target:NamingTarget(path:folder.path,folder:true,projectPath:""),onClose:{folderClosed=true},onArchive:{folderHandoff=$0}),NSSize(width:700,height:460))
    try namingRegionWait({button(compact.contentView!)?.isEnabled == true},"Compact folder naming action is available")
    try capture(compact,"folder-actions.png")
    try edit(compact,"文件夹确认标题");button(compact.contentView!)!.performClick(nil)
    try verify(folderClosed && folderHandoff?.rows.first?.id == folderInbox.appendingPathComponent("文件夹确认标题").path && folderHandoff?.rows.first?.folder == true,"Compact folder action uses the same native handoff")
    dispose(compact)
    print("PASS: actual native Confirm-and-Archive button, required order/disabled state, production workspace/source onDismiss handoff, Finder window replacement, compact folder path, successful rename retained on cancellation; no user data or physical input")
}
