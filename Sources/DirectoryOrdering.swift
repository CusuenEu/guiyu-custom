import SwiftUI
import AppKit

let directoryOrderType = "local.guiyu.project-directory-order"
struct DirectoryOrderPayload: Codable { let root: String; let path: String }

@MainActor extension Store {
    var orderedDirectories: [Project] {
        let available = settings.projects.filter { $0.shallow == true }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let byPath = Dictionary(available.map { ($0.path,$0) },uniquingKeysWith:{ a,_ in a })
        var seen = Set<String>(); var result: [Project] = []
        for root in settings.activeProjectRoots {
            let group = available.filter { navigationRoot(for:$0.path) == root }
            result += (settings.directoryOrders?[root] ?? []).compactMap { path -> Project? in
                guard let directory = byPath[path], navigationRoot(for:path) == root, seen.insert(path).inserted else { return nil }; return directory
            }
            result += group.filter { seen.insert($0.path).inserted }
        }
        return result + available.filter { seen.insert($0.path).inserted }
    }
    @discardableResult func reorderDirectory(_ payload: DirectoryOrderPayload, relativeTo target: String, after: Bool) -> Bool {
        let current = directories(in:payload.root).map(\.path)
        guard settings.activeProjectRoots.contains(payload.root), payload.path != target, current.contains(payload.path), current.contains(target) else { return false }
        var paths = current.filter { $0 != payload.path }
        guard let index = paths.firstIndex(of:target) else { return false }
        paths.insert(payload.path,at:index+(after ? 1 : 0))
        guard paths != current else { return true }
        var updated = settings; var orders = updated.directoryOrders ?? [:]; orders[payload.root] = paths; updated.directoryOrders = orders
        do {
            try fm.createDirectory(at:stateURL.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(updated).write(to:stateURL,options:.atomic)
            settings = updated
            return true
        } catch { self.error = "目录顺序未保存："+error.localizedDescription; return false }
    }
}

// Native event handling keeps a row's click action from consuming its drag gesture.
struct DirectoryOrderRow: NSViewRepresentable {
    let store: Store
    let directory: Project
    let selected: Bool
    let select: () -> Void
    func makeNSView(context:Context) -> DirectoryOrderRowView { DirectoryOrderRowView(frame:.zero) }
    func updateNSView(_ view:DirectoryOrderRowView,context:Context) {
        view.store = store; view.payload = DirectoryOrderPayload(root:store.navigationRoot(for:directory.path),path:directory.path)
        view.title = URL(fileURLWithPath:directory.path).lastPathComponent
        view.toolTip = directory.path+"\n按住文件夹上下拖动调整顺序"
        view.selected = selected; view.select = select
        view.setAccessibilityLabel(view.title)
        view.setAccessibilityValue(selected ? "已选中" : "")
        view.needsDisplay = true
    }
}

final class DirectoryOrderRowView: NSView, NSDraggingSource {
    // Every point between adjacent rows belongs to a drop target; visuals stay 48pt tall.
    static let dropPadding: CGFloat = 4.5
    static let dropHeight: CGFloat = 57
    private var rowBounds: NSRect { bounds.insetBy(dx:0,dy:Self.dropPadding) }
    static func dropAfter(y:CGFloat,height:CGFloat) -> Bool { y > height/2 }

