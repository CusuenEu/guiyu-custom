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
    @StateObject var preview = NamingPreviewModel()
    @State var recognizedSelection = NSRange(location:0,length:0)
    @State var recognitionNotice = ""
    @State private var started = false
    var onClose: (() -> Void)? = nil
    private var literalName:Bool { let format = store.namingFormat(for:target); return format == .category || format == .nameOnly }
    var finalName: String {
        if originalFallback && !edited { return URL(fileURLWithPath:target.path).lastPathComponent }
        if !target.folder {
            // Manual final-name edits stay literal; only generated/recognized text is cleaned.
            let value = smartNamingLiteralStem(base,target:target).trimmingCharacters(in:.whitespacesAndNewlines)
            let prefix = literalName || originalFallback ? "" : store.smartNamingPrefix(for:target,date:namingDate,month:month)
            return proposedName(base:prefix.isEmpty ? value : prefix+" "+value,month:1,folder:false,original:target.path)
        }
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
    private func close() { token.cancel();preview.cancel(); if let onClose { onClose() } else { dismiss() } }
    func confirm() {
        guard canConfirm else { return }
        if originalFallback && !edited { close();return }
        if store.confirmRename(target,newName:finalName,requireMonth:!originalFallback) { close() }
    }
    var compactBody: some View {
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
    }
    var body:some View {
        Group { if target.folder { compactBody } else { previewBody } }
        .onAppear {
            guard !started else { return };started = true
            namingDate = store.namingDate(for:target)
            month = store.namingMonth(for:target,date:namingDate)
            if !target.folder { preview.load(target) }
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
        }.onDisappear { token.cancel();preview.cancel() }
        .alert("重命名未完成",isPresented:Binding(get:{!store.error.isEmpty},set:{if !$0 { store.error = "" }})) { Button("知道了") { store.error = "" } } message: { Text(store.error) }
    }

    func useRecognizedText() {
        let text = cleanRegionRecognizedText(selectedNamingText(preview.state.text,range:recognizedSelection))
        guard !text.isEmpty else { recognitionNotice = "没有可用的名称文字，请重新框选或手动输入。";return }
        originalFallback = false;base = editableBase(text);edited = true;recognitionNotice = ""
    }
    func panelHeading(_ title:String) -> some View {
        HStack(spacing:8) {
            RoundedRectangle(cornerRadius:1.5).fill(accent).frame(width:3,height:15)
            Text(title).font(.system(size:15,weight:.semibold))
        }
    }
    var previewBody:some View {
        VStack(spacing:0) {
            HStack(spacing:12) {
                Image(systemName:"doc.text.fill").font(.system(size:24)).foregroundStyle(accent).accessibilityHidden(true)
                Text("智能命名").font(.system(size:20,weight:.semibold))
                Spacer()
                Text(URL(fileURLWithPath:target.path).lastPathComponent).font(.system(size:12)).foregroundStyle(WorkspaceTheme.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth:300,alignment:.trailing).help(target.path)
                Button(action:close) { Image(systemName:"xmark").frame(width:28,height:28) }.buttonStyle(.plain).foregroundStyle(WorkspaceTheme.secondary).help("关闭智能命名")
            }.padding(.horizontal,22).frame(height:56)
            Divider().overlay(WorkspaceTheme.line)
            HStack(alignment:.top,spacing:14) {
                previewPanel.frame(width:440)
                VStack(spacing:12) {
                    recognizedPanel.frame(height:170)
                    recommendationPanel
                    HStack(spacing:10) {
                        Label("确认后才修改文件名",systemImage:"info.circle").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary)
                        Spacer(minLength:0)
                        Button("取消",action:close).buttonStyle(SmartDialogActionStyle()).keyboardShortcut(.cancelAction)
                        Button("确认重命名",action:confirm).buttonStyle(SmartDialogActionStyle(primary:true)).keyboardShortcut(.defaultAction).disabled(!canConfirm)
                    }.frame(height:38)
                }
            }.padding(16)
        }.frame(width:1000,height:660).background(WorkspaceTheme.projectCanvas).foregroundStyle(WorkspaceTheme.ink).tint(accent)
        .onChange(of:preview.selectedPage) { _ in recognizedSelection = NSRange(location:0,length:0);recognitionNotice = "" }
    }
    var previewPanel:some View {
        VStack(alignment:.leading,spacing:10) {
            panelHeading("文件预览")
            HStack(spacing:6) {
                ForEach(preview.pages.indices,id:\.self) { index in
                    Button("第 \(index+1) 页") { preview.selectPage(index) }
                        .font(.system(size:12,weight:.medium)).padding(.horizontal,12).frame(height:28)
                        .background(preview.selectedPage == index ? WorkspaceTheme.mint : WorkspaceTheme.projectCanvas,in:RoundedRectangle(cornerRadius:6))
                        .overlay(RoundedRectangle(cornerRadius:6).stroke(WorkspaceTheme.line,lineWidth:1)).buttonStyle(.plain)
                        .accessibilityAddTraits(preview.selectedPage == index ? .isSelected : [])
                }
                Spacer(minLength:0)
                Menu {
                    ForEach([1.0,1.25,1.5,2.0],id:\.self) { value in Button(value == 1 ? "适合页面" : "\(Int(value*100))%") { preview.zoom = value } }
                } label: { Text(preview.zoom == 1 ? "适合页面" : "\(Int(preview.zoom*100))%").font(.system(size:11)) }.fixedSize().disabled(preview.pages.isEmpty)
                Button { preview.rotate() } label: { Image(systemName:"rotate.right").frame(width:24,height:28) }.buttonStyle(.plain).disabled(preview.pages.isEmpty).help("顺时针旋转预览，不修改原文件")
            }.frame(height:28)
            Group {
                if preview.loading {
                    VStack(spacing:10) { ProgressView();Text("正在加载前两页预览…").font(.system(size:12)).foregroundStyle(WorkspaceTheme.secondary) }.frame(maxWidth:.infinity,maxHeight:.infinity)
                } else if let image = preview.displayImage {
                    NamingRegionPreview(image:image,zoom:preview.zoom,turns:preview.state.turns,region:preview.state.region,selected:{ region in
                        recognizedSelection = NSRange(location:0,length:0);recognitionNotice = "";preview.recognize(region)
                    },invalid:{preview.invalidSelection()})
                } else {
                    VStack(spacing:12) { Image(systemName:"doc.text.magnifyingglass").font(.system(size:30)).foregroundStyle(WorkspaceTheme.secondary);Text(preview.notice).font(.system(size:12)).foregroundStyle(WorkspaceTheme.secondary).multilineTextAlignment(.center).padding(.horizontal,22) }.frame(maxWidth:.infinity,maxHeight:.infinity)
                }
            }.background(Color(nsColor:NSColor(calibratedWhite:0.93,alpha:1))).clipShape(RoundedRectangle(cornerRadius:6))
            Label("按住鼠标拖动，框选需要识别的文字",systemImage:"viewfinder").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary)
        }.padding(14).frame(maxHeight:.infinity).background(.white,in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).stroke(WorkspaceTheme.line,lineWidth:1))
    }
    var recognizedPanel:some View {
        VStack(alignment:.leading,spacing:8) {
            panelHeading("识别文字")
            NamingRecognizedTextEditor(text:Binding(get:{preview.state.text},set:{preview.editText($0)}),selection:$recognizedSelection)
                .frame(maxWidth:.infinity,maxHeight:.infinity).clipShape(RoundedRectangle(cornerRadius:6))
                .overlay(RoundedRectangle(cornerRadius:6).stroke(WorkspaceTheme.line,lineWidth:1))
            HStack(spacing:6) {
                if preview.state.recognizing { ProgressView().controlSize(.small);Text("正在识别选框…").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary) }
                else { Text(recognitionNotice.isEmpty ? preview.state.message : recognitionNotice).font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary).lineLimit(2) }
                Spacer(minLength:2)
                NamingUseRecognizedButton(enabled:!preview.state.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !preview.state.recognizing,action:useRecognizedText).frame(width:120,height:34)
            }
        }.padding(14).background(.white,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(WorkspaceTheme.line,lineWidth:1))
    }
    var recommendationPanel:some View {
        VStack(alignment:.leading,spacing:10) {
            panelHeading("推荐名称")
            ScrollView {
                VStack(spacing:6) {
                    if loading { HStack(spacing:8) { ProgressView().controlSize(.small);Text("正在分析标题…").font(.system(size:12)).foregroundStyle(WorkspaceTheme.secondary);Spacer() }.padding(.vertical,12) }
                    else if candidates.isEmpty { Text("未找到可靠标题，已保留原名。可框选文字或手动修改。").font(.system(size:12)).foregroundStyle(WorkspaceTheme.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,10) }
                    ForEach(candidates) { candidate in
                        let chosen = base == editableBase(candidate.name)
                        Button { originalFallback = false;base = editableBase(candidate.name);edited = true } label: {
                            HStack(spacing:10) {
                                Image(systemName:chosen ? "checkmark.circle.fill" : "circle").font(.system(size:16)).foregroundStyle(chosen ? accent : WorkspaceTheme.secondary)
                                VStack(alignment:.leading,spacing:3) {
                                    Text(editableBase(candidate.name)).font(.system(size:13,weight:chosen ? .medium : .regular)).lineLimit(2).multilineTextAlignment(.leading)
                                    Text(candidate.evidence.components(separatedBy:" · ").first ?? candidate.evidence).font(.system(size:10)).foregroundStyle(WorkspaceTheme.secondary).lineLimit(1)
                                }
                                Spacer(minLength:0)
                            }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(chosen ? WorkspaceTheme.mint : WorkspaceTheme.projectCanvas,in:RoundedRectangle(cornerRadius:7))
                        }.buttonStyle(.plain).help(candidate.evidence).accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
            }.frame(minHeight:65,maxHeight:.infinity)
            panelHeading("最终文件名")
            HStack(spacing:0) {
                if !originalFallback && store.namingFormat(for:target) == .month {
                    Picker("月份",selection:$month) { ForEach(1...12,id:\.self) { Text("\($0)月").tag($0) } }.labelsHidden().frame(width:70).padding(.leading,4)
                    Rectangle().fill(WorkspaceTheme.line).frame(width:1,height:18)
                }
                if !originalFallback && store.namingFormat(for:target) == .monthDay {
                    Text(store.smartNamingPrefix(for:target,date:namingDate)).font(.system(size:13)).padding(.horizontal,10)
                    Rectangle().fill(WorkspaceTheme.line).frame(width:1,height:18)
                }
                SmartDialogTextField(text:Binding(get:{base},set:{base=$0;edited=true}),focused:$fieldFocused,placeholder:"最终文件名",submit:confirm).frame(height:20).padding(.horizontal,10)
                let ext = URL(fileURLWithPath:target.path).pathExtension
                if !ext.isEmpty {
                    Text("."+ext).font(.system(size:12)).foregroundStyle(WorkspaceTheme.secondary).padding(.horizontal,10).frame(height:38).background(WorkspaceTheme.projectCanvas)
                }
            }.frame(height:40).background(.white,in:RoundedRectangle(cornerRadius:7)).clipShape(RoundedRectangle(cornerRadius:7))
                .overlay(RoundedRectangle(cornerRadius:7).stroke(fieldFocused ? accent : WorkspaceTheme.line,lineWidth:fieldFocused ? 2 : 1))
        }.padding(14).frame(maxHeight:.infinity).background(.white,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(WorkspaceTheme.line,lineWidth:1))
    }
}
