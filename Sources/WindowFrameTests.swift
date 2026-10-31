import AppKit
import SwiftUI

@MainActor func windowFrameReadTest(_ name:String) throws {
    guard name.hasPrefix("GuiyuWindowTest-") else { throw namingError("窗口测试名称无效") }
    NSApplication.shared.setActivationPolicy(.prohibited)
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:600,height:400),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    guard window.setFrameUsingName(name,force:true) else { throw namingError("未找到已保存的测试窗口") }
    let frame = window.frame
    let data = try JSONEncoder().encode([frame.origin.x,frame.origin.y,frame.width,frame.height])
    print(String(decoding:data,as:UTF8.self))
}

@MainActor func windowFrameTest(root:URL) throws {
    let main = NSRect(x:0,y:0,width:1600,height:1000), second = NSRect(x:-1440,y:100,width:1440,height:900)
    let minSize = NSSize(width:1060,height:700)
    let saved = NSRect(x:-1300,y:200,width:1200,height:750)
    try verify(WindowFrameGeometry.fitted(saved,screens:[main,second],preferred:main,minimum:minSize) == saved,"An available second display retains exact window size and position")
    let removed = WindowFrameGeometry.fitted(NSRect(x:9000,y:3000,width:1800,height:1200),screens:[main],preferred:main,minimum:minSize)
    try verify(main.contains(removed) && removed.size == main.size,"Disconnected display and oversized frame restore within the active display")
    let small = WindowFrameGeometry.fitted(NSRect(x:100,y:100,width:200,height:100),screens:[main],preferred:main,minimum:minSize)
    try verify(small.size == minSize && main.contains(small),"Restoration retains the workspace's minimum size")
    let tinyScreen = NSRect(x:0,y:0,width:1024,height:600)
    let tiny = WindowFrameGeometry.fitted(saved,screens:[tinyScreen],preferred:tinyScreen,minimum:minSize)
    try verify(tiny.minX == tinyScreen.minX && tiny.maxY == tinyScreen.maxY,"A smaller physical display keeps the window title area reachable")

    NSApplication.shared.setActivationPolicy(.prohibited)
    let name = "GuiyuWindowTest-"+UUID().uuidString, key = "NSWindow Frame "+name
    defer { NSWindow.removeFrame(usingName:name); UserDefaults.standard.removeObject(forKey:key) }
    func settle(_ seconds:Double = 0.3) { RunLoop.current.run(until:Date().addingTimeInterval(seconds)) }
    func near(_ a:NSRect,_ b:NSRect) -> Bool {
        abs(a.minX-b.minX) <= 1 && abs(a.minY-b.minY) <= 1 && abs(a.width-b.width) <= 1 && abs(a.height-b.height) <= 1
    }
    func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect:NSRect(x:40,y:40,width:600,height:400),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; return window
    }
    let bounds = NSScreen.main?.visibleFrame ?? main
    let first = makeWindow()
    let controller = MainWindowFrameController(name:name,minimumContentSize:NSSize(width:400,height:300))
    let initial = first.frame
    controller.attach(first)
    try verify(first.frame == initial,"A first launch without saved geometry retains the default size")
    let desired = NSRect(x:bounds.minX+40,y:bounds.minY+40,width:min(1200,bounds.width-80),height:min(780,bounds.height-80))
    first.setFrame(desired,display:false); settle()
    try verify(UserDefaults.standard.string(forKey:key) != nil,"Native resize/move notifications save geometry without explicit confirmation")
    controller.attach(first)
    try verify(near(first.frame,desired),"Repeated attachment during SwiftUI updates cannot reset a user-resized window")
    let latest = desired.offsetBy(dx:12,dy:8)
    first.setFrame(latest,display:false)
    first.close() // Closing flushes before the coalesced save fires.
    try verify(controller.window == nil,"Closing detaches the window and flushes its latest frame")
    UserDefaults.standard.synchronize()
    let output = run(CommandLine.arguments[0],["--window-frame-read-test",name])
    let readback = try JSONDecoder().decode([CGFloat].self,from:Data(output.trimmingCharacters(in:.whitespacesAndNewlines).utf8))
    try verify(readback.count == 4,"A new process can read the locally persisted native frame")
    let restored = NSRect(x:readback[0],y:readback[1],width:readback[2],height:readback[3])
    try verify(near(restored,latest),"A separate process restores the last resized size and position, including an immediate close")

    // Mount the production background attachment on an isolated window, using a unique key.
    let fixtureStore = Store(stateURL:root.appendingPathComponent("window-frame/settings.json"),loadOnLaunch:false)
    func content() -> some View {
        ProjectWorkspace(store:fixtureStore).preferredColorScheme(.light)
            .background(MainWindowFramePersistence(name:name).frame(width:0,height:0))
    }
    let secondWindow = makeWindow()
    secondWindow.alphaValue = 0; secondWindow.ignoresMouseEvents = true
    let host = NSHostingView(rootView:content()); secondWindow.contentView = host
    secondWindow.orderBack(nil); host.layoutSubtreeIfNeeded(); settle()
    try verify(near(secondWindow.frame,latest),"The actual SwiftUI workspace restores the saved window on opening: expected \(latest), got \(secondWindow.frame)")
    let manual = desired.offsetBy(dx:20,dy:14)
    secondWindow.setFrame(manual,display:false)
    fixtureStore.settings.categories = WorkspaceCategory.defaults; settle()
    try verify(near(secondWindow.frame,manual),"Content refresh does not reapply the restored/default size")
    secondWindow.close(); secondWindow.contentView = nil
    print("PASS: native window size/position autosave, immediate-close flush, new-process restoration, production SwiftUI attachment, refresh preservation and multi-display/minimum-size recovery; isolated key only")
}
