import Foundation
import Combine
import GRDB

// Only names and ownership are indexed. No document body, OCR, or directory scan occurs here.
struct FilenameQuery: Sendable {
    let phrase: String
    let tokens: [String]
    init(_ text:String) {
        phrase = Self.normalize(text).split(whereSeparator: { $0.isWhitespace }).joined(separator:" ")
        var seen = Set<String>()
        tokens = phrase.split(separator:" ").map(String.init).filter { seen.insert($0).inserted }
    }
    static func normalize(_ value:String) -> String {
        value.folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX")).precomposedStringWithCanonicalMapping.lowercased()
    }
    func matches(_ name:String) -> Bool { matchesNormalized(Self.normalize(name)) }
    func matchesNormalized(_ name:String) -> Bool { tokens.allSatisfy { name.contains($0) } }
    func rank(_ name:String) -> Int {
        if name == phrase { return 0 }
        if name.hasPrefix(phrase) { return 1 }
        if name.contains(phrase) { return 2 }
        return 3
    }
}

private struct FilenameDocument: Equatable {
    let id: String; let owner: String; let scope: String; let name: String; let normalized: String; let kind: Int
    init(id:String,owner:String,scope:String,name:String,kind:Int) {
        self.id = id; self.owner = owner; self.scope = scope; self.name = name
        self.normalized = FilenameQuery.normalize(name); self.kind = kind
    }
    init(row:Row) {
        id = row["id"]; owner = row["owner"]; scope = row["scope"]; name = row["name"]; normalized = row["normalized"]; kind = row["kind"]
    }
}

struct FilenameMatches {
    var projectRanks: [String:Int] = [:]
    var fileRanks: [String:Int] = [:]
    var usedDatabase = false
}

final class FilenameSearchIndex: @unchecked Sendable {
    private let queue = DispatchQueue(label:"local.guiyu.filename-index",qos:.userInitiated)
    private let revisionLock = NSLock()
    private var revision = 0
    private let databaseURL: URL
    private var database: DatabaseQueue?
    private var documents: [String:FilenameDocument] = [:]
    private var usesDatabase = false
    init(databaseURL:URL) { self.databaseURL = databaseURL }

    private func nextRevision() -> Int { revisionLock.lock(); defer { revisionLock.unlock() }; revision += 1; return revision }
    private func isCurrent(_ value:Int) -> Bool { revisionLock.lock(); defer { revisionLock.unlock() }; return revision == value }
    func replace(root:String,projects:[Project],files:[FileItem]) {
        let ticket = nextRevision()
        queue.async { [weak self] in
            guard let self, self.isCurrent(ticket) else { return }
            self.replaceOnQueue(root:root,projects:projects,files:files)
        }
    }
    // Used by isolated correctness/performance fixtures, never by UI typing.
    func synchronize(root:String,projects:[Project],files:[FileItem]) {
        _ = nextRevision()
        queue.sync { replaceOnQueue(root:root,projects:projects,files:files) }
    }
    func lookup(_ query:FilenameQuery,scope:String,token:IndexCancellation,completion:@escaping (FilenameMatches) -> Void) {
        queue.async { [self] in
            guard !token.isCancelled else { return }
            let result = lookupOnQueue(query,scope:scope)
            guard !token.isCancelled else { return }
            completion(result)
        }
    }
    func lookupSync(_ text:String,scope:String) -> FilenameMatches { queue.sync { lookupOnQueue(FilenameQuery(text),scope:scope) } }

