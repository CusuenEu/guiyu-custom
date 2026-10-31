import SwiftUI
import AppKit

@MainActor final class CategoryWorkflow: ObservableObject {
    enum Operation { case copy, importReply }
    @Published var operation: Operation = .importReply
    @Published var message = ""
    @Published var failed = false
    func copyPrompt(store:Store, pasteboard:NSPasteboard = .general, openWebsite:@MainActor () -> Void = openDoubaoWebsite) {
        operation = .copy
        guard !CategoryRuleExchange.targets(store.workspaceCategories).isEmpty else { failed = true; message = "请先添加文件分类。"; return }
        pasteboard.clearContents()
        guard pasteboard.setString(CategoryRuleExchange.prompt(categories:store.workspaceCategories),forType:.string) else { failed = true; message = "复制失败，请重试。"; return }
        failed = false; message = "复制成功，请去豆包提问"
        openWebsite()
    }
    func importReply(store:Store, pasteboard:NSPasteboard = .general) {
        operation = .importReply
        guard let text = pasteboard.string(forType:.string), !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { failed = true; message = "未读取到文字，请先复制豆包回复。"; return }
        do {
            let imports = try CategoryRuleExchange.parse(text,categories:store.workspaceCategories)
            guard store.importCategoryRules(imports) else { failed = true; message = store.error; store.error = ""; return }
            failed = false; message = "录入成功，已更新 \(imports.count) 个分类规则"
        } catch { failed = true; message = error.localizedDescription }
    }
}

struct CategoryWorkflowView: View {
    @ObservedObject var store:Store
    @ObservedObject var workflow:CategoryWorkflow
    let showGuide:() -> Void
    private func number(_ value:String) -> some View {
        Text(value).font(.system(size:12,weight:.semibold)).foregroundStyle(.white).frame(width:22,height:22).background(accent,in:Circle()).accessibilityHidden(true)
    }
    @ViewBuilder private var feedback:some View {
        if !workflow.message.isEmpty {
            Label(workflow.message,systemImage:workflow.failed ? "exclamationmark.circle" : "checkmark.circle.fill").font(.system(size:11)).foregroundStyle(workflow.failed ? Color(red:0.70,green:0.16,blue:0.13) : accent).lineLimit(3).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:7) {
            HStack(spacing:6) {
                Text("分类设置后，请务必按一下操作。").font(.system(size:13,weight:.semibold)).foregroundStyle(Color(red:0.70,green:0.16,blue:0.13)).fixedSize(horizontal:false,vertical:true)
                Button(action:showGuide) { Image(systemName:"exclamationmark.circle").font(.system(size:15)).foregroundStyle(accent).frame(width:26,height:26) }.buttonStyle(.plain).accessibilityLabel("查看操作图解").help("复制、豆包发文、录入规则")
                Spacer(minLength:0)
            }
            HStack(spacing:9) {
                number("1")
                Button("复制提示词，去豆包官网") { workflow.copyPrompt(store:store) }.buttonStyle(SmartDialogActionStyle(primary:true)).disabled(CategoryRuleExchange.targets(store.workspaceCategories).isEmpty).accessibilityIdentifier("copy-category-prompt")
                if workflow.operation == .copy { feedback }
                Spacer(minLength:0)
            }
            HStack(spacing:9) {
                number("2")
                Text("把提示词发给豆包，复制豆包的回复。").font(.system(size:12))
                Button(action:openDoubaoWebsite) { Label("豆包官网",systemImage:"arrow.up.right").font(.system(size:12)).foregroundStyle(accent) }.buttonStyle(.plain)
                Spacer(minLength:0)
            }.frame(minHeight:24)
            HStack(spacing:9) {
                number("3")
                Button("录入豆包回复") { workflow.importReply(store:store) }.buttonStyle(SoftWorkspaceButton()).disabled(CategoryRuleExchange.targets(store.workspaceCategories).isEmpty).accessibilityIdentifier("import-category-reply")
                if workflow.operation == .importReply { feedback }
                Spacer(minLength:0)
            }
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(WorkspaceTheme.projectCanvas,in:RoundedRectangle(cornerRadius:10))
    }
}

struct CategorySetupPlaceholder: View {
    let openSettings:() -> Void
    var body:some View {
        Button("请设置文件分类",action:openSettings).buttonStyle(SmartDialogActionStyle(primary:true)).accessibilityIdentifier("setup-file-categories")
            .frame(maxWidth:.infinity,maxHeight:.infinity).background(WorkspaceTheme.canvas)
    }
}

struct CategoryWorkflowGuide: View {
    @Environment(\.dismiss) private var dismiss
    static let scenes = [("copy-prompt","复制提示词"),("doubao-message","豆包发文"),("import-rules","录入规则")]
    static func image(_ name:String) -> NSImage? {
        let url = Bundle.main.url(forResource:name,withExtension:"png",subdirectory:"CategoryGuides")
            ?? URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent("Resources/CategoryGuides/\(name).png")
        return NSImage(contentsOf:url)
    }
    var body:some View {
        VStack(spacing:0) {
            HStack { Text("操作图解").font(.system(size:20,weight:.semibold)); Spacer(); Button("关闭") { dismiss() }.buttonStyle(SoftWorkspaceButton()).keyboardShortcut(.cancelAction) }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    ForEach(Array(Self.scenes.enumerated()),id:\.offset) { index,scene in
                        VStack(alignment:.leading,spacing:10) {
                            Text("\(index+1)  \(scene.1)").font(.system(size:14,weight:.semibold))
                            if let image = Self.image(scene.0) {
                                Image(nsImage:image).resizable().scaledToFit().accessibilityLabel(scene.1+"操作示意图")
                            } else { Text("图解暂不可用，请重新打开应用。").foregroundStyle(.secondary) }
                        }
                    }
                }.padding(20)
            }
        }.frame(width:620,height:580).background(WorkspaceTheme.canvas).foregroundStyle(WorkspaceTheme.ink)
    }
}