    weak var store: Store?
    var payload: DirectoryOrderPayload?
    var title = ""
    var selected = false
    var select: () -> Void = {}
    var copyPasteboard:NSPasteboard = .general
    private let icon = NSImageView()
    private var pressPoint: NSPoint?
    private var isDragging = false
    private var insertionAfter: Bool?
    private static let pasteboardType = NSPasteboard.PasteboardType(directoryOrderType)

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame)
        icon.image = WorkspaceTheme.folder; icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityElement(false); addSubview(icon)
        registerForDraggedTypes([Self.pasteboardType])
        toolTip = "按住文件夹上下拖动调整顺序，松手自动保存"
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityHelp(toolTip)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point:NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func layout() {
        super.layout(); icon.frame = NSRect(x:12,y:(bounds.height-28)/2,width:29,height:28)
    }
    override func accessibilityPerformPress() -> Bool { window?.makeFirstResponder(self);select(); return true }
    @objc func copy(_ sender:Any?) {
        guard let window,window.firstResponder === self,window.attachedSheet == nil,selected,let payload else { return }
        copyFilePaths([payload.path],to:copyPasteboard)
    }
    private func performCopyShortcut(_ event:NSEvent) -> Bool {
        guard let window,window.firstResponder === self,window.attachedSheet == nil,selected,payload != nil,fileShortcut(for:event) == .copy else { return false }
        copy(nil);return true
    }
    override func performKeyEquivalent(with event:NSEvent) -> Bool { performCopyShortcut(event) || super.performKeyEquivalent(with:event) }
    override func keyDown(with event:NSEvent) {
        if performCopyShortcut(event) { return }
        if event.keyCode == 36 || event.keyCode == 49 { select() } else { super.keyDown(with:event) }
    }
    override func draw(_ dirtyRect:NSRect) {
        if selected {
            NSColor(WorkspaceTheme.sidebarSelection).setFill()
            NSBezierPath(roundedRect:rowBounds,xRadius:12,yRadius:12).fill()
        }
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
        let font = NSFont.systemFont(ofSize:15).fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor:$0,size:15) } ?? NSFont.systemFont(ofSize:15)
        let attributes: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor(WorkspaceTheme.sidebarText),.paragraphStyle:style]
        let label = title as NSString
        let height = label.size(withAttributes:attributes).height
        label.draw(in:NSRect(x:53,y:(bounds.height-height)/2,width:max(0,bounds.width-65),height:height),withAttributes:attributes)
        if let after = insertionAfter {
            NSColor(WorkspaceTheme.sidebarText).setFill()
            NSBezierPath(roundedRect:NSRect(x:0,y:after ? bounds.height-2 : 0,width:bounds.width,height:2),xRadius:1,yRadius:1).fill()
        }
        if window?.firstResponder === self {
            NSColor(WorkspaceTheme.sidebarMuted).setStroke()
            let ring = NSBezierPath(roundedRect:rowBounds.insetBy(dx:1,dy:1),xRadius:11,yRadius:11); ring.lineWidth = 1; ring.stroke()
        }
    }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self)
        pressPoint = convert(event.locationInWindow,from:nil); isDragging = false
    }
    override func mouseDragged(with event:NSEvent) {
        guard let pressPoint, !isDragging, let payload,
              hypot(event.locationInWindow.x-convert(pressPoint,to:nil).x,event.locationInWindow.y-convert(pressPoint,to:nil).y) >= 4,
              let data = try? JSONEncoder().encode(payload),
              let bitmap = bitmapImageRepForCachingDisplay(in:bounds) else { return }
        cacheDisplay(in:bounds,to:bitmap)
        let image = NSImage(size:bounds.size); image.addRepresentation(bitmap)
        let item = NSPasteboardItem(); item.setData(data,forType:Self.pasteboardType)
        let draggingItem = NSDraggingItem(pasteboardWriter:item)
        draggingItem.setDraggingFrame(bounds,contents:image)
        isDragging = true; self.pressPoint = nil
        beginDraggingSession(with:[draggingItem],event:event,source:self).animatesToStartingPositionsOnCancelOrFail = true
    }
    override func mouseUp(with event:NSEvent) {
        defer { pressPoint = nil }
        if pressPoint != nil && !isDragging && bounds.contains(convert(event.locationInWindow,from:nil)) { select() }
    }
    func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func draggingSession(_ session:NSDraggingSession,endedAt screenPoint:NSPoint,operation:NSDragOperation) {
        isDragging = false; pressPoint = nil; insertionAfter = nil; needsDisplay = true
    }
    private func dropPayload(_ sender:NSDraggingInfo) -> DirectoryOrderPayload? {
        guard sender.draggingSource is DirectoryOrderRowView,
              let data = sender.draggingPasteboard.data(forType:Self.pasteboardType),
              let value = try? JSONDecoder().decode(DirectoryOrderPayload.self,from:data),
              let store, let payload, store.settings.activeProjectRoots.contains(value.root), value.root == payload.root,
              value.path != payload.path, store.orderedDirectories.contains(where:{$0.path == value.path}) else { return nil }
        return value
    }
    override func draggingEntered(_ sender:NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender:NSDraggingInfo) -> NSDragOperation {
        insertionAfter = dropPayload(sender) == nil ? nil : Self.dropAfter(y:convert(sender.draggingLocation,from:nil).y,height:bounds.height)
        needsDisplay = true
        return insertionAfter == nil ? [] : .move
    }
    override func draggingExited(_ sender:NSDraggingInfo?) { insertionAfter = nil; needsDisplay = true }
    override func prepareForDragOperation(_ sender:NSDraggingInfo) -> Bool { dropPayload(sender) != nil }
    override func performDragOperation(_ sender:NSDraggingInfo) -> Bool {
        defer { insertionAfter = nil; needsDisplay = true }
        guard let value = dropPayload(sender), let store, let payload else { return false }
        return store.reorderDirectory(value,relativeTo:payload.path,after:Self.dropAfter(y:convert(sender.draggingLocation,from:nil).y,height:bounds.height))
    }
}

