import AppKit
let image = NSImage(size:NSSize(width:1024,height:1024))
image.lockFocus()
NSColor(calibratedRed:0.14,green:0.38,blue:0.30,alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:40,y:40,width:944,height:944),xRadius:210,yRadius:210).fill()
for i in (0...2).reversed() {
    NSColor(calibratedWhite:1,alpha:CGFloat(1)-CGFloat(i)*0.22).setFill()
    let y = CGFloat(300+i*135)
    let path = NSBezierPath(); path.move(to:NSPoint(x:250,y:y+70)); path.line(to:NSPoint(x:512,y:y+210)); path.line(to:NSPoint(x:774,y:y+70)); path.line(to:NSPoint(x:512,y:y-70)); path.close(); path.fill()
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
