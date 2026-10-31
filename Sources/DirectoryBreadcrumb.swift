import SwiftUI
import AppKit

struct DirectoryPathItem:Identifiable,Equatable {
    let path:String
    let title:String
    var id:String { path }
}
enum DirectoryBreadcrumb {
    private static func normalized(_ path:String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        // Normalize only lexical components. Foundation can rewrite /private/var
        // to /var; retaining the stored root spelling keeps navigation identity stable.
        var parts:[Substring] = []
        for part in path.split(separator:"/") {
            if part == "." { continue }
            if part == ".." { if !parts.isEmpty { parts.removeLast() } }
            else { parts.append(part) }
        }
        return "/"+parts.joined(separator:"/")
    }
    static func items(root:String,current:String,rootTitle:String) -> [DirectoryPathItem] {
        guard let rootPath = normalized(root), let currentPath = normalized(current) else { return [] }
        let rootParts = rootPath.split(separator:"/"), parts = currentPath.split(separator:"/")
        guard parts.starts(with:rootParts) else { return [] }
        var path = rootPath
        var result = [DirectoryPathItem(path:path,title:rootTitle)]
        for part in parts.dropFirst(rootParts.count) {
            path = (path == "/" ? "" : path)+"/"+part
            result.append(DirectoryPathItem(path:path,title:String(part)))
        }
        return result
    }
    static func destination(_ path:String,root:String,current:String) -> String? {
        guard let destination = normalized(path) else { return nil }
        return items(root:root,current:current,rootTitle:"").first { $0.path == destination }?.path
    }
}

struct DirectoryBreadcrumbBar:View {
    let root:String
    let current:String
    let rootTitle:String
    let navigate:(String) -> Void
    private var items:[DirectoryPathItem] { DirectoryBreadcrumb.items(root:root,current:current,rootTitle:rootTitle) }
    var body:some View {
        HStack(spacing:8) {
            Button {
                if items.count > 1 { navigate(items[items.count-2].path) }
            } label: {
                Image(systemName:"chevron.left").font(.system(size:12,weight:.semibold)).frame(width:28,height:28)
            }.buttonStyle(.bordered).disabled(items.count <= 1).help("上一级目录").accessibilityLabel("上一级目录")
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal,showsIndicators:true) {
                        HStack(spacing:4) {
                            ForEach(Array(items.enumerated()),id:\.element.id) { index,item in
                                HStack(spacing:4) {
                                    if index > 0 { Image(systemName:"chevron.right").font(.system(size:9,weight:.medium)).foregroundStyle(WorkspaceTheme.secondary).accessibilityHidden(true) }
                                    DirectoryBreadcrumbLink(item:item,root:index == 0,current:index == items.count-1,hint:items.prefix(index+1).map(\.title).joined(separator:" / ")) { navigate(item.path) }
                                }.id(item.id)
                            }
                        }.padding(.vertical,2)
                    }
                    .onAppear { revealCurrent(proxy) }
                    .onChange(of:current) { _ in revealCurrent(proxy) }
                    .onChange(of:geometry.size.width) { _ in revealCurrent(proxy) }
                }
            }
            Menu {
                ForEach(items) { item in
                    Button(item.title) { navigate(item.path) }.disabled(item.id == items.last?.id)
                }
            } label: { Image(systemName:"ellipsis").frame(width:24,height:28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("选择任意上级目录").accessibilityLabel("选择路径层级")
        }.frame(height:36)
    }
    private func revealCurrent(_ proxy:ScrollViewProxy) {
        guard let id = items.last?.id else { return }
        DispatchQueue.main.async { proxy.scrollTo(id,anchor:.trailing) }
    }
}
private struct DirectoryBreadcrumbLink:View {
    let item:DirectoryPathItem
    let root:Bool
    let current:Bool
    let hint:String
    let action:() -> Void
    var body:some View {
        Button(action:action) {
            HStack(spacing:5) {
                if root { Image(systemName:"folder").font(.system(size:12)).accessibilityHidden(true) }
                Text(item.title).font(.system(size:12,weight:current ? .semibold : .medium)).underline(!current).lineLimit(1).truncationMode(.middle).frame(maxWidth:170)
            }.foregroundStyle(current ? WorkspaceTheme.ink : accent).padding(.horizontal,8).frame(height:28)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(current).help(hint)
            .accessibilityLabel((current ? "当前目录：" : "前往目录：")+item.title)
            .onHover { value in
                if !current { (value ? NSCursor.pointingHand : NSCursor.arrow).set() }
            }
    }
}

func directoryBreadcrumbTest(root:URL) throws {
    let base = root.appendingPathComponent("breadcrumb/项目")
    let current = base.appendingPathComponent("招标文件下载2026-07-23-165700/5_附件B-技术规范书/附件B-技术规范书")
    try fm.createDirectory(at:current,withIntermediateDirectories:true)
    let file = current.appendingPathComponent("保留文件.txt")
    try "unchanged".write(to:file,atomically:true,encoding:.utf8)
    let items = DirectoryBreadcrumb.items(root:base.path,current:current.path,rootTitle:"项目根目录")
    try verify(items.count == 4 && items[0].path == base.path && items[0].title == "项目根目录" && items.last?.path == current.path,"Breadcrumbs retain every level and its exact absolute destination")
    for item in items {
        try verify(DirectoryBreadcrumb.destination(item.path,root:base.path,current:current.path) == item.path,"Every visible ancestor can be selected")
        _ = try directoryEntries(path:item.path,project:base.path)
    }
    let first = items[1].path
    try verify(DirectoryBreadcrumb.items(root:base.path,current:first,rootTitle:"项目根目录").count == 2,"Jumping to an ancestor removes deeper path levels")
    try verify(DirectoryBreadcrumb.destination(base.deletingLastPathComponent().path,root:base.path,current:current.path) == nil,"Breadcrumbs cannot escape their project or linked-source root")
    try verify(DirectoryBreadcrumb.destination(base.path+"-other",root:base.path,current:current.path) == nil,"Sibling paths sharing a text prefix are outside the breadcrumb scope")
    try verify(DirectoryBreadcrumb.destination(base.appendingPathComponent("other").path,root:base.path,current:current.path) == nil,"Only the current ancestor chain can be navigated")
    try verify(DirectoryBreadcrumb.items(root:base.path,current:base.path+"-other",rootTitle:"项目根目录").isEmpty,"Out-of-root current paths cannot expose unrelated ancestors")
    try verify(DirectoryBreadcrumb.destination(current.appendingPathComponent("../../..").path,root:base.path,current:current.path) == base.path,"Dot components normalize to the correct in-root ancestor")
    let content = try String(contentsOf:file,encoding:.utf8)
    try verify(content == "unchanged","Building and reading breadcrumbs must not rename or modify files")
    print("PASS: breadcrumb root/deep ancestor destinations, repeated Chinese names, normalized paths, root/sibling/non-ancestor guards and unchanged files")
}
