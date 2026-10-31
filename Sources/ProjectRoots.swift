import Foundation
import AppKit

extension Settings {
    var activeProjectRoots: [String] {
        var seen = Set<String>()
        return ([root]+(projectRoots ?? [])).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    var workspaceIdentity: String { activeProjectRoots.joined(separator:"\u{001F}") }
    var hasProjectRoots: Bool { !activeProjectRoots.isEmpty }
    var protectedProjectPaths: [String] { activeProjectRoots + projects.filter { $0.shallow == true }.map(\.path) }
    func ownsProjectDestination(_ path: String) -> Bool {
        let destination = canonicalPath(path)
        return activeProjectRoots.contains { destination.hasPrefix(canonicalPath($0)+"/") }
    }
}
struct ProjectRootsSnapshot {
    var projects: [Project] = []
    var unavailable: [String] = []
}
func discoverProjectRoots(_ roots: [String], saved: [Project]) throws -> ProjectRootsSnapshot {
    var snapshot = ProjectRootsSnapshot(); var seen = Set<String>()
    for root in roots {
        let values: [Project]
        do { values = try discoverProjects(root:root,saved:saved) }
        catch {
            if roots.count == 1 { throw error }
            snapshot.unavailable.append(root)
            // A disconnected root must not erase its saved navigation or hide other roots.
            values = saved.filter { $0.path.hasPrefix(root+"/") }
        }
        for var project in values where seen.insert(project.path).inserted {
            project.directoryPath = project.shallow == true ? project.path : URL(fileURLWithPath:project.path).deletingLastPathComponent().path
            snapshot.projects.append(project)
        }
    }
    return snapshot
}
@MainActor extension Store {
    func navigationRoot(for path: String) -> String {
        let parent = URL(fileURLWithPath:path).deletingLastPathComponent().standardizedFileURL.path
        return settings.activeProjectRoots.first { URL(fileURLWithPath:$0).standardizedFileURL.path == parent } ?? settings.root
    }
    func directories(in root: String) -> [Project] { orderedDirectories.filter { navigationRoot(for:$0.path) == root } }
    func rootDisplayName(_ root: String) -> String {
        let url = URL(fileURLWithPath:root), name = URL(fileURLWithPath:root).lastPathComponent
        if settings.activeProjectRoots.filter({ URL(fileURLWithPath:$0).lastPathComponent == name }).count > 1 { return url.deletingLastPathComponent().lastPathComponent+" / "+name }
        return name
    }
    func chooseProjectRoots() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.message = "追加关联项目总目录，可一次选择多个；左侧显示各总目录下的子文件夹。"
        panel.prompt = "关联目录"
        guard panel.runModal() == .OK else { return }
        _ = addProjectRoots(panel.urls.map(\.path))
    }
    @discardableResult func addProjectRoots(_ paths: [String], refreshAfter: Bool = true) -> Bool {
        do {
            var roots = settings.activeProjectRoots
            let original = roots
            for path in paths {
                let resolved = canonicalPath(path)
                var folder: ObjCBool = false
                guard fm.fileExists(atPath:resolved,isDirectory:&folder), folder.boolValue,
                      (try? URL(fileURLWithPath:resolved).resourceValues(forKeys:[.isPackageKey]).isPackage) != true else { throw namingError("请选择存在且可访问的普通文件夹。") }
                if roots.contains(resolved) { continue }
                guard !roots.contains(where:{ resolved.hasPrefix($0+"/") || $0.hasPrefix(resolved+"/") }), resolved != "/" else { throw namingError("项目总目录不能互相嵌套，请选择独立的总目录。") }
                let inbox = settings.inbox
                guard inbox.isEmpty || !(resolved == inbox || resolved.hasPrefix(inbox+"/") || inbox.hasPrefix(resolved+"/")) else { throw namingError("项目总目录与待归档目录不能重叠。") }
                // Validate the directory before committing any part of a multi-selection.
                _ = try fm.contentsOfDirectory(atPath:resolved)
                roots.append(resolved)
            }
            guard roots != original else { message = "所选项目总目录已关联"; return true }
            var updated = settings; updated.root = roots.first ?? ""; updated.projectRoots = roots
            try persistProjectRoots(updated)
            if refreshAfter { scanCancellation?.cancel(); busy = false; refresh() }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func removeProjectRoot(_ path: String, refreshAfter: Bool = true) -> Bool {
        guard settings.activeProjectRoots.contains(path) else { return false }
        var updated = settings; let roots = updated.activeProjectRoots.filter { $0 != path }
        updated.root = roots.first ?? ""; updated.projectRoots = roots
        updated.projects.removeAll { $0.path.hasPrefix(path+"/") }
        do {
            try persistProjectRoots(updated)
            files.removeAll { $0.path.hasPrefix(path+"/") }; cache = cache.filter { !$0.key.hasPrefix(path+"/") }
            if refreshAfter { scanCancellation?.cancel(); busy = false; refresh() }
            return true
        } catch { self.error = "关联目录未移除："+error.localizedDescription; return false }
    }
    private func persistProjectRoots(_ updated: Settings) throws {
        try fm.createDirectory(at:stateURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(updated).write(to:stateURL,options:.atomic)
        settings = updated
    }
}
