import Foundation

struct CategoryRule: Codable, Equatable {
    enum Origin: String, Codable { case automatic, edited, builtIn }
    enum Scope: String, Codable, CaseIterable { case all = "文件和文件夹", files = "仅文件", folders = "仅文件夹" }
    var keywords: [String] = []
    var excludedKeywords: [String] = []
    var extensions: [String] = []
    var enabled = true
    var scope: Scope = .all
    var priority = 0
    var origin: Origin = .automatic
    var generatedFor = ""
    var legacyCategory: String? = nil
    var summary: String {
        if !enabled { return "自动分类已关闭" }
        if legacyCategory == DocumentCategory.other.rawValue { return "接收未匹配或规则冲突的条目" }
        let terms = Array(keywords.prefix(4)) + Array(extensions.prefix(3)).map { "."+$0 }
        return terms.isEmpty ? "没有匹配条件" : terms.joined(separator:"、") + (keywords.count+extensions.count > terms.count ? "…" : "")
    }
    static func terms(_ text:String) -> [String] {
        unique(text.components(separatedBy:CharacterSet(charactersIn:",，、;；\n")).map { $0.trimmingCharacters(in:.whitespacesAndNewlines) })
    }
    static func unique(_ values:[String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert(FilenameQuery.normalize($0)).inserted }
    }
    func samePositiveConditions(as other:CategoryRule) -> Bool {
        Set(keywords.map(FilenameQuery.normalize)) == Set(other.keywords.map(FilenameQuery.normalize)) && Set(extensions.map{$0.lowercased()}) == Set(other.extensions.map{$0.lowercased()})
    }
    func sameMatchingConditions(as other:CategoryRule) -> Bool {
        samePositiveConditions(as:other) && Set(excludedKeywords.map(FilenameQuery.normalize)) == Set(other.excludedKeywords.map(FilenameQuery.normalize)) && scope == other.scope && priority == other.priority
    }
}

