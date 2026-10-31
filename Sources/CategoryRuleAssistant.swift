import SwiftUI
import AppKit

@MainActor func openDoubaoWebsite() {
    // User-facing links open in Chrome; no website automation or model API calls.
    if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.google.Chrome") {
        NSWorkspace.shared.open([CategoryRuleExchange.website],withApplicationAt:chrome,configuration:NSWorkspace.OpenConfiguration())
    } else { NSWorkspace.shared.open(CategoryRuleExchange.website) }
}

struct CategoryRuleAssistant: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store:Store
    @State private var snapshot:[WorkspaceCategory]
    let onApplied: () -> Void
    @State private var stage:Int
    @State private var response:String
    @State private var parsed:[CategoryRuleImport] = []
    @State private var selected = Set<String>()
    @State private var message = ""
    @State private var failed = false
    init(store:Store,importing:Bool = false,response:String = "",reviewing:Bool = false,onApplied:@escaping () -> Void = {}) {
        self.store = store; _snapshot = State(initialValue:store.workspaceCategories); self.onApplied = onApplied
        _stage = State(initialValue:importing ? 1 : 0); _response = State(initialValue:response)
        var initial:[CategoryRuleImport] = []
        if reviewing {
            do { initial = try CategoryRuleExchange.parse(response,categories:store.workspaceCategories) }
            catch { _message = State(initialValue:error.localizedDescription); _failed = State(initialValue:true) }
        }
        _parsed = State(initialValue:initial); _selected = State(initialValue:Set(initial.map(\.id)))
    }
    private var targets:[WorkspaceCategory] { CategoryRuleExchange.targets(snapshot) }
    private var prompt:String { CategoryRuleExchange.prompt(categories:snapshot) }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("借助豆包生成分类规则").font(.system(size:22,weight:.semibold,design:.rounded))
            Text("复制提示词发给豆包，再把回复粘贴回来。归屿会识别规则，供你确认后应用。").font(.callout).foregroundStyle(WorkspaceTheme.secondary).fixedSize(horizontal:false,vertical:true)
            HStack(spacing:12) {
                Picker("操作步骤",selection:$stage) { Text("生成提示词").tag(0); Text("录入回复").tag(1) }.pickerStyle(.segmented).frame(width:270)
                Spacer()
                Button("去豆包官网",action:openDoubaoWebsite).buttonStyle(SoftWorkspaceButton())
            }
            Group {
                if stage == 0 { promptContent }
                else if parsed.isEmpty { replyContent }
                else { previewContent }
            }.frame(height:420).clipped()
            Divider()
            HStack {
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if stage == 1 {
                    if parsed.isEmpty {
                        Button("识别规则") { parse() }.buttonStyle(SoftWorkspaceButton(peach:true)).disabled(response.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction)
                    } else {
                        Button("应用 \(selected.count) 个分类的规则") { apply() }.buttonStyle(SoftWorkspaceButton(peach:true)).disabled(selected.isEmpty).keyboardShortcut(.defaultAction)
                    }
                }
            }
        }.padding(24).frame(width:740,height:650,alignment:.topLeading).background(WorkspaceTheme.canvas).tint(accent)
        .onChange(of:stage) { _ in message = ""; failed = false }
        .alert("规则未保存",isPresented:Binding(get:{!store.error.isEmpty},set:{if !$0 { store.error = "" }})) { Button("知道了") { store.error = "" } } message: { Text(store.error) }
    }
    @ViewBuilder private var promptContent:some View {
        VStack(alignment:.leading,spacing:12) {
                Text("根据 \(targets.count) 个分类生成；提示词仅包含分类名称，不包含文件名、路径或正文。").font(.caption).foregroundStyle(WorkspaceTheme.secondary)
                ScrollView {
                    Text(prompt).font(.system(size:13)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.topLeading).padding(12)
                }.background(Color.white,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(WorkspaceTheme.line))
                HStack {
                    Button("复制提示词") { copyPrompt() }.buttonStyle(SoftWorkspaceButton(peach:true)).disabled(targets.isEmpty).accessibilityIdentifier("copy-category-prompt")
                    Text(message).font(.caption).foregroundStyle(failed ? Color.red : WorkspaceTheme.secondary)
                    Spacer()
                    Button("已获得回复，去录入") { stage = 1; message = "" }.buttonStyle(SoftWorkspaceButton())
                }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
    @ViewBuilder private var replyContent:some View {
        VStack(alignment:.leading,spacing:12) {
                HStack {
                    Text("粘贴豆包回复的完整规则正文").font(.callout.weight(.semibold))
                    Spacer()
                    Button("从剪贴板粘贴") { pasteResponse() }.buttonStyle(SoftWorkspaceButton())
                }
                TextEditor(text:$response).font(.system(size:13)).frame(minHeight:80,maxHeight:.infinity).padding(8).background(Color.white).overlay(RoundedRectangle(cornerRadius:10).stroke(WorkspaceTheme.line)).accessibilityLabel("豆包回复")
                Text("首行为“归屿规则：1”，每类六行。格式有误会提示修正；识别时不会保存规则。").font(.caption).foregroundStyle(WorkspaceTheme.secondary)
                if !message.isEmpty { Text(message).font(.callout).foregroundStyle(failed ? Color.red : WorkspaceTheme.secondary).lineLimit(3).help(message).accessibilityLabel(message).accessibilityIdentifier("category-import-message") }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
    @ViewBuilder private var previewContent:some View {
        VStack(alignment:.leading,spacing:12) {
                HStack {
                    Text("已识别 \(parsed.count) 个分类，选择要应用的规则").font(.callout.weight(.semibold))
                    Spacer()
                    Button("返回修改回复") { parsed = []; selected = []; message = "" }.buttonStyle(SoftWorkspaceButton())
                }
                ScrollView {
                    VStack(alignment:.leading,spacing:14) {
                        ForEach(parsed) { item in
                            previewRow(item)
                            Divider()
                        }
                    }.padding(12)
                }.background(Color.white,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(WorkspaceTheme.line))
                Text("应用会替换勾选分类的规则（包括内置特殊匹配）。未勾选分类、兜底分类、启用状态和手动分类保留，源文件保持原样。").font(.caption).foregroundStyle(WorkspaceTheme.secondary).fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
    private func previewRow(_ item:CategoryRuleImport) -> some View {
        let rule = item.rule
        let excluded = rule.excludedKeywords.isEmpty ? "无" : rule.excludedKeywords.joined(separator:"、")
        let formats = rule.extensions.isEmpty ? "无" : rule.extensions.joined(separator:"、")
        let details = "排除词：\(excluded)　扩展名：\(formats)"
        let priorityLabel = rule.priority == 0 ? "普通优先级" : "优先"
        let status = "\(rule.scope.rawValue) · \(priorityLabel)"+(rule.enabled ? "" : " · 保持停用")
        let selection = Binding<Bool>(get:{ selected.contains(item.id) },set:{ if $0 { selected.insert(item.id) } else { selected.remove(item.id) } })
        return VStack(alignment:.leading,spacing:6) {
            Toggle(item.category.name,isOn:selection).font(.callout.weight(.semibold))
            Text("关键词："+rule.keywords.joined(separator:"、")).font(.system(size:12)).textSelection(.enabled)
            Text(details).font(.system(size:12)).textSelection(.enabled)
            Text(status).font(.caption).foregroundStyle(WorkspaceTheme.secondary)
        }
    }
    private func copyPrompt() {
        NSPasteboard.general.clearContents()
        failed = !NSPasteboard.general.setString(prompt,forType:.string)
        message = failed ? "复制失败，请选中上方提示词手动复制。" : "已复制，可到豆包粘贴发送。"
    }
    private func pasteResponse() {
        guard let text = NSPasteboard.general.string(forType:.string),!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { failed = true; message = "剪贴板中没有文字，请先复制豆包的回复。"; return }
        response = text; message = ""; failed = false
    }
    private func parse() {
        do { parsed = try CategoryRuleExchange.parse(response,categories:snapshot); selected = Set(parsed.map(\.id)); message = ""; failed = false }
        catch { failed = true; message = error.localizedDescription }
    }
    private func apply() {
        if store.importCategoryRules(parsed.filter { selected.contains($0.id) }) { onApplied(); dismiss() }
    }
}
