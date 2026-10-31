import SwiftUI

struct RenameDialog: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store: Store
    let target: NamingTarget
    @State var candidates: [Suggestion] = []
    @State var loading = true
    @State var base = ""
    @State var month = 1
    @State var namingDate = Date()
    @State var edited = false
    @State private var originalFallback = false
    @State var token = IndexCancellation()
    @State private var fieldFocused = false
    var onClose: (() -> Void)? = nil
    private var literalName:Bool { let format = store.namingFormat(for:target); return format == .category || format == .nameOnly }
    var finalName: String {
        if originalFallback && !edited { return URL(fileURLWithPath:target.path).lastPathComponent }
        if literalName || originalFallback {
            let value = cleanNamingTitle(base)
            return target.folder ? value : proposedName(base:value,month:1,folder:false,original:target.path)
        }
        return store.titleProposedName(base,target:target,date:namingDate,month:month)
    }
    func editableBase(_ value:String) -> String {
        if store.namingFormat(for:target) == .category {
            return smartNamingLiteralStem(store.titleProposedName(value,target:target,date:namingDate,month:month),target:target)
        }
        return cleanNamingTitle(smartNamingLiteralStem(value,target:target))
    }
    var canConfirm: Bool { !cleanNamingTitle(smartNamingLiteralStem(base,target:target)).isEmpty && !store.busy }
    private func close() { token.cancel(); if let onClose { onClose() } else { dismiss() } }
    func confirm() {
        guard canConfirm else { return }
        if originalFallback && !edited { close();return }
        if store.confirmRename(target,newName:finalName,requireMonth:!originalFallback) { close() }
    }
    var body: some View {
        VStack(spacing:0) {
            SmartDialogHeader(title:"智能命名",symbol:"text.cursor")
            Divider().overlay(WorkspaceTheme.line)
            VStack(alignment:.leading,spacing:22) {
                VStack(alignment:.leading,spacing:8) {
                    Text("原名称").font(.system(size:12)).foregroundStyle(WorkspaceTheme.secondary)
                    Text(URL(fileURLWithPath:target.path).lastPathComponent).font(.system(size:13)).lineLimit(2).textSelection(.enabled).help(target.path)
                }
                VStack(alignment:.leading,spacing:9) {
                    Text("修改名称").font(.system(size:12,weight:.semibold))
                    HStack(spacing:0) {
                        if !originalFallback && store.namingFormat(for:target) == .month {
                            Picker("月份",selection:$month) { ForEach(1...12,id:\.self) { Text("\($0)月").tag($0) } }.labelsHidden().frame(width:76).padding(.leading,8)
                            Rectangle().fill(WorkspaceTheme.line).frame(width:1,height:18)
                        }
                        if !originalFallback && store.namingFormat(for:target) == .monthDay {
                            Text(store.smartNamingPrefix(for:target,date:namingDate)).font(.system(size:13)).padding(.horizontal,12).help("月日格式：MMDD")
                            Rectangle().fill(WorkspaceTheme.line).frame(width:1,height:18)
                        }
                        SmartDialogTextField(text:Binding(get:{base},set:{base=$0;edited=true}),focused:$fieldFocused,placeholder:"修改名称",submit:confirm).frame(height:20).padding(.horizontal,12)
                        let ext = URL(fileURLWithPath:target.path).pathExtension
                        if !target.folder && !ext.isEmpty {
                            Rectangle().fill(WorkspaceTheme.line).frame(width:1,height:18)
                            Text("."+ext).font(.system(size:12)).foregroundStyle(WorkspaceTheme.secondary).padding(.horizontal,12)
                        }
                    }.frame(height:40).background(.white,in:RoundedRectangle(cornerRadius:8))
                        .overlay(RoundedRectangle(cornerRadius:8).stroke(fieldFocused ? accent : WorkspaceTheme.line,lineWidth:fieldFocused ? 2 : 1))
                }
                VStack(alignment:.leading,spacing:9) {
                    Text("推荐名称").font(.system(size:12,weight:.semibold))
                    if loading { HStack(spacing:8) { ProgressView().controlSize(.small); Text("正在读取文档…").font(.system(size:12)).foregroundStyle(WorkspaceTheme.secondary) } }
                    else if candidates.isEmpty { Text("未找到明确标题，已保留原名，可直接修改。").font(.system(size:12)).foregroundStyle(WorkspaceTheme.secondary).padding(.vertical,12) }
                    else {
                        ScrollView {
                            VStack(spacing:4) {
                                ForEach(candidates) { candidate in
                                    let chosen = base == editableBase(candidate.name)
                                    Button { originalFallback = false; base = editableBase(candidate.name); edited = true } label: {
                                        HStack(spacing:10) {
                                            Image(systemName:chosen ? "checkmark.circle.fill" : "circle").font(.system(size:16)).foregroundStyle(chosen ? accent : WorkspaceTheme.secondary)
                                            Text(editableBase(candidate.name)).font(.system(size:13,weight:chosen ? .medium : .regular)).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true)
                                            Spacer(minLength:0)
                                        }.padding(.horizontal,12).padding(.vertical,13).frame(maxWidth:.infinity,alignment:.leading)
                                            .background(chosen ? WorkspaceTheme.mint : WorkspaceTheme.projectCanvas,in:RoundedRectangle(cornerRadius:8))
                                    }.buttonStyle(.plain).help(candidate.evidence).accessibilityAddTraits(chosen ? .isSelected : [])
                                }
                            }
                        }
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            }.padding(.horizontal,26).padding(.vertical,22)
            Divider().overlay(WorkspaceTheme.line)
            HStack {
                Spacer()
                Button("取消") { close() }.buttonStyle(SmartDialogActionStyle()).keyboardShortcut(.cancelAction)
                Button("确认重命名",action:confirm).buttonStyle(SmartDialogActionStyle(primary:true)).disabled(!canConfirm).keyboardShortcut(.defaultAction)
            }.padding(.horizontal,26).frame(height:68).background(WorkspaceTheme.projectCanvas)
        }.frame(width:700,height:460).background(WorkspaceTheme.canvas).foregroundStyle(WorkspaceTheme.ink).tint(accent)
        .onAppear {
            namingDate = store.namingDate(for:target)
            month = store.namingMonth(for:target,date:namingDate)
            store.loadSuggestions(target,token:token) { values in
                candidates = values; loading = false
                if !edited && base.isEmpty {
                    if let first = values.first { base = editableBase(first.name) }
                    else {
                        originalFallback = true
                        let url = URL(fileURLWithPath:target.path)
                        base = target.folder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
                    }
                }
            }
        }.onDisappear { token.cancel() }
        .alert("重命名未完成",isPresented:Binding(get:{!store.error.isEmpty},set:{if !$0 { store.error = "" }})) { Button("知道了") { store.error = "" } } message: { Text(store.error) }
    }
}
