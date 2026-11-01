import Foundation
import AppKit
import PDFKit
import Vision

func namingTitleWhitespace(_ value:String) -> String {
    var text = value.replacingOccurrences(of:"(?<=[\\p{Han}])\\s*\\r?\\n\\s*(?=[\\p{Han}])",with:"",options:.regularExpression)
    text = text.replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression)
    return text.trimmingCharacters(in:.whitespacesAndNewlines)
}
func cleanNamingTitle(_ value:String) -> String {
    var text = namingTitleWhitespace(value)
    text = text.replacingOccurrences(of:"[/\\\\:：*?\"<>|\\x00-\\x1F\\x7F]",with:"-",options:.regularExpression)
    return text.trimmingCharacters(in:CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn:".")))
}
struct NamingTitleLine {
    var text:String
    var prominent = false
    var joinsNext = false
}
struct NamingTitlePage {
    let index:Int
    let lines:[NamingTitleLine]
}
private let namingGenericLabels:Set<String> = ["目录","目 录","正文","封面","技术方案","招标文件","投标文件","响应文件","应答文件","商务部分","技术部分","方案","项目名称","采购人","供应商","序号","名称","单位","数量","单价","金额","日期","备注","合计","总计","单位名称"]
func usableNamingTitle(_ raw:String) -> Bool {
    let value = cleanNamingTitle(raw)
    return value.count >= 2 && value.count <= 160 && !namingGenericLabels.contains(value) &&
        value.range(of:"^[0-9年月日\\s./_-]+$",options:.regularExpression) == nil &&
        value.range(of:"^(?:第[一二三四五六七八九十0-9]+[章节条]|项目编号|采购编号|招标编号|法定代表人|编制单位|编制日期|联系人|联系电话|根据|本项目|本文件|本承诺书|本方案|被审查文件|审查对象|引用文件|参考文献)|^(?:单位名称|采购人|供应商|投标人|日期|地址|邮编)[：:]",options:.regularExpression) == nil
}
func looksLikeNamingTitle(_ value:String) -> Bool {
    guard usableNamingTitle(value), value.count >= 4, !value.contains("。"), !value.contains("；"), !value.contains("，") else { return false }
    if value.range(of:"(?:方案|报告|计划|规划|清单|明细|汇总|统计|报价|预算|合同|协议|通知|公告|函|承诺书|说明书|手册|规范|标准|要求|指南|记录|试卷|论文|设计|分析|总结|纪要|申请书|申请表|台账|表|建议书|项目|工程|大事记)$",options:.regularExpression) != nil { return true }
    let words = value.split(separator:" ").filter { $0.contains(where:{$0.isLetter}) }
    return words.count >= 2 && words.count <= 12 && words.allSatisfy { word in
        ["of","and","the","for","to","in"].contains(word.lowercased()) || word.first?.isUppercase == true
    }
}
func namingTitleSuggestions(pages:[NamingTitlePage],source:String) -> [Suggestion] {
    let titleLabels = ["文件名称","文件标题","文档标题","标题","方案名称","报告名称","合同名称","协议名称","表名","报表名称","论文题目","题目"]
    let projectLabels = ["项目名称","工程名称","采购项目名称","招标项目名称","项目全称"]
    var ranked:[(String,String,Int)] = []
    for page in pages.prefix(2) {
        let lines = page.lines
        for (index,line) in lines.prefix(40).enumerated() {
            let raw = line.text.trimmingCharacters(in:.whitespacesAndNewlines)
            let pageLabel = page.index == 0 ? "首页" : "第2页"
            var explicitField = false
            for label in titleLabels+projectLabels {
                let pattern = "^"+label.map { NSRegularExpression.escapedPattern(for:String($0)) }.joined(separator:"\\s*")+"\\s*[：:]\\s*"
                let range = raw.range(of:pattern,options:.regularExpression)
                guard range != nil || raw.replacingOccurrences(of:" ",with:"") == label else { continue }
                explicitField = true
                var value = range.map { String(raw[$0.upperBound...]) } ?? ""
                if value.isEmpty && index+1 < lines.count { value = lines[index+1].text }
                if usableNamingTitle(value) { ranked.append((cleanNamingTitle(value),pageLabel+"明确标题 · "+source,page.index*100+(projectLabels.contains(label) ? 20 : 0))) }
            }
            let text = raw.replacingOccurrences(of:"^#{1,6}\\s+",with:"",options:.regularExpression)
            let metadata = text.contains("：") || text.contains(":")
            if !explicitField, usableNamingTitle(text), !text.hasSuffix("有限公司"), !text.hasSuffix("委员会"),
               line.prominent || (!metadata && looksLikeNamingTitle(text)) {
                ranked.append((cleanNamingTitle(text),pageLabel+"标题 · "+source,page.index*100+(line.prominent ? 5 : 10)+min(index,8)))
            }
            if line.joinsNext, index+1 < lines.count, !metadata {
                var joined = text;var nextIndex = index+1
                while nextIndex < min(lines.count,index+4), lines[nextIndex-1].joinsNext {
                    let next = lines[nextIndex].text
                    guard !next.contains("："), !next.contains(":"), !joined.contains("。"), !next.contains("。") else { break }
                    let separator = joined.last?.isASCII == true && next.first?.isASCII == true ? " " : ""
                    joined += separator+next;nextIndex += 1
                }
                if nextIndex > index+1, usableNamingTitle(joined) { ranked.append((cleanNamingTitle(joined),pageLabel+"连续标题 · "+source,page.index*100+1+min(index,30))) }
            }
        }
    }
    var seen = Set<String>()
    return ranked.enumerated().sorted { $0.element.2 == $1.element.2 ? $0.offset < $1.offset : $0.element.2 < $1.element.2 }.map(\.element).compactMap { title,evidence,_ in
        guard seen.insert(FilenameQuery.normalize(title)).inserted else { return nil }
        return Suggestion(name:title,evidence:evidence)
    }.prefix(8).map{$0}
}
func textNamingPages(_ text:String) -> [NamingTitlePage] {
    text.components(separatedBy:"\u{000C}").prefix(2).enumerated().map { index,page in
        NamingTitlePage(index:index,lines:page.components(separatedBy:.newlines).map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }.filter{!$0.isEmpty}.prefix(40).map { NamingTitleLine(text:$0) })
    }
}
func namingOCRTitleLines(_ image:CGImage,token:IndexCancellation) -> [NamingTitleLine] {
    guard !token.isCancelled else { return [] }
    let request = VNRecognizeTextRequest();request.recognitionLanguages = ["zh-Hans","en-US"];request.recognitionLevel = .accurate;request.usesLanguageCorrection = true
    do { try VNImageRequestHandler(cgImage:image,options:[:]).perform([request]) } catch { return [] }
    guard !token.isCancelled else { return [] }
    let observations = Array((request.results ?? []).sorted {
        abs($0.boundingBox.midY-$1.boundingBox.midY) > 0.012 ? $0.boundingBox.midY > $1.boundingBox.midY : $0.boundingBox.minX < $1.boundingBox.minX
    }.prefix(40))
    let heights = observations.map{$0.boundingBox.height}.sorted(), maximum = heights.max() ?? 0
    let median = heights.isEmpty ? 0 : heights[heights.count/2]
    var lines = observations.map { item in
        NamingTitleLine(text:item.topCandidates(1).first?.string ?? "",prominent:item.boundingBox.height >= maximum*0.85 && maximum >= max(0.018,median*1.2))
    }
    if lines.count > 1 {
        for index in 0..<(lines.count-1) where lines[index].prominent && lines[index+1].prominent {
            let a = observations[index].boundingBox,b = observations[index+1].boundingBox
            lines[index].joinsNext = abs(a.midX-b.midX) < 0.1 && abs(a.midY-b.midY) < max(a.height,b.height)*2.8
        }
    }
    return lines
}
func recognizeNamingTitles(_ file:FileItem,token:IndexCancellation) -> [Suggestion] {
    guard !token.isCancelled else { return [] }
    if file.ext == "xlsx" { return spreadsheetNamingTitles(file,token:token) }
    if ["docx","doc","rtf"].contains(file.ext) {
        let opening = wordNamingOpening(file,token:token)
        let titles = namingTitleSuggestions(pages:textNamingPages(opening.text),source:file.name)
        return opening.paginated ? titles : titles.map {
            Suggestion(name:$0.name,evidence:$0.evidence.replacingOccurrences(of:"首页",with:"Word 开头节选").replacingOccurrences(of:"第2页",with:"Word 开头节选"))
        }
    }
    if file.ext == "pdf", let pdf = PDFDocument(url:file.url) {
        guard !pdf.isLocked else { return [] }
        var pages:[NamingTitlePage] = []
        for index in 0..<min(pdf.pageCount,2) {
            guard !token.isCancelled, let page = pdf.page(at:index) else { break }
            let text = page.string ?? ""
            if text.trimmingCharacters(in:.whitespacesAndNewlines).count < 15 {
                let image = page.thumbnail(of:NSSize(width:1400,height:1800),for:.mediaBox)
                if let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) {
                    let lines = namingOCRTitleLines(cg,token:token)
                    pages.append(NamingTitlePage(index:index,lines:lines))
                }
                continue
            }
            let selections = Array((page.selection(for:page.bounds(for:.mediaBox))?.selectionsByLine() ?? []).sorted { a,b in
                let x = a.bounds(for:page), y = b.bounds(for:page)
                return abs(x.maxY-y.maxY) > 4 ? x.maxY > y.maxY : x.minX < y.minX
            }.prefix(40))
            var fonts:[CGFloat] = []
            for selection in selections {
                var size:CGFloat = 0
                if let value = selection.attributedString {
                    value.enumerateAttribute(.font,in:NSRange(location:0,length:value.length)) { font,_,_ in size = max(size,(font as? NSFont)?.pointSize ?? 0) }
                }
                fonts.append(size)
            }
            let ordered = fonts.filter{$0 > 0}.sorted(), median = ordered.isEmpty ? 0 : ordered[ordered.count/2]
            let largest = fonts.max() ?? 0
            var lines = selections.enumerated().map { i,selection in
                NamingTitleLine(text:selection.string ?? "",prominent:fonts[i] >= largest*0.9 && largest >= 18 && (largest >= median*1.15 || selections.count <= 8))
            }
            if lines.count > 1 {
                for i in 0..<(lines.count-1) where lines[i].prominent && lines[i+1].prominent {
                    let a = selections[i].bounds(for:page), b = selections[i+1].bounds(for:page)
                    lines[i].joinsNext = abs(a.midX-b.midX) < 40 && abs(a.midY-b.midY) < max(a.height,b.height)*2.5
                }
            }
            pages.append(NamingTitlePage(index:index,lines:lines.isEmpty ? (textNamingPages(text).first?.lines ?? []) : lines))
        }
        return namingTitleSuggestions(pages:pages,source:file.name)
    }
    if ["png","jpg","jpeg","heic","tiff","tif"].contains(file.ext),let page = try? loadNamingPreview(NamingTarget(path:file.path,folder:false,projectPath:file.project),token:token).first {
        return namingTitleSuggestions(pages:[NamingTitlePage(index:0,lines:namingOCRTitleLines(page.image,token:token))],source:file.name)
    }
    return namingTitleSuggestions(pages:textNamingPages(extractForNaming(file,token:token)),source:file.name)
}

@MainActor extension Store {
    func titleProposedName(_ title:String,target:NamingTarget,date:Date,month:Int? = nil) -> String {
        let stem = cleanNamingTitle(smartNamingLiteralStem(title,target:target))
        guard !stem.isEmpty else { return "" }
        let prefix = namingFormat(for:target) == .category ? cleanNamingTitle(smartNamingCategory(for:target,recognizedName:stem)) : smartNamingPrefix(for:target,date:date,month:month)
        let value = prefix.isEmpty ? stem : prefix+" "+stem
        return target.folder ? value : proposedName(base:value,month:1,folder:false,original:target.path)
    }
}
