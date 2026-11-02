import Foundation

private let archiveMatchThreshold = 65

// A request-local, in-memory index. Building and querying it never reads documents or directories.
struct ArchiveProjectIndex {
    private struct Name {
        let text: String; let grams: Set<String>; let label: String
    }
    private struct Entry {
        let project: Project; let names: [Name]; let keywords: [String]; let identifiers: [String]
    }
    private let entries: [Entry]
    private let frequency: [String:Int]
    private static let generic: Set<String> = ["建设","采购","项目","文件","公司","服务","技术","方案","响应","中国","贵州","要求","系统","信息","有限","集团","招标","投标","说明","附件","资料","20","2026","xx","rfp","rfq","input","document","scan"]
    private static func usable(_ text: String) -> Bool {
        text.count >= 2 && text.contains(where: { $0.isLetter }) && !generic.contains(text) && text.range(of:"^(?:附件|文档|资料|扫描件|未命名|新建|input|document|scan|img|image)[0-9一二三四五六七八九十]*$",options:.regularExpression) == nil
    }
    private static func grams(_ text: String) -> Set<String> {
        let chars = Array(text)
        guard chars.count >= 2 else { return [] }
        return Set((0..<chars.count-1).map { String(chars[$0...$0+1]) }).subtracting(generic).filter { !$0.allSatisfy(\.isNumber) }
    }
    init(projects: [Project], references: [FileItem] = [], includeCachedText: Bool = false) {
        let grouped = Dictionary(grouping:references,by:\.project)
        var built: [Entry] = []; var counts: [String:Int] = [:]
        let codeRegex = try! NSRegularExpression(pattern:"(?:项目编号|合同编号|招标编号|采购编号)[：:\\s]*([A-Za-z0-9][A-Za-z0-9_./—-]{3,})")
        for project in projects where project.shallow != true {
            // Dates and bare numeric folders are containers, not project
            // identities. Their nested documents may belong to many projects.
            let container = FilenameQuery.normalize(project.name).range(of:"^[\\p{N}〇零一二三四五六七八九十百千\\s年月日./_—–\\-]+$",options:.regularExpression) != nil
            var labels = container ? [] : [project.name]
            let files = grouped[project.path] ?? []
            // File names are already-loaded metadata; generic attachment labels add no identity.
            if !container { labels += files.map { $0.url.deletingPathExtension().lastPathComponent }.filter { archiveProjectStem($0).count >= 6 } }
            var codes: [String] = []
            if includeCachedText {
                for var file in files where !file.text.isEmpty {
                    file.text = String(file.text.prefix(6000))
                    if !container { labels += projectNames(file) }
                    let corpus = file.text as NSString
                    codes += codeRegex.matches(in:file.text,range:NSRange(location:0,length:corpus.length)).map { corpus.substring(with:$0.range(at:1)) }
                }
            }
            var seen = Set<String>()
            let names: [Name] = labels.compactMap { label in
                let text = archiveProjectStem(label)
                guard Self.usable(text), seen.insert(text).inserted else { return nil }
                return Name(text:text,grams:Self.grams(text),label:label)
            }
            let keywords = project.keywords.components(separatedBy:CharacterSet(charactersIn:",，;；\n")).map(archiveNormal).filter(Self.usable)
            let allGrams = names.reduce(into:Set<String>()) { $0.formUnion($1.grams) }
            for gram in allGrams { counts[gram,default:0] += 1 }
            built.append(Entry(project:project,names:names,keywords:keywords,identifiers:codes))
        }
        entries = built; frequency = counts
    }
    func choices(input: String, origin: String) -> [ProjectArchiveChoice] {
        let normalized = archiveNormal(input), stem = archiveProjectStem(input)
        let queryGrams = Self.grams(stem)
        func weight(_ gram: String) -> Double { 1 + log(Double(entries.count+1)/Double((frequency[gram] ?? 0)+1)) }
        func total(_ grams: Set<String>) -> Double { grams.reduce(0) { $0+weight($1) } }
        let queryWeight = max(total(queryGrams),1)
        return entries.compactMap { entry in
            var score = 0; var evidence = ""
            for name in entry.names {
                var points = 0
                if normalized.contains(name.text) { points = name.text.count >= 6 ? 120 : 100 }
                else if Self.usable(stem), stem.count >= 4, name.text.contains(stem) { points = 85 }
                else {
                    let shared = queryGrams.intersection(name.grams)
                    if shared.count >= 2 {
                        let hits = total(shared)
                        let a = hits/queryWeight, b = hits/max(total(name.grams),1)
                        if max(a,b) >= 0.35 && min(a,b) >= 0.12 {
                            points = min(90,Int(65*max(a,b)+25*min(a,b)))
                        }
                    }
                }
                if points > score { score = points; evidence = origin+"与“"+name.label+"”"+(points >= archiveMatchThreshold ? "匹配" : "部分相似，请核对") }
            }
            let hits = entry.keywords.filter { normalized.contains($0) }
            if !hits.isEmpty {
                score = max(score,min(110,70+20*(hits.count-1))); evidence = origin+"关键词："+hits.prefix(3).joined(separator:"、")
            }
            for code in entry.identifiers {
                let pattern = "(?<![A-Za-z0-9_./—-])"+NSRegularExpression.escapedPattern(for:code)+"(?![A-Za-z0-9_./—-])"
                if input.range(of:pattern,options:[.regularExpression,.caseInsensitive]) != nil { score = max(score,120); evidence = origin+"项目编号："+code }
            }
            guard score > 0 else { return nil }
            return ProjectArchiveChoice(project:entry.project,score:score,evidence:evidence)
        }.sorted { $0.score == $1.score ? $0.project.name.localizedStandardCompare($1.project.name) == .orderedAscending : $0.score > $1.score }
    }
    func search(_ query: String) -> [Project] {
        let tokens = FilenameQuery(query).tokens
        let fuzzy = choices(input:query,origin:"搜索词")
        let direct = entries.filter { entry in
            let name = FilenameQuery.normalize((entry.project.group ?? "")+" "+entry.project.name+" "+entry.project.keywords)
            return tokens.allSatisfy { name.contains($0) }
        }.map(\.project)
        let directIDs = Set(direct.map(\.path))
        return direct + fuzzy.map(\.project).filter { !directIDs.contains($0.path) }
    }
}
func clearArchiveMatch(_ choices: [ProjectArchiveChoice]) -> Bool {
    guard let first = choices.first, first.score >= archiveMatchThreshold else { return false }
    return choices.count == 1 || first.score-choices[1].score >= 20
}
func mergedArchiveChoices(_ choices: [[ProjectArchiveChoice]]) -> [ProjectArchiveChoice] {
    var scores: [String:Int] = [:]; var projects: [String:Project] = [:]; var evidence: [String:[String]] = [:]
    for row in choices {
        for choice in row.prefix(8) where choice.score >= archiveMatchThreshold {
            scores[choice.id,default:0] += choice.score; projects[choice.id] = choice.project
            if !(evidence[choice.id] ?? []).contains(choice.evidence) { evidence[choice.id,default:[]].append(choice.evidence) }
        }
    }
    return scores.map { ProjectArchiveChoice(project:projects[$0.key]!,score:$0.value,evidence:(evidence[$0.key] ?? []).prefix(2).joined(separator:"；")) }.sorted {
        $0.score == $1.score ? $0.project.name.localizedStandardCompare($1.project.name) == .orderedAscending : $0.score > $1.score
    }
}

