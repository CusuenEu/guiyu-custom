import SwiftUI
import AppKit

// Explicit native colors keep the light window appearance from darkening sidebar text.
struct SidebarSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context:Context) -> SidebarNativeTextField {
        let field = SidebarNativeTextField()
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = .systemFont(ofSize:13); field.textColor = NSColor(WorkspaceTheme.sidebarText)
        field.placeholderAttributedString = NSAttributedString(string:"搜索项目或文件",attributes:[.foregroundColor:NSColor(white:0.64,alpha:1),.font:NSFont.systemFont(ofSize:13)])
        field.setAccessibilityLabel("搜索项目或文件")
        field.delegate = context.coordinator
        field.onFocus = { context.coordinator.setFocused(true) }
        field.setContentHuggingPriority(.defaultLow,for:.horizontal)
        field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        return field
    }
    func updateNSView(_ field:SidebarNativeTextField,context:Context) {
        context.coordinator.parent = self
        if (field.currentEditor() as? NSTextView)?.hasMarkedText() != true, field.stringValue != text { field.stringValue = text }
        field.textColor = NSColor(WorkspaceTheme.sidebarText)
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SidebarSearchField
        init(_ parent:SidebarSearchField) { self.parent = parent }
        func setFocused(_ value:Bool) {
            if parent.focused != value { parent.focused = value }
        }
        func controlTextDidBeginEditing(_ notification:Notification) { setFocused(true) }
        func controlTextDidEndEditing(_ notification:Notification) { setFocused(false) }
        func controlTextDidChange(_ notification:Notification) {
            guard let field = notification.object as? NSTextField else { return }
            guard (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            if parent.text != field.stringValue { parent.text = field.stringValue }
        }
    }
}

final class SidebarNativeTextField: NSTextField {
    var onFocus: (() -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }
}
