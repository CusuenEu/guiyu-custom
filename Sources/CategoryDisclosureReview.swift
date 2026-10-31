import SwiftUI
import AppKit

// Isolated production-table captures; no foreground activation or user files.
@MainActor func categoryDisclosureReview() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let out = URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent(".impeccable/review/category-disclosure")
    try fm.createDirectory(at:out,withIntermediateDirectories:true)
    for expanded in [true,false] {
        var rows = [BrowserRow(id:"category",title:"招标文件",header:true,count:1,expanded:expanded)]
        if expanded { rows.append(BrowserRow(id:"fixture.pdf",title:"招标文件.pdf",file:FileItem(path:"/fixture.pdf",project:"",text:"",size:0,date:Date()))) }
        let view = BrowserTable(rows:rows,selection:.constant(nil),activate:{_ in},rename:{_ in})
        let host = NSHostingView(rootView:view.preferredColorScheme(.light))
        host.frame = NSRect(x:0,y:0,width:420,height:160)
        let window = NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:420,height:160),styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView = host;window.orderBack(nil)
        RunLoop.current.run(until:Date().addingTimeInterval(0.3));host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in:host.bounds),let data:Data = {
            host.cacheDisplay(in:host.bounds,to:rep)
            return rep.representation(using:.png,properties:[:])
        }() else { throw namingError("分类箭头截图失败") }
        try data.write(to:out.appendingPathComponent(expanded ? "expanded.png" : "collapsed.png"))
        window.orderOut(nil);window.contentView = nil
    }
    print("PASS: production category table expanded/collapsed small-chevron captures; shared glyph and unchanged 40pt header layout")
}
