import SwiftUI
import AppKit

enum SettingsSection: String, CaseIterable {
    case locations = "文件位置", categories = "文件分类", history = "归档记录"
    var symbol: String {
        switch self { case .locations: return "folder"; case .categories: return "square.grid.2x2"; case .history: return "clock.arrow.circlepath" }
    }
    var detail: String {
        switch self {
        case .locations: return "把项目和待整理文件，放在顺手的位置。"
        case .categories: return "按你的习惯整理，原文件夹结构保持不变。"
        case .history: return "查看文件去向，需要时可以撤销归档。"
        }
    }
}

struct WorkspaceSettingsView: View {
    @ObservedObject var store: Store
    var close: () -> Void
    var openPending: () -> Void
    @State var section: SettingsSection = .locations
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:24) {
                HStack(spacing:10) {
                    if let image = NSImage(named:"GuiyuLogo") { Image(nsImage:image).resizable().scaledToFit().frame(width:44,height:48).accessibilityHidden(true) }
                    Text("设置").font(.system(size:21,weight:.semibold,design:.rounded))
                }.padding(.top,10).padding(.horizontal,8)
                VStack(spacing:7) {
                    ForEach(SettingsSection.allCases,id:\.self) { item in
                        Button { section = item } label: {
                            HStack(spacing:10) {
                                Image(systemName:item.symbol).font(.system(size:16)).frame(width:20).foregroundStyle(accent)
                                Text(item.rawValue).font(.system(size:14,weight:section == item ? .semibold : .regular,design:.rounded))
                                Spacer(minLength:0)
                            }.padding(.horizontal,12).frame(height:44)
                                .background(section == item ? WorkspaceTheme.mint : .clear,in:RoundedRectangle(cornerRadius:12)).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityAddTraits(section == item ? .isSelected : [])
                    }
                }
                Spacer()
                Label("文件留在本机",systemImage:"internaldrive").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary).padding(.horizontal,9)
            }.padding(16).frame(width:174).background(WorkspaceTheme.rail)
            Divider()
            VStack(alignment:.leading,spacing:0) {
                VStack(alignment:.leading,spacing:8) {
                    Text(section.rawValue).font(.system(size:25,weight:.semibold,design:.rounded))
                    Text(section.detail).font(.system(size:13)).foregroundStyle(WorkspaceTheme.secondary)
                }.padding(.horizontal,28).padding(.top,30).padding(.bottom,24)
                ScrollView {
                    VStack(alignment:.leading,spacing:26) {
                        switch section {
                        case .locations: locations
                        case .categories: CategorySettingsView(store:store)
                        case .history: history
                        }
                    }.padding(.horizontal,28).padding(.bottom,24).frame(maxWidth:.infinity,alignment:.leading)
                }
                Divider()
                HStack {
                    Circle().fill(accent).frame(width:5,height:5)
                    Text("本地保存 · 更改即生效").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary)
                    Spacer()
                    Button("完成",action:close).buttonStyle(SoftWorkspaceButton(peach:true)).keyboardShortcut(.defaultAction)
                }.padding(.horizontal,28).frame(height:64)
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(width:820,height:620).background(WorkspaceTheme.canvas).tint(accent)
        .onExitCommand(perform:close)
        .alert("设置未完成",isPresented:Binding(get:{!store.error.isEmpty && section != .categories},set:{if !$0 { store.error = "" }})) { Button("知道了") { store.error = "" } } message: { Text(store.error) }
    }
    var locations: some View {
        VStack(alignment:.leading,spacing:24) {
            VStack(alignment:.leading,spacing:12) {
                Text("项目总目录").font(.system(size:14,weight:.semibold))
                HStack(spacing:13) {
                    Image(nsImage:WorkspaceTheme.folder).resizable().frame(width:34,height:32)
                    VStack(alignment:.leading,spacing:5) {
                        Text(store.settings.root.isEmpty ? "还没有选择目录" : URL(fileURLWithPath:store.settings.root).lastPathComponent).font(.system(size:14,weight:.medium)).lineLimit(1)
                        Text(store.settings.root.isEmpty ? "选择存放项目文件夹的位置" : store.settings.root).font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary).lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(store.settings.root)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    Button(store.settings.root.isEmpty ? "选择目录…" : "更换…") { store.choose("root") }.buttonStyle(SoftWorkspaceButton())
                }.padding(16).background(WorkspaceTheme.rail.opacity(0.65),in:RoundedRectangle(cornerRadius:14))
                Text("左侧按真实文件夹显示，文件继续保留在 Finder 中。").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary)
            }
            ArchiveSourceSettingsView(store:store)
            DisclosureGroup("更多目录选项") {
                VStack(alignment:.leading,spacing:10) {
                    Text("待归档目录").font(.system(size:13,weight:.medium))
                    Text(store.settings.inbox.isEmpty ? "尚未设置" : store.settings.inbox).font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary).lineLimit(2).textSelection(.enabled)
                    Button("更换待归档目录…") { store.choose("inbox") }.buttonStyle(SoftWorkspaceButton())
                }.padding(.top,12)
            }.font(.system(size:12)).foregroundStyle(WorkspaceTheme.secondary)
        }
    }
    var history: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                Text("待确认文件").font(.system(size:14,weight:.semibold))
                Text("\(store.incoming.count) 项").font(.system(size:12)).foregroundStyle(WorkspaceTheme.secondary)
                Spacer()
                Button("查看…",action:openPending).buttonStyle(SoftWorkspaceButton())
            }
            Divider()
            Text("最近归档").font(.system(size:14,weight:.semibold))
            if store.settings.moves.isEmpty {
                VStack(spacing:12) {
                    Image(systemName:"tray").font(.system(size:30,weight:.light)).foregroundStyle(accent)
                    Text("还没有归档记录").font(.system(size:14,weight:.medium))
                    Text("从下载或最近使用里，右键文件即可快速归类。").font(.system(size:12)).foregroundStyle(WorkspaceTheme.secondary)
                }.frame(maxWidth:.infinity).padding(.vertical,50)
            } else {
                ForEach(Array(store.settings.moves.prefix(30))) { move in
                    HStack(alignment:.top,spacing:12) {
                        Image(systemName:"doc").font(.system(size:19)).foregroundStyle(accent).padding(.top,3)
                        VStack(alignment:.leading,spacing:6) {
                            Text(URL(fileURLWithPath:move.destination).lastPathComponent).font(.system(size:13,weight:.medium)).lineLimit(2)
                            Text("归入「"+URL(fileURLWithPath:move.destination).deletingLastPathComponent().lastPathComponent+"」").font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary).lineLimit(1).help(move.destination)
                            Text(move.date.formatted(date:.abbreviated,time:.shortened)).font(.system(size:11)).foregroundStyle(WorkspaceTheme.secondary)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                        Button(move.undone ? "已撤销" : "撤销") { store.undo(move) }.buttonStyle(SoftWorkspaceButton()).disabled(move.undone || store.busy)
                    }.padding(.vertical,6)
                    Divider()
                }
            }
        }
    }
}
