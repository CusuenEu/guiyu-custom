import AppKit

// Cached presentation assets; drawing an icon never opens or parses a document.
enum WorkspaceFileIcons {
    private static var cache: [String:NSImage] = [:]
    static func image(for file:FileItem?) -> NSImage? {
        guard let file else { return nil }
        let key: String
        switch file.ext {
        case "doc", "docx": key = "W"
        case "xls", "xlsx": key = "X"
        case "pdf": key = "PDF"
        default: return NSImage(systemSymbolName:file.symbol,accessibilityDescription:"文件")
        }
        if let image = cache[key] { return image }
        let color: NSColor = key == "W" ? .systemBlue : key == "X" ? NSColor(calibratedRed:0.02,green:0.55,blue:0.28,alpha:1) : .systemRed
        let image = NSImage(size:NSSize(width:24,height:28),flipped:false) { _ in
            let body = NSBezierPath(roundedRect:NSRect(x:1,y:1,width:22,height:26),xRadius:3,yRadius:3)
            NSGradient(starting:color.blended(withFraction:0.12,of:.white) ?? color,ending:color)?.draw(in:body,angle:-90)
            let fold = NSBezierPath(); fold.move(to:NSPoint(x:16,y:27)); fold.line(to:NSPoint(x:23,y:20)); fold.line(to:NSPoint(x:16,y:20)); fold.close()
            NSColor.white.withAlphaComponent(0.3).setFill(); fold.fill()
            let label = key as NSString
            let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:key == "PDF" ? 8 : 16,weight:.semibold),.foregroundColor:NSColor.white]
            let size = label.size(withAttributes:attributes)
            label.draw(at:NSPoint(x:(24-size.width)/2,y:(28-size.height)/2-1),withAttributes:attributes)
            return true
        }
        image.isTemplate = false; cache[key] = image; return image
    }
}
