import Foundation

// Recommendations compare names only. Manual search also accepts groups and keywords.
struct ArchiveProjectIndex {
    private struct Entry {
        let project: Project
        let searchName: String
        let searchGrams: Set<String>
        let keywords: [String]
    }

    private let entries: [Entry]
    private let frequency: [String:Int]
    private static let generic: Set<String> = ["建设","采购","项目","文件","公司","服务","技术","方案","响应","中国","贵州","要求","系统","信息","有限","集团","招标","投标","说明","附件","资料","20","2026","xx","rfp","rfq","input","document","scan"]

    private static func characters(_ name: String) -> [String?] {
        name.map { character in
            guard character.isLetter || character.isNumber else { return nil }
            return FilenameQuery.normalize(String(character))
        }
    }

    private static func matchingRanges(in name: String, covered: [Bool]) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        for (index,matched) in zip(name.indices,covered) where matched {
            let end = name.index(after:index)
            if let last = ranges.last, last.upperBound == index {
                ranges[ranges.count-1] = last.lowerBound..<end
            } else {
                ranges.append(index..<end)
            }
        }
        return ranges
    }

    // Track continuous runs ending at each project character. Walking backwards
    // then marks their union, so overlapping runs never count a position twice.
    private static func continuousMatch(_ filename: [String?], _ project: [String?]) -> (longest: Int, count: Int, covered: [Bool])? {
        guard filename.count >= 2, project.count >= 2 else { return nil }
        var suffixes = Array(repeating:0,count:project.count+1)
        var projectEnds = Array(repeating:0,count:project.count)
        var filenameEnds = Array(repeating:0,count:filename.count)
        for (fileIndex,character) in filename.enumerated() {
            for index in project.indices.reversed() {
                let length = character != nil && character == project[index] ? suffixes[index]+1 : 0
                suffixes[index+1] = length
                projectEnds[index] = max(projectEnds[index],length)
                filenameEnds[fileIndex] = max(filenameEnds[fileIndex],length)
            }
        }
        guard let longest = projectEnds.max(), longest >= 2 else { return nil }
        let covered = coveredPositions(projectEnds)
        let count = min(covered.filter { $0 }.count,coveredPositions(filenameEnds).filter { $0 }.count)
        return (longest,count,covered)
    }

    private static func coveredPositions(_ longestEndingAt: [Int]) -> [Bool] {
        var covered = Array(repeating:false,count:longestEndingAt.count)
        var leftmost = longestEndingAt.count
        for index in longestEndingAt.indices.reversed() {
            let length = longestEndingAt[index]
            if length >= 2 { leftmost = min(leftmost,index+1-length) }
            covered[index] = index >= leftmost
        }
        return covered
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
            let stem = archiveProjectStem(project.name)
            let searchName = Self.usable(stem) ? stem : ""
            let grams = Self.grams(searchName)
            for gram in grams { frequency[gram,default:0] += 1 }
            let keywords = project.keywords.components(separatedBy:CharacterSet(charactersIn:",，;；\n")).map(archiveNormal).filter(Self.usable)
            return Entry(project:project,searchName:searchName,searchGrams:grams,keywords:keywords)
        }
        self.frequency = frequency
    }

    func recommendations(for rows: [BrowserRow], token: IndexCancellation) -> [ProjectArchiveChoice] {
        let filenames = rows.map { row in
            let stem = row.folder ? row.title : URL(fileURLWithPath:row.title).deletingPathExtension().lastPathComponent
            return Self.characters(stem)
        }
        var matches: [(choice: ProjectArchiveChoice, longest: Int)] = []
        for entry in entries {
            guard !token.isCancelled else { return [] }
            let project = Self.characters(entry.project.name)
            var longest = 0
            var total = 0
            var highlighted = Array(repeating:false,count:project.count)
            for filename in filenames {
                guard let match = Self.continuousMatch(filename,project) else { continue }
                longest = max(longest,match.longest)
                total += match.count
                for index in match.covered.indices where match.covered[index] {
                    highlighted[index] = true
                }
            }
            guard longest >= 2 else { continue }
            let evidence = "最长连续匹配 \(longest) 个字符，累计匹配 \(total) 个字符"
            let ranges = Self.matchingRanges(in:entry.project.name,covered:highlighted)
            matches.append((ProjectArchiveChoice(project:entry.project,score:total,evidence:evidence,matchingRanges:ranges),longest))
        }
        return matches.sorted {
            if $0.longest != $1.longest { return $0.longest > $1.longest }
            if $0.choice.score != $1.choice.score { return $0.choice.score > $1.choice.score }
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
