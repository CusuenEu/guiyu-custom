import AppKit

@MainActor func namingArchiveTests(root:URL) throws {
    let base = root.appendingPathComponent("rename-archive")
    let inbox = base.appendingPathComponent("inbox"),destination = base.appendingPathComponent("workspace/2026/目标项目")
    try fm.createDirectory(at:inbox,withIntermediateDirectories:true)
    try fm.createDirectory(at:destination,withIntermediateDirectories:true)
    let store = Store(stateURL:base.appendingPathComponent("state/settings.json"),loadOnLaunch:false)
    store.settings.root = base.appendingPathComponent("workspace").path
    let project = Project(path:destination.path,name:"目标项目",group:"2026",shallow:false)
    store.settings.projects = [project]
    func source(_ name:String) throws -> NamingTarget {
        let path = inbox.appendingPathComponent(name);try Data("isolated content".utf8).write(to:path)
        return NamingTarget(path:path.path,folder:false,projectPath:"")
    }
    let original = try source("原始文档.PDF"),identity = original.identity
    guard let request = store.renameForArchive(original,newName:"确认标题.PDF",requireMonth:false) else { throw namingError(store.error) }
    let renamed = inbox.appendingPathComponent("确认标题.PDF")
    try verify(!fm.fileExists(atPath:original.path) && request.rows.first?.id == renamed.path && request.rows.first?.title == "确认标题.PDF","Archive handoff contains the actual renamed URL and preserved extension spelling")
    try verify(request.targets.first?.identity == identity && request.targets.first?.modified == NamingTarget(path:renamed.path,folder:false,projectPath:"").modified,"Archive request refreshes identity and mtime after the rename")
    try verify(store.settings.moves.isEmpty && fm.fileExists(atPath:renamed.path),"Opening or cancelling archiving leaves the renamed document at its current location")
    let moved = store.confirmQuickArchive(request,to:project)
    try verify(moved.failure == nil && moved.completed == [renamed.path] && fm.fileExists(atPath:destination.appendingPathComponent("确认标题.PDF").path),"Only the separate archive confirmation moves the freshly renamed document")
    store.scanCancellation?.cancel();store.busy = false

    let unchanged = try source("保留原名.txt"),records = store.settings.renames?.count ?? 0
    try verify(store.renameForArchive(unchanged,newName:"保留原名.txt",requireMonth:false)?.rows.first?.id == unchanged.path && store.settings.renames?.count == records,"An unchanged/fallback name can continue to archive without inventing a rename record")
    let collision = try source("冲突源.txt")
    try Data("do not overwrite".utf8).write(to:inbox.appendingPathComponent("已存在.txt"))
    try verify(store.renameForArchive(collision,newName:"已存在.txt",requireMonth:false) == nil && fm.fileExists(atPath:collision.path),"A rename collision never produces an archive handoff")
    let changed = try source("已变更.txt")
    try fm.setAttributes([.modificationDate:Date().addingTimeInterval(5)],ofItemAtPath:changed.path)
    try verify(store.renameForArchive(changed,newName:"不应改名.txt",requireMonth:false) == nil && fm.fileExists(atPath:changed.path),"A stale source cannot be renamed or sent to archive")
    let busy = try source("忙碌.txt");store.busy = true
    try verify(store.renameForArchive(busy,newName:"不应执行.txt",requireMonth:false) == nil && fm.fileExists(atPath:busy.path),"Busy operations do not create a handoff")
    store.busy = false
    let folder = inbox.appendingPathComponent("原文件夹");try fm.createDirectory(at:folder,withIntermediateDirectories:true)
    try Data("nested".utf8).write(to:folder.appendingPathComponent("内部.txt"))
    let folderTarget = NamingTarget(path:folder.path,folder:true,projectPath:"")
    let folderRequest = store.renameForArchive(folderTarget,newName:"确认文件夹",requireMonth:false)
    try verify(folderRequest?.rows.first?.folder == true && folderRequest?.rows.first?.id == inbox.appendingPathComponent("确认文件夹").path && fm.fileExists(atPath:inbox.appendingPathComponent("确认文件夹/内部.txt").path),"Folder handoff uses the renamed directory and preserves its entire hierarchy")
    print("PASS: rename-before-archive handoff, refreshed paths/identity/mtime, no-op names, failure/busy/stale guards, folder hierarchy and confirmation-only movement")
}