enum CategoryRuleGenerator {
    private struct Concept {
        let names: [String]; let words: [String]; let extensions: [String]
        init(_ names:[String],_ words:[String],_ extensions:[String] = []) { self.names = names; self.words = words; self.extensions = extensions }
    }
    // Offline vocabulary expansion. Unknown names keep literal, conservative matching.
    private static let concepts: [Concept] = [
        Concept(["发票","票据","税票"],["发票","收据","税票","invoice","invoices","receipt","receipts"]),
        Concept(["合同","协议"],["合同","协议","补充协议","contract","contracts","agreement","agreements"]),
        Concept(["报销","报账"],["报销","报账","差旅费","费用申请","reimbursement","expense claim"]),
        Concept(["财务","财会"],["财务","发票","收据","付款","对账","结算","invoice","receipt","payment"]),
        Concept(["报价","价格清单"],["报价","报价单","报价表","价格清单","quotation","quote"]),
        Concept(["售前"],["售前","售前材料","售前资料","presales","pre-sales"]),
        Concept(["售中"],["售中","售中材料","售中资料"]),
        Concept(["售后","客服"],["售后","保修","维修","客服","售后服务","after-sales","warranty"]),
        Concept(["交付","验收"],["交付","验收","移交","交接","竣工","delivery","acceptance","handover"]),
        Concept(["方案","建议书"],["方案","建议书","解决方案","proposal","solution"]),
        Concept(["招标","采购文件","招采"],["招标文件","采购文件","招采需求","招标公告","采购公告","rfp","rfq","tender"]),
        Concept(["投标","响应材料","应答"],["投标","响应文件","应答文件","商务标","技术标","bid response"]),
        Concept(["设计","设计稿"],["设计","设计稿","原型","效果图","design","mockup","prototype"]),
        Concept(["素材","资源库"],["素材","贴图","纹理","图标","配图","asset","assets","texture","icon"]),
        Concept(["需求"],["需求","需求说明","需求分析","requirement","requirements","brief"]),
        Concept(["报告","汇报"],["报告","汇报","调研报告","分析报告","report","reports"]),
        Concept(["会议","纪要"],["会议","纪要","议程","meeting","minutes","agenda"]),
        Concept(["计划","排期"],["计划","排期","进度表","日程","schedule","planning","roadmap"]),
        Concept(["人事","员工"],["人事","员工","考勤","入职","离职","employee","personnel"]),
        Concept(["简历","招聘"],["简历","招聘","求职","面试","resume","curriculum vitae","recruitment"]),
        Concept(["学习","课程","教学"],["学习","课程","讲义","课件","作业","教材","lesson","lecture","homework"]),
        Concept(["论文","文献"],["论文","文献","期刊","学位论文","thesis","dissertation","journal"]),
        Concept(["证件","证照"],["证件","证照","身份证","护照","户口本","驾驶证","passport","license"]),
        Concept(["图片","照片","摄影"],["图片","照片","摄影","photo","photos","image","images"],["jpg","jpeg","png","heic","webp","gif","tif","tiff","bmp","raw"]),
        Concept(["视频","录像","影片"],["视频","录像","影片","video","movie"],["mp4","mov","m4v","avi","mkv","webm"]),
        Concept(["音频","音乐","录音"],["音频","音乐","录音","audio","music","recording"],["mp3","wav","m4a","aac","flac","aiff"]),
        Concept(["表格","excel"],["表格","统计表","excel","spreadsheet"],["xlsx","xls","csv","tsv","numbers"]),
        Concept(["演示","幻灯片","ppt"],["演示","幻灯片","presentation"],["pptx","ppt","key"]),
        Concept(["pdf"],["pdf"],["pdf"]),
        Concept(["压缩包","压缩文件"],["压缩包","压缩文件","archive"],["zip","rar","7z","tar","gz"]),
        Concept(["代码","源码","程序"],["代码","源码","程序","source code"],["swift","py","js","ts","tsx","jsx","java","c","cpp","h","rs","go"])
    ]
    static func generate(name:String,legacyID:String? = nil) -> CategoryRule {
        if let id = legacyID, DocumentCategory.allCases.contains(where:{$0.rawValue == id}) {
            var rule = CategoryRule(origin:.builtIn,generatedFor:name,legacyCategory:id)
            switch id {
            case "方案": rule.keywords = ["方案","建议书","解决方案"]
            case "投标文件": rule.keywords = ["投标","响应文件","应答文件","报价","商务响应","技术响应","商务标","技术标"]
            case "招标文件": rule.keywords = ["招标文件","采购文件","采购需求","磋商文件","谈判文件","比选文件","询价文件","征集文件","招标公告","采购公告","招标答疑","招标澄清","招标补遗","竞争性磋商","招采文件","招采需求","招标需求","投标邀请","采购邀请","招标邀请","征求建议书","rfp","rfq"]
            default: break
            }
            return rule
        }
        let label = name.trimmingCharacters(in:.whitespacesAndNewlines)
        var rule = CategoryRule(keywords:[label],generatedFor:label)
        let normalized = FilenameQuery.normalize(label)
        // A negated/unclear name must not expand to the category it excludes.
        if !["非","不含","排除"].contains(where:normalized.hasPrefix) {
            let matching = concepts.filter { $0.names.contains(where:{ normalized.contains(FilenameQuery.normalize($0)) }) }
            let broadDomains = Set(["财务","人事","设计"])
            let hasSpecificConcept = matching.contains { !broadDomains.contains($0.names[0]) }
            for concept in matching where !hasSpecificConcept || !broadDomains.contains(concept.names[0]) {
                rule.keywords += concept.words; rule.extensions += concept.extensions
            }
            for suffix in ["相关资料","相关文件","文件资料","资料","材料","文档","文件","档案"] where label.hasSuffix(suffix) {
                let stem = String(label.dropLast(suffix.count)).trimmingCharacters(in:.whitespacesAndNewlines)
                if stem.count >= 2 && !["项目","其他","相关","所有","全部","通用","自定义"].contains(stem) { rule.keywords.append(stem) }
                break
            }
        }
        rule.keywords = CategoryRule.unique(rule.keywords); rule.extensions = CategoryRule.unique(rule.extensions)
        return rule
    }
}

