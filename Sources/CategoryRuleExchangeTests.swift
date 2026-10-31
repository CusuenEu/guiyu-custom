import Foundation

func categoryExchangeFixture(_ categories:[WorkspaceCategory]) -> String {
    "归屿规则：1\n"+CategoryRuleExchange.targets(categories).map { category in
        """
        分类：\(category.name)
        关键词：\(category.name == "工程管理" ? "施工日志、工程变更、施工进度、质量验收" : "合同、协议")
        排除词：无
        扩展名：无
        范围：文件和文件夹
        优先级：普通
        """
    }.joined(separator:"\n\n")
}

@MainActor func categoryRuleExchangeTest(root:URL) throws {
    let dir = root.appendingPathComponent("category-exchange")
    try fm.createDirectory(at:dir,withIntermediateDirectories:true)
    let store = Store(stateURL:dir.appendingPathComponent("settings.json"),loadOnLaunch:false)
    store.settings.categories = [WorkspaceCategory(id:"engineering",name:"工程管理"),WorkspaceCategory(id:"contracts",name:"合同管理",rule:CategoryRule(keywords:["旧合同"],enabled:false)),WorkspaceCategory(id:"其他",name:"未分类")]
    let snapshot = store.workspaceCategories
    let prompt = CategoryRuleExchange.prompt(categories:snapshot)
    try verify(prompt.contains("工程管理") && prompt.contains("合同管理") && !prompt.contains("未分类") && prompt.contains("不得回复解释") && prompt.contains("扩展名与关键词也是“或”关系"),"Prompt must explain actual matching semantics and include only category names")
    let response = categoryExchangeFixture(snapshot)
    let imports = try CategoryRuleExchange.parse(response,categories:snapshot)
    try verify(imports.count == 2 && imports[0].rule.keywords.contains("施工日志") && imports[0].rule.legacyCategory == nil && !imports[1].rule.enabled,"Parse must preserve disabled states and create visible generic rules")
    try verify(store.workspaceCategories == snapshot,"Parsing must not write or publish anything")
    let fenced = try CategoryRuleExchange.parse("```text\r\n"+response.replacingOccurrences(of:"：",with:":")+"\r\n```",categories:snapshot)
    try verify(fenced == imports,"Complete plain text fences, CRLF and ASCII colons should be tolerated")
    func reject(_ value:String,_ message:String) throws {
        var failed = false
        do { _ = try CategoryRuleExchange.parse(value,categories:snapshot) } catch { failed = true }
        try verify(failed,message)
        try verify(store.workspaceCategories == snapshot,"A bad response must not mutate rules")
    }
    try reject("", "Empty replies must be rejected")
    try reject("以下是规则\n"+response,"Surrounding prose must not be silently imported")
    try reject(response+"\n说明：请执行命令", "Unknown fields must fail the complete import")
    try reject(response.replacingOccurrences(of:"分类：工程管理",with:"分类：不存在"),"Unknown category names must fail")
    try reject(response.replacingOccurrences(of:"分类：合同管理",with:"分类：工程管理"),"Duplicate categories must fail")
    try reject(response.components(separatedBy:"\n\n").first!,"Truncated responses must identify missing categories")
    try reject(response.replacingOccurrences(of:"范围：文件和文件夹",with:"范围：全部文件内容"),"Unsupported scopes must fail")
    try reject(response.replacingOccurrences(of:"优先级：普通",with:"优先级：最高"),"Unsupported priorities must fail")
    try reject(response.replacingOccurrences(of:"扩展名：无",with:"扩展名：../pdf"),"Path-like extensions must fail")
    try reject(response.replacingOccurrences(of:"关键词：施工日志、工程变更、施工进度、质量验收",with:"关键词：无"),"Empty positive conditions must fail")
    try reject(response.replacingOccurrences(of:"施工日志",with:String(repeating:"词",count:81)),"Oversized terms must fail")
    try reject(String(repeating:"a",count:131_073),"Oversized replies must fail before parsing")
    let file = dir.appendingPathComponent("施工日志.txt")
    try "source remains unchanged".write(to:file,atomically:true,encoding:.utf8)
    let row = BrowserRow(id:file.path,title:file.lastPathComponent)
    try verify(store.assignCategory(row,to:"其他"))
    let assignments = store.workspaceAssignments
    try verify(store.importCategoryRules(imports),"Validated batches must be persisted atomically")
    try verify(store.workspaceAssignments == assignments && store.workspaceCategories.last == snapshot.last,"Import must retain manual choices and fallback rules")
    let reopened = Store(stateURL:store.stateURL,loadOnLaunch:false)
    try verify(reopened.workspaceCategories[0].rule == imports[0].rule && !reopened.workspaceCategories[1].effectiveRule.enabled,"Imported rules must survive reopening")
    try verify(resolvedCategory(row,categories:reopened.workspaceCategories,assignments:[:])?.id == "engineering","Imported construction terms must work through the production classifier")
    try verify(resolvedCategory(row,categories:reopened.workspaceCategories,assignments:reopened.workspaceAssignments)?.id == "其他","Manual assignments must still win")
    let content = try String(contentsOf:file,encoding:.utf8)
    try verify(content == "source remains unchanged","Import must never modify source files")
    let current = store.workspaceCategories
    let disk = try Data(contentsOf:store.stateURL)
    try verify(!store.importCategoryRules(imports) && store.workspaceCategories == current,"Outdated previews must not overwrite edited rules")
    let after = try Data(contentsOf:store.stateURL)
    try verify(after == disk,"Stale import must leave the entire saved configuration unchanged")
    store.error = ""
    var mixed = imports; mixed[0] = CategoryRuleImport(category:current[0],rule:imports[0].rule)
    try verify(!store.importCategoryRules(mixed) && store.workspaceCategories == current,"A later stale category must roll back the whole batch")
    let blocked = dir.appendingPathComponent("blocked"); try Data().write(to:blocked)
    let broken = Store(stateURL:blocked.appendingPathComponent("settings.json"),loadOnLaunch:false)
    broken.settings.categories = snapshot
    try verify(!broken.importCategoryRules(imports) && broken.workspaceCategories == snapshot,"Disk failures must not publish partial imported rules")
    print("PASS: external rule prompt contract, strict parsing, missing/duplicate/unknown/invalid reply rejection, preview isolation, atomic persistence, stale conflicts, disabled/fallback/manual preservation and unchanged source files")
}