@MainActor func directoryOrderingTest(root:URL) throws {
    let state = root.appendingPathComponent("directory-order/state.json")
    let store = Store(stateURL:state,loadOnLaunch:false)
    let base = root.appendingPathComponent("directory-order/projects")
    try fm.createDirectory(at:base,withIntermediateDirectories:true)
    let marker = base.appendingPathComponent("keep.txt"); try "untouched".write(to:marker,atomically:true,encoding:.utf8)
    store.settings.root = base.path
    store.settings.projects = ["CD类项目","2026","2025"].map { Project(path:base.appendingPathComponent($0).path,name:$0,group:$0,shallow:true) }
    let row = DirectoryOrderRowView(frame:NSRect(x:0,y:0,width:218,height:DirectoryOrderRowView.dropHeight))
    row.store = store; row.payload = DirectoryOrderPayload(root:base.path,path:base.appendingPathComponent("CD类项目").path)
    var clicks = 0; row.select = { clicks += 1 }
    func event(_ type:NSEvent.EventType,_ point:NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1)!
    }
    row.mouseDown(with:event(.leftMouseDown,NSPoint(x:100,y:20)))
    row.mouseDragged(with:event(.leftMouseDragged,NSPoint(x:102,y:21)))
    row.mouseUp(with:event(.leftMouseUp,NSPoint(x:102,y:21)))
    try verify(clicks == 1,"Small pointer movement must remain a normal directory click")
    row.mouseDown(with:event(.leftMouseDown,NSPoint(x:100,y:20)))
    row.mouseUp(with:event(.leftMouseUp,NSPoint(x:250,y:20)))
    try verify(clicks == 1,"Releasing outside a directory must not select it")
    try verify(row.accessibilityPerformPress() && clicks == 2,"Directory remains accessible as a button")
    try verify(row.bounds.height == 57 && DirectoryOrderRowView.dropPadding * 2 + 48 == row.bounds.height,"Drop targets must include the full 9pt gap while preserving 48pt visible rows")
    for y in [CGFloat(0),4,16,28] { try verify(!DirectoryOrderRowView.dropAfter(y:y,height:57),"Upper row and gap must accept insertion before") }
    for y in [CGFloat(29),40,52,57] { try verify(DirectoryOrderRowView.dropAfter(y:y,height:57),"Lower row and gap must accept insertion after") }
    try verify(row.hitTest(NSPoint(x:100,y:2)) === row && row.hitTest(NSPoint(x:100,y:row.bounds.height-2)) === row,"Expanded top and bottom margins must receive mouse input")
    print("PASS: native directory click, movement threshold, cancellation, accessibility, continuous 57pt drop targets including the compact gaps")
    let original = store.orderedDirectories.map(\.path)
    let cd = base.appendingPathComponent("CD类项目").path, y26 = base.appendingPathComponent("2026").path, y25 = base.appendingPathComponent("2025").path
    try verify(store.reorderDirectory(DirectoryOrderPayload(root:base.path,path:cd),relativeTo:y25,after:true))
    try verify(store.orderedDirectories.map(\.path) == [y25,cd,y26],"Drop after row must set exact order")
    let reopened = Store(stateURL:state,loadOnLaunch:false)
    try verify(reopened.orderedDirectories.map(\.path) == [y25,cd,y26],"Directory order must survive disk readback and reopening")
    reopened.settings.projects.reverse()
    try verify(reopened.orderedDirectories.map(\.path) == [y25,cd,y26],"Metadata refresh order must not override manual order")
    try verify(reopened.reorderDirectory(DirectoryOrderPayload(root:base.path,path:cd),relativeTo:y25,after:false))
    try verify(reopened.orderedDirectories.map(\.path) == [cd,y25,y26],"Drop before row must insert before the target")
    let y24 = base.appendingPathComponent("2024").path
    reopened.settings.projects.append(Project(path:y24,name:"2024",group:"2024",shallow:true))
    try verify(reopened.orderedDirectories.last?.path == y24,"New directories append without disturbing saved order")
    reopened.settings.projects.removeAll { $0.path == y25 }
    try verify(!reopened.orderedDirectories.contains { $0.path == y25 },"Missing directories must stay hidden")
    let previous = reopened.orderedDirectories
    try verify(!reopened.reorderDirectory(DirectoryOrderPayload(root:"/another-root",path:cd),relativeTo:y26,after:false))
    try verify(!reopened.reorderDirectory(DirectoryOrderPayload(root:base.path,path:"/outside"),relativeTo:y26,after:false))
    let markerText = try String(contentsOf:marker)
    try verify(reopened.orderedDirectories == previous && markerText == "untouched","Rejected drops must not alter state or disk files")
    reopened.settings.root = "/another-root"
    try verify(reopened.orderedDirectories.map(\.path) == reopened.settings.projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map(\.path),"Custom order is scoped to selected root")
    print("PASS: sidebar drop before/after, atomic persisted readback, refresh/root isolation, new/missing directories, foreign payload rejection; Finder files unchanged")
}
