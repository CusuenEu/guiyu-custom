import SwiftUI
import AppKit

struct NamingUseRecognizedButton:NSViewRepresentable {
    let enabled:Bool
    let action:()->Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context:Context) -> NSButton {
        let button = NSButton(title:"使用识别文字",target:context.coordinator,action:#selector(Coordinator.useText))
        button.identifier = NSUserInterfaceItemIdentifier("naming-use-recognized-text")
        button.bezelStyle = .rounded;button.controlSize = .regular;button.font = .systemFont(ofSize:13,weight:.medium)
        button.setAccessibilityLabel("使用识别文字")
        return button
    }
    func updateNSView(_ button:NSButton,context:Context) {
        context.coordinator.action = action;button.isEnabled = enabled
    }
    final class Coordinator:NSObject {
        var action:()->Void
        init(_ action:@escaping ()->Void) { self.action = action }
        @objc func useText() { action() }
    }
}

struct NamingRegionPreview:NSViewRepresentable {
    let image:CGImage
    let zoom:CGFloat
    let turns:Int
    let region:CGRect?
    let selected:(CGRect) -> Void
    let invalid:() -> Void
    func makeNSView(context:Context) -> NamingPreviewScrollView {
        let scroll = NamingPreviewScrollView()
        scroll.hasVerticalScroller = true;scroll.hasHorizontalScroller = true;scroll.autohidesScrollers = true
        scroll.borderType = .noBorder;scroll.drawsBackground = true;scroll.backgroundColor = NSColor(calibratedWhite:0.93,alpha:1)
        scroll.documentView = scroll.canvas
        return scroll
    }
    func updateNSView(_ scroll:NamingPreviewScrollView,context:Context) {
        let changed = scroll.canvas.image !== image || scroll.canvas.zoom != zoom
        scroll.canvas.image = image;scroll.canvas.zoom = zoom;scroll.canvas.turns = turns
        scroll.canvas.region = region;scroll.canvas.selected = selected;scroll.canvas.invalid = invalid
        scroll.layoutCanvas();scroll.canvas.needsDisplay = true
        if changed {
            if let region {
                let r = NamingRegionGeometry.rotated(region,turns:turns), box = scroll.canvas.imageRect
                scroll.canvas.scrollToVisible(CGRect(x:box.minX+r.minX*box.width,y:box.minY+r.minY*box.height,width:r.width*box.width,height:r.height*box.height).insetBy(dx:-10,dy:-10))
            } else { scroll.contentView.scroll(to:.zero);scroll.reflectScrolledClipView(scroll.contentView) }
        }
    }
}
final class NamingPreviewScrollView:NSScrollView {
    let canvas = NamingRegionCanvas()
    override func layout() { super.layout();layoutCanvas() }
    func layoutCanvas() { canvas.configure(viewport:contentView.bounds.size) }
}
final class NamingRegionCanvas:NSView {
    var image:CGImage?
    var zoom:CGFloat = 1
    var turns = 0
    var region:CGRect?
    var selected:((CGRect)->Void)?
    var invalid:(()->Void)?
    private(set) var imageRect = CGRect.zero
    private var start:CGPoint?
    private var drag:CGRect?
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    func configure(viewport:NSSize) {
        guard let image, viewport.width > 24, viewport.height > 24 else { return }
        let factor = min((viewport.width-24)/CGFloat(image.width),(viewport.height-24)/CGFloat(image.height))*zoom
        let size = NSSize(width:CGFloat(image.width)*factor,height:CGFloat(image.height)*factor)
        let documentSize = NSSize(width:max(viewport.width,size.width+24),height:max(viewport.height,size.height+24))
        if frame.size != documentSize { setFrameSize(documentSize) }
        imageRect = CGRect(x:(documentSize.width-size.width)/2,y:(documentSize.height-size.height)/2,width:size.width,height:size.height)
        needsDisplay = true
    }
    override func resetCursorRects() { addCursorRect(imageRect,cursor:.crosshair) }
    override func draw(_ dirtyRect:NSRect) {
        NSColor(calibratedWhite:0.93,alpha:1).setFill();bounds.fill()
        guard let image else { return }
        NSColor.white.setFill();imageRect.fill()
        NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)).draw(in:imageRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
        NSColor(WorkspaceTheme.line).setStroke();NSBezierPath(rect:imageRect).stroke()
        let selectedRect:CGRect?
        if let drag { selectedRect = drag.standardized.intersection(imageRect) }
        else if let region {
            let normalized = NamingRegionGeometry.rotated(region,turns:turns)
            selectedRect = CGRect(x:imageRect.minX+normalized.minX*imageRect.width,y:imageRect.minY+normalized.minY*imageRect.height,width:normalized.width*imageRect.width,height:normalized.height*imageRect.height)
        } else { selectedRect = nil }
        if let rect = selectedRect, !rect.isNull {
            NSColor(WorkspaceTheme.mint).withAlphaComponent(0.4).setFill();rect.fill()
            NSColor(accent).setStroke();let outline = NSBezierPath(rect:rect);outline.lineWidth = 1.5;outline.stroke()
        }
    }
    override func mouseDown(with event:NSEvent) {
        let point = convert(event.locationInWindow,from:nil)
        guard imageRect.contains(point) else { return }
        window?.makeFirstResponder(self);start = point;drag = CGRect(origin:point,size:.zero);needsDisplay = true
    }
    override func mouseDragged(with event:NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow,from:nil)
        drag = CGRect(x:min(start.x,point.x),y:min(start.y,point.y),width:abs(point.x-start.x),height:abs(point.y-start.y))
        autoscroll(with:event);needsDisplay = true
    }
    override func mouseUp(with event:NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow,from:nil)
        let rect = CGRect(x:min(start.x,point.x),y:min(start.y,point.y),width:abs(point.x-start.x),height:abs(point.y-start.y))
        self.start = nil;drag = nil;needsDisplay = true
        if let region = NamingRegionGeometry.region(from:rect,imageRect:imageRect,turns:turns) { selected?(region) }
        else { invalid?() }
    }
}

