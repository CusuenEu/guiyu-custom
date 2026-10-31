import Foundation

struct WorkspaceCategory: Identifiable, Codable, Equatable {
    var id: String; var name: String
    static var defaults: [WorkspaceCategory] { DocumentCategory.allCases.map { WorkspaceCategory(id:$0.rawValue,name:$0.rawValue) } }
}
struct CategoryAssignment: Codable, Equatable {
    var categoryID: String; var identity: String
}
func resolvedCategory(_ row: BrowserRow, categories: [WorkspaceCategory], assignments: [String:CategoryAssignment]) -> WorkspaceCategory? {
    if let assignment = assignments[row.id], let category = categories.first(where:{$0.id == assignment.categoryID}), assignment.identity == fileIdentity(row.id) { return category }
    let automatic = categoryForEntry(row).rawValue
    return categories.first(where:{$0.id == automatic}) ?? categories.first(where:{$0.id == DocumentCategory.other.rawValue}) ?? categories.first
}
func categoryDestinations(_ row: BrowserRow, categories: [WorkspaceCategory], assignments: [String:CategoryAssignment]) -> [WorkspaceCategory] {
    let current = resolvedCategory(row,categories:categories,assignments:assignments)?.id
    return categories.filter { $0.id != current }
}
@MainActor extension Store {
    var workspaceCategories: [WorkspaceCategory] { settings.categories ?? WorkspaceCategory.defaults }
    var workspaceAssignments: [String:CategoryAssignment] { settings.categoryAssignments ?? [:] }
    @discardableResult func saveCategory(id: String?, name: String) -> Bool {
        let name = name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40, !name.contains("\n") else { error = "分类名称请填写 1–40 个字，不能包含换行。"; return false }
        var categories = workspaceCategories
        guard !categories.contains(where:{$0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame}) else { error = "已有同名分类，请更换名称。"; return false }
        if let id {
            guard let i = categories.firstIndex(where:{$0.id == id}) else { error = "该分类已不存在，请重新选择。"; return false }
            categories[i].name = name
        } else { categories.append(WorkspaceCategory(id:UUID().uuidString,name:name)) }
        settings.categories = categories; save(); return true
    }
    @discardableResult func deleteCategory(_ id: String) -> Bool {
        var categories = workspaceCategories
        guard categories.count > 1 else { error = "至少保留一个分类，请先新增其他分类。"; return false }
        categories.removeAll { $0.id == id }
        settings.categories = categories
        let fallback = categories.first(where:{$0.id == DocumentCategory.other.rawValue}) ?? categories[0]
        settings.categoryAssignments = workspaceAssignments.mapValues { value in
            value.categoryID == id ? CategoryAssignment(categoryID:fallback.id,identity:value.identity) : value
        }
        save(); return true
    }
    @discardableResult func assignCategory(_ row: BrowserRow, to id: String) -> Bool { assignCategories([row],to:id) }
    @discardableResult func assignCategories(_ rows: [BrowserRow], to id: String) -> Bool {
        guard !rows.isEmpty, workspaceCategories.contains(where:{$0.id == id}) else { error = "请选择文件和有效分类。"; return false }
        var assignments = workspaceAssignments
        for row in rows {
            guard !row.header, let identity = fileIdentity(row.id) else { error = "部分文件已变化，请刷新后重新选择；本次分类未更改。"; return false }
            assignments[row.id] = CategoryAssignment(categoryID:id,identity:identity)
        }
        settings.categoryAssignments = assignments; save(); return true
    }
    func remapCategoryAssignments(source: String, destination: String, folder: Bool) {
        guard let assignments = settings.categoryAssignments else { return }
        settings.categoryAssignments = Dictionary(assignments.map { (remapPath($0.key,source:source,destination:destination,folder:folder),$0.value) },uniquingKeysWith:{a,_ in a})
    }
}
@MainActor func categoryManagementTest(root: URL) throws {
    let dir = root.appendingPathComponent("Categories"); try fm.createDirectory(at:dir,withIntermediateDirectories:true)
    let file = dir.appendingPathComponent("技术响应文件.txt"); try "原始内容".write(to:file,atomically:true,encoding:.utf8)
    let nested = dir.appendingPathComponent("响应文件夹"); try fm.createDirectory(at:nested,withIntermediateDirectories:true)
    let child = nested.appendingPathComponent("保留层级.txt"); try "child".write(to:child,atomically:true,encoding:.utf8)
    let store = Store(stateURL:dir.appendingPathComponent("state.json"),loadOnLaunch:false)
    let row = BrowserRow(id:file.path,title:file.lastPathComponent)
    try verify(store.workspaceCategories.count == 4,"Old settings get four default categories")
    try verify(!categoryDestinations(row,categories:store.workspaceCategories,assignments:[:]).contains(where:{$0.id == "投标文件"}),"Menu hides actual current category")
    try verify(store.saveCategory(id:nil,name:"交付资料")); let custom = store.workspaceCategories.last!
    try verify(!store.saveCategory(id:nil,name:"交付资料")); store.error = ""
    try verify(store.assignCategory(row,to:custom.id))
    let grouped = presentDirectory([row],mode:"按类别",query:"",collapsed:[],categories:store.workspaceCategories,assignments:store.workspaceAssignments)
    try verify(grouped.first?.title == "交付资料" && grouped.count == 2)
    try verify(!categoryDestinations(row,categories:store.workspaceCategories,assignments:store.workspaceAssignments).contains(where:{$0.id == custom.id}))
    let disk = try JSONDecoder().decode(Settings.self,from:Data(contentsOf:store.stateURL))
    try verify(disk.categoryAssignments?[row.id]?.categoryID == custom.id,"Manual classification persists on disk")
    try verify(store.saveCategory(id:custom.id,name:"交付归档"))
    try verify(resolvedCategory(row,categories:store.workspaceCategories,assignments:store.workspaceAssignments)?.name == "交付归档")
    try verify(store.saveCategory(id:"投标文件",name:"响应材料"))
    try verify(resolvedCategory(BrowserRow(id:nested.path,title:nested.lastPathComponent,folder:true),categories:store.workspaceCategories,assignments:[:])?.name == "响应材料","Renamed built-in category keeps recognition rules")
    let target = NamingTarget(path:file.path,folder:false,projectPath:dir.path)
    try verify(store.confirmRename(target,newName:"手动修改.txt",requireMonth:false))
    let renamed = dir.appendingPathComponent("手动修改.txt")
    try verify(store.workspaceAssignments[renamed.path]?.categoryID == custom.id,"Rename preserves manual classification")
    try verify(store.deleteCategory(custom.id))
    try verify(store.workspaceAssignments[renamed.path]?.categoryID == "其他","Delete migrates assigned entries to remaining fallback")
    let folderTarget = NamingTarget(path:nested.path,folder:true,projectPath:dir.path)
    try verify(store.confirmRename(folderTarget,newName:"手动文件夹",requireMonth:false))
    try verify(fm.fileExists(atPath:dir.appendingPathComponent("手动文件夹/保留层级.txt").path),"Manual folder rename preserves children without month constraint")
    let preserved = try String(contentsOf:renamed,encoding:.utf8); try verify(preserved == "原始内容")
    for category in store.workspaceCategories.dropLast() { try verify(store.deleteCategory(category.id)) }
    try verify(!store.deleteCategory(store.workspaceCategories[0].id),"Cannot delete the last category")
    print("PASS: category CRUD, stable built-in rules, hidden current destination, persisted overrides, rename remapping, delete fallback, direct file/folder rename")
}

func batchCategoryDestinations(_ rows: [BrowserRow], categories: [WorkspaceCategory], assignments: [String:CategoryAssignment]) -> [WorkspaceCategory] {
    guard !rows.isEmpty else { return [] }
    let current = Set(rows.compactMap { resolvedCategory($0,categories:categories,assignments:assignments)?.id })
    return categories.filter { current.count != 1 || !current.contains($0.id) }
}
