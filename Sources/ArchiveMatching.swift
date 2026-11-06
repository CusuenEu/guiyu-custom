import Foundation

// Recommendations compare names only. Manual search also accepts groups and keywords.
struct ArchiveProjectIndex {
    private struct Entry {
        let project: Project
        let characters: [Character]
        let counts: [Character:Int]
        let searchName: String
        let searchGrams: Set<String>
        let keywords: [String]
    }

    private let entries: [Entry]
    private let frequency: [String:Int]
    private static let generic: Set<String> = ["建设","采购","项目","文件","公司","服务","技术","方案","响应","中国","贵州","要求","系统","信息","有限","集团","招标","投标","说明","附件","资料","20","2026","xx","rfp","rfq","input","document","scan"]

    private static func characters(_ name: String) -> [Character] {
        FilenameQuery.normalize(name).filter { $0.isLetter || $0.isNumber }.map { $0 }
    }

    private static func counts(_ characters: [Character]) -> [Character:Int] {
        characters.reduce(into:[:]) { $0[$1,default:0] += 1 }
    }

    // Longest common subsequence. Spaces, punctuation and gaps do not break the order.
    private static func orderedCount(_ filename: [Character], _ project: [Character]) -> Int {
        var lengths = Array(repeating:0,count:project.count+1)
        for character in filename {
            var diagonal = 0
            for (index,other) in project.enumerated() {
                let previous = lengths[index+1]
                lengths[index+1] = character == other ? diagonal+1 : max(lengths[index],previous)
                diagonal = previous
            }
        }
        return lengths[project.count]
    }

    private static func usable(_ text: String) -> Bool {
        text.count >= 2 && text.contains(where: { $0.isLetter }) && !generic.contains(text) && text.range(of:"^(?:附件|文档|资料|扫描件|未命名|新建|input|document|scan|img|image)[0-9一二三四五六七八九十]*$",options:.regularExpression) == nil
    }

    private static func grams(_ text: String) -> Set<String> {
        let chars = Array(text)
        guard chars.count >= 2 else { return [] }
        return Set((0..<chars.count-1).map { String(chars[$0...$0+1]) }).subtracting(generic).filter { !$0.allSatisfy(\.isNumber) }
    }

    init(projects: [Project]) {
        var frequency: [String:Int] = [:]
        entries = projects.filter { $0.shallow != true }.map { project in
            let characters = Self.characters(project.name)
            let stem = archiveProjectStem(project.name)
            let searchName = Self.usable(stem) ? stem : ""
            let grams = Self.grams(searchName)
            for gram in grams { frequency[gram,default:0] += 1 }
            let keywords = project.keywords.components(separatedBy:CharacterSet(charactersIn:",，;；\n")).map(archiveNormal).filter(Self.usable)
            return Entry(project:project,characters:characters,counts:Self.counts(characters),searchName:searchName,searchGrams:grams,keywords:keywords)
        }
        self.frequency = frequency
    }

    func recommendations(for rows: [BrowserRow], token: IndexCancellation) -> [ProjectArchiveChoice] {
        let filenames = rows.map { row in
            let stem = row.folder ? row.title : URL(fileURLWithPath:row.title).deletingPathExtension().lastPathComponent
            let characters = Self.characters(stem)
            return (characters:characters,counts:Self.counts(characters))
        }
        var matches: [(choice: ProjectArchiveChoice, ordered: Int)] = []
        for entry in entries {
            guard !token.isCancelled else { return [] }
            var shared = 0
            var ordered = 0
            for filename in filenames {
                let count = filename.counts.reduce(0) { sum, pair in
                    sum + min(pair.value,entry.counts[pair.key,default:0])
                }
                guard count > 0 else { continue }
                shared += count
                ordered += Self.orderedCount(filename.characters,entry.characters)
            }
            guard shared > 0 else { continue }
            let evidence = rows.count == 1 ? "与项目名有 \(shared) 个相同字符，其中 \(ordered) 个顺序相同" : "所选名称合计匹配 \(shared) 个字符，其中 \(ordered) 个顺序相同"
            matches.append((ProjectArchiveChoice(project:entry.project,score:shared,evidence:evidence),ordered))
        }
        return matches.sorted {
            if $0.choice.score != $1.choice.score { return $0.choice.score > $1.choice.score }
            if $0.ordered != $1.ordered { return $0.ordered > $1.ordered }
            return $0.choice.project.name.localizedStandardCompare($1.choice.project.name) == .orderedAscending
        }.map(\.choice)
    }

    func search(_ query: String) -> [Project] {
        let tokens = FilenameQuery(query).tokens
        let normalized = archiveNormal(query), stem = archiveProjectStem(query)
        let queryGrams = Self.grams(stem)
        func total(_ grams: Set<String>) -> Double {
            grams.reduce(0) { $0+1+log(Double(entries.count+1)/Double((frequency[$1] ?? 0)+1)) }
        }
        let queryWeight = max(total(queryGrams),1)
        var direct: [Project] = []
        var fuzzy: [(project: Project, score: Int)] = []
        for entry in entries {
            let searchText = FilenameQuery.normalize((entry.project.group ?? "")+" "+entry.project.name+" "+entry.project.keywords)
            if tokens.allSatisfy({ searchText.contains($0) }) {
                direct.append(entry.project)
                continue
            }
            var points = 0
            if !entry.searchName.isEmpty {
                if normalized.contains(entry.searchName) { points = entry.searchName.count >= 6 ? 120 : 100 }
                else if Self.usable(stem), stem.count >= 4, entry.searchName.contains(stem) { points = 85 }
                else {
                    let shared = queryGrams.intersection(entry.searchGrams)
                    if shared.count >= 2 {
                        let hits = total(shared)
                        let a = hits/queryWeight, b = hits/max(total(entry.searchGrams),1)
                        if max(a,b) >= 0.35 && min(a,b) >= 0.12 {
                            points = min(90,Int(65*max(a,b)+25*min(a,b)))
                        }
                    }
                }
            }
            let keywordHits = entry.keywords.filter { normalized.contains($0) }.count
            if keywordHits > 0 { points = max(points,min(110,70+20*(keywordHits-1))) }
            if points > 0 { fuzzy.append((entry.project,points)) }
        }
        return direct + fuzzy.sorted {
            $0.score == $1.score ? $0.project.name.localizedStandardCompare($1.project.name) == .orderedAscending : $0.score > $1.score
        }.map(\.project)
    }
}
