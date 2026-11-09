import AppKit
import Darwin

struct FilePasteResult: Identifiable {
    let id = UUID()
    let destination: String
    var paths: [String] = []
    var failure: String? = nil
}

func filePasteURLs(from board: NSPasteboard) -> [URL] {
    let urls = (board.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]) ?? []
    var seen = Set<String>()
    return urls.filter { $0.isFileURL && seen.insert($0.standardizedFileURL.path).inserted }
}

// Left A with no middle folder -> A; selected middle B -> B.
// The right table always supplies its current directory, including a nested one.
func filePasteDestination(directory: String?, selectedFolder: String?) -> String? {
    selectedFolder.flatMap { $0.isEmpty ? nil : $0 } ?? directory.flatMap { $0.isEmpty ? nil : $0 }
}

func executeFilePaste(_ sources: [URL], into destination: String) -> FilePasteResult {
    let folder = URL(fileURLWithPath:canonicalPath(destination))
    var result = FilePasteResult(destination:folder.path)
    do {
        let values = try folder.resourceValues(forKeys:[.isDirectoryKey,.isPackageKey])
        guard values.isDirectory == true, values.isPackage != true else { throw namingError("请选择可写入的普通文件夹。") }
        let targetIdentity = fileIdentity(folder.path)
        guard targetIdentity != nil else { throw namingError("目标文件夹已失效，请重新选择。") }
        guard !sources.isEmpty else { throw namingError("剪贴板中没有可粘贴的文件。") }
        let paths = sources.map { canonicalPath($0.path) }
        guard Set(paths).count == paths.count else { throw namingError("剪贴板包含重复条目。") }
        let identities = try sources.map { source -> String in
            guard source.isFileURL, let identity = fileIdentity(source.path) else { throw namingError("源文件已移动或无法访问："+source.lastPathComponent) }
            let value = try source.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            let path = canonicalPath(source.path)
            if value.isDirectory == true && value.isSymbolicLink != true {
                guard path != "/", folder.path != path, !folder.path.hasPrefix(path+"/") else { throw namingError("不能把文件夹复制到它自身或内部。") }
            }
            guard !paths.contains(where: { $0 != path && path.hasPrefix($0+"/") }) else { throw namingError("请只复制外层文件夹，不要同时复制它的内部条目。") }
            return identity
        }
        for (index,source) in sources.enumerated() {
            guard fileIdentity(folder.path) == targetIdentity else { throw namingError("目标文件夹已变化，已停止复制。") }
            guard fileIdentity(source.path) == identities[index] else { throw namingError("源文件已变化，已停止复制。") }
            // Stage on the destination volume, then publish with an exclusive
            // atomic rename. A failed copy never appears as a completed item.
            let staging = folder.appendingPathComponent(".guiyu-copy-"+UUID().uuidString)
            try fm.createDirectory(at:staging,withIntermediateDirectories:false)
            defer { try? fm.removeItem(at:staging) }
            let item = staging.appendingPathComponent(source.lastPathComponent)
            try fm.copyItem(at:source,to:item)
            guard fileIdentity(folder.path) == targetIdentity else { throw namingError("目标文件夹已变化，已停止复制。") }
            let isFolder = (try? source.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])).map { $0.isDirectory == true && $0.isSymbolicLink != true } ?? false
            let ext = isFolder ? "" : source.pathExtension
            let stem = ext.isEmpty ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
            var number = 1
            while true {
                let name = number == 1 ? source.lastPathComponent : stem+" (\(number))"+(ext.isEmpty ? "" : "."+ext)
                let target = folder.appendingPathComponent(name)
                if renameatx_np(AT_FDCWD,item.path,AT_FDCWD,target.path,UInt32(RENAME_EXCL)) == 0 {
                    result.paths.append(target.path); break
                }
                let code = errno
                guard code == EEXIST, number < 10000 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(code)) }
                number += 1
            }
        }
    } catch { result.failure = error.localizedDescription }
    return result
}

// Pin only live rows; older copied items retain their order beneath the new batch.
func pastedRowsFirst(_ rows: [BrowserRow], paths: [String], grouped: Bool = false, collapsed: Set<String> = [], scope: String = "") -> [BrowserRow] {
    let lookup = Dictionary(rows.filter{!$0.header}.map{($0.id,$0)},uniquingKeysWith:{a,_ in a})
    let pinned = paths.compactMap { lookup[$0] }
    guard !pinned.isEmpty else { return rows }
    let ids = Set(pinned.map(\.id))
    var rest: [BrowserRow] = []
    var header: BrowserRow?; var group: [BrowserRow] = []
    func flush() {
        if var h = header { if !group.isEmpty { h.count = group.count; rest.append(h); rest += group } else if !h.expanded { rest.append(h) } }
        else { rest += group }
        group = []
    }
    for row in rows {
        if row.header { flush(); header = row }
        else if !ids.contains(row.id) { group.append(row) }
    }
    flush()
    guard grouped else { return pinned+rest }
    let id = "recent-paste:"+scope
    return [BrowserRow(id:id,title:"刚复制",header:true,count:pinned.count,expanded:!collapsed.contains(id))]+(collapsed.contains(id) ? [] : pinned)+rest
}

func presentDirectoryWithPastes(_ entries:[BrowserRow], mode:String, collapsed:Set<String>, categories:[WorkspaceCategory], assignments:[String:CategoryAssignment], paths:[String], scope:String) -> [BrowserRow] {
    let lookup = Dictionary(entries.map{($0.id,$0)},uniquingKeysWith:{a,_ in a})
    let pinned = paths.compactMap{lookup[$0]}
    guard !pinned.isEmpty else { return presentDirectory(entries,mode:mode,query:"",collapsed:collapsed,categories:categories,assignments:assignments) }
    let ids = Set(pinned.map(\.id))
    let rest = presentDirectory(entries.filter{!ids.contains($0.id)},mode:mode,query:"",collapsed:collapsed,categories:categories,assignments:assignments)
    guard mode != "源文档" else { return pinned+rest }
    let id = "recent-paste:"+scope
    return [BrowserRow(id:id,title:"刚复制",header:true,count:pinned.count,expanded:!collapsed.contains(id))]+(collapsed.contains(id) ? [] : pinned)+rest
}

@MainActor extension Store {
    func canPasteFiles(into directory: String?, from board: NSPasteboard = .general) -> Bool {
        directory?.isEmpty == false && !busy && !isPastingFiles && !filePasteURLs(from:board).isEmpty
    }
    func pasteFiles(into directory: String, from board: NSPasteboard = .general, completion: ((FilePasteResult) -> Void)? = nil) {
        guard !busy, !isPastingFiles else { return }
        let sources = filePasteURLs(from:board)
        guard !sources.isEmpty else { return }
        isPastingFiles = true; message = "正在复制 \(sources.count) 项…"
        DispatchQueue.global(qos:.userInitiated).async {
            let result = executeFilePaste(sources,into:directory)
            DispatchQueue.main.async {
                self.isPastingFiles = false
                if !result.paths.isEmpty {
                    let previous = self.pastedPathsByDirectory[result.destination] ?? []
                    self.pastedPathsByDirectory[result.destination] = result.paths+previous.filter{!result.paths.contains($0)}
                    self.fileOperationRevision += 1
                    self.lastFilePaste = result
                    self.refresh()
                }
                self.message = "已复制 \(result.paths.count) 项"
                if let problem = result.failure { self.error = "已复制 \(result.paths.count) 项，剩余未完成："+problem }
                completion?(result)
            }
        }
    }
}
