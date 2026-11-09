import AppKit
import SwiftUI

@MainActor func filePasteTests(root:URL) throws {
    let base = root.appendingPathComponent("file-paste"), a = base.appendingPathComponent("A"), b = a.appendingPathComponent("B")
    let source = base.appendingPathComponent("来源/项目 中文 #1")
    try fm.createDirectory(at:source,withIntermediateDirectories:true)
    try fm.createDirectory(at:b,withIntermediateDirectories:true)
    let file = source.appendingPathComponent("旧日期合同.PDF")
    try Data("original bytes".utf8).write(to:file)
    try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:1000)],ofItemAtPath:file.path)
    let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
    try verify(copyFilePaths([source.path],to:board))
    let sourceIdentity = fileIdentity(source.path)
    let first = executeFilePaste(filePasteURLs(from:board),into:filePasteDestination(directory:a.path,selectedFolder:nil)!)
    let second = executeFilePaste(filePasteURLs(from:board),into:filePasteDestination(directory:a.path,selectedFolder:b.path)!)
    try verify(first.failure == nil && second.failure == nil && first.paths.first == a.appendingPathComponent(source.lastPathComponent).path && second.paths.first == b.appendingPathComponent(source.lastPathComponent).path,"Left A and selected middle B resolve to the correct destinations")
    let third = executeFilePaste([file],into:b.path), duplicate = executeFilePaste([file],into:b.path)
    try verify(third.failure == nil && duplicate.paths.first == b.appendingPathComponent("旧日期合同 (2).PDF").path,"Repeated paste numbers the filename and preserves its extension")
    let nested = try Data(contentsOf:URL(fileURLWithPath:second.paths[0]).appendingPathComponent(file.lastPathComponent))
    try verify(nested == Data("original bytes".utf8) && fileIdentity(source.path) == sourceIdentity && fm.fileExists(atPath:file.path),"Copy complete folder contents without moving or changing the source")
    let recursive = executeFilePaste([source],into:source.path)
    let inside = source.appendingPathComponent("内部");try fm.createDirectory(at:inside,withIntermediateDirectories:true)
    try verify(recursive.failure != nil && executeFilePaste([source],into:inside.path).failure != nil,"Reject folder copies into self or descendants")
    try verify(executeFilePaste([URL(fileURLWithPath:"/")],into:a.path).failure != nil,"A volume root cannot be recursively copied into its own descendant")
    let missing = base.appendingPathComponent("missing")
    let stale = executeFilePaste([file,missing],into:a.path), overlapping = executeFilePaste([source,file],into:a.path)
    try verify(stale.paths.isEmpty && stale.failure != nil,"Preflight rejects stale selections before copying anything")
    try verify(overlapping.paths.isEmpty && overlapping.failure != nil,"Preflight rejects overlapping selections before copying anything: \(overlapping)")
    let names = try fm.contentsOfDirectory(atPath:b.path)
    try verify(!names.contains(where:{$0.hasPrefix(".guiyu-copy-")}),"No staging directories remain after copying")
    board.clearContents();board.setString("只粘贴文字",forType:.string)
    let store = Store(stateURL:base.appendingPathComponent("settings.json"),loadOnLaunch:false)
    try verify(!store.canPasteFiles(into:a.path,from:board) && !store.canPasteFiles(into:nil,from:board),"Text clipboard and missing destinations cannot trigger file paste")
    let rows = try directoryEntries(path:b.path,project:b.path), pins = duplicate.paths+third.paths
    try verify(Array(pastedRowsFirst(rows,paths:pins).prefix(2).map(\.id)) == pins,"New copies stay at the top despite preserved old modification dates")
    for mode in ["按类别","按时间","源文档"] {
        let result = presentDirectoryWithPastes(rows,mode:mode,collapsed:[],categories:WorkspaceCategory.defaults,assignments:[:],paths:pins,scope:b.path)
        try verify(Array(result.filter{!$0.header}.prefix(2).map(\.id)) == pins && Set(result.filter{!$0.header}.map(\.id)).count == rows.count,"Copies lead all views without disappearing or duplicating: "+mode)
    }
    let closed = presentDirectoryWithPastes(rows,mode:"按类别",collapsed:["recent-paste:"+b.path],categories:WorkspaceCategory.defaults,assignments:[:],paths:pins,scope:b.path)
    try verify(closed.first?.expanded == false && !closed.contains(where:{pins.contains($0.id)}),"The recent-copy group can collapse without duplicating items elsewhere")
    print("PASS: A/B destinations, recursive copy, source preservation, collisions, preflight, staging cleanup, text clipboard and top ordering in all three views")
}