private struct CategoryTermMatcher {
    let text: String
    let expression: NSRegularExpression?
    init(_ term:String) {
        text = FilenameQuery.normalize(term)
        if text.unicodeScalars.allSatisfy({ $0.isASCII }) && text.unicodeScalars.contains(where:{ CharacterSet.letters.contains($0) }) {
            expression = try? NSRegularExpression(pattern:"(?<![a-z0-9])"+NSRegularExpression.escapedPattern(for:text)+"(?![a-z0-9])")
        } else { expression = nil }
    }
    func matches(_ value:String) -> Bool {
        guard !text.isEmpty else { return false }
        if let expression { return expression.firstMatch(in:value,range:NSRange(value.startIndex...,in:value)) != nil }
        return value.contains(text)
    }
}
private struct CategoryRuleMatcher {
    let rule: CategoryRule
    private let terms: [CategoryTermMatcher]
    private let exclusions: [CategoryTermMatcher]
    private let seed: CategoryTermMatcher
    init(_ rule:CategoryRule) {
        self.rule = rule; terms = rule.legacyCategory == nil ? rule.keywords.map(CategoryTermMatcher.init) : []
        exclusions = rule.excludedKeywords.map(CategoryTermMatcher.init); seed = CategoryTermMatcher(rule.generatedFor)
    }
    func score(_ row:BrowserRow,name:String,legacy:String?) -> Int? {
        guard rule.enabled, rule.scope != .files || !row.folder, rule.scope != .folders || row.folder,
              !exclusions.contains(where:{$0.matches(name)}) else { return nil }
        if let category = rule.legacyCategory {
            return category != "其他" && legacy == category ? rule.priority*1000+100 : nil
        }
        let matching = terms.filter { $0.matches(name) }
        if let longest = matching.map(\.text).max(by:{$0.count < $1.count}) {
            let stem = row.folder ? name : FilenameQuery.normalize(URL(fileURLWithPath:row.title).deletingPathExtension().lastPathComponent)
            let exact = matching.contains { $0.text == stem }
            return rule.priority*1000+(exact ? 400 : 200)+min(longest.count,80)+(seed.matches(name) ? 40 : 0)
        }
        if !row.folder && rule.extensions.contains(where:{ name.hasSuffix("."+$0.lowercased()) }) { return rule.priority*1000+20 }
        return nil
    }
}
struct CategoryClassifier {
    private let categories: [WorkspaceCategory]
    private let matchers: [CategoryRuleMatcher]
    init(categories:[WorkspaceCategory]) { self.categories = categories; matchers = categories.map { CategoryRuleMatcher($0.effectiveRule) } }
    func resolve(_ row:BrowserRow,assignments:[String:CategoryAssignment]) -> WorkspaceCategory? {
        if let assignment = assignments[row.id], let category = categories.first(where:{$0.id == assignment.categoryID}), assignment.identity == fileIdentity(row.id) { return category }
        let fallback = categories.first(where:{$0.id == DocumentCategory.other.rawValue}) ?? categories.first
        let name = FilenameQuery.normalize(row.title)
        let legacy = matchers.contains(where:{$0.rule.legacyCategory != nil}) ? categoryForEntry(row).rawValue : nil
        let candidates = categories.indices.compactMap { index -> (WorkspaceCategory,Int)? in
            guard let score = matchers[index].score(row,name:name,legacy:legacy) else { return nil }
            return (categories[index],score)
        }
        guard let best = candidates.map(\.1).max() else { return fallback }
        let winners = candidates.filter { $0.1 == best }
        return winners.count == 1 ? winners[0].0 : fallback
    }
}
func categoryRuleScore(_ rule:CategoryRule,row:BrowserRow) -> Int? {
    CategoryRuleMatcher(rule).score(row,name:FilenameQuery.normalize(row.title),legacy:rule.legacyCategory == nil ? nil : categoryForEntry(row).rawValue)
}

@MainActor extension Store {
    @discardableResult func saveCategoryRule(id:String,rule:CategoryRule) -> Bool {
        var categories = workspaceCategories
        guard let index = categories.firstIndex(where:{$0.id == id}) else { error = "该分类已不存在，请重新选择。"; return false }
        if let problem = rule.validationError(categoryID:id) { error = problem; return false }
        categories[index].rule = rule
        var updated = settings; updated.categories = categories
        do {
            try fm.createDirectory(at:stateURL.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(updated).write(to:stateURL,options:.atomic)
            settings = updated; return true
        } catch { self.error = "分类规则未保存："+error.localizedDescription; return false }
    }
}
