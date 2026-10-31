import SwiftUI
import AppKit

// Both lists keep usable space, and a saved proportion adapts to a different window height.
enum SidebarSectionsLayout {
    static let dividerHeight: CGFloat = 16
    static func projectHeight(total: CGFloat, fraction: Double?, preferred: CGFloat) -> CGFloat {
        let usable = max(0,total-dividerHeight)
        let minimum = min(92,usable/2), maximum = max(minimum,usable-min(116,usable/2))
        let proposed = fraction.flatMap { $0.isFinite ? CGFloat($0)*usable : nil } ?? min(preferred,usable*0.65)
        return min(maximum,max(minimum,proposed))
    }
    static func fraction(height: CGFloat, total: CGFloat) -> Double {
        Double(height/max(1,total-dividerHeight))
    }
}
@MainActor extension Store {
    @discardableResult func saveSidebarFraction(_ value: Double) -> Bool {
        guard value.isFinite else { return false }
        var updated = settings; updated.sidebarProjectsFraction = min(1,max(0,value))
        do {
            try fm.createDirectory(at:stateURL.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(updated).write(to:stateURL,options:.atomic)
            settings = updated; return true
        } catch { self.error = "分隔线位置未保存："+error.localizedDescription; return false }
    }
}

struct SidebarSectionDivider: NSViewRepresentable {
    let fraction: Double
    let begin: () -> Void
    let change: (CGFloat) -> Void
    let finish: () -> Void
    let cancel: () -> Void
    let nudge: (CGFloat) -> Void
    func makeNSView(context:Context) -> SidebarSectionDividerView { SidebarSectionDividerView() }
    func updateNSView(_ view:SidebarSectionDividerView,context:Context) {
        view.begin = begin; view.change = change; view.finish = finish; view.cancel = cancel; view.nudge = nudge
        view.setAccessibilityValue(Int(fraction*100)); view.needsDisplay = true
    }
}
final class SidebarSectionDividerView: NSView {
    var begin: () -> Void = {}; var change: (CGFloat) -> Void = { _ in }; var finish: () -> Void = {}; var cancel: () -> Void = {}; var nudge: (CGFloat) -> Void = { _ in }
    private var startY: CGFloat?; private var dragging = false; private var hovered = false; private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame)
        toolTip = "上下拖动，调整项目目录与可归档目录的高度"
        setAccessibilityElement(true); setAccessibilityRole(.splitter); setAccessibilityLabel("项目与可归档目录分隔线")
        setAccessibilityHelp("上下拖动或使用上下方向键调整高度，松手后自动保存")
        setAccessibilityOrientation(.horizontal)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.resizeUpDown) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect:bounds,options:[.activeInActiveApp,.mouseEnteredAndExited,.inVisibleRect],owner:self)
        tracking = area; addTrackingArea(area)
    }
    override func mouseEntered(with event:NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event:NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect:NSRect) {
        let focused = window?.firstResponder === self
        NSColor(WorkspaceTheme.sidebarMuted).withAlphaComponent(dragging || hovered || focused ? 0.8 : 0.25).setFill()
        NSRect(x:0,y:floor(bounds.midY),width:bounds.width,height:dragging || hovered ? 2 : 1).fill()
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self); startY = event.locationInWindow.y; dragging = false
    }
    override func mouseDragged(with event:NSEvent) {
        guard let startY else { return }
        let delta = startY-event.locationInWindow.y
        guard dragging || abs(delta) >= 2 else { return }
        if !dragging { dragging = true; begin() }
        change(delta); needsDisplay = true
    }
    override func mouseUp(with event:NSEvent) {
        if let startY, dragging { change(startY-event.locationInWindow.y); finish() }
        self.startY = nil; dragging = false; needsDisplay = true
    }
    override func viewWillMove(toWindow newWindow:NSWindow?) {
        if newWindow == nil && dragging { cancel(); startY = nil; dragging = false }
        super.viewWillMove(toWindow:newWindow)
    }
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 126 { nudge(-12) }
        else if event.keyCode == 125 { nudge(12) }
        else { super.keyDown(with:event) }
    }
    override func accessibilityPerformIncrement() -> Bool { nudge(12); return true }
    override func accessibilityPerformDecrement() -> Bool { nudge(-12); return true }
}

@MainActor func sidebarSectionsTest(root: URL) throws {
    let total: CGFloat = 600
    let high = SidebarSectionsLayout.projectHeight(total:total,fraction:100,preferred:300)
    let low = SidebarSectionsLayout.projectHeight(total:total,fraction:-100,preferred:300)
    try verify(high == 468 && low == 92,"Dragging to extremes must keep both sections usable")
    for height in [CGFloat(0),40,100,300,600,1000] {
        let value = SidebarSectionsLayout.projectHeight(total:height,fraction:0.5,preferred:300)
        try verify(value >= 0 && value <= max(0,height-16),"Small windows must not produce a negative or overflowing section")
    }
    try verify(SidebarSectionsLayout.projectHeight(total:600,fraction:.nan,preferred:300) == 300,"Invalid persisted ratios fall back to a useful default")
    let store = Store(stateURL:root.appendingPathComponent("sidebar-split/settings.json"),loadOnLaunch:false)
    let baseline = try Data(contentsOf:store.stateURL)
    var height: CGFloat = 250, start: CGFloat = 0, commits = 0
    let divider = SidebarSectionDividerView(frame:NSRect(x:0,y:0,width:218,height:16))
    divider.begin = { start = height }
    divider.change = { delta in height = SidebarSectionsLayout.projectHeight(total:total,fraction:SidebarSectionsLayout.fraction(height:start+delta,total:total),preferred:300) }
    divider.finish = { commits += 1; _ = store.saveSidebarFraction(SidebarSectionsLayout.fraction(height:height,total:total)) }
    func mouse(_ kind:NSEvent.EventType,_ y:CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with:kind,location:NSPoint(x:100,y:y),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1)!
    }
    divider.mouseDown(with:mouse(.leftMouseDown,300)); divider.mouseDragged(with:mouse(.leftMouseDragged,250)); divider.mouseDragged(with:mouse(.leftMouseDragged,200))
    let during = try Data(contentsOf:store.stateURL)
    try verify(height == 350 && commits == 0 && during == baseline,"Dragging updates layout live without writing settings on every mouse event")
    divider.mouseUp(with:mouse(.leftMouseUp,200))
    let loaded = Store(stateURL:store.stateURL,loadOnLaunch:false)
    let fraction = loaded.settings.sidebarProjectsFraction
    try verify(commits == 1 && abs((fraction ?? 0)-350/584) < 0.0001,"Mouse-up saves the divider position and restart restores it")
    try verify(SidebarSectionsLayout.projectHeight(total:800,fraction:fraction,preferred:300) > 350,"Saved proportions adapt when the window grows")
    divider.nudge = { delta in height += delta }
    try verify(divider.accessibilityPerformIncrement() && height == 362 && divider.accessibilityPerformDecrement() && height == 350,"The splitter exposes accessible increment/decrement actions")
    let before = commits; divider.mouseDown(with:mouse(.leftMouseDown,300)); divider.mouseUp(with:mouse(.leftMouseUp,300))
    try verify(commits == before,"Clicking the line without dragging does not persist a change")
    print("PASS: live native sidebar divider drag, section limits, save-on-release persistence, restart/resize, no per-frame writes and accessibility")
}