// Kept independent of Store and the filesystem so ordering/IO budgets can be tested directly.
func matchArchiveRows(_ rows: [BrowserRow], index: ArchiveProjectIndex, token: IndexCancellation,
                      readOpening: (BrowserRow) -> String, update: ([ProjectArchiveChoice],Bool,String) -> Void) {
    guard !token.isCancelled else { return }
    var results = rows.map { index.choices(input:URL(fileURLWithPath:$0.title).deletingPathExtension().lastPathComponent,origin:"文件名").filter{$0.score >= archiveMatchThreshold} }
    let pending = results.indices.filter { !clearArchiveMatch(results[$0]) }
    update(mergedArchiveChoices(results),pending.isEmpty,pending.isEmpty ? "已按文件名匹配 · 请选择项目后确认归档" : "文件名匹配不明确，仅补读待归档文件的前两页…")
    for (offset,i) in pending.enumerated() {
        guard !token.isCancelled else { return }
        let text = readOpening(rows[i])
        guard !token.isCancelled else { return }
        // Apply the same confidence floor before the content bonus: a weak
        // resemblance must not become a recommendation merely by adding 30.
        let content = index.choices(input:text,origin:"前两页").filter{$0.score >= archiveMatchThreshold}
        if !content.isEmpty {
            // Opening-page evidence takes precedence over a weak or misleading filename.
            let contentIDs = Set(content.map(\.id))
            results[i] = content.map { ProjectArchiveChoice(project:$0.project,score:$0.score+30,evidence:$0.evidence) }
                + results[i].filter { !contentIDs.contains($0.id) }.map { ProjectArchiveChoice(project:$0.project,score:$0.score/2,evidence:$0.evidence) }
        }
        let done = offset == pending.count-1
        let choices = mergedArchiveChoices(results)
        update(choices,done,done ? (choices.isEmpty ? "文件名及前两页未找到明确匹配，可输入关键词手动选择" : "已结合文件名与前两页匹配 · 请选择项目后确认归档") : "正在补读待归档文件前两页（\(offset+1)/\(pending.count)）…")
    }
}
