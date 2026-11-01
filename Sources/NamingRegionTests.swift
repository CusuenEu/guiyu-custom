import AppKit
import PDFKit
import SwiftUI

@MainActor func namingRegionFixture(_ root:URL) throws -> URL {
    let file = root.appendingPathComponent("框选命名示例.pdf")
    var bounds = CGRect(x:0,y:0,width:600,height:800)
    guard let context = CGContext(file as CFURL,mediaBox:&bounds,nil) else { throw namingError("测试 PDF 无法创建") }
    for index in 0..<3 {
        context.beginPDFPage(nil);NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
        NSColor.white.setFill();bounds.fill()
        ("被审查文件：《某项目招标文件》" as NSString).draw(at:NSPoint(x:50,y:735),withAttributes:[.font:NSFont.systemFont(ofSize:11)])
        let lines = index == 0 ? ["关于投标文件合规性的","审查意见书"] : ["第二页安全检查","记录表"]
        (lines[0] as NSString).draw(at:NSPoint(x:95,y:625),withAttributes:[.font:NSFont.systemFont(ofSize:26,weight:.bold)])
        (lines[1] as NSString).draw(at:NSPoint(x:185,y:585),withAttributes:[.font:NSFont.systemFont(ofSize:26,weight:.bold)])
        ("框外正文不应混入识别结果" as NSString).draw(at:NSPoint(x:60,y:505),withAttributes:[.font:NSFont.systemFont(ofSize:15)])
        ("一、审查依据\n\n依据已提供的材料进行审查。\n\n二、审查结论\n\n此文档仅为隔离测试使用的合成样例。" as NSString).draw(in:NSRect(x:60,y:210,width:480,height:230),withAttributes:[.font:NSFont.systemFont(ofSize:14)])
        NSGraphicsContext.restoreGraphicsState();context.endPDFPage()
    }
    context.closePDF();return file
}

@MainActor func namingRegionWait(_ condition:()->Bool,_ message:String,seconds:Double = 12) throws {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition(),Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.02)) }
    try verify(condition(),message)
}

