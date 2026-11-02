import AppKit

// Layout preview derived from the mounted image; this is not a Finder capture.
let volume = URL(fileURLWithPath:CommandLine.arguments[1])
let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1320,pixelsHigh:840,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
bitmap.size = NSSize(width:660,height:420)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
let background = NSImage(contentsOf:volume.appendingPathComponent(".background.tiff"))!
background.draw(in:NSRect(x:0,y:0,width:660,height:420))
for (file,label,x) in [("归屿.app","归屿.app",CGFloat(180)),("应用程序","应用程序",CGFloat(480))] {
    let icon = NSWorkspace.shared.icon(forFile:volume.appendingPathComponent(file).path)
    icon.draw(in:NSRect(x:x-50,y:160,width:100,height:100))
    let paragraph = NSMutableParagraphStyle();paragraph.alignment = .center
    (label as NSString).draw(in:NSRect(x:x-100,y:128,width:200,height:28),withAttributes:[.font:NSFont.systemFont(ofSize:14),.foregroundColor:NSColor.labelColor,.paragraphStyle:paragraph])
}
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