struct NamingRecognizedTextEditor:NSViewRepresentable {
    @Binding var text:String
    @Binding var selection:NSRange
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context:Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView();scroll.hasVerticalScroller = true;scroll.autohidesScrollers = true;scroll.borderType = .noBorder
        let view = scroll.documentView as! NSTextView
        view.isRichText = false;view.isEditable = true;view.isSelectable = true
        view.isVerticallyResizable = true;view.isHorizontallyResizable = false
        view.autoresizingMask = [.width];view.textContainer?.widthTracksTextView = true
        view.textContainerInset = NSSize(width:8,height:8);view.font = .systemFont(ofSize:13)
        view.textColor = NSColor(WorkspaceTheme.ink);view.backgroundColor = NSColor(WorkspaceTheme.projectCanvas);view.insertionPointColor = NSColor(accent)
        view.selectedTextAttributes = [.backgroundColor:NSColor(WorkspaceTheme.mint),.foregroundColor:NSColor(WorkspaceTheme.ink)]
        view.setAccessibilityLabel("识别文字，可修改或选择部分文字")
        view.delegate = context.coordinator;scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let coordinator = context.coordinator;coordinator.parent = self;coordinator.updating = true
        defer { coordinator.updating = false }
        if !view.hasMarkedText(),view.string != text { view.string = text }
        if selection.location <= (view.string as NSString).length,NSMaxRange(selection) <= (view.string as NSString).length,view.selectedRange() != selection { view.setSelectedRange(selection) }
    }
    final class Coordinator:NSObject,NSTextViewDelegate {
        var parent:NamingRecognizedTextEditor
        var updating = false
        init(_ parent:NamingRecognizedTextEditor) { self.parent = parent }
        func textDidChange(_ notification:Notification) {
            guard !updating,let view = notification.object as? NSTextView,!view.hasMarkedText() else { return }
            parent.text = view.string
        }
        func textViewDidChangeSelection(_ notification:Notification) {
            guard !updating,let view = notification.object as? NSTextView else { return }
            let range = view.selectedRange();if parent.selection != range { parent.selection = range }
        }
    }
}
