import AppKit
import SwiftUI

enum WindowFrameGeometry {
    static func fitted(_ frame:NSRect,screens:[NSRect],preferred:NSRect?,minimum:NSSize) -> NSRect {
        guard frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0, !screens.isEmpty else { return frame }
        let closest = screens.max { a,b in
            let x = frame.intersection(a), y = frame.intersection(b)
            return (x.isNull ? 0 : x.width*x.height) < (y.isNull ? 0 : y.width*y.height)
        }!
        let screen = frame.intersects(closest) ? closest : (preferred ?? screens[0])
        let width = max(minimum.width,min(frame.width,screen.width))
        let height = max(minimum.height,min(frame.height,screen.height))
        let x = width <= screen.width ? min(max(frame.minX,screen.minX),screen.maxX-width) : screen.minX
        let y = height <= screen.height ? min(max(frame.minY,screen.minY),screen.maxY-height) : screen.maxY-height
        return NSRect(x:x,y:y,width:width,height:height)
    }
}

// Native frame descriptors live in this application's local preferences, separate
// from workspace data. Never replace SwiftUI's window delegate or touch its sheets.
@MainActor final class MainWindowFrameController {
    static let autosaveName = "Guiyu.MainWindow.v1"
    let name:String
    let minimumContentSize:NSSize
    private(set) weak var window:NSWindow?
    private var observers:[NSObjectProtocol] = []
    private var pending:DispatchWorkItem?
    init(name:String = MainWindowFrameController.autosaveName,minimumContentSize:NSSize = NSSize(width:1060,height:700)) {
        self.name = name; self.minimumContentSize = minimumContentSize
    }
    func attach(_ window:NSWindow) {
        guard self.window !== window, window.sheetParent == nil else { return }
        detach()
        self.window = window
        if window.setFrameUsingName(name,force:true) { fitToScreens() }
        observe(NSWindow.didMoveNotification,object:window) { $0.scheduleSave() }
        observe(NSWindow.didResizeNotification,object:window) { $0.scheduleSave() }
        observe(NSWindow.didEndLiveResizeNotification,object:window) { $0.save() }
        observe(NSWindow.willCloseNotification,object:window) { $0.detach() }
        observe(NSWindow.willEnterFullScreenNotification,object:window) { $0.save() }
        observe(NSWindow.didExitFullScreenNotification,object:window) { $0.scheduleSave() }
        observe(NSApplication.willTerminateNotification,object:nil) { $0.save() }
        observe(NSApplication.didChangeScreenParametersNotification,object:nil) { value in
            guard value.window?.styleMask.contains(.fullScreen) != true else { return }
            value.fitToScreens(); value.scheduleSave()
        }
    }
    private func observe(_ name:Notification.Name,object:AnyObject?,perform:@escaping @MainActor (MainWindowFrameController) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName:name,object:object,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { perform(self) } }
        })
    }
    private func fitToScreens() {
        guard let window else { return }
        let minimum = window.frameRect(forContentRect:NSRect(origin:.zero,size:minimumContentSize)).size
        let frame = WindowFrameGeometry.fitted(window.frame,screens:NSScreen.screens.map(\.visibleFrame),preferred:NSScreen.main?.visibleFrame,minimum:minimum)
        if frame != window.frame { window.setFrame(frame,display:false) }
    }
    private func scheduleSave() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.save() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline:.now()+0.2,execute:work)
    }
    func save() {
        pending?.cancel(); pending = nil
        guard let window, !window.styleMask.contains(.fullScreen), !window.isMiniaturized,
              window.frame.width > 0, window.frame.height > 0 else { return }
        window.saveFrame(usingName:name)
    }
    func detach() {
        save(); pending?.cancel(); pending = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        window = nil
    }
    deinit { pending?.cancel(); observers.forEach(NotificationCenter.default.removeObserver) }
}

struct MainWindowFramePersistence:NSViewRepresentable {
    var name:String = MainWindowFrameController.autosaveName
    var minimumContentSize = NSSize(width:1060,height:700)
    func makeCoordinator() -> MainWindowFrameController { MainWindowFrameController(name:name,minimumContentSize:minimumContentSize) }
    func makeNSView(context:Context) -> MainWindowFrameAttachment {
        let view = MainWindowFrameAttachment(); view.controller = context.coordinator; return view
    }
    func updateNSView(_ view:MainWindowFrameAttachment,context:Context) { view.scheduleAttachment() }
    static func dismantleNSView(_ view:MainWindowFrameAttachment,coordinator:MainWindowFrameController) { coordinator.detach() }
}
final class MainWindowFrameAttachment:NSView {
    weak var controller:MainWindowFrameController?
    private var scheduled = false
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleAttachment() }
    func scheduleAttachment() {
        guard !scheduled, let window, controller?.window !== window else { return }
        scheduled = true
        // Let WindowGroup apply its initial/default size before restoring the saved frame.
        DispatchQueue.main.async { [weak self,weak window] in
            guard let self else { return }; self.scheduled = false
            guard let window, self.window === window else { return }
            self.controller?.attach(window)
        }
    }
}
