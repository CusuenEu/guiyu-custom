import SwiftUI
import AppKit

// Shared native presentation for confirmed naming and archiving. No file I/O here.
struct SmartDialogActionStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size:13,weight:.medium))
            .padding(.horizontal,16).frame(height:34)
            .foregroundStyle(primary && enabled ? Color.white : enabled ? WorkspaceTheme.ink : WorkspaceTheme.secondary)
            .background(primary && enabled ? accent : primary ? WorkspaceTheme.line : .white,in:RoundedRectangle(cornerRadius:8))
            .overlay(RoundedRectangle(cornerRadius:8).stroke(primary ? .clear : WorkspaceTheme.line,lineWidth:1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
struct SmartDialogHeader: View {
    let title: String; let symbol: String
    var prominentIcon = false
    var body: some View {
        HStack(spacing:12) {
            Image(systemName:symbol).font(.system(size:20,weight:.medium)).foregroundStyle(accent)
                .frame(width:prominentIcon ? 42 : 24,height:42)
                .background(prominentIcon ? WorkspaceTheme.mint : .clear,in:RoundedRectangle(cornerRadius:10))
                .accessibilityHidden(true)
            Text(title).font(.system(size:20,weight:.semibold))
            Spacer()
        }.padding(.horizontal,26).frame(height:prominentIcon ? 82 : 76)
    }
}
struct SmartDialogFileSummary: View {
    let rows: [BrowserRow]
    var body: some View {
        HStack(spacing:12) {
            if let row = rows.first {
                if let icon = WorkspaceFileIcons.image(for:row) { Image(nsImage:icon).resizable().scaledToFit().frame(width:28,height:28) }
                else { Image(systemName:"doc").font(.system(size:24)).foregroundStyle(accent).frame(width:28) }
                VStack(alignment:.leading,spacing:5) {
                    Text(row.title+(rows.count > 1 ? " 等 \(rows.count) 项" : "")).font(.system(size:13,weight:.medium)).lineLimit(1).truncationMode(.middle)
                    Text("\(rows.count) 项待归档").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary)
                }
            }
            Spacer(minLength:0)
        }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
            .background(WorkspaceTheme.projectCanvas,in:RoundedRectangle(cornerRadius:10))
            .help(rows.map(\.id).joined(separator:"\n"))
    }
}

// AppKit retains IME marked text and uses an explicit accessible placeholder color.
struct SmartDialogTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let placeholder: String
    var submit: (() -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> SidebarNativeTextField {
        let field = SidebarNativeTextField()
        field.isBordered = false; field.isBezeled = false; field.drawsBackground = false
        field.focusRingType = .none; field.font = .systemFont(ofSize:13)
        field.textColor = NSColor(WorkspaceTheme.ink)
        field.placeholderAttributedString = NSAttributedString(string:placeholder,attributes:[.foregroundColor:NSColor(WorkspaceTheme.secondary),.font:NSFont.systemFont(ofSize:13)])
        field.delegate = context.coordinator
        field.onFocus = { context.coordinator.setFocused(true) }
        field.setAccessibilityLabel(placeholder)
        field.setContentHuggingPriority(.defaultLow,for:.horizontal)
        field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        return field
    }
    func updateNSView(_ field: SidebarNativeTextField, context: Context) {
        context.coordinator.parent = self
        if (field.currentEditor() as? NSTextView)?.hasMarkedText() != true, field.stringValue != text { field.stringValue = text }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SmartDialogTextField
        init(_ parent: SmartDialogTextField) { self.parent = parent }
        func setFocused(_ value: Bool) { if parent.focused != value { parent.focused = value } }
        func controlTextDidBeginEditing(_ notification: Notification) { setFocused(true) }
        func controlTextDidEndEditing(_ notification: Notification) { setFocused(false) }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            if parent.text != field.stringValue { parent.text = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText(), let submit = parent.submit { submit(); return true }
            return false
        }
    }
}

func smartNamingEditableBase(_ name: String, target: NamingTarget) -> String {
    if target.folder {
        return name.replacingOccurrences(of:"^\\s*(1[0-2]|[1-9])月\\s*",with:"",options:.regularExpression)
    }
    let ext = URL(fileURLWithPath:target.path).pathExtension
    return !ext.isEmpty && name.hasSuffix("."+ext) ? String(name.dropLast(ext.count+1)) : name
}

// For editable category names, strip only the protected original extension.
// Do not normalize away category words or date-like text typed by the user.
func smartNamingLiteralStem(_ name:String,target:NamingTarget) -> String {
    guard !target.folder else { return name }
    let ext = URL(fileURLWithPath:target.path).pathExtension
    return !ext.isEmpty && name.hasSuffix("."+ext) ? String(name.dropLast(ext.count+1)) : name
}
