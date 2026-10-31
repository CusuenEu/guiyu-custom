import SwiftUI
import AppKit

@MainActor func namingRulesTest(root:URL) throws {
    let dir = root.appendingPathComponent("naming-rules")
    try fm.createDirectory(at:dir,withIntermediateDirectories:true)
    let store = Store(stateURL:dir.appendingPathComponent("state/settings.json"),loadOnLaunch:false)
    let folder = dir.appendingPathComponent("6月 原文件夹")
    try fm.createDirectory(at:folder,withIntermediateDirectories:true)
    let file = dir.appendingPathComponent("合同资料.DOCX")
    try "source unchanged".write(to:file,atomically:true,encoding:.utf8)
    store.settings.categories = [WorkspaceCategory(id:"contracts",name:"合同管理"),WorkspaceCategory(id:"其他",name:"其他")]
    let folderTarget = NamingTarget(path:folder.path,folder:true,projectPath:dir.path)
    let fileTarget = NamingTarget(path:file.path,folder:false,projectPath:dir.path)
    try verify(store.assignCategory(browserEntry(folder.path)!,to:"contracts"))
    let now = namingCalendar().date(from:DateComponents(year:2026,month:10,day:1,hour:9))!
    for format in SmartNamingFormat.allCases {
        var rules = NamingRuleSettings();rules.folder = format;rules.document = format
        try verify(store.saveNamingRuleSettings(rules))
        let prefix = format == .month ? "10月" : format == .monthDay ? "1001" : "合同管理"
        let expectedFolder = prefix+" 智慧园区建设项目"
        let expectedFile = expectedFolder+".DOCX"
        try verify(store.smartProposedName(base:"智慧园区建设项目",target:folderTarget,now:now) == expectedFolder,"Each folder format uses the selected rule")
        try verify(store.smartProposedName(base:"解决方案-智慧园区建设项目",target:fileTarget,now:now) == expectedFile,"Each document format strips the recognized type prefix and preserves extension case")
        try verify(store.smartProposedName(base:expectedFile,target:fileTarget,now:now) == expectedFile,"Formatting an already formatted candidate is idempotent")
        try verify(store.validateSmartFolderPrefix(expectedFolder,target:folderTarget),"Configured folder prefix passes the execution guard")
    }
    var rules = NamingRuleSettings();rules.folder = .monthDay;rules.document = .category
    try verify(store.saveNamingRuleSettings(rules))
    let reopened = Store(stateURL:store.stateURL,loadOnLaunch:false)
    try verify(reopened.namingRuleSettings == rules,"Independent settings survive restart")
    try verify(!store.validateSmartFolderPrefix("0231 项目",target:folderTarget),"Invalid MMDD calendar dates cannot reach rename")
    try verify(store.validateSmartFolderPrefix("0229 项目",target:folderTarget),"A leap-day MMDD prefix is valid without a year")
    try verify(store.smartProposedName(base:"1001创新项目",target:fileTarget,now:now).contains("1001创新项目"),"Numbers inside the recognized title are not removed")
    let midnight = ISO8601DateFormatter().date(from:"2026-09-30T16:01:00Z")!
    rules.document = .monthDay;try verify(store.saveNamingRuleSettings(rules))
    try verify(store.smartProposedName(base:"项目名称",target:fileTarget,now:midnight) == "1001 项目名称.DOCX","Date prefixes use Beijing calendar day")
    rules.dateSource = .created;rules.folder = .month
    try verify(store.saveNamingRuleSettings(rules))
    try verify(store.smartProposedName(base:"项目名称",target:folderTarget,now:now).hasPrefix("6月 "),"Created-date mode retains an existing folder month")
    let current = store.namingRuleSettings
    let blocked = dir.appendingPathComponent("blocked");try Data().write(to:blocked)
    let broken = Store(stateURL:blocked.appendingPathComponent("settings.json"),loadOnLaunch:false)
    let before = broken.namingRuleSettings
    try verify(!broken.saveNamingRuleSettings(rules) && broken.namingRuleSettings == before,"Failed settings writes do not publish unsaved choices")
    try verify(fm.fileExists(atPath:folder.path) && fm.fileExists(atPath:file.path),"Saving/previewing naming settings never renames files")
    let content = try String(contentsOf:file,encoding:.utf8);try verify(content == "source unchanged")
    // Exercise real folder renames in both new formats, including batch preflight.
    rules.folder = .monthDay;rules.document = .month;rules.dateSource = .today
    try verify(store.saveNamingRuleSettings(rules))
    let edit = BatchNameEdit(target:folderTarget,name:store.smartProposedName(base:"项目名称",target:folderTarget,now:now))
    let result = store.confirmBatchRenames([edit],requireMonth:true)
    try verify(result.failed == nil && fm.fileExists(atPath:dir.appendingPathComponent("1001 项目名称").path),"Smart batch accepts the configured MMDD folder format")
    let updatedFolder = dir.appendingPathComponent("1001 项目名称")
    let updatedTarget = NamingTarget(path:updatedFolder.path,folder:true,projectPath:dir.path)
    rules.folder = .category;try verify(store.saveNamingRuleSettings(rules))
    let categoryName = store.smartProposedName(base:"项目名称",target:updatedTarget,now:now)
    try verify(store.confirmRename(updatedTarget,newName:categoryName) && categoryName == "合同管理 项目名称","Confirmed category-prefix folder naming preserves manual category assignments")
    try "collision".write(to:dir.appendingPathComponent("1001 碰撞.DOCX"),atomically:true,encoding:.utf8)
    try verify(!store.confirmRename(fileTarget,newName:"1001 碰撞.DOCX"),"No-overwrite protection still applies to prefixed document names")
    store.error = ""
    try verify(store.confirmRename(fileTarget,newName:"手动名称.DOCX",requireMonth:false),"Manual renaming is independent of smart settings")
    _ = current
    print("PASS: six folder/document formats, independent persistence, Beijing/creation dates, prefix idempotence, numeric titles, extension preservation, failed-save rollback, preview isolation, MMDD batch/category physical rename, collision guard and manual rename independence")
}

