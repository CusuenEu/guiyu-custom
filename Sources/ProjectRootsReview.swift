import SwiftUI
import AppKit

@MainActor func projectRootsUIReview() throws {
    fputs("ROOTS REVIEW: initialize application\n",stderr)
    NSApplication.shared.setActivationPolicy(.prohibited)
    let base = URL(fileURLWithPath:canonicalPath(fm.temporaryDirectory.path)).appendingPathComponent("guiyu-roots-review-"+UUID().uuidString)
    defer { try? fm.removeItem(at:base) }
    let a = base.appendingPathComponent("研究项目"), b = base.appendingPathComponent("交付项目")
    let pa = a.appendingPathComponent("2026/10月 机关网络运维项目"), pb = b.appendingPathComponent("2026/10月 园区网络安全项目")
    for folder in [pa,pb,a.appendingPathComponent("2025"),b.appendingPathComponent("2025")] { try fm.createDirectory(at:folder,withIntermediateDirectories:true) }
    try "fixture".write(to:pa.appendingPathComponent("验收资料.txt"),atomically:true,encoding:.utf8)
    fputs("ROOTS REVIEW: directories ready\n",stderr)
    let store = Store(stateURL:base.appendingPathComponent("settings.json"),loadOnLaunch:false)
    store.settings.categories = WorkspaceCategory.defaults // Existing configured-user fixture.
    store.settings.root = a.path; store.settings.projectRoots = [a.path,b.path]
    fputs("ROOTS REVIEW: store ready\n",stderr)
    store.settings.projects = try discoverProjectRoots([a.path,b.path],saved:[]).projects
    store.files = store.settings.projects.flatMap { metadataFiles($0.path,project:$0.path,recursive:$0.shallow != true,cache:[:]) }; store.metadataReady = true
    fputs("ROOTS REVIEW: metadata ready\n",stderr)
    let out = URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent(".impeccable/review/project-roots")
    try fm.createDirectory(at:out,withIntermediateDirectories:true)
    func capture<V:View>(_ view: V, width:CGFloat, height:CGFloat, name:String) throws {
        fputs("ROOTS REVIEW: create host\n",stderr)
        let host = NSHostingView(rootView:view.background(Color(nsColor:.windowBackgroundColor)).preferredColorScheme(.light))
        fputs("ROOTS REVIEW: size host\n",stderr)
        host.frame = NSRect(x:0,y:0,width:width,height:height)
        let window = NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:width,height:height),styleMask:.borderless,backing:.buffered,defer:false)
        fputs("ROOTS REVIEW: host window\n",stderr)
        window.contentView = host; window.orderBack(nil)
        RunLoop.current.run(until:Date().addingTimeInterval(0.8)); host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw namingError("无法渲染多目录界面") }
        host.cacheDisplay(in:host.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(name))
        window.orderOut(nil)
    }
    fputs("ROOTS REVIEW: capture workspace\n",stderr)
    try capture(ProjectWorkspace(store:store,year:a.appendingPathComponent("2026").path,projectPath:pa.path,sourceFolder:pa.path,sourceRows:try directoryEntries(path:pa.path,project:pa.path)),width:1280,height:820,name:"multiple-roots.png")
    try capture(ProjectWorkspace(store:store,year:b.appendingPathComponent("2026").path,projectPath:pb.path,sourceFolder:pb.path),width:1060,height:760,name:"multiple-roots-minimum.png")
    try capture(WorkspaceSettingsView(store:store,updater:AppUpdater.fixture(),close:{},openPending:{}),width:820,height:620,name:"settings-roots-version.png")
    store.settings.projectRoots = nil; store.settings.root = a.path; store.settings.projects = try discoverProjectRoots([a.path],saved:[]).projects
    try capture(ProjectWorkspace(store:store,year:a.appendingPathComponent("2026").path),width:1280,height:820,name:"single-root-plus.png")
    print("PASS: captured single/multiple project roots, same-name selection at normal/minimum widths, settings links and current version")
}