@MainActor func filePasteUIReview() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let root = URL(fileURLWithPath:canonicalPath(fm.temporaryDirectory.path)).appendingPathComponent("GuiyuPasteUI-"+UUID().uuidString)
    try fm.createDirectory(at:root,withIntermediateDirectories:true);defer { try? fm.removeItem(at:root) }
    let out = URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent(".impeccable/review/file-paste")
    try fm.createDirectory(at:out,withIntermediateDirectories:true)
    let board = NSPasteboard.withUniqueName();defer { board.releaseGlobally() }
    func wait(_ condition:() -> Bool) throws {
        let deadline = Date().addingTimeInterval(12)
        while !condition() && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.02)) }
        try verify(condition(),"Native paste fixture timed out")
    }
    func tables(_ view:NSView) -> [BrowserNSTable] { (view as? BrowserNSTable).map{[$0]} ?? view.subviews.flatMap{tables($0)} }
    func directoryRows(_ view:NSView) -> [DirectoryOrderRowView] { (view as? DirectoryOrderRowView).map{[$0]} ?? view.subviews.flatMap{directoryRows($0)} }
    func key(_ character:String = "v") -> NSEvent { NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:0,context:nil,characters:character,charactersIgnoringModifiers:character,isARepeat:false,keyCode:character == "v" ? 9 : 8)! }
    for scenario in ["left-A","middle-B","right-empty"] {
        let base = root.appendingPathComponent(scenario), projects = base.appendingPathComponent("项目"), a = projects.appendingPathComponent("A"), b = a.appendingPathComponent("B"), nested = b.appendingPathComponent("内部目录")
        let source = base.appendingPathComponent("来源/1月 复制项目")
        for path in [nested,source] { try fm.createDirectory(at:path,withIntermediateDirectories:true) }
        try Data("test".utf8).write(to:source.appendingPathComponent("完整内容.txt"))
        try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:1000)],ofItemAtPath:source.path)
        let store = Store(stateURL:base.appendingPathComponent("state.json"),loadOnLaunch:false)
        store.settings.root = projects.path;store.settings.categories = WorkspaceCategory.defaults
        store.settings.projects = try discoverProjectRoots([projects.path],saved:[]).projects
        store.metadataReady = true
        let isRight = scenario == "right-empty", selected = scenario == "left-A" ? nil : b.path
        let view = ProjectWorkspace(store:store,year:a.path,projectPath:selected,mode:"源文档",sourceFolder:isRight ? nested.path : b.path,sourceRows:isRight ? [] : try directoryEntries(path:b.path,project:b.path))
        let host = NSHostingView(rootView:view);host.frame = NSRect(x:0,y:0,width:1280,height:820)
        let window = NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:1280,height:820),styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView = host;window.orderBack(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        try wait { tables(host).contains { table in (table.delegate as? BrowserTable.Coordinator)?.parent.appearance == (isRight ? .files : .projects) } }
        guard let table = tables(host).first(where:{($0.delegate as? BrowserTable.Coordinator)?.parent.appearance == (isRight ? .files : .projects)}),let coordinator = table.delegate as? BrowserTable.Coordinator else { throw namingError("缺少目标列表") }
        if scenario == "middle-B" {
            try wait { coordinator.rows.contains(where:{$0.id == b.path}) }
            table.selectRowIndexes(IndexSet(integer:coordinator.rows.firstIndex(where:{$0.id == b.path})!),byExtendingSelection:false)
        } else if scenario == "left-A" { table.deselectAll(nil) }
        let expected = isRight ? nested.path : scenario == "middle-B" ? b.path : a.path
        try verify(coordinator.resolvedPasteDestination == expected,"Production destination for "+scenario)
        try verify(copyFilePaths([source.path],to:board));table.copyPasteboard = board;window.makeFirstResponder(table)
        let menu = NSMenu();coordinator.updateContextMenu(menu,at:-1)
        try verify(menu.items.contains(where:{$0.title == "粘贴" && $0.isEnabled}),"Blank-space context menu supports paste, including empty directories")
        if isRight {
            let point = table.convert(NSPoint(x:20,y:table.bounds.maxY-10),to:nil)
            let event = NSEvent.mouseEvent(with:.rightMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
            try verify(table.menu(for:event) != nil && window.firstResponder === table && table.contextClickRow == -1,"Right-clicking native blank space focuses the right pane and exposes its paste menu")
        }
        if scenario == "middle-B" { coordinator.pasteClicked() }
        else if scenario == "left-A" {
            guard let sidebar = directoryRows(host).first(where:{$0.payload?.path == a.path}) else { throw namingError("缺少左侧目录") }
            sidebar.copyPasteboard = board; window.makeFirstResponder(sidebar)
            try verify(sidebar.performKeyEquivalent(with:key()),"Command-V on selected left A pastes inside A")
        } else { try verify(table.performKeyEquivalent(with:key()),"Command-V dispatches to the focused destination table") }
        try verify(store.isPastingFiles,"Copy starts asynchronously")
        try wait { store.lastFilePaste != nil && !store.busy && !store.isPastingFiles }
        guard let result = store.lastFilePaste else { throw namingError("复制结果缺失") }
        try verify(result.failure == nil && result.destination == expected && result.paths.count == 1,"Production paste copies to "+expected)
        let pasted = result.paths[0]
        try wait {
            tables(host).contains { table in
                guard let c = table.delegate as? BrowserTable.Coordinator else { return false }
                return c.rows.first(where:{!$0.header})?.id == pasted && c.selectedRows.map(\.id) == [pasted]
            }
        }
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) {
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(scenario+".png"))
        }
        try verify(fm.fileExists(atPath:source.appendingPathComponent("完整内容.txt").path),"Source folder remains intact")
        if scenario == "middle-B", let index = coordinator.rows.firstIndex(where:{$0.id == b.path}) {
            coordinator.updateContextMenu(menu,at:index)
            try verify(menu.items.contains(where:{$0.title == "复制"}),"Row context menu exposes Copy")
            coordinator.copyClicked()
            try verify(filePasteURLs(from:board).map(\.path) == [b.path],"Context-menu Copy publishes the clicked project as native file URLs")
        }
        if let focused = tables(host).first {
            let editor = NSTextView(frame:NSRect(x:0,y:0,width:100,height:30));host.addSubview(editor);window.makeFirstResponder(editor)
            let before = store.lastFilePaste?.id
            try verify(!focused.performFileShortcut(key()),"Text editing retains Command-V")
            focused.paste(nil);try verify(store.lastFilePaste?.id == before,"Responder paste cannot copy files behind a text editor")
            editor.removeFromSuperview()
        }
        print("PASS: production "+scenario+", context menu / Command-V, recursive copy, top placement and selection")
    }
}