@MainActor func namingRegionTests(root:URL) throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let directory = root.appendingPathComponent("naming-region");try fm.createDirectory(at:directory,withIntermediateDirectories:true)
    let file = try namingRegionFixture(directory), original = try Data(contentsOf:file)
    let target = NamingTarget(path:file.path,folder:false,projectPath:directory.path)
    try verify(cleanRegionRecognizedText("风险 审查\n报告？。") == "风险审查报告" && cleanRegionRecognizedText("版本 1.2\n最终版") == "版本1.2最终版","Region cleanup removes layout whitespace/punctuation while retaining meaningful English periods")
    try verify(cleanRegionRecognizedText("<>:\"/\\|?*：\u{0}标题") == "标题","Region-generated names remove illegal filename characters")
    let manual = "方案甲😀\n方案乙"
    try verify(selectedNamingText(manual,range:(manual as NSString).range(of:"方案乙")) == "方案乙" && selectedNamingText(manual,range:NSRange(location:0,length:0)) == manual,"Recognized text supports an actual UTF-16 substring selection or the complete editable result")
    let model = NamingPreviewModel();model.load(target)
    try verify(model.state.text.isEmpty,"Recognized text starts empty during preview loading")
    try namingRegionWait({!model.loading},"PDF preview loading completes")
    try verify(model.pages.count == 2 && model.state.text.isEmpty,"Preview only loads the first two actual pages and never autofills page text")
    let region = CGRect(x:0.1,y:0.16,width:0.8,height:0.15)
    let pages = model.pages
    let suggestions = recognizeNamingTitles(FileItem(path:file.path,project:directory.path,text:"",size:1,date:Date()),token:IndexCancellation())
    try verify(suggestions.first?.name == "关于投标文件合规性的审查意见书" && !suggestions.contains{$0.name.hasPrefix("被审查文件")},"Generic cover typography favors the complete two-line report title over a quoted source filename")
    let colors:[UInt8] = [255,0,0,255, 0,255,0,255, 0,0,255,255, 255,255,0,255, 255,0,255,255, 0,255,255,255]
    let provider = CGDataProvider(data:Data(colors) as CFData)!
    let colorImage = CGImage(width:2,height:3,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:8,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
    for turns in 0..<4 {
        let raster = NSBitmapImageRep(cgImage:NamingRegionGeometry.image(colorImage,turns:turns)!)
        for y in 0..<3 { for x in 0..<2 {
            let p = NamingRegionGeometry.point(CGPoint(x:(CGFloat(x)+0.5)/2,y:(CGFloat(y)+0.5)/3),turns:turns)
            let color = raster.colorAt(x:min(raster.pixelsWide-1,Int(p.x*CGFloat(raster.pixelsWide))),y:min(raster.pixelsHigh-1,Int(p.y*CGFloat(raster.pixelsHigh))))!.usingColorSpace(.deviceRGB)!
            let offset = (y*2+x)*4
            try verify(abs(color.redComponent-CGFloat(colors[offset])/255)<0.05 && abs(color.greenComponent-CGFloat(colors[offset+1])/255)<0.05 && abs(color.blueComponent-CGFloat(colors[offset+2])/255)<0.05,"Actual rotated image pixels match normalized original-region geometry")
        } }
    }
    guard let crop = NamingRegionGeometry.crop(pages[0].image,region:region) else { throw namingError("测试裁剪失败") }
    try verify(crop.width < pages[0].image.width && crop.height < pages[0].image.height,"OCR receives an actual cropped image, not the full page with a region hint")
    model.recognize(region)
    try namingRegionWait({!model.state.recognizing},"Local cropped Vision OCR completes",seconds:25)
    try verify(model.state.text == "关于投标文件合规性的审查意见书","Real cropped OCR combines the title lines without the nearby quoted filename or body: \(model.state.text)")
    model.selectPage(1);try verify(model.state.text.isEmpty,"A different page begins with an empty recognition result")
    model.editText("第二页用户纠错？。")
    model.selectPage(0);try verify(model.state.text == "关于投标文件合规性的审查意见书","Returning to a page retains its own selected-region result")
    model.selectPage(1);try verify(model.state.text == "第二页用户纠错？。","Manual recognition edits are retained literally, without destructive normalization")
    model.invalidSelection();try verify(model.state.message.contains("太小"),"Tiny selections explain how to recover")

    // Exercise actual canvas event conversion after scroll/zoom/quarter-turn rotation.
    let scroll = NamingPreviewScrollView(frame:NSRect(x:0,y:0,width:410,height:390));scroll.documentView = scroll.canvas
    let window = NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:410,height:390),styleMask:.borderless,backing:.buffered,defer:false)
    window.contentView = scroll;window.orderBack(nil)
    defer { window.orderOut(nil);window.contentView = nil }
    let source = pages[0].image, expected = CGRect(x:0.2,y:0.25,width:0.35,height:0.2)
    for turns in 0..<4 {
        scroll.canvas.image = NamingRegionGeometry.image(source,turns:turns);scroll.canvas.turns = turns;scroll.canvas.zoom = 2
        scroll.layoutSubtreeIfNeeded();scroll.layoutCanvas()
        let normalized = NamingRegionGeometry.rotated(expected,turns:turns), imageRect = scroll.canvas.imageRect
        let rect = CGRect(x:imageRect.minX+normalized.minX*imageRect.width,y:imageRect.minY+normalized.minY*imageRect.height,width:normalized.width*imageRect.width,height:normalized.height*imageRect.height)
        scroll.contentView.scroll(to:NSPoint(x:max(0,rect.minX-12),y:max(0,rect.minY-12)));scroll.reflectScrolledClipView(scroll.contentView)
        var actual:CGRect?
        scroll.canvas.selected = {actual=$0}
        func event(_ type:NSEvent.EventType,_ point:NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with:type,location:scroll.canvas.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        }
        let start = CGPoint(x:rect.minX,y:rect.minY), end = CGPoint(x:rect.maxX,y:rect.maxY)
        scroll.canvas.mouseDown(with:event(.leftMouseDown,start));scroll.canvas.mouseDragged(with:event(.leftMouseDragged,end));scroll.canvas.mouseUp(with:event(.leftMouseUp,end))
        try verify(actual.map{abs($0.minX-expected.minX)<0.001 && abs($0.minY-expected.minY)<0.001 && abs($0.width-expected.width)<0.001 && abs($0.height-expected.height)<0.001} == true,"Native scrolled/zoomed drag maps back to the same original image region at rotation \(turns)")
    }
    // Deliberately finish a cancelled request late to test publication guards.
    let late = NamingPreviewModel(recognizer:{_,_ in Thread.sleep(forTimeInterval:0.15);return "不应回写的旧结果"})
    late.load(target);try namingRegionWait({!late.loading},"Cancellation fixture loads")
    late.recognize(region);late.selectPage(1)
    RunLoop.current.run(until:Date().addingTimeInterval(0.25))
    try verify(late.state.text.isEmpty,"Switching pages rejects an old page's late OCR completion")
    late.selectPage(0);late.recognize(region);late.editText("用户手动输入")
    RunLoop.current.run(until:Date().addingTimeInterval(0.25))
    try verify(late.state.text == "用户手动输入","Manual edits cancel in-flight recognition and cannot be overwritten")
    late.recognize(region);late.cancel();RunLoop.current.run(until:Date().addingTimeInterval(0.25))
    try verify(late.state.text.isEmpty,"Closing cancels pending work and prevents late result publication")
    model.cancel()
    let unchanged = try Data(contentsOf:file)
    try verify(unchanged == original,"Preview, rectangle OCR, rotation, text editing and cancellation never modify the source bytes")
    print("PASS: actual cropped local OCR, first-two-page preview, selected-text cleanup, page retention, scrolled/zoomed rotated native drag coordinates, tiny selection recovery, manual edits/cancellation guards and unchanged source bytes")
}