    private func openDatabase() throws -> DatabaseQueue {
        if let database { return database }
        if (try? databaseURL.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) == true { throw namingError("搜索缓存路径不能是符号链接") }
        try fm.createDirectory(at:databaseURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        func open() throws -> DatabaseQueue {
            var configuration = Configuration()
            configuration.busyMode = .timeout(2)
            let db = try DatabaseQueue(path:databaseURL.path,configuration:configuration)
            try db.write { db in
                try db.execute(sql:"""
                    CREATE TABLE IF NOT EXISTS search_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                    CREATE TABLE IF NOT EXISTS search_documents (
                        id TEXT PRIMARY KEY NOT NULL, owner TEXT NOT NULL, scope TEXT NOT NULL,
                        name TEXT NOT NULL, normalized TEXT NOT NULL, kind INTEGER NOT NULL);
                    CREATE INDEX IF NOT EXISTS search_scope ON search_documents(scope);
                    CREATE TABLE IF NOT EXISTS search_grams (
                        scope TEXT NOT NULL, gram TEXT NOT NULL,
                        entry_id TEXT NOT NULL REFERENCES search_documents(id) ON DELETE CASCADE,
                        PRIMARY KEY(scope,gram,entry_id)) WITHOUT ROWID;
                    """)
            }
            return db
        }
        do { let db = try open(); database = db; return db }
        catch {
            guard let sqliteError = error as? DatabaseError,
                  sqliteError.resultCode == .SQLITE_CORRUPT || sqliteError.resultCode == .SQLITE_NOTADB else { throw error }
            let values = try? databaseURL.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { throw error }
            // This file is a disposable name cache, separate from settings and original documents.
            for suffix in ["", "-wal", "-shm", "-journal"] {
                let url = URL(fileURLWithPath:databaseURL.path + suffix)
                if fm.fileExists(atPath:url.path) { try fm.removeItem(at:url) }
            }
            let db = try open(); database = db; return db
        }
    }
    private func grams(_ name:String) -> Set<String> {
        let chars = Array(name.unicodeScalars)
        var result = Set<String>()
        // Bigrams support two-character Chinese words; unigrams use a scoped literal fallback.
        for length in [2,3] where chars.count >= length {
            for start in 0...(chars.count-length) { result.insert(String(String.UnicodeScalarView(chars[start..<(start+length)]))) }
        }
        return result
    }
    private func replaceOnQueue(root:String,projects:[Project],files:[FileItem]) {
        let owners = Dictionary(projects.map { ($0.path,$0) },uniquingKeysWith:{ first,_ in first })
        var next: [String:FilenameDocument] = [:]
        for project in projects where project.shallow != true {
            next[project.path] = FilenameDocument(id:project.path,owner:project.path,scope:project.scopeID,name:project.name,kind:0)
        }
        for file in files {
            guard let owner = owners[file.project] else { continue }
            next[file.path] = FilenameDocument(id:file.path,owner:file.project,scope:owner.scopeID,name:file.name,kind:1)
        }
        documents = next // Correct in-memory fallback even if the cache is unavailable.
        do {
            let db = try openDatabase()
            try db.write { db in
                let oldRoot = try String.fetchOne(db,sql:"SELECT value FROM search_metadata WHERE key='root'")
                if oldRoot != root { try db.execute(sql:"DELETE FROM search_documents") }
                let old = Dictionary(try Row.fetchAll(db,sql:"SELECT * FROM search_documents").map { row -> (String,FilenameDocument) in
                    let doc = FilenameDocument(row:row); return (doc.id,doc)
                },uniquingKeysWith:{ first,_ in first })
                let remove = try db.makeStatement(sql:"DELETE FROM search_documents WHERE id=?")
                let insert = try db.makeStatement(sql:"INSERT INTO search_documents(id,owner,scope,name,normalized,kind) VALUES (?,?,?,?,?,?)")
                let gramInsert = try db.makeStatement(sql:"INSERT INTO search_grams(scope,gram,entry_id) VALUES (?,?,?)")
                for id in old.keys where next[id] == nil { try remove.execute(arguments:[id]) }
                for doc in next.values where old[doc.id] != doc {
                    try remove.execute(arguments:[doc.id])
                    try insert.execute(arguments:[doc.id,doc.owner,doc.scope,doc.name,doc.normalized,doc.kind])
                    for gram in grams(doc.normalized) { try gramInsert.execute(arguments:[doc.scope,gram,doc.id]) }
                }
                try db.execute(sql:"INSERT OR REPLACE INTO search_metadata(key,value) VALUES ('root',?)",arguments:[root])
            }
            usesDatabase = true
        } catch { usesDatabase = false }
    }
    private func lookupOnQueue(_ query:FilenameQuery,scope:String) -> FilenameMatches {
        guard !query.tokens.isEmpty else { return FilenameMatches() }
        if usesDatabase, let database {
            do {
                let hits = try database.read { db -> [FilenameDocument] in
                    var candidates = Set<String>()
                    for token in query.tokens {
                        let chars = Array(token.unicodeScalars)
                        if chars.count == 2 { candidates.insert(token) }
                        else if chars.count >= 3 {
                            for start in Set([0,(chars.count-3)/2,chars.count-3]) {
                                candidates.insert(String(String.UnicodeScalarView(chars[start..<(start+3)])))
                            }
                        }
                    }
                    var best: (String,Int)?
                    for gram in candidates {
                        let count = try Int.fetchOne(db,sql:"SELECT COUNT(*) FROM search_grams WHERE scope=? AND gram=?",arguments:[scope,gram]) ?? 0
                        if count == 0 { return [] }
                        if best == nil || count < best!.1 { best = (gram,count) }
                    }
                    var sql = "SELECT * FROM search_documents WHERE scope=?"
                    var args = [scope]
                    if let best {
                        sql += " AND id IN (SELECT entry_id FROM search_grams WHERE scope=? AND gram=?)"
                        args += [scope,best.0]
                    }
                    for token in query.tokens { sql += " AND instr(normalized,?)>0"; args.append(token) }
                    return try Row.fetchAll(db,sql:sql,arguments:StatementArguments(args)).map(FilenameDocument.init(row:))
                }
                return matches(hits,query:query,database:true)
            } catch { usesDatabase = false }
        }
        return matches(documents.values.filter { $0.scope == scope && query.matchesNormalized($0.normalized) },query:query,database:false)
    }
    private func matches(_ hits:[FilenameDocument],query:FilenameQuery,database:Bool) -> FilenameMatches {
        var result = FilenameMatches(); result.usedDatabase = database
        for hit in hits {
            let rank = query.rank(hit.normalized)
            result.projectRanks[hit.owner] = min(result.projectRanks[hit.owner] ?? Int.max,rank + (hit.kind == 0 ? 0 : 4))
            if hit.kind == 1 { result.fileRanks[hit.id] = rank }
        }
        return result
    }
}

struct WorkspaceSearchOutput: Equatable {
    var query = ""
    var projectRows: [BrowserRow] = []
    var sourceIDs: Set<String>? = nil
    var fileRows: [BrowserRow] = []
    var searchEntries: [BrowserRow] = []
    var unavailableProjects: [String] = []
}

@MainActor final class WorkspaceSearchController: ObservableObject {
    @Published private(set) var output = WorkspaceSearchOutput()
    @Published private(set) var isSearching = false
    private var pending: DispatchWorkItem?
    private var cancellation: IndexCancellation?
    private var generation = UUID()
    private let thirdLevelCache = ThirdLevelSearchCache()
    func submit(index:FilenameSearchIndex,query:String,scope:String,projects:[Project],files:[FileItem],sourceRows:[BrowserRow],byMonth:Bool,mode:String = "按类别",collapsed:Set<String> = [],categories:[WorkspaceCategory] = WorkspaceCategory.defaults,assignments:[String:CategoryAssignment] = [:],aggregateThirdLevel:Bool = false,metadataRevision:Int = 0,pastedPaths:[String] = [],pasteScope:String = "") {
        pending?.cancel(); cancellation?.cancel(); isSearching = true
        let ticket = UUID(); generation = ticket
        let token = IndexCancellation(); cancellation = token
        let parsed = FilenameQuery(query)
        let cache = thirdLevelCache
        let finish: (FilenameMatches,ThirdLevelSearchCache.Snapshot?) -> Void = { [weak self] matches, snapshot in
                guard !token.isCancelled else { return }
                var matches = matches
                // Project names are usable even before the first metadata/index publication.
                if !parsed.tokens.isEmpty {
                    for project in projects where project.shallow != true && project.scopeID == scope {
                        let name = FilenameQuery.normalize(project.name)
                        if parsed.matchesNormalized(name) {
                            matches.projectRanks[project.path] = min(matches.projectRanks[project.path] ?? Int.max,parsed.rank(name))
                        }
                    }
                }
                if let snapshot {
                    for row in snapshot.rows where parsed.matches(row.title) {
                        let owner = URL(fileURLWithPath:row.id).deletingLastPathComponent().path
                        matches.projectRanks[owner] = min(matches.projectRanks[owner] ?? Int.max,parsed.rank(FilenameQuery.normalize(row.title))+4)
                    }
                }
                var folders = newestProjects(projects.filter { $0.shallow != true && $0.scopeID == scope },byMonth:byMonth)
                let directory = projects.first { $0.shallow == true && $0.scopeID == scope }?.path
                var loose = files.filter { $0.project == directory }.sorted { $0.date > $1.date }
                let searching = !parsed.tokens.isEmpty
                if searching {
                    folders = folders.filter { matches.projectRanks[$0.path] != nil }
                    // Stable ordering within a relevance tier retains the user's month/date choice.
                    folders = folders.enumerated().sorted {
                        let x = matches.projectRanks[$0.element.path] ?? Int.max, y = matches.projectRanks[$1.element.path] ?? Int.max
                        return x == y ? $0.offset < $1.offset : x < y
                    }.map(\.element)
                    loose = loose.filter { matches.fileRanks[$0.path] != nil }.enumerated().sorted {
                        let x = matches.fileRanks[$0.element.path] ?? Int.max, y = matches.fileRanks[$1.element.path] ?? Int.max
                        return x == y ? $0.offset < $1.offset : x < y
                    }.map(\.element)
                }
                let rows = folders.map { BrowserRow(id:$0.path,title:$0.name,folder:true) } + loose.map { BrowserRow(id:$0.path,title:$0.name,date:$0.date,file:$0) }
                let entries = snapshot?.rows ?? sourceRows
                let matchingSource = searching ? entries.filter { parsed.matches($0.title) } : entries
                let ids = searching ? Set(matchingSource.map(\.id)) : nil
                let presented = presentDirectoryWithPastes(matchingSource,mode:mode,collapsed:collapsed,categories:categories,assignments:assignments,paths:pastedPaths,scope:pasteScope)
                guard !token.isCancelled else { return }
                DispatchQueue.main.async {
                    guard let self, self.generation == ticket, !token.isCancelled else { return }
                    self.isSearching = false
                    self.output = WorkspaceSearchOutput(query:query,projectRows:rows,sourceIDs:ids,fileRows:presented,searchEntries:snapshot == nil ? [] : matchingSource,unavailableProjects:snapshot?.unavailable ?? [])
                }
        }
        let complete: (FilenameMatches) -> Void = { matches in
            if aggregateThirdLevel && !parsed.tokens.isEmpty {
                cache.load(scope:scope,projects:projects,revision:metadataRevision,token:token) { finish(matches,$0) }
            } else { finish(matches,nil) }
        }
        let work = DispatchWorkItem {
            guard !token.isCancelled else { return }
            if parsed.tokens.isEmpty {
                // Ordinary browsing never waits for a cache rebuild.
                DispatchQueue.global(qos:.userInitiated).async { complete(FilenameMatches()) }
            } else { index.lookup(parsed,scope:scope,token:token,completion:complete) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline:.now() + (parsed.tokens.isEmpty ? 0 : 0.05),execute:work)
    }
    deinit { pending?.cancel(); cancellation?.cancel() }
}
