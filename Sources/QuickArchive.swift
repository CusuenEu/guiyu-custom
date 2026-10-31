import SwiftUI

struct QuickArchiveRequest: Identifiable {
    let id = UUID(); let rows: [BrowserRow]; let targets: [NamingTarget]
    init(rows: [BrowserRow]) { self.rows = rows.filter { !$0.header }; targets = self.rows.map { NamingTarget(path:$0.id,folder:$0.folder,projectPath:"") } }
}
struct ProjectArchiveChoice: Identifiable {
    var id: String { project.path }; let project: Project; let score: Int; let evidence: String
}
func archiveProjectAccepts(_ project: Project, request: QuickArchiveRequest) -> Bool {
    let destination = canonicalPath(project.path)
    return project.shallow != true && request.targets.allSatisfy { target in
        let source = canonicalPath(target.path)
        return destination != source && !destination.hasPrefix(source+"/") && URL(fileURLWithPath:source).deletingLastPathComponent().path != destination
    }
}
func archiveNormal(_ text: String) -> String {
    FilenameQuery.normalize(text).replacingOccurrences(of:"[^\\p{L}\\p{N}]",with:"",options:.regularExpression)
}
func archiveProjectStem(_ name: String) -> String {
    var text = name.replacingOccurrences(of:"^(?:1[0-2]|[1-9])(?=月|\\s|[^0-9]|$)月?\\s*",with:"",options:.regularExpression)
    for word in ["股份有限公司","有限责任公司","有限公司","投标响应文件","招标文件","投标文件","采购文件","解决方案","服务项目","建设项目","项目","方案"] { text = text.replacingOccurrences(of:word,with:"") }
    return archiveNormal(text)
}
func projectArchiveChoices(input: String, projects: [Project], references: [FileItem]) -> [ProjectArchiveChoice] {
    ArchiveProjectIndex(projects:projects,references:references,includeCachedText:true).choices(input:input,origin:"文件")
}
@MainActor extension Store {
    func suggestArchiveProjects(_ request: QuickArchiveRequest, token: IndexCancellation, update: @escaping ([ProjectArchiveChoice],Bool,String) -> Void) {
        let workspaceID = settings.workspaceIdentity, roots = settings.activeProjectRoots, saved = settings.projects, known = files
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                // Reuse the workspace's project snapshot. Only a first-use empty list needs discovery.
                let discovered = saved.isEmpty ? try discoverProjectRoots(roots,saved:[]).projects : saved
                let projects = discovered.filter { archiveProjectAccepts($0,request:request) }
                let index = ArchiveProjectIndex(projects:projects,references:known)
                if saved.isEmpty {
                    DispatchQueue.main.async {
                        guard !token.isCancelled, self.settings.workspaceIdentity == workspaceID, self.settings.projects.isEmpty else { return }
                        self.settings.projects = discovered; self.save()
                    }
                }
                matchArchiveRows(request.rows,index:index,token:token,readOpening:{ row in
                    archiveOpeningText(row,known:known,token:token)
                }) { choices,done,message in
                    DispatchQueue.main.async {
                        guard !token.isCancelled, self.settings.workspaceIdentity == workspaceID else { return }
                        update(choices,done,message)
                    }
                }
            } catch {
                DispatchQueue.main.async { guard !token.isCancelled, self.settings.workspaceIdentity == workspaceID else { return }; update([],true,"项目列表暂不可用："+error.localizedDescription) }
            }
        }
    }
    func confirmQuickArchive(_ request: QuickArchiveRequest, to project: Project) -> (completed: Set<String>, failure: String?) {
        var completed = Set<String>(); error = ""
        do {
            guard !busy, settings.projects.contains(where:{$0.path == project.path && $0.shallow != true}), settings.hasProjectRoots else { throw namingError("项目已变化或仍在读取，请刷新后重试。") }
            let destinationRoot = canonicalPath(project.path)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath:destinationRoot,isDirectory:&isDirectory), isDirectory.boolValue, settings.ownsProjectDestination(destinationRoot) else { throw namingError("目标项目文件夹不存在或不在项目总目录中。") }
            var reserved = Set<String>(); var plans: [(NamingTarget,URL)] = []; var sources = Set<String>()
            for target in request.targets {
                guard sources.insert(target.path).inserted, target.identity != nil, target.identity == fileIdentity(target.path), (try? URL(fileURLWithPath:target.path).resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) == target.modified else { throw namingError("部分源文件已更新或被替换，请重新选择；本次尚未移动。") }
                let source = canonicalPath(target.path)
                guard destinationRoot != source, !destinationRoot.hasPrefix(source+"/"), URL(fileURLWithPath:source).deletingLastPathComponent().path != destinationRoot else { throw namingError("文件已在目标项目中，或目标位于源文件夹内部，请选择其他项目。") }
                guard !request.targets.contains(where:{$0.path != target.path && target.path.hasPrefix($0.path+"/")}) else { throw namingError("不能同时归档文件夹及其内部文件，请只选择外层文件夹。") }
                let original = URL(fileURLWithPath:target.path); let ext = target.folder ? "" : original.pathExtension
                let stem = target.folder ? original.lastPathComponent : original.deletingPathExtension().lastPathComponent
                var number = 1; var name = original.lastPathComponent
                while fm.fileExists(atPath:URL(fileURLWithPath:destinationRoot).appendingPathComponent(name).path) || reserved.contains(name.precomposedStringWithCanonicalMapping.lowercased()) {
                    number += 1; name = stem+" (\(number))"+(ext.isEmpty ? "" : "."+ext)
                }
                reserved.insert(name.precomposedStringWithCanonicalMapping.lowercased()); plans.append((target,URL(fileURLWithPath:destinationRoot).appendingPathComponent(name)))
            }
            for (target,destination) in plans {
                guard target.identity == fileIdentity(target.path), !fm.fileExists(atPath:destination.path) else { throw namingError("执行时文件或目标发生变化，已停止剩余操作。") }
                try fm.moveItem(atPath:target.path,toPath:destination.path)
                remapCategoryAssignments(source:target.path,destination:destination.path,folder:target.folder)
                for i in settings.moves.indices { settings.moves[i].destination = remapPath(settings.moves[i].destination,source:target.path,destination:destination.path,folder:target.folder) }
                settings.moves.insert(MoveRecord(source:target.path,destination:destination.path,identity:fileIdentity(destination.path),automatic:false,evidence:"智能归档 · 用户确认项目",folder:target.folder),at:0)
                incoming.removeAll { $0.path == target.path }; completed.insert(target.path); save()
                if !error.isEmpty { throw namingError("文件已移动，归档记录保存失败："+error) }
            }
            message = "已归档 \(completed.count) 项至 "+project.name; refresh(); return (completed,nil)
        } catch { if !completed.isEmpty { refresh() }; return (completed,"已完成 \(completed.count) 项；"+error.localizedDescription) }
    }
}

