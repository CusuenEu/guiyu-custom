import SwiftUI
import AppKit
let green = Color(red:0.14,green:0.38,blue:0.30)
let mint = Color(red:0.876,green:0.955,blue:0.925)
struct Guide:View {
    let stage:Int
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Image(systemName:stage == 1 ? "globe" : "square.grid.2x2").foregroundStyle(green); Text(stage == 1 ? "豆包官网 · 操作示意" : "归屿 · 文件分类").fontWeight(.semibold); Spacer() }.font(.system(size:15))
            Divider()
            if stage == 0 {
                Text("分类设置后，请务必按一下操作。").foregroundStyle(Color(red:0.7,green:0.16,blue:0.13)).font(.system(size:16,weight:.semibold))
                label("复制提示词，去豆包官网",symbol:"doc.on.doc",filled:true)
                Text("复制成功，请去豆包提问").font(.system(size:14)).foregroundStyle(green)
            } else if stage == 1 {
                Text("把复制的提示词粘贴给豆包，然后发送。").font(.system(size:16))
                HStack { Text("粘贴提示词…").foregroundStyle(.secondary); Spacer(); label("发送",symbol:"arrow.up",filled:true) }.padding(12).background(mint.opacity(0.4),in:RoundedRectangle(cornerRadius:8))
                HStack { Image(systemName:"text.bubble").foregroundStyle(green); Text("豆包生成的完整分类规则"); Spacer(); label("复制回复",symbol:"doc.on.doc",filled:false) }
            } else {
                Text("复制完整回复后，回到归屿。").font(.system(size:16))
                label("录入豆包回复",symbol:"clipboard",filled:true)
                Label("录入成功，已更新分类规则",systemImage:"checkmark.circle.fill").font(.system(size:14)).foregroundStyle(green)
            }
            Spacer(minLength:0)
        }.padding(22).frame(width:560,height:230,alignment:.topLeading).background(Color.white).foregroundStyle(Color(red:0.09,green:0.14,blue:0.13))
    }
    func label(_ text:String,symbol:String,filled:Bool)->some View { Label(text,systemImage:symbol).font(.system(size:14,weight:.medium)).padding(.horizontal,14).frame(height:36).foregroundStyle(filled ? .white : green).background(filled ? green : mint,in:RoundedRectangle(cornerRadius:8)) }
}
NSApplication.shared.setActivationPolicy(.prohibited)
let output=URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
for (index,name) in ["copy-prompt","doubao-message","import-rules"].enumerated() {
    let host=NSHostingView(rootView:Guide(stage:index).preferredColorScheme(.light));host.frame=NSRect(x:0,y:0,width:560,height:230)
    let window=NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:560,height:230),styleMask:.borderless,backing:.buffered,defer:false)
    window.contentView=host;window.orderBack(nil);RunLoop.current.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded()
    let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
    try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
    window.orderOut(nil)
}
