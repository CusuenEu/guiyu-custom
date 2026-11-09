import SwiftUI

struct QuickArchiveDialog: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store: Store
    let request: QuickArchiveRequest
    @State private var query = ""
    @State var selected: String? = nil
    @State private var choices: [ProjectArchiveChoice] = []
    @State private var loading = true
    @State private var status = ""
    @State private var failure = ""
    @State private var token = IndexCancellation()
    @State private var searchIndex: ArchiveProjectIndex?
    @State private var fieldFocused = false
    @State private var requiresReselection = false
    var onClose: (() -> Void)? = nil
    private func close() { token.cancel(); if let onClose { onClose() } else { dismiss() } }
    var searching: Bool { !query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
    var searchResults: [Project] {
        (searchIndex?.search(query) ?? []).filter { archiveProjectAccepts($0,request:request) }
    }
    var destination: Project? {
        guard let project = store.settings.projects.first(where: { $0.path == selected && $0.shallow != true }),
              archiveProjectAccepts(project,request:request),
              (searching ? searchResults.contains { $0.path == project.path } : choices.contains { $0.id == project.path }) else { return nil }
        return project
    }
    var matchedChoices: [ProjectArchiveChoice] { choices.filter { archiveProjectAccepts($0.project,request:request) } }
    var body: some View {
        VStack(spacing:0) {
            SmartDialogHeader(title:"智能归档",symbol:"tray.and.arrow.down",prominentIcon:true)
            Divider().overlay(WorkspaceTheme.line)
            VStack(alignment:.leading,spacing:18) {
                SmartDialogFileSummary(rows:request.rows)
                HStack(spacing:9) {
                    Image(systemName:"magnifyingglass").foregroundStyle(WorkspaceTheme.secondary)
                    SmartDialogTextField(text:$query,focused:$fieldFocused,placeholder:"搜索项目名、单位或关键词",submit:confirm).frame(height:20)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(WorkspaceTheme.secondary) }.buttonStyle(.plain).accessibilityLabel("清除搜索") }
                }.padding(.horizontal,12).frame(height:36).background(.white,in:RoundedRectangle(cornerRadius:8))
                    .overlay(RoundedRectangle(cornerRadius:8).stroke(fieldFocused ? accent : WorkspaceTheme.line,lineWidth:fieldFocused ? 2 : 1))
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:8) {
                        if searching {
                            let results = searchResults
                            Text("搜索结果").font(.system(size:12,weight:.semibold)).padding(.bottom,2)
                            ForEach(results) { project in projectButton(project,evidence:nil) }
                            if results.isEmpty { listMessage("没有匹配的项目") }
                        } else if loading {
                            HStack(spacing:8) { ProgressView().controlSize(.small); Text("正在匹配项目…").font(.system(size:12)).foregroundStyle(WorkspaceTheme.secondary) }
                        } else {
                            let matches = matchedChoices
                            if !matches.isEmpty {
                                Text("匹配项目").font(.system(size:12,weight:.semibold)).padding(.bottom,2)
                                ForEach(matches) { choice in projectButton(choice.project,evidence:choice.evidence,matchingRanges:choice.matchingRanges) }
                            } else {
                                listMessage(status.isEmpty ? "未找到匹配项目，可输入项目名搜索" : status)
                            }
                        }
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                if !failure.isEmpty { Text(failure).font(.system(size:12)).foregroundStyle(.red).textSelection(.enabled) }
            }.padding(.horizontal,26).padding(.top,20).padding(.bottom,18)
            Divider().overlay(WorkspaceTheme.line)
            HStack {
                if store.busy {
                    Text("后台索引进行中，不影响归档").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary)
                }
                Spacer()
                Button("取消") { close() }.buttonStyle(SmartDialogActionStyle()).keyboardShortcut(.cancelAction)
                Button("确认归档",action:confirm).buttonStyle(SmartDialogActionStyle(primary:true)).disabled(destination == nil || requiresReselection).keyboardShortcut(.defaultAction)
            }.padding(.horizontal,26).frame(height:68).background(WorkspaceTheme.projectCanvas)
        }.frame(width:700,height:620).background(WorkspaceTheme.canvas).foregroundStyle(WorkspaceTheme.ink).tint(accent)
        .onAppear {
            searchIndex = ArchiveProjectIndex(projects:store.settings.projects)
            store.suggestArchiveProjects(request,token:token) { values,message in choices = values; loading = false; status = message }
        }.onChange(of:query) { _ in selected = nil }.onChange(of:store.settings.projects) { values in searchIndex = ArchiveProjectIndex(projects:values) }.onDisappear { token.cancel() }
    }
    private func listMessage(_ message: String) -> some View {
        Text(message).font(.system(size:13)).foregroundStyle(WorkspaceTheme.secondary).frame(maxWidth:.infinity).padding(.vertical,24)
    }
    private func projectTitle(_ name: String, matchingRanges: [Range<String.Index>]) -> Text {
        var title = AttributedString(name)
        for range in matchingRanges {
            guard let start = AttributedString.Index(range.lowerBound,within:title),
                  let end = AttributedString.Index(range.upperBound,within:title) else { continue }
            title[start..<end].backgroundColor = Color(red:0.98,green:0.81,blue:0.81)
        }
        return Text(title)
    }
    func projectButton(_ project: Project, evidence: String?, matchingRanges: [Range<String.Index>] = []) -> some View {
        Button { selected = project.path } label: {
            HStack(spacing:12) {
                Image(nsImage:WorkspaceTheme.folder).resizable().frame(width:26,height:25)
                VStack(alignment:.leading,spacing:5) {
                    projectTitle(project.name,matchingRanges:matchingRanges).font(.system(size:13,weight:selected == project.path ? .semibold : .regular)).lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true)
                    if let group = project.group, !group.isEmpty { Text(group).font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary) }
                }
                Spacer(minLength:8)
                Image(systemName:selected == project.path ? "checkmark.circle.fill" : "circle").font(.system(size:17)).foregroundStyle(selected == project.path ? accent : WorkspaceTheme.secondary)
            }.padding(.horizontal,12).padding(.vertical,12).frame(maxWidth:.infinity,alignment:.leading)
                .background(selected == project.path ? WorkspaceTheme.mint : .white,in:RoundedRectangle(cornerRadius:8))
        }.buttonStyle(.plain).help([project.path,evidence].compactMap{$0}.joined(separator:"\n")).accessibilityAddTraits(selected == project.path ? .isSelected : [])
    }
    func confirm() {
        guard let project = destination, !requiresReselection else {
            if destination == nil { failure = "请先在列表中选择一个目标项目。" }
            return
        }
        if store.busy { store.scanCancellation?.cancel(); store.busy = false }
        token.cancel()
        let result = store.confirmQuickArchive(request,to:project)
        if result.failure == nil { close() }
        else {
            requiresReselection = !result.completed.isEmpty
            failure = (result.failure ?? "归档未完成") + (result.completed.isEmpty ? "" : "。请关闭窗口，重新选择未完成的条目。")
            loading = false
        }
    }
}