@MainActor func quickArchiveTest(root: URL) throws {
    let workspace = root.appendingPathComponent("QuickWorkspace"), projectDir = workspace.appendingPathComponent("2026/10 抖音")
    let inbox = root.appendingPathComponent("QuickInbox")
    try fm.createDirectory(at:projectDir,withIntermediateDirectories:true); try fm.createDirectory(at:inbox,withIntermediateDirectories:true)
    let first = inbox.appendingPathComponent("RFP.txt"); try "抖音集团机房租赁招采项目\n项目编号：DY-2026-001".write(to:first,atomically:true,encoding:.utf8)
    try "原有文件".write(to:projectDir.appendingPathComponent(first.lastPathComponent),atomically:true,encoding:.utf8)
    let store = Store(stateURL:root.appendingPathComponent("QuickState/settings.json"),loadOnLaunch:false)
    store.settings.categories = WorkspaceCategory.defaults // Existing configured-user fixture.
    let project = Project(path:projectDir.path,name:"10 抖音",group:"2026")
    store.settings.root = workspace.path; store.settings.projects = [project]
    try verify(store.availableArchiveSources.prefix(2).map(\.id) == ["downloads","recent"],"Default archive sources are real Downloads and Finder Recents")
    let custom = ArchiveSource(id:"custom",name:"资料",kind:"folder",path:inbox.path)
    store.settings.archiveSources = store.availableArchiveSources+[custom]; store.save()
    let saved = try JSONDecoder().decode(Settings.self,from:Data(contentsOf:store.stateURL)); try verify(saved.archiveSources?.last?.path == inbox.path)
    let choices = projectArchiveChoices(input:"抖音集团机房租赁招采项目",projects:[project,Project(path:"/other",name:"9 水利投资")],references:[])
    try verify(choices.first?.project.path == project.path,"Short project name can yield a reviewable suggestion")
    let ambiguous = Project(path:"/other",name:"8 抖音")
    try verify(projectArchiveChoices(input:"抖音集团资料",projects:[project,ambiguous],references:[]).count == 2,"Ambiguous suggestions remain choices, never automatic moves")
    let coded = Project(path:projectDir.path,name:"A")
    let ref = FileItem(path:projectDir.appendingPathComponent("招标文件.txt").path,project:projectDir.path,text:"项目编号：DY-2026-001",size:1,date:Date())
    try verify(projectArchiveChoices(input:"项目编号：DY-2026-001",projects:[coded],references:[ref]).first?.score == 120)
    try verify(projectArchiveChoices(input:"项目编号：DY-2026-0012",projects:[coded],references:[ref]).isEmpty,"Identifier matching must honor boundaries")
    let row = browserEntry(first.path)!, request = QuickArchiveRequest(rows:[row])
    try verify(!archiveProjectAccepts(Project(path:inbox.path,name:"来源目录"),request:request),"Already-in-target source is excluded from recommendations and manual choices")
    let alias = root.appendingPathComponent("QuickInboxAlias"); try fm.createSymbolicLink(at:alias,withDestinationURL:inbox)
    try verify(!archiveProjectAccepts(Project(path:alias.path,name:"来源别名"),request:request),"Symlink aliases must not bypass target filtering")
    try verify(fm.fileExists(atPath:first.path),"Previewing suggestions must not move anything")
    let result = store.confirmQuickArchive(request,to:project)
    try verify(result.failure == nil && result.completed.count == 1)
    let move = store.settings.moves[0]; try verify(move.destination.hasSuffix("RFP (2).txt") && move.automatic == false)
    let retained = try String(contentsOf:projectDir.appendingPathComponent("RFP.txt"),encoding:.utf8); try verify(retained == "原有文件")
    store.scanCancellation?.cancel(); store.busy = false; store.undo(move,refreshAfter:false)
    try verify(fm.fileExists(atPath:first.path),"Quick archive is undoable")
    let changed = QuickArchiveRequest(rows:[browserEntry(first.path)!]); try "新内容，保持原位".write(to:first,atomically:true,encoding:.utf8)
    let rejected = store.confirmQuickArchive(changed,to:project); try verify(rejected.completed.isEmpty && rejected.failure != nil && fm.fileExists(atPath:first.path),"Modified source is rejected before moving")
    let nested = inbox.appendingPathComponent("资料文件夹"); try fm.createDirectory(at:nested,withIntermediateDirectories:true)
    let child = nested.appendingPathComponent("内部.txt"); try "child".write(to:child,atomically:true,encoding:.utf8)
    let folder = browserEntry(nested.path)!; try verify(store.assignCategory(browserEntry(child.path)!,to:"方案"))
    let folderResult = store.confirmQuickArchive(QuickArchiveRequest(rows:[folder]),to:project)
    try verify(folderResult.failure == nil && fm.fileExists(atPath:projectDir.appendingPathComponent("资料文件夹/内部.txt").path),"Folder archiving preserves internal hierarchy")
    let folderMove = store.settings.moves[0]; store.scanCancellation?.cancel(); store.busy = false; store.undo(folderMove,refreshAfter:false)
    try verify(fm.fileExists(atPath:child.path) && store.workspaceAssignments[child.path]?.categoryID == "方案","Folder undo preserves manual classifications")
    store.removeArchiveSource("custom"); try verify(fm.fileExists(atPath:inbox.path),"Removing a linked source does not delete its folder")
    print("PASS: Downloads/Recents defaults, linked-source persistence, short-name and identifier project suggestions, confirmation-only move, no overwrite, stale-source rejection, folder hierarchy and undo")
}