@MainActor func namingRulesUIReview() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let root = fm.temporaryDirectory.appendingPathComponent("guiyu-naming-rules-"+UUID().uuidString)
    try fm.createDirectory(at:root,withIntermediateDirectories:true)
    defer { try? fm.removeItem(at:root) }
    try namingRulesTest(root:root)
    let store = Store(stateURL:root.appendingPathComponent("ui/settings.json"),loadOnLaunch:false)
    store.settings.categories = WorkspaceCategory.defaults
    let file = root.appendingPathComponent("网络建设方案.txt")
    try "解决方案\n项目名称：智慧园区建设项目\n方案名称：智慧园区建设方案".write(to:file,atomically:true,encoding:.utf8)
    let folder = root.appendingPathComponent("10月 示例文件夹")
    try fm.createDirectory(at:folder,withIntermediateDirectories:true)
    try "招标文件\n项目名称：智慧园区建设项目".write(to:folder.appendingPathComponent("招标文件.txt"),atomically:true,encoding:.utf8)
    let out = URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent(".impeccable/review/naming-rules")
    try fm.createDirectory(at:out,withIntermediateDirectories:true)
    func capture<V:View>(_ view:V,_ width:CGFloat,_ height:CGFloat,_ name:String) throws {
        let host = NSHostingView(rootView:view.background(Color(nsColor:.windowBackgroundColor)).preferredColorScheme(.light));host.frame = NSRect(x:0,y:0,width:width,height:height)
        let window = NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:width,height:height),styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView = host;window.orderBack(nil)
        RunLoop.current.run(until:Date().addingTimeInterval(0.8));host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:rep)
        try rep.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(name))
        window.orderOut(nil);window.contentView = nil
    }
    try capture(WorkspaceSettingsView(store:store,updater:AppUpdater.fixture(),close:{},openPending:{},section:.namingRules),820,620,"naming-rules-settings.png")
    for format in SmartNamingFormat.allCases {
        var rules = NamingRuleSettings();rules.folder = format;rules.document = format
        _ = store.saveNamingRuleSettings(rules)
        try capture(RenameDialog(store:store,target:NamingTarget(path:file.path,folder:false,projectPath:"")),700,460,"document-"+format.rawValue+".png")
        try capture(RenameDialog(store:store,target:NamingTarget(path:folder.path,folder:true,projectPath:folder.path)),700,460,"folder-"+format.rawValue+".png")
    }
    let rows = [browserEntry(file.path)!,browserEntry(folder.path)!]
    try capture(BatchRenameDialog(store:store,request:BatchNamingRequest(rows:rows,projectPath:root.path,recommended:true)),760,560,"batch-smart-rules.png")
    print("PASS: native settings sidebar/page and all six smart naming editors plus mixed folder/document batch captured")
}
