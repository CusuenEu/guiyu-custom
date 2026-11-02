import AppKit
import SwiftUI

@MainActor func fileCopyTests(root:URL) throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let directory = root.appendingPathComponent("file-copy")
    let folder = directory.appendingPathComponent("项目 资料 #1")
    try fm.createDirectory(at:folder,withIntermediateDirectories:true)
    let file = directory.appendingPathComponent("合同 中文 #2.pdf")
    let nested = folder.appendingPathComponent("内部文档.txt")
    try Data("temporary document".utf8).write(to:file)
    try Data("nested document".utf8).write(to:nested)
    let original = try Data(contentsOf:file), identity = fileIdentity(file.path)
    let pasteboard = NSPasteboard.withUniqueName();defer { pasteboard.releaseGlobally() }
    func urls() -> [URL] { (pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]) ?? [] }
    func key(_ flags:NSEvent.ModifierFlags = .command,_ character:String = "c",_ code:UInt16 = 8) -> NSEvent {
        NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:character,charactersIgnoringModifiers:character,isARepeat:false,keyCode:code)!
    }
    try verify(fileShortcut(for:key()) == .copy && fileShortcut(for:key([.command,.capsLock],"C")) == .copy,"Command-C supports native uppercase/caps-lock events")
    try verify(fileShortcut(for:key([])) == nil && fileShortcut(for:key([.command,.option])) == nil && fileShortcut(for:key([.command,.shift])) == nil && fileShortcut(for:key(.command,"j")) == nil,"Copy does not intercept typing, other shortcuts or a remapped non-C key")
    let rows = [BrowserRow(id:"category",title:"分类",header:true),BrowserRow(id:file.path,title:file.lastPathComponent),BrowserRow(id:folder.path,title:folder.lastPathComponent,folder:true)]
    try verify(copyFileRows(rows+[rows[1]],to:pasteboard) && urls().map(\.path) == [file.path,folder.path],"Mixed Unicode file/folder selection writes ordered, deduplicated native file URLs, excluding category headers")
    try verify(pasteboard.pasteboardItems?.allSatisfy{$0.types.contains(.fileURL)} == true,"Each selected entry is a native file object, not just filename text")
    let count = pasteboard.changeCount
    try verify(!copyFileRows([],to:pasteboard) && !copyFileRows([rows[0]],to:pasteboard) && !copyFilePaths([file.path,directory.appendingPathComponent("missing.txt").path],to:pasteboard) && pasteboard.changeCount == count,"Empty/header/stale selections preserve the existing clipboard without a partial copy")

    func findTable(_ view:NSView) -> BrowserNSTable? {
        if let table = view as? BrowserNSTable { return table }
        return view.subviews.lazy.compactMap(findTable).first
    }
    for style in [BrowserTableAppearance.files,.projects] {
        let multiple = style == .files
        let browser = BrowserTable(rows:rows,selection:.constant(multiple ? nil : folder.path),multipleSelection:multiple ? .constant([file.path,folder.path]) : nil,appearance:style,activate:{_ in},rename:{_ in})
        let host = NSHostingView(rootView:browser);host.frame = NSRect(x:0,y:0,width:500,height:220)
        let window = NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:500,height:220),styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView = host;window.orderBack(nil);host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until:Date().addingTimeInterval(0.1))
        guard let table = findTable(host) else { throw namingError("缺少复制测试原生列表") }
        table.copyPasteboard = pasteboard;window.makeFirstResponder(table)
        try verify(table.performKeyEquivalent(with:key()) && urls().map(\.path) == (multiple ? [file.path,folder.path] : [folder.path]),"Production browser native Command-C copies its actual selection for file and project layouts")
        pasteboard.clearContents();pasteboard.setString("sentinel",forType:.string)
        try verify(window.firstResponder?.tryToPerform(#selector(BrowserNSTable.copy(_:)),with:nil) == true && !urls().isEmpty,"Standard responder-chain Copy action uses the same focused selection")
        let editor = NSTextView(frame:NSRect(x:0,y:0,width:100,height:30));host.addSubview(editor);editor.string = "仅复制选中的文字";window.makeFirstResponder(editor);editor.setSelectedRange(NSRange(location:0,length:3))
        let unchanged = pasteboard.changeCount
        try verify(!table.performFileShortcut(key()),"A text editor retains Command-C even while files remain selected")
        table.copy(nil)
        try verify(pasteboard.changeCount == unchanged,"Copy responder action never copies files behind a focused text editor")
        try verify(editor.writeSelection(to:pasteboard,types:editor.writablePasteboardTypes) && pasteboard.string(forType:.string) == "仅复制","Native selected-text copying remains available on its own pasteboard")
        editor.removeFromSuperview();window.makeFirstResponder(table)
        let sheet = NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:120,height:80),styleMask:.titled,backing:.buffered,defer:false)
        window.beginSheet(sheet)
        let beforeSheet = pasteboard.changeCount
        try verify(!table.performFileShortcut(key()),"A modal sheet blocks background-table file copying")
        table.copy(nil);try verify(pasteboard.changeCount == beforeSheet)
        window.endSheet(sheet);sheet.orderOut(nil)
        RunLoop.current.run(until:Date().addingTimeInterval(0.1))
        window.orderOut(nil);window.contentView = nil
    }

    let sidebar = DirectoryOrderRowView(frame:NSRect(x:0,y:0,width:220,height:57))
    sidebar.payload = DirectoryOrderPayload(root:directory.path,path:folder.path);sidebar.selected = true;sidebar.copyPasteboard = pasteboard
    let window = NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:220,height:57),styleMask:.borderless,backing:.buffered,defer:false)
    window.contentView = sidebar
    let event = NSEvent.mouseEvent(with:.leftMouseDown,location:NSPoint(x:20,y:20),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
    sidebar.mouseDown(with:event)
    try verify(window.firstResponder === sidebar && sidebar.performKeyEquivalent(with:key()) && urls().map(\.path) == [folder.path],"Clicking the sidebar takes focus and copies that directory instead of the old file-table selection")
    window.orderOut(nil);window.contentView = nil

    try verify(copyFileRows(rows,to:pasteboard))
    let destination = directory.appendingPathComponent("PasteRecipient");try fm.createDirectory(at:destination,withIntermediateDirectories:true)
    for url in urls() { try fm.copyItem(at:url,to:destination.appendingPathComponent(url.lastPathComponent)) }
    let pasted = try Data(contentsOf:destination.appendingPathComponent(file.lastPathComponent))
    let nestedCopy = try Data(contentsOf:destination.appendingPathComponent(folder.lastPathComponent).appendingPathComponent(nested.lastPathComponent))
    let source = try Data(contentsOf:file)
    try verify(pasted == original && nestedCopy == Data("nested document".utf8) && source == original && fileIdentity(file.path) == identity,"A native file-URL recipient can copy documents and complete folders; original bytes and identities are unchanged")
    print("PASS: native Command-C and responder Copy, real file/folder URL pasteboard payloads, multi-selection and project/sidebar focus, text-editor/modal exclusion, empty/stale preservation and isolated recipient copies; general clipboard untouched")
}
