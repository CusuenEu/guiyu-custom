import AppKit

// Authored geometry and text, rendered at 1× and 2× for Finder's native canvas.
let size = NSSize(width:660,height:420)
let output = CommandLine.arguments[1]
let image = NSImage(size:size)
for scale in [1,2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:660*scale,pixelsHigh:420*scale,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
    NSColor(calibratedRed:0.95,green:0.974,blue:0.958,alpha:1).setFill()
    NSRect(origin:.zero,size:size).fill()
    func text(_ value:String,y:CGFloat,font:NSFont,color:NSColor) {
        let paragraph = NSMutableParagraphStyle();paragraph.alignment = .center
        (value as NSString).draw(in:NSRect(x:30,y:y,width:600,height:42),withAttributes:[.font:font,.foregroundColor:color,.paragraphStyle:paragraph])
    }
    let forest = NSColor(calibratedRed:0.14,green:0.38,blue:0.30,alpha:1)
    let secondary = NSColor(calibratedRed:0.30,green:0.40,blue:0.35,alpha:1)
    text("安装归屿",y:326,font:.systemFont(ofSize:28,weight:.semibold),color:forest)
    text("将归屿拖到右侧的“应用程序”文件夹",y:290,font:.systemFont(ofSize:15),color:secondary)
    let arrow = NSBezierPath();arrow.lineWidth = 3;arrow.lineCapStyle = .round;arrow.lineJoinStyle = .round
    arrow.move(to:NSPoint(x:298,y:210));arrow.line(to:NSPoint(x:362,y:210))
    arrow.move(to:NSPoint(x:350,y:222));arrow.line(to:NSPoint(x:362,y:210));arrow.line(to:NSPoint(x:350,y:198))
    forest.setStroke();arrow.stroke()
    text("安装完成后，请从“应用程序”打开归屿。",y:50,font:.systemFont(ofSize:13),color:secondary)
    NSGraphicsContext.restoreGraphicsState()
    image.addRepresentation(bitmap)
}
try image.tiffRepresentation!.write(to:URL(fileURLWithPath:output))
