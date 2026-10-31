import SwiftUI
import AppKit

@MainActor func categoryWorkflowTest(root:URL) throws {
    let folder = root.appendingPathComponent("category-workflow")
    try fm.createDirectory(at:folder,withIntermediateDirectories:true)
    let fresh = Store(stateURL:folder.appendingPathComponent("fresh.json"),loadOnLaunch:false)
    try verify(fresh.workspaceCategories.isEmpty,"Fresh installation must have no categories")
    let reopenedFresh = Store(stateURL:fresh.stateURL,loadOnLaunch:false)
    try verify(reopenedFresh.workspaceCategories.isEmpty,"Empty first-run categories persist across restart")
    let oldURL = folder.appendingPathComponent("legacy.json")
    try JSONEncoder().encode(Settings()).write(to:oldURL)
    let legacy = Store(stateURL:oldURL,loadOnLaunch:false)
    try verify(legacy.workspaceCategories.count == 4,"An existing older settings file with no category field retains its old defaults")
    let pb = NSPasteboard.withUniqueName(); defer { pb.releaseGlobally() }
    pb.setString("unchanged",forType:.string)
    let flow = CategoryWorkflow()
    var opens = 0
    flow.copyPrompt(store:fresh,pasteboard:pb,openWebsite:{opens += 1})
    try verify(flow.failed && opens == 0 && pb.string(forType:.string) == "unchanged","No categories cannot copy or open a website")
    try verify(fresh.saveCategory(id:nil,name:"工程管理"))
    try verify(fresh.saveCategory(id:nil,name:"合同管理"))
    let categories = fresh.workspaceCategories
    flow.copyPrompt(store:fresh,pasteboard:pb,openWebsite:{opens += 1})
    try verify(!flow.failed && flow.operation == .copy && opens == 1 && flow.message == "复制成功，请去豆包提问","Copy immediately reports success and opens the requested website")
    try verify(pb.string(forType:.string) == CategoryRuleExchange.prompt(categories:categories),"Copy writes only the exact current category prompt")
    let disk = try Data(contentsOf:fresh.stateURL)
    pb.clearContents()
    flow.importReply(store:fresh,pasteboard:pb)
    try verify(flow.failed && fresh.workspaceCategories == categories,"Empty clipboard leaves categories intact")
    pb.setString("不完整的豆包回复",forType:.string)
    flow.importReply(store:fresh,pasteboard:pb)
    let afterInvalid = try Data(contentsOf:fresh.stateURL)
    try verify(flow.failed && disk == afterInvalid,"Invalid clipboard reply never partially writes rules")
    pb.setString(categoryExchangeFixture(categories),forType:.string)
    flow.importReply(store:fresh,pasteboard:pb)
    try verify(!flow.failed && flow.operation == .importReply && flow.message == "录入成功，已更新 2 个分类规则","One direct clipboard action parses, applies and reports the import")
    let reopened = Store(stateURL:fresh.stateURL,loadOnLaunch:false)
    try verify(reopened.workspaceCategories == fresh.workspaceCategories && reopened.workspaceCategories.count == 2,"User categories/rules survive restart without injected defaults")
    for (name,_) in CategoryWorkflowGuide.scenes {
        try verify(CategoryWorkflowGuide.image(name) != nil,"Packaged help picture must exist: "+name)
    }
    print("PASS: empty first installation/restart, legacy category preservation, direct clipboard copy + injected website callback, blank/invalid import atomicity, immediate full import result/persistence and all three packaged guide pictures")
}

@MainActor func categoryWorkflowUIReview() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let root = fm.temporaryDirectory.appendingPathComponent("guiyu-category-flow-"+UUID().uuidString)
    try fm.createDirectory(at:root,withIntermediateDirectories:true)
    defer { try? fm.removeItem(at:root) }
    try categoryWorkflowTest(root:root)
    let out = URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent(".impeccable/review/category-flow")
    try fm.createDirectory(at:out,withIntermediateDirectories:true)
    func capture<V:View>(_ view:V,_ width:CGFloat,_ height:CGFloat,_ name:String) throws {
        let host = NSHostingView(rootView:view.preferredColorScheme(.light))
        host.frame = NSRect(x:0,y:0,width:width,height:height)
        let window = NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:width,height:height),styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView = host; window.orderBack(nil)
        RunLoop.current.run(until:Date().addingTimeInterval(0.5));host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in:host.bounds)!
        host.cacheDisplay(in:host.bounds,to:rep)
        try rep.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(name))
        window.orderOut(nil);window.contentView = nil
    }
    let fresh = Store(stateURL:root.appendingPathComponent("fresh/settings.json"),loadOnLaunch:false)
    try capture(ProjectWorkspace(store:fresh),1060,700,"first-launch-minimum.png")
    try capture(ProjectWorkspace(store:fresh),1440,900,"first-launch-desktop.png")
    try capture(WorkspaceSettingsView(store:fresh,updater:AppUpdater.fixture(),close:{},openPending:{},section:.categories),820,620,"empty-category-settings.png")
    let configured = Store(stateURL:root.appendingPathComponent("configured/settings.json"),loadOnLaunch:false)
    for name in ["方案","招标文件","投标文件","其他","财务票据","售中材料"] { _ = configured.saveCategory(id:nil,name:name) }
    try capture(WorkspaceSettingsView(store:configured,updater:AppUpdater.fixture(),close:{},openPending:{},section:.categories),820,620,"category-flow-settings.png")
    let flow = CategoryWorkflow();flow.message = "录入成功，已更新 6 个分类规则"
    try capture(CategorySettingsView(store:configured,workflow:flow).padding(28).frame(width:646,height:480).background(.white),646,480,"category-flow-success.png")
    flow.operation = .copy;flow.message = "复制成功，请去豆包提问"
    try capture(CategorySettingsView(store:configured,workflow:flow).padding(28).frame(width:646,height:480).background(.white),646,480,"category-flow-copy-success.png")
    flow.operation = .importReply
    flow.failed = true;flow.message = "未读取到文字，请先复制豆包回复。"
    try capture(CategorySettingsView(store:configured,workflow:flow).padding(28).frame(width:646,height:480).background(.white),646,480,"category-flow-error.png")
    try capture(CategoryWorkflowGuide(),620,580,"category-flow-guide.png")
    for (name,_) in CategoryWorkflowGuide.scenes { try verify(CategoryWorkflowGuide.image(name) != nil,"Guide resources present") }
    print("PASS: actual native first-launch CTA at minimum/desktop, direct category settings destination, red three-step workflow, import success/error and scrolling image help rendered; clipboard tests use a private pasteboard; no external browser or real files touched")
}
