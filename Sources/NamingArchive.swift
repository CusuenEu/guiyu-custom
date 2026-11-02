import SwiftUI
import AppKit

@MainActor extension Store {
    func renameForArchive(_ target:NamingTarget,newName:String,requireMonth:Bool) -> QuickArchiveRequest? {
        error = ""
        do {
            let destination = try validateRename(target,newName:newName,requireMonth:requireMonth)
            let name = URL(fileURLWithPath:destination).lastPathComponent
            guard !name.hasPrefix("."),!name.hasPrefix("~$"),browserEntry(target.path)?.folder == target.folder else {
                throw namingError("归档不能使用隐藏或临时文件，请修改名称后重试。")
            }
            guard confirmRename(target,newName:newName,requireMonth:requireMonth),error.isEmpty else { return nil }
            guard fileIdentity(destination) == target.identity,let row = browserEntry(destination),row.folder == target.folder else {
                throw namingError("已完成命名，但文件随后发生变化，未打开归档；请刷新后重新选择。")
            }
            return QuickArchiveRequest(rows:[row])
        } catch { self.error = error.localizedDescription;return nil }
    }
}

// Native target/action also permits isolated activation without mouse takeover.
struct NamingArchiveButton:NSViewRepresentable {
    let enabled:Bool
    let action:()->Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context:Context) -> NSButton {
        let button = ActionButton(title:"确认并归档",target:context.coordinator,action:#selector(Coordinator.press))
        button.identifier = NSUserInterfaceItemIdentifier("confirm-name-and-archive")
        button.setButtonType(.momentaryPushIn);button.isBordered = false;button.focusRingType = .exterior
        button.wantsLayer = true;button.layer?.cornerRadius = 8;button.layer?.borderWidth = 1
        return button
    }
    func updateNSView(_ button:NSButton,context:Context) {
        context.coordinator.action = action;button.isEnabled = enabled
        button.layer?.backgroundColor = NSColor.white.cgColor;button.layer?.borderColor = NSColor(WorkspaceTheme.line).cgColor
        button.attributedTitle = NSAttributedString(string:"确认并归档",attributes:[.font:NSFont.systemFont(ofSize:13,weight:.medium),.foregroundColor:enabled ? NSColor(WorkspaceTheme.ink) : NSColor(WorkspaceTheme.secondary)])
    }
    final class Coordinator:NSObject {
        var action:()->Void
        init(_ action:@escaping()->Void) { self.action = action }
        @objc func press() { action() }
    }
    final class ActionButton:NSButton {
        override func highlight(_ flag:Bool) { super.highlight(flag);alphaValue = flag && isEnabled ? 0.7 : 1 }
    }
}
