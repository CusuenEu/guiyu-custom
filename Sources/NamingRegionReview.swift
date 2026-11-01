import SwiftUI
import AppKit
import ImageIO
import PDFKit

@MainActor func namingRegionUIReview() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let root = fm.temporaryDirectory.appendingPathComponent("GuiyuRegionUI-"+UUID().uuidString)
    try fm.createDirectory(at:root,withIntermediateDirectories:true)
    defer { try? fm.removeItem(at:root) }
    let pdf = try namingRegionFixture(root), before = try Data(contentsOf:pdf)
    let target = NamingTarget(path:pdf.path,folder:false,projectPath:root.path)
    let store = Store(stateURL:root.appendingPathComponent("state/settings.json"),loadOnLaunch:false)
    let out = URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent(".impeccable/review/naming-region")
    try fm.createDirectory(at:out,withIntermediateDirectories:true)
    func settle(_ seconds:Double = 0.08) { RunLoop.current.run(until:Date().addingTimeInterval(seconds)) }
    func mount(_ view:RenameDialog) -> NSWindow {
        let host = NSHostingView(rootView:view.preferredColorScheme(.light));host.frame = NSRect(x:0,y:0,width:1000,height:660)
        let window = NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:1000,height:660),styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView = host;window.orderBack(nil);host.layoutSubtreeIfNeeded();settle(0.02);return window
    }
    func capture(_ window:NSWindow,_ name:String) throws {
        let host = window.contentView!;host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw namingError("框选命名截图失败") }
        host.cacheDisplay(in:host.bounds,to:rep)
        try rep.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(name))
    }
    func find<T>(_ view:NSView,_ type:T.Type) -> T? { (view as? T) ?? view.subviews.lazy.compactMap{find($0,type)}.first }
    func useTextButton(_ view:NSView) -> NSButton? {
        if let button = view as? NSButton,button.identifier?.rawValue == "naming-use-recognized-text" { return button }
        return view.subviews.lazy.compactMap{useTextButton($0)}.first
    }
    func edit(_ field:NSTextField,_ text:String) { field.stringValue = text;field.delegate?.controlTextDidChange?(Notification(name:NSControl.textDidChangeNotification,object:field));settle() }
    let model = NamingPreviewModel(loader:{target,token in Thread.sleep(forTimeInterval:0.6);return try loadNamingPreview(target,token:token)},recognizer:{image,task in Thread.sleep(forTimeInterval:0.3);return try recognizeNamingCrop(image,task:task)})
    var closed = false
    let window = mount(RenameDialog(store:store,target:target,preview:model,onClose:{closed=true}))
    defer { window.orderOut(nil);window.contentView = nil }
    try capture(window,"loading.png")
    try namingRegionWait({!model.loading && model.pages.count == 2},"Native sheet preview finishes loading")
    guard let input = find(window.contentView!,SidebarNativeTextField.self),let editor = find(window.contentView!,NSTextView.self) else { throw namingError("新版编辑区未挂载") }
    try namingRegionWait({!input.stringValue.isEmpty},"Native sheet recommendations populate the final name")
    try verify(editor.string.isEmpty,"The actual recognized-text editor is empty before any rectangle is selected")
    try capture(window,"initial.png")
    guard let canvas = find(window.contentView!,NamingRegionCanvas.self) else { throw namingError("缺少原生框选预览") }
    let region = CGRect(x:0.1,y:0.16,width:0.8,height:0.15), box = canvas.imageRect
    let a = CGPoint(x:box.minX+box.width*region.minX,y:box.minY+box.height*region.minY),b = CGPoint(x:box.minX+box.width*region.maxX,y:box.minY+box.height*region.maxY)
    func event(_ type:NSEvent.EventType,_ point:CGPoint) -> NSEvent { NSEvent.mouseEvent(with:type,location:canvas.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)! }
    canvas.mouseDown(with:event(.leftMouseDown,a));canvas.mouseDragged(with:event(.leftMouseDragged,b));canvas.mouseUp(with:event(.leftMouseUp,b));settle(0.02)
    try capture(window,"recognizing.png")
    try namingRegionWait({!model.state.recognizing && !model.state.text.isEmpty},"Native rectangle selection invokes local OCR",seconds:25)
    try verify(editor.string == "关于投标文件合规性的审查意见书","The native editor displays only the selected title")
    try capture(window,"recognized.png")
    model.selectPage(1);settle();try verify(editor.string.isEmpty,"The native editor switches to the other page's result")
    try capture(window,"page-two.png")
    model.selectPage(0);model.zoom = 1.5;model.rotate();settle();try capture(window,"rotated-zoom.png")
    guard let textCoordinator = editor.delegate as? NamingRecognizedTextEditor.Coordinator else { throw namingError("缺少识别文字编辑绑定") }
    editor.string = "版本 1.2\n最终版？。";textCoordinator.textDidChange(Notification(name:NSText.didChangeNotification,object:editor))
    editor.setSelectedRange((editor.string as NSString).range(of:"1.2"));textCoordinator.textViewDidChangeSelection(Notification(name:NSTextView.didChangeSelectionNotification,object:editor));settle()
    guard let useButton = useTextButton(window.contentView!),useButton.isEnabled else { throw namingError("缺少可用的原生识别文字按钮") }
    useButton.performClick(nil)
    settle();try verify(input.stringValue == "1.2","The selected substring, rather than the full recognized text, fills the final filename")
    try capture(window,"use-selected-text.png")
    edit(input,"用户 完整标题 1.2")
    try capture(window,"manual-final.png")
    let stillOriginal = try Data(contentsOf:pdf)
    try verify(stillOriginal == before && (store.settings.renames ?? []).isEmpty,"Preview, OCR and editor actions leave source bytes and name unchanged")
    guard let coordinator = input.delegate as? SmartDialogTextField.Coordinator else { throw namingError("缺少最终名称事件") }
    _ = coordinator.control(input,textView:NSTextView(),doCommandBy:#selector(NSResponder.insertNewline(_:)))
    try verify(closed && fm.fileExists(atPath:root.appendingPathComponent("用户 完整标题 1.2.pdf").path),"Only confirmation applies the literal manual name and protected extension")

    let text = root.appendingPathComponent("资料.txt");try "标题：示例技术方案".write(to:text,atomically:true,encoding:.utf8)
    let unsupported = mount(RenameDialog(store:store,target:NamingTarget(path:text.path,folder:false,projectPath:root.path)))
    settle(0.3);try capture(unsupported,"unsupported.png");unsupported.orderOut(nil);unsupported.contentView = nil
    let corrupt = root.appendingPathComponent("损坏样例.pdf");try Data("not-a-pdf".utf8).write(to:corrupt)
    let bad = mount(RenameDialog(store:store,target:NamingTarget(path:corrupt.path,folder:false,projectPath:root.path)))
    settle(0.3);try capture(bad,"damaged.png");bad.orderOut(nil);bad.contentView = nil
    let image = root.appendingPathComponent("图片样例.png")
    let destination = CGImageDestinationCreateWithURL(image as CFURL,"public.png" as CFString,1,nil)!
    CGImageDestinationAddImage(destination,model.pages[0].image,nil);try verify(CGImageDestinationFinalize(destination))
    let imageModel = NamingPreviewModel()
    let picture = mount(RenameDialog(store:store,target:NamingTarget(path:image.path,folder:false,projectPath:root.path),preview:imageModel))
    try namingRegionWait({!imageModel.loading && imageModel.pages.count == 1},"Image uses a single available preview page")
    imageModel.recognize(CGRect(x:0.1,y:0.93,width:0.7,height:0.04));try namingRegionWait({!imageModel.state.recognizing},"Empty image crop finishes",seconds:25)
    try verify(imageModel.state.text.isEmpty && imageModel.state.message.contains("未识别"),"An empty rectangle gives a readable retry/manual-entry message")
    try capture(picture,"image-empty-region.png");imageModel.invalidSelection();settle();try capture(picture,"tiny-selection.png")
    picture.orderOut(nil);picture.contentView = nil
    let encrypted = root.appendingPathComponent("加密样例.pdf")
    let pdfDocument = PDFDocument(url:root.appendingPathComponent("用户 完整标题 1.2.pdf"))!
    try verify(pdfDocument.write(to:encrypted,withOptions:[.userPasswordOption:"fixture-password",.ownerPasswordOption:"fixture-owner"]))
    let lockedModel = NamingPreviewModel()
    let locked = mount(RenameDialog(store:store,target:NamingTarget(path:encrypted.path,folder:false,projectPath:root.path),preview:lockedModel))
    try namingRegionWait({!lockedModel.loading},"Encrypted preview reports a clear manual-entry fallback")
    try verify(lockedModel.notice.contains("加密"),"Encrypted documents have an honest preview error")
    try capture(locked,"encrypted.png");locked.orderOut(nil);locked.contentView = nil
    print("PASS: native two-column loading/initial/region OCR/page switch/rotation/selection-to-final/manual confirmation, image/tiny/empty/unsupported/corrupt/encrypted states; no real user files or physical input")
}
