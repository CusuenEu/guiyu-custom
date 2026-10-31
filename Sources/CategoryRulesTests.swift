import Foundation

@MainActor func categoryRulesTest(root:URL) throws {
    let dir = root.appendingPathComponent("category-rules"); try fm.createDirectory(at:dir,withIntermediateDirectories:true)
    let state = dir.appendingPathComponent("settings.json")
    let store = Store(stateURL:state,loadOnLaunch:false)
    store.settings.categories = WorkspaceCategory.defaults // Existing configured-user fixture.
    func add(_ name:String) throws -> WorkspaceCategory {
        try verify(store.saveCategory(id:nil,name:name)); return store.workspaceCategories.last!
    }
    func row(_ name:String,folder:Bool = false) -> BrowserRow { BrowserRow(id:dir.appendingPathComponent(name).path,title:name,folder:folder) }
    func match(_ row:BrowserRow) -> String? { resolvedCategory(row,categories:store.workspaceCategories,assignments:store.workspaceAssignments)?.id }
    let receipts = try add("财务票据")
    try verify(receipts.rule?.origin == .automatic && receipts.effectiveRule.keywords.contains("invoice"),"Adding a category must persist generated synonyms without setup")
    try verify(!receipts.effectiveRule.keywords.contains("付款") && match(row("财务结算说明.txt")) == "其他","A compound category such as financial receipts must not expand into the entire broad financial domain")
    try verify(match(row("增值税发票.pdf")) == receipts.id && match(row("Annual_Invoice_07.PDF")) == receipts.id,"Generated names/synonyms must classify files across case and punctuation")
    try verify(match(row("invoiced.docx")) == "其他","English terms must not match inside unrelated words")
    let sales = try add("售中材料")
    try verify(match(row("售中技术方案.docx")) == sales.id,"An explicit custom category name must precede broad built-in recognition")
    let photos = try add("照片")
    try verify(match(row("IMG_001.HEIC")) == photos.id,"A format category must infer appropriate extensions")
    try verify(match(row("RFP需求文件.pdf")) == "招标文件" && match(row("RFP响应文件.docx")) == "投标文件","Default procurement precedence must remain unchanged")
    let unknown = try add("量子档案")
    try verify(match(row("量子档案.txt")) == unknown.id && match(row("普通档案.txt")) == "其他","Unknown names must conservatively match their own label, not generic suffixes")
    let negative = try add("非合同资料")
    try verify(!negative.effectiveRule.keywords.contains("合同") && match(row("客户合同.pdf")) == "其他","Negated labels must not expand to the category they exclude")
    let builtIn = store.workspaceCategories.first{$0.id == "招标文件"}!.effectiveRule
    var formatted = builtIn; formatted.keywords = builtIn.keywords.reversed().map{$0.uppercased()}
    try verify(formatted.sameMatchingConditions(as:builtIn),"Changing keyword order or case must not disable specialized built-in matching")
    formatted.excludedKeywords = ["模板"]
    try verify(formatted.samePositiveConditions(as:builtIn) && !formatted.sameMatchingConditions(as:builtIn),"Custom filters may preserve built-in positive recognition")
    formatted.origin = .edited; try verify(store.saveCategoryRule(id:"招标文件",rule:formatted))
    try verify(match(row("RFP需求文件.pdf")) == "招标文件" && match(row("RFP模板.pdf")) == "其他" && match(row("RFP响应文件.docx")) == "投标文件","Additional exclusions must preserve built-in procurement and response precedence")
    let reopened = Store(stateURL:state,loadOnLaunch:false)
    try verify(reopened.workspaceCategories.first(where:{$0.id == receipts.id})?.rule == receipts.rule,"Automatically generated rules must survive a disk roundtrip")

    var edited = receipts.effectiveRule; edited.origin = .edited; edited.excludedKeywords = ["模板"]
    try verify(store.saveCategoryRule(id:receipts.id,rule:edited))
    try verify(match(row("发票模板.pdf")) == "其他" && match(row("发票.pdf")) == receipts.id,"Exclusion rules must win over positive matches")
    edited.scope = .folders; try verify(store.saveCategoryRule(id:receipts.id,rule:edited))
    try verify(match(row("发票.pdf")) == "其他" && match(row("发票材料",folder:true)) == receipts.id,"File/folder scope must be enforced")
    edited.scope = .all; try verify(store.saveCategoryRule(id:receipts.id,rule:edited))
    let manual = dir.appendingPathComponent("发票.pdf"); try "content remains unchanged".write(to:manual,atomically:true,encoding:.utf8)
    try verify(store.assignCategory(row(manual.lastPathComponent),to:sales.id))
    try verify(match(row(manual.lastPathComponent)) == sales.id,"Saved manual choices must override automatic matching")
    edited.enabled = false; try verify(store.saveCategoryRule(id:receipts.id,rule:edited))
    try verify(match(row("收据.pdf")) == "其他" && match(row(manual.lastPathComponent)) == sales.id,"Disabling a rule must not discard manual assignments")
    try verify(store.saveCategory(id:receipts.id,name:"我的票据"))
    try verify(store.workspaceCategories.first(where:{$0.id == receipts.id})?.rule == edited,"Renaming must retain a manually edited rule")
    try verify(store.saveCategory(id:unknown.id,name:"蓝鲸资料"))
    try verify(match(row("蓝鲸说明.txt")) == unknown.id,"Renaming an automatic category must regenerate its name-derived rule")

    let x = try add("甲分类"), y = try add("乙分类")
    var conflict = CategoryRule(keywords:["共享资料"],origin:.edited)
    try verify(store.saveCategoryRule(id:x.id,rule:conflict) && store.saveCategoryRule(id:y.id,rule:conflict))
    try verify(match(row("共享资料.txt")) == "其他","Ambiguous matches must not depend on category display order")
    conflict.priority = 1; try verify(store.saveCategoryRule(id:y.id,rule:conflict))
    try verify(match(row("共享资料.txt")) == y.id,"An explicit rule priority must resolve a conflict")
    let before = store.workspaceCategories
    var invalid = conflict; invalid.extensions = ["../pdf"]
    try verify(!store.saveCategoryRule(id:y.id,rule:invalid) && store.workspaceCategories == before,"Invalid rules must leave configuration unchanged")
    store.error = ""
    let legacy = try JSONDecoder().decode([WorkspaceCategory].self,from:Data("[{\"id\":\"old-custom\",\"name\":\"合同\"},{\"id\":\"投标文件\",\"name\":\"响应材料\"}]".utf8))
    try verify(legacy[0].effectiveRule.keywords.contains("协议") && legacy[1].effectiveRule.legacyCategory == "投标文件","Old custom categories gain generated rules while renamed built-ins retain their old recognition")
    let blocked = dir.appendingPathComponent("blocked"); try Data().write(to:blocked)
    let broken = Store(stateURL:blocked.appendingPathComponent("settings.json"),loadOnLaunch:false)
    let original = broken.workspaceCategories
    try verify(!broken.saveCategory(id:nil,name:"合同") && broken.workspaceCategories == original,"A disk failure must not claim a category or its rule was saved")
    let contents = try String(contentsOf:manual,encoding:.utf8)
    try verify(contents == "content remains unchanged","Automatic classification must not modify file contents")
    let many = (0..<1000).map { row("售中技术方案-\($0).docx") }
    let presented = presentDirectory(many,mode:"按类别",query:"",collapsed:[],categories:store.workspaceCategories,assignments:[:])
    try verify(presented.filter{!$0.header}.count == many.count && presented.first?.categoryID == sales.id,"The complete grouping path must apply generated rules once per entry without dropping or duplicating entries")
    print("PASS: automatic category rules, vocabulary/name/type generation, conservative unknowns, English boundaries, persistence/editing/scope/exclusions, manual precedence, conflict/priority, legacy compatibility and non-destructive failure")
}
