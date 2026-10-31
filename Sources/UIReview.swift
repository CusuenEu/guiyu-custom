import SwiftUI
import AppKit

// Explicit, isolated UI verification. Never opens or renames the user's project files.
@MainActor func batchUIReview() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let root = fm.temporaryDirectory.appendingPathComponent("GuiyuUI-"+UUID().uuidString)
    defer { try? fm.removeItem(at:root) }
    let dir = root.appendingPathComponent("2026/10月 示例园区项目")
    try fm.createDirectory(at:dir,withIntermediateDirectories:true)
    for (name,text) in [("响应文件.txt","响应文件\n项目名称：示例园区网络建设项目"),("建设方案.txt","示例园区网络建设方案"),("采购文件.txt","招标文件\n项目名称：示例园区网络建设项目")] {
        try text.write(to:dir.appendingPathComponent(name),atomically:true,encoding:.utf8)
    }
    let store = Store(stateURL:root.appendingPathComponent("state.json"),loadOnLaunch:false)
    store.settings.categories = WorkspaceCategory.defaults // Existing configured-user fixture.
    store.settings.root = root.path; store.settings.projects = [Project(path:dir.deletingLastPathComponent().path,name:"2026",group:"2026",shallow:true),Project(path:dir.path,name:dir.lastPathComponent,group:"2026")]
    for name in ["9月 企业数字化转型诊断","8月 园区网络建设项目"] {
        let path = dir.deletingLastPathComponent().appendingPathComponent(name)
        try fm.createDirectory(at:path,withIntermediateDirectories:true)
        store.settings.projects.append(Project(path:path.path,name:name,group:"2026"))
    }
    let cdRoot = root.appendingPathComponent("CD类项目"), cdProject = cdRoot.appendingPathComponent("示例合同服务项目")
    try fm.createDirectory(at:cdProject,withIntermediateDirectories:true)
    try "合同示例文档".write(to:cdProject.appendingPathComponent("合同.txt"),atomically:true,encoding:.utf8)
    try "散放说明".write(to:cdRoot.appendingPathComponent("项目说明.txt"),atomically:true,encoding:.utf8)
    store.settings.projects += [Project(path:cdRoot.path,name:"CD类项目",group:"CD类项目",shallow:true),Project(path:cdProject.path,name:cdProject.lastPathComponent,group:"CD类项目")]
    store.files = store.settings.projects.flatMap { metadataFiles($0.path,project:$0.path,recursive:$0.shallow != true,cache:[:]) }; store.metadataReady = true
    let rows = try directoryEntries(path:dir.path,project:dir.path)
    let selected = rows.filter { $0.title != "采购文件.txt" }
    let out = URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent(".impeccable/review")
    try fm.createDirectory(at:out,withIntermediateDirectories:true)
    func capture<V:View>(_ view: V, size: NSSize, name: String, afterAppear: (() -> Void)? = nil) throws {
        let host = NSHostingView(rootView:view.background(Color(nsColor:.controlBackgroundColor)).preferredColorScheme(.light)); host.frame = NSRect(origin:.zero,size:size)
        let window = NSWindow(contentRect:NSRect(origin:NSPoint(x:-5000,y:-5000),size:size),styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView = host; window.orderBack(nil)
        if let afterAppear { DispatchQueue.main.asyncAfter(deadline:.now()+0.1,execute:afterAppear) }
        RunLoop.current.run(until:Date().addingTimeInterval(0.7))
        host.layoutSubtreeIfNeeded()
        if name.hasPrefix("category-") {
            print("CATEGORY CAPTURE GEOMETRY: \(name), frame=\(host.frame), bounds=\(host.bounds), fitting=\(host.fittingSize), window=\(window.frame)")
            host.setBoundsOrigin(.zero)
        }
        func saveRaster() throws {
            guard let rep = host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw namingError("截图缓冲区不可用") }
            host.cacheDisplay(in:host.bounds,to:rep)
            guard let data = rep.representation(using:.png,properties:[:]) else { throw namingError("截图编码失败") }
            try data.write(to:out.appendingPathComponent(name))
        }
        if name.hasPrefix("project-row-alignment-") {
            try saveRaster()
            func findTable(_ view:NSView) -> NSTableView? {
                (view as? NSTableView) ?? view.subviews.lazy.compactMap { findTable($0) }.first
            }
            guard let table = findTable(host) else { throw namingError("项目行测试缺少原生列表") }
            func checkCells() throws {
                for row in 0..<table.numberOfRows {
                    guard let cell = table.view(atColumn:0,row:row,makeIfNecessary:true) as? BrowserCell else { throw namingError("项目行测试缺少单元格") }
                    cell.layoutSubtreeIfNeeded()
                    let textRect = cell.title.alignmentRect(forFrame:cell.title.frame)
                    let iconRect = cell.icon.alignmentRect(forFrame:cell.icon.frame)
                    print("ROW GEOMETRY: \(name) row \(row), cell \(cell.bounds), title \(cell.title.frame), icon \(cell.icon.frame), date \(cell.date.frame)")
                    try verify(abs(textRect.midY-iconRect.midY) < 0.5,"Project title block and folder must share a vertical center: \(textRect) / \(iconRect)")
                    try verify(cell.title.frame.minY >= 0 && cell.title.frame.maxY <= cell.bounds.height,"Project title must stay inside its row")
                    // NSTextField optical insets differ from its Auto Layout alignment rectangle.
                    try verify(cell.title.frame.maxX <= cell.date.frame.minX,"Project title must not overlap date metadata")
                }
            }
            // NSTableView row rectangles include the existing 1pt intercell spacing.
            try verify(table.rect(ofRow:0).height == 45,"Short project name should use a compact single-line row: height=\(table.rect(ofRow:0).height), width=\(table.tableColumns[0].width)")
            let narrow = name.contains("narrow")
            try verify(table.rect(ofRow:1).height == (narrow ? 61 : 45),"Native wrapping must determine project row height")
            try verify(table.rect(ofRow:2).height == 61,"Very long project name must be capped at two lines")
            try checkCells()
            if narrow {
                table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
                let column = table.tableColumns[0], oldWidth = column.width
                column.width = 760; table.needsLayout = true; table.layoutSubtreeIfNeeded()
                try verify(table.rect(ofRow:1).height == 45,"Widening a live project column must remove unnecessary second-line space")
                column.width = oldWidth; table.needsLayout = true; table.layoutSubtreeIfNeeded()
                try verify(table.rect(ofRow:1).height == 61 && table.selectedRow == 1,"Narrowing must restore wrapping without losing selection")
                try checkCells()
            }
            print("PASS: native project title centering, content-based heights, clipping and resizing: \(name)")
        }
        if name == "resizable-workspace-fixture.png" {
            func findSplit(_ view: NSView) -> NSSplitView? {
                if let split = view as? NSSplitView, split.isVertical && split.arrangedSubviews.count == 3 { return split }
                return view.subviews.lazy.compactMap { findSplit($0) }.first
            }
            guard let split = findSplit(host) else { throw namingError("未找到原生三栏分隔视图") }
            let before = split.arrangedSubviews[1].frame.width
            let position = split.arrangedSubviews[1].frame.maxX - 45
            split.setPosition(position,ofDividerAt:1); host.layoutSubtreeIfNeeded()
            try verify(abs(split.arrangedSubviews[1].frame.width-before) > 20,"Native divider must actually change the column width")
            print("PASS: native three-column divider resizes center width from \(before) to \(split.arrangedSubviews[1].frame.width)")
        }
        if name == "settings-categories-many.png" {
            func scrolls(_ view:NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrolls($0) }
            }
            let lists = scrolls(host)
            try verify(lists.count == 1,"Category settings must have one list scroller, without an outer nested scroller")
            guard let list = lists.first, let document = list.documentView else { throw namingError("分类列表未显示") }
            try verify(list.contentSize.height >= 120,"Category list must use the expanded remaining height: \(list.contentSize.height)")
            try verify(document.bounds.height > list.contentSize.height,"Additional categories must remain reachable by scrolling")
            print("PASS: fixed top category editor/search, one list scroller, viewport \(list.contentSize.height)pt with 16 categories")
        }
        if name == "search-multi-term.png" || name == "search-no-results.png" || name == "search-projects-first.png" || name == "search-third-level-no-selection.png" {
            func tables(_ view:NSView) -> [NSTableView] {
                (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap { tables($0) }
            }
            let counts = tables(host).map(\.numberOfRows).sorted()
            let expected = name == "search-no-results.png" ? [] : [1,6]
            try verify(counts == expected,"Native indexed search must render the expected project and third-level rows: \(name) \(counts)")
            print("PASS: native indexed search \(name), table row counts \(counts)")
        }
        if !name.hasPrefix("project-row-alignment-") { try saveRaster() }
        window.orderOut(nil)
    }
    let alignmentRows = [
        BrowserRow(id:"short",title:"9月 企业数字化转型诊断",folder:true),
        BrowserRow(id:"wrap",title:"8月 贵州电网有限责任公司服务类2026年第二批信息终端运维服务",folder:true),
        BrowserRow(id:"long",title:String(repeating:"项目网络信息安全运维服务与配套建设方案",count:5),folder:true),
        BrowserRow(id:"dated",title:"采购需求与技术规范.docx",date:Date(),folder:false)
    ]
    for (label,width) in [("narrow",400.0),("wide",760.0)] {
        try capture(BrowserTable(rows:alignmentRows,selection:.constant(nil),appearance:.projects,activate:{_ in},rename:{_ in}),size:NSSize(width:width,height:270),name:"project-row-alignment-\(label).png")
    }
    // The approved layout is exercised with long names, all categories and real temporary entries.
    let forestDir = root.appendingPathComponent("2026/10月 民政厅机关网络运维及网络安全运维项目")
    try fm.createDirectory(at:forestDir,withIntermediateDirectories:true)
    let names = ["民政厅网络运维服务方案.docx","网络安全保障方案.pdf","民政厅机关网络运维采购文件.pdf","采购需求与技术规范.docx","投标文件-民政厅网络运维项目.docx","分项报价表.xlsx"]
    for name in names { try Data().write(to:forestDir.appendingPathComponent(name)) }
    let nested = forestDir.appendingPathComponent("参考资料")
    try fm.createDirectory(at:nested,withIntermediateDirectories:true)
    try Data().write(to:nested.appendingPathComponent("内部资料.txt"))
    store.settings.projects.append(Project(path:forestDir.path,name:forestDir.lastPathComponent,group:"2026"))
    store.files += metadataFiles(forestDir.path,project:forestDir.path,recursive:true,cache:[:])
    let forestRows = try directoryEntries(path:forestDir.path,project:forestDir.path)
    let chosen = forestRows.first { $0.title == "民政厅机关网络运维采购文件.pdf" }!.id
    let workspace = ProjectWorkspace(store:store,year:"2026",projectPath:forestDir.path,filePath:chosen,sourceFolder:forestDir.path,sourceRows:forestRows,fileSelections:[chosen])
    let earlyStore = Store(stateURL:root.appendingPathComponent("early-state/settings.json"),loadOnLaunch:false)
    earlyStore.settings.categories = WorkspaceCategory.defaults // Existing configured-user fixture.
    earlyStore.settings.root = root.path
    earlyStore.settings.projects = [Project(path:forestDir.deletingLastPathComponent().path,name:"2026",group:"2026",shallow:true)]
    try capture(ProjectWorkspace(store:earlyStore,year:"2026",query:"民政 运维"),size:NSSize(width:1280,height:820),name:"search-projects-first.png",afterAppear:{
        earlyStore.settings.projects.append(Project(path:forestDir.path,name:forestDir.lastPathComponent,group:"2026"))
    })
    try capture(workspace,size:NSSize(width:1440,height:900),name:"forest-desktop.png")
    try capture(ProjectWorkspace(store:store,year:"2026",projectPath:forestDir.path,query:"民政 运维",sourceFolder:forestDir.path,sourceRows:forestRows),size:NSSize(width:1280,height:820),name:"search-multi-term.png")
    try capture(ProjectWorkspace(store:store,year:"2026",query:"民政 运维"),size:NSSize(width:1280,height:820),name:"search-third-level-no-selection.png")
    try capture(ProjectWorkspace(store:store,year:"2026",projectPath:forestDir.path,query:"不存在的搜索结果XYZ",sourceFolder:forestDir.path,sourceRows:forestRows),size:NSSize(width:1280,height:820),name:"search-no-results.png")
    try capture(workspace,size:NSSize(width:1060,height:700),name:"forest-minimum.png")
    try capture(workspace,size:NSSize(width:1728,height:983),name:"forest-wide.png")
    try capture(ProjectWorkspace(store:store,year:"2026",projectPath:forestDir.path,mode:"按时间",sourceFolder:forestDir.path,sourceRows:forestRows),size:NSSize(width:1280,height:820),name:"forest-time.png")
    try capture(ProjectWorkspace(store:store,year:"2026",projectPath:forestDir.path,mode:"源文档",sourceFolder:forestDir.path,sourceRows:forestRows),size:NSSize(width:1280,height:820),name:"forest-source.png")
    try capture(ProjectWorkspace(store:store,year:"2026",projectPath:forestDir.path,sourceFolder:nested.path,sourceRows:try directoryEntries(path:nested.path,project:forestDir.path)),size:NSSize(width:1280,height:820),name:"forest-nested.png")
    let breadcrumbFolder = nested.appendingPathComponent("招标文件下载2026-07-23-165700/5_附件B-技术规范书/附件B-技术规范书")
    try fm.createDirectory(at:breadcrumbFolder,withIntermediateDirectories:true)
    try Data().write(to:breadcrumbFolder.appendingPathComponent("技术规范.pdf"))
    let breadcrumbRows = try directoryEntries(path:breadcrumbFolder.path,project:forestDir.path)
    try capture(ProjectWorkspace(store:store,year:"2026",projectPath:forestDir.path,sourceFolder:breadcrumbFolder.path,sourceRows:breadcrumbRows),size:NSSize(width:1060,height:700),name:"breadcrumb-workspace-narrow.png")
    try capture(DirectoryBreadcrumbBar(root:forestDir.path,current:breadcrumbFolder.path,rootTitle:"项目根目录",navigate:{_ in}).padding(12),size:NSSize(width:760,height:60),name:"breadcrumb-wide.png")
    try capture(DirectoryBreadcrumbBar(root:forestDir.path,current:breadcrumbFolder.path,rootTitle:"项目根目录",navigate:{_ in}).padding(12),size:NSSize(width:320,height:60),name:"breadcrumb-narrow.png")
    try capture(ProjectWorkspace(store:store,year:"2026",projectPath:dir.path,sourceFolder:dir.path,sourceRows:rows),size:NSSize(width:1440,height:900),name:"soft-workspace-final.png")
    try capture(ProjectWorkspace(store:store,year:"CD类项目"),size:NSSize(width:1280,height:820),name:"real-directory-sidebar-fixture.png")
    try capture(ProjectWorkspace(store:store,year:"2026"),size:NSSize(width:1280,height:820),name:"year-only-fixture.png")
    try capture(ProjectWorkspace(store:store,year:"2026",projectPath:dir.path,sourceFolder:dir.path,sourceRows:rows,fileSelections:Set(selected.map(\.id))),size:NSSize(width:1280,height:820),name:"batch-workspace-fixture.png")
    try capture(ProjectWorkspace(store:store,year:"2026",projectPath:dir.path,sourceFolder:dir.path,sourceRows:rows),size:NSSize(width:1280,height:820),name:"resizable-workspace-fixture.png")
    try capture(BatchRenameDialog(store:store,request:BatchNamingRequest(rows:selected,projectPath:dir.path,recommended:false)),size:NSSize(width:760,height:560),name:"batch-rename-fixture.png")
    try capture(BatchRenameDialog(store:store,request:BatchNamingRequest(rows:selected,projectPath:dir.path,recommended:true)),size:NSSize(width:760,height:560),name:"batch-recommend-fixture.png")
    let inbox = root.appendingPathComponent("示例待归档"); try fm.createDirectory(at:inbox,withIntermediateDirectories:true)
    try "招标文件\n项目名称：示例园区网络建设项目".write(to:inbox.appendingPathComponent("RFP需求文件.txt"),atomically:true,encoding:.utf8)
    let linked = ArchiveSource(id:"downloads",name:"下载",kind:"folder",path:inbox.path)
    store.settings.archiveSources = [linked,ArchiveSource.defaults[1]]
    try capture(ProjectWorkspace(store:store,year:"2026",archiveSourceID:linked.id),size:NSSize(width:1280,height:820),name:"archive-sources-fixture.png")
    let archiveRequest = QuickArchiveRequest(rows:[browserEntry(inbox.appendingPathComponent("RFP需求文件.txt").path)!])
    try capture(QuickArchiveDialog(store:store,request:archiveRequest),size:NSSize(width:720,height:620),name:"quick-archive-fixture.png")
    try capture(WorkspaceSettingsView(store:store,updater:AppUpdater.fixture(),close:{},openPending:{}),size:NSSize(width:820,height:620),name:"archive-source-settings-fixture.png")
    try capture(WorkspaceSettingsView(store:store,updater:AppUpdater.fixture(version:"9.9.9"),close:{},openPending:{},section:.categories),size:NSSize(width:820,height:620),name:"settings-categories-final.png")
    let manyCategories = Store(stateURL:root.appendingPathComponent("many-categories/settings.json"),loadOnLaunch:false)
    manyCategories.settings.categories = WorkspaceCategory.defaults + (1...12).map { WorkspaceCategory(id:"custom-\($0)",name:"自定义分类 \($0)") }
    try capture(WorkspaceSettingsView(store:manyCategories,updater:AppUpdater.fixture(),close:{},openPending:{},section:.categories),size:NSSize(width:820,height:620),name:"settings-categories-many.png")
    let automaticCategories = Store(stateURL:root.appendingPathComponent("automatic-categories/settings.json"),loadOnLaunch:false)
    _ = automaticCategories.saveCategory(id:nil,name:"财务票据")
    _ = automaticCategories.saveCategory(id:nil,name:"售中材料")
    try capture(WorkspaceSettingsView(store:automaticCategories,updater:AppUpdater.fixture(),close:{},openPending:{},section:.categories),size:NSSize(width:820,height:620),name:"settings-category-rules.png")
    if let category = automaticCategories.workspaceCategories.first(where:{$0.name == "财务票据"}) {
        try capture(CategoryRuleEditor(store:automaticCategories,category:category),size:NSSize(width:660,height:570),name:"category-rule-editor.png")
    }
    let exchangeStore = Store(stateURL:root.appendingPathComponent("exchange-ui/settings.json"),loadOnLaunch:false)
    exchangeStore.settings.categories = [WorkspaceCategory(id:"engineering",name:"工程管理"),WorkspaceCategory(id:"contracts",name:"合同管理"),WorkspaceCategory(id:"其他",name:"其他")]
    let exchangeReply = categoryExchangeFixture(exchangeStore.workspaceCategories)
    try capture(CategoryRuleAssistant(store:exchangeStore),size:NSSize(width:740,height:650),name:"category-prompt.png")
    try capture(CategoryRuleAssistant(store:exchangeStore,importing:true,response:exchangeReply),size:NSSize(width:740,height:650),name:"category-reply.png")
    try capture(CategoryRuleAssistant(store:exchangeStore,importing:true,response:exchangeReply,reviewing:true),size:NSSize(width:740,height:650),name:"category-import-preview.png")
    try capture(CategoryRuleAssistant(store:exchangeStore,importing:true,response:exchangeReply.replacingOccurrences(of:"分类：工程管理",with:"分类：未知分类"),reviewing:true),size:NSSize(width:740,height:650),name:"category-import-error.png")
    try capture(WorkspaceSettingsView(store:store,close:{},openPending:{},section:.history),size:NSSize(width:820,height:620),name:"settings-history-final.png")
    var recentFinished = false; var recentMessage = ""; var recentCount = 0
    let recent = RecentFilesQuery()
    recent.start { values,message in recentCount = values.count; recentMessage = message ?? ""; recentFinished = true }
    let until = Date().addingTimeInterval(14)
    while !recentFinished && Date() < until { RunLoop.current.run(until:Date().addingTimeInterval(0.05)) }
    recent.stop()
    print("RECENTS: queryCompleted=\(recentFinished), localAccessibleCount=\(recentCount), message=\(recentMessage)")
    print("PASS: isolated native workspace and batch-name screenshots; user settings/files untouched")
}
