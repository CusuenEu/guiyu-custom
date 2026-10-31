import SwiftUI
import AppKit

// Set proportions only when a split view is first attached. Subsequent user drags win.
struct WorkspaceSplitLayout: NSViewRepresentable {
    func makeNSView(context:Context) -> InitialSplitLayoutView { InitialSplitLayoutView() }
    func updateNSView(_ view:InitialSplitLayoutView,context:Context) { view.scheduleLayout() }
}
final class InitialSplitLayoutView: NSView {
    private weak var configuredSplit: NSSplitView?
    private var scheduled = false
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleLayout() }
    func scheduleLayout() {
        guard !scheduled, window != nil else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.scheduled = false
            guard let root = self.window?.contentView, let split = self.findSplit(root), split !== self.configuredSplit, split.bounds.width >= 970 else { return }
            self.configuredSplit = split
            let sidebar = min(250,max(200,split.bounds.width * 0.16))
            let projects = min(520,max(340,split.bounds.width * 0.305))
            split.setPosition(sidebar,ofDividerAt:0)
            split.setPosition(sidebar + projects + split.dividerThickness,ofDividerAt:1)
        }
    }
    private func findSplit(_ view:NSView) -> NSSplitView? {
        if let split = view as? NSSplitView, split.isVertical && split.arrangedSubviews.count == 3 { return split }
        return view.subviews.lazy.compactMap { self.findSplit($0) }.first
    }
}
