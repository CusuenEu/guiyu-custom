import SwiftUI

struct CategoryRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: Store
    let category: WorkspaceCategory
    @State private var keywords: String
    @State private var exclusions: String
    @State private var extensions: String
    @State private var enabled: Bool
    @State private var scope: CategoryRule.Scope
    @State private var priority: Int
    @State private var regenerated: CategoryRule?
    init(store:Store,category:WorkspaceCategory) {
        self.store = store; self.category = category
        let rule = category.effectiveRule
        _keywords = State(initialValue:rule.keywords.joined(separator:"、"))
        _exclusions = State(initialValue:rule.excludedKeywords.joined(separator:"、"))
        _extensions = State(initialValue:rule.extensions.joined(separator:"、"))
        _enabled = State(initialValue:rule.enabled); _scope = State(initialValue:rule.scope); _priority = State(initialValue:rule.priority)
    }
    private var base: CategoryRule { regenerated ?? category.effectiveRule }
    private var rule: CategoryRule {
        var value = base
        value.keywords = CategoryRule.terms(keywords); value.excludedKeywords = CategoryRule.terms(exclusions)
        value.extensions = CategoryRule.terms(extensions).map { $0.lowercased().trimmingCharacters(in:CharacterSet(charactersIn:" .")) }
        value.enabled = enabled; value.scope = scope; value.priority = priority
        if !value.sameMatchingConditions(as:base) { value.origin = .edited }
        if !value.samePositiveConditions(as:base) { value.legacyCategory = nil }
        return value
    }
    private var sourceLabel: String {
        switch rule.origin { case .automatic: return "系统根据分类名称自动生成"; case .edited: return "使用你修改后的规则"; case .builtIn: return "沿用内置识别规则" }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:6) {
                    Text("「"+category.name+"」的分类规则").font(.system(size:21,weight:.semibold,design:.rounded)).lineLimit(2)
                    Text(sourceLabel).font(.caption).foregroundStyle(WorkspaceTheme.secondary)
                }
                Spacer(minLength:12)
                Button("按名称重新生成") { regenerate() }.buttonStyle(SoftWorkspaceButton())
            }
            Toggle("自动归入此分类",isOn:$enabled)
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    VStack(alignment:.leading,spacing:7) {
                        Text("匹配关键词").font(.callout.weight(.semibold))
                        TextEditor(text:$keywords).font(.system(size:13)).frame(height:76).padding(7)
                            .background(Color.white).overlay(RoundedRectangle(cornerRadius:8).stroke(WorkspaceTheme.line))
                            .accessibilityLabel("匹配关键词")
                        Text("文件名含任一关键词，或扩展名匹配时自动分类；用逗号、顿号或换行分隔。").font(.caption).foregroundStyle(WorkspaceTheme.secondary)
                    }
                    VStack(alignment:.leading,spacing:7) {
                        Text("排除关键词").font(.callout.weight(.semibold))
                        TextField("例如：模板、草稿（可留空）",text:$exclusions).textFieldStyle(.roundedBorder).accessibilityLabel("排除关键词")
                        Text("文件名命中排除词时，不会自动归入此分类。").font(.caption).foregroundStyle(WorkspaceTheme.secondary)
                    }
                    VStack(alignment:.leading,spacing:7) {
                        Text("匹配扩展名").font(.callout.weight(.semibold))
                        TextField("例如：pdf、docx、xlsx（可留空）",text:$extensions).textFieldStyle(.roundedBorder).accessibilityLabel("匹配扩展名")
                    }
                    HStack(spacing:24) {
                        Picker("应用范围",selection:$scope) { ForEach(CategoryRule.Scope.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                        Picker("优先级",selection:$priority) { Text("普通").tag(0); Text("优先").tag(1) }.frame(width:180)
                    }
                    if let legacy = rule.legacyCategory {
                        if legacy == "其他" { Text("这是兜底分类：没有匹配其他规则，或无法区分规则的条目会显示在这里。").font(.caption).foregroundStyle(WorkspaceTheme.secondary) }
                        else {
                            DisclosureGroup("内置特殊匹配说明") {
                                Text("招投标规则识别独立的 RFP／RFQ 代号及 REQUEST FOR PROPOSALS／QUOTATIONS；响应、应答及报价材料会按原有优先关系区分。修改匹配关键词或扩展名后，将采用新的关键词规则；排除词、范围及优先级可以独立调整。").font(.caption).foregroundStyle(WorkspaceTheme.secondary).padding(.top,6)
                            }.font(.caption)
                        }
                    }
                    Text("手动指定的分类优先保留。自动规则先比较优先级，再比较名称匹配；文件类型匹配优先级较低，无法区分时显示在兜底分类。").font(.caption).foregroundStyle(WorkspaceTheme.secondary)
                }.padding(.trailing,4)
            }
            Divider()
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存规则") { if store.saveCategoryRule(id:category.id,rule:rule) { dismiss() } }.buttonStyle(SoftWorkspaceButton(peach:true)).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width:660,height:570).background(WorkspaceTheme.canvas).tint(accent)
        .alert("规则未保存",isPresented:Binding(get:{!store.error.isEmpty},set:{if !$0 { store.error = "" }})) { Button("知道了") { store.error = "" } } message: { Text(store.error) }
    }
    private func regenerate() {
        let rule = CategoryRuleGenerator.generate(name:category.name,legacyID:category.name == category.id ? category.id : nil)
        regenerated = rule; keywords = rule.keywords.joined(separator:"、"); exclusions = rule.excludedKeywords.joined(separator:"、")
        extensions = rule.extensions.joined(separator:"、"); enabled = rule.enabled; scope = rule.scope; priority = rule.priority
    }
}
