import SwiftUI
import AppKit

@MainActor func automaticCategoryUIReview() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let root = URL(fileURLWithPath:canonicalPath(fm.temporaryDirectory.path)).appendingPathComponent("GuiyuAutoCategories-"+UUID().uuidString)
    defer { try? fm.removeItem(at:root) }
    let projects = root.appendingPathComponent("项目"), a = projects.appendingPathComponent("A")
    let b = a.appendingPathComponent("B"), c = a.appendingPathComponent("C"), child = b.appendingPathComponent("子目录")
    for path in [b,c,child] { try fm.createDirectory(at:path,withIntermediateDirectories:true) }
    let fixtures = [b.appendingPathComponent("采购合同.docx"),b.appendingPathComponent("客户合同.pdf"),b.appendingPathComponent("截图.png"),b.appendingPathComponent("说明.txt"),c.appendingPathComponent("乙合同.pdf"),child.appendingPathComponent("子目录合同.txt")]
    for file in fixtures { try Data("fixture; never parse this body".utf8).write(to:file) }
    let identities = fixtures.map { fileIdentity($0.path) }
    let store = Store(stateURL:root.appendingPathComponent("state.json"),loadOnLaunch:false)
    store.settings.root = projects.path
    store.settings.categories = [WorkspaceCategory(id:"其他",name:"其他")]
    store.settings.projects = try discoverProjectRoots([projects.path],saved:[]).projects
    store.files = store.settings.projects.flatMap { metadataFiles($0.path,project:$0.path,recursive:$0.shallow != true,cache:[:]) }
    store.metadataReady = true
    let manual = try directoryEntries(path:b.path,project:b.path).first(where:{$0.title == "客户合同.pdf"})!
    try verify(store.assignCategory(manual,to:"其他"),"Manual classification fixture")
    let out = URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent(".impeccable/review/automatic-categories")
    try fm.createDirectory(at:out,withIntermediateDirectories:true)
    func tables(_ view:NSView) -> [BrowserNSTable] { (view as? BrowserNSTable).map{[$0]} ?? view.subviews.flatMap{tables($0)} }
    func coordinator(_ host:NSView, _ kind:BrowserTableAppearance) -> BrowserTable.Coordinator? {
        tables(host).compactMap { $0.delegate as? BrowserTable.Coordinator }.first { $0.parent.appearance == kind }
    }
    func wait(_ label:String,_ condition:() -> Bool) throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.02)) }
        try verify(condition(),label)
    }
    func capture(_ host:NSView,_ name:String) throws {
        RunLoop.current.run(until:Date().addingTimeInterval(0.5))
        host.setBoundsOrigin(.zero)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw namingError("分类截图不可用") }
        host.cacheDisplay(in:host.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(name))
    }
    func mount(_ mode:String) -> (NSWindow,NSHostingView<ProjectWorkspace>) {
        let view = ProjectWorkspace(store:store,year:a.path,projectPath:b.path,mode:mode,sourceFolder:b.path,sourceRows:(try? directoryEntries(path:b.path,project:b.path)) ?? [])
        let host = NSHostingView(rootView:view);host.frame = NSRect(x:0,y:0,width:1280,height:820)
        let window = NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:1280,height:820),styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView = host;window.orderBack(nil)
        return (window,host)
    }
    let (window,host) = mount("源文档")
    defer { window.orderOut(nil); window.contentView = nil }
    try wait("Initial hierarchy view is available") { coordinator(host,.files)?.rows.filter{!$0.header}.count == 5 && coordinator(host,.files)?.rows.filter{$0.header}.isEmpty == true }
    // Previously copied rows must join the new category instead of staying in
    // the temporary recent-copy group when settings trigger reclassification.
    store.pastedPathsByDirectory[b.path] = [fixtures[0].path]
    try verify(store.saveCategory(id:nil,name:"合同"),"Add a category through the production save path")
    let contracts = store.workspaceCategories.first(where:{$0.name == "合同"})!
    try wait("Adding a category immediately switches the open folder to category grouping") {
        coordinator(host,.files)?.rows.contains(where:{$0.header && $0.categoryID == contracts.id}) == true
    }
    var rows = coordinator(host,.files)!.rows
    try verify(rows.first(where:{$0.id == fixtures[0].path})?.categoryID == contracts.id && !rows.contains(where:{$0.id.hasPrefix("recent-paste:")}),"Copied files rejoin their actual category")
    try verify(rows.first(where:{$0.id == manual.id})?.categoryID == "其他","Automatic grouping preserves explicit manual assignments")
    try capture(host,"added-contract-category.png")
    try verify(store.saveCategory(id:nil,name:"图片"),"Add a format category")
    let pictures = store.workspaceCategories.first(where:{$0.name == "图片"})!
    try wait("New extension rules immediately reclassify the current directory") { coordinator(host,.files)?.rows.first(where:{$0.title == "截图.png"})?.categoryID == pictures.id }
    try capture(host,"added-picture-category.png")
    var rule = contracts.effectiveRule;rule.keywords = ["说明"];rule.origin = .edited
    try verify(store.saveCategoryRule(id:contracts.id,rule:rule),"Update a saved rule")
    try wait("Rule edits reclassify the existing rows without refresh or re-entering") { coordinator(host,.files)?.rows.first(where:{$0.title == "说明.txt"})?.categoryID == contracts.id }
    try verify(store.saveCategoryRule(id:contracts.id,rule:contracts.effectiveRule),"Restore the contract rule")
    window.orderOut(nil);window.contentView = nil

    for (name,navigate) in [("middle-project",true),("right-subfolder",false)] {
        let (next,content) = mount("按时间")
        defer { next.orderOut(nil);next.contentView = nil }
        try wait("Explicit time mode remains usable before navigation") { coordinator(content,.files)?.rows.contains(where:{$0.id.hasPrefix("date:")}) == true }
        let destination:URL
        if navigate {
            try wait("Middle project rows are ready") { coordinator(content,.projects)?.rows.contains(where:{$0.id == c.path}) == true }
            let middle = coordinator(content,.projects)!, table = middle.table!
            table.selectRowIndexes(IndexSet(integer:middle.rows.firstIndex(where:{$0.id == c.path})!),byExtendingSelection:false)
            destination = c
        } else {
            let right = coordinator(content,.files)!, row = right.rows.first(where:{$0.id == child.path})!
            right.parent.activate(row);destination = child
        }
        try wait("Entering another folder defaults to automatic categories: "+name) {
            guard let right = coordinator(content,.files) else { return false }
            return right.rows.contains(where:{$0.header && $0.categoryID == contracts.id}) && right.rows.filter{!$0.header}.allSatisfy{URL(fileURLWithPath:$0.id).deletingLastPathComponent().path == destination.path}
        }
        rows = coordinator(content,.files)!.rows
        try verify(rows.filter{!$0.header}.count == 1,"Only the entered directory's immediate entries are classified")
        try capture(content,name+"-auto-categories.png")
        next.orderOut(nil);next.contentView = nil
    }
    let fresh = Store(stateURL:root.appendingPathComponent("fresh.json"),loadOnLaunch:false)
    fresh.settings.root = projects.path;fresh.settings.projects = store.settings.projects;fresh.metadataReady = true
    let freshView = ProjectWorkspace(store:fresh,year:a.path,projectPath:b.path,mode:"源文档",sourceFolder:b.path,sourceRows:try directoryEntries(path:b.path,project:b.path))
    let freshHost = NSHostingView(rootView:freshView);freshHost.frame = NSRect(x:0,y:0,width:1280,height:820)
    let freshWindow = NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:1280,height:820),styleMask:.borderless,backing:.buffered,defer:false)
    freshWindow.contentView = freshHost;freshWindow.orderBack(nil)
    defer { freshWindow.orderOut(nil);freshWindow.contentView = nil }
    RunLoop.current.run(until:Date().addingTimeInterval(0.15))
    try verify(coordinator(freshHost,.files) == nil,"No categories still displays the setup action")
    try verify(fresh.saveCategory(id:nil,name:"合同"),"Add the first category")
    try wait("The first category replaces setup with grouped current-directory files") {
        guard let right = coordinator(freshHost,.files) else { return false }
        return Set(right.rows.filter{$0.header}.map(\.title)) == Set(["合同","其他"]) && right.rows.filter{!$0.header}.count == 5
    }
    try verify(fresh.workspaceCategories.count == 1,"Unmatched display grouping does not add a category to user settings")
    try capture(freshHost,"first-category-live-grouping.png")
    for (index,file) in fixtures.enumerated() {
        let data = try Data(contentsOf:file)
        try verify(fileIdentity(file.path) == identities[index] && data == Data("fixture; never parse this body".utf8),"Classification must leave source identities and bytes unchanged")
    }
    try verify(store.files.allSatisfy{$0.text.isEmpty},"Category setup and navigation do not parse document bodies")
    print("PASS: live new category/rule regrouping, copied-item classification, preserved manual choices, middle/right navigation defaults, immediate-child boundaries and unchanged files")
}
