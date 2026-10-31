import SwiftUI
import AppKit

@MainActor func archiveSourceLayoutReview() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let root = fm.temporaryDirectory.appendingPathComponent("GuiyuSourceLayout-"+UUID().uuidString)
    let download = root.appendingPathComponent("Downloads"), year = root.appendingPathComponent("2026")
    for directory in [download,year] { try fm.createDirectory(at:directory,withIntermediateDirectories:true) }
    defer { try? fm.removeItem(at:root) }
    try "示例资料".write(to:download.appendingPathComponent("招标文件.txt"),atomically:true,encoding:.utf8)
    try fm.createDirectory(at:download.appendingPathComponent("示例项目"),withIntermediateDirectories:true)
    let store = Store(stateURL:root.appendingPathComponent("state/settings.json"),loadOnLaunch:false)
    store.settings.root = root.path;store.settings.categories = WorkspaceCategory.defaults
    store.settings.projects = [Project(path:year.path,name:"2026",group:"2026",shallow:true)]
    store.settings.archiveSources = [ArchiveSource(id:"downloads",name:"下载",kind:"folder",path:download.path),ArchiveSource(id:"recent",name:"最近使用",kind:"recent",path:"")]
    store.metadataReady = true
    let out = URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent(".impeccable/review/archive-source-layout")
    try fm.createDirectory(at:out,withIntermediateDirectories:true)
    for source in ["downloads","recent"] {
        for size in [NSSize(width:1280,height:820),NSSize(width:1060,height:700)] {
            let host = NSHostingView(rootView:ProjectWorkspace(store:store,year:"2026",archiveSourceID:source).preferredColorScheme(.light))
            host.frame = NSRect(origin:.zero,size:size)
            let window = NSWindow(contentRect:NSRect(origin:NSPoint(x:-5000,y:-5000),size:size),styleMask:.borderless,backing:.buffered,defer:false)
            window.contentView = host;window.orderBack(nil)
            RunLoop.current.run(until:Date().addingTimeInterval(0.8));host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw namingError("来源列表截图失败") }
            host.cacheDisplay(in:host.bounds,to:rep)
            try rep.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(source+"-\(Int(size.width)).png"))
            window.orderOut(nil);window.contentView = nil
        }
    }
    print("PASS: Downloads and Recents native workspace captures at 1280/1060pt; shared toolbar and plain list presentation. Downloads use temporary fixtures; Recents uses the real read-only system metadata query. No file operations or foreground activation.")
}
