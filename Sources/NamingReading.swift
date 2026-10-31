import Foundation
import PDFKit
import AppKit

// Naming text is intentionally separate from the full text cache used by archiving.
// Stop after the cover and second page when a usable identity is already available.
func namingPageText(count: Int, cancelled: () -> Bool, page: (Int) -> String, enough: (String) -> Bool) -> String {
    var text = ""
    for i in 0..<count {
        if cancelled() { break }
        text += (text.isEmpty ? "" : "\n\u{000C}\n") + page(i)
        if i >= 1 && enough(text) { break }
        if text.count >= 100000 { break }
    }
    return String(text.prefix(100000))
}

private final class NamingWordReader: NSObject, XMLParserDelegate {
    var text = ""; var pages = 1; var paragraphs = 0; var inText = false; var paragraph = ""
    var hasPageMarkers = false
    let cancelled: () -> Bool; let enough: (String) -> Bool
    init(cancelled: @escaping () -> Bool, enough: @escaping (String) -> Bool) { self.cancelled = cancelled; self.enough = enough }
    func boundary(_ parser: XMLParser) {
        // Break occurs before the next page: never consume page 3 if pages 1–2 suffice.
        if pages >= 2 && enough(text + "\n" + paragraph) { text += "\n" + paragraph; paragraph = ""; parser.abortParsing(); return }
        pages += 1; paragraph += "\n\u{000C}\n"
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String:String]) {
        if cancelled() || text.count > 100000 { parser.abortParsing(); return }
        if elementName == "w:t" { inText = true }
        if elementName == "w:tab" { paragraph += " " }
        if elementName == "w:lastRenderedPageBreak" || (elementName == "w:br" && attributes["w:type"] == "page") { boundary(parser) }
        if elementName == "w:br" && attributes["w:type"] != "page" { paragraph += "\n" }
        if elementName == "w:pageBreakBefore" && attributes["w:val"] != "0" && attributes["w:val"] != "false" { boundary(parser) }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { paragraph += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "w:t" { inText = false }
        if elementName == "w:p" {
            text += "\n" + paragraph; paragraph = ""; paragraphs += 1
            // Unpaginated Word has no reliable physical pages. Use a bounded opening excerpt.
            if !hasPageMarkers && (paragraphs >= 60 || text.count >= 6000) && enough(text) { parser.abortParsing() }
        }
    }
}

func extractForNaming(_ file: FileItem, token: IndexCancellation) -> String {
    func enough(_ text: String) -> Bool { var f = file; f.text = text; return hasNamingIdentity(f) }
    if file.ext == "pdf", let pdf = PDFDocument(url:file.url) {
        return namingPageText(count:pdf.pageCount,cancelled:{ token.isCancelled },page:{ i in
            guard let page = pdf.page(at:i) else { return "" }
            let text = page.string ?? ""
            if text.trimmingCharacters(in:.whitespacesAndNewlines).count >= 15 { return text }
            let image = page.thumbnail(of:NSSize(width:1400,height:1800),for:.mediaBox)
            guard let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return text }
            return text + "\n" + ocr(cg)
        },enough:enough)
    }
    if file.ext == "docx" {
        let xml = run("/usr/bin/unzip",["-p",file.path,"word/document.xml"])
        if !xml.isEmpty, !token.isCancelled {
            let reader = NamingWordReader(cancelled:{ token.isCancelled },enough:enough)
            reader.hasPageMarkers = xml.contains("lastRenderedPageBreak") || xml.range(of:"w:type=[\"']page[\"']|w:pageBreakBefore",options:.regularExpression) != nil
            let parser = XMLParser(data:Data(xml.utf8)); parser.delegate = reader; parser.shouldResolveExternalEntities = false
            _ = parser.parse()
            if !reader.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return reader.text }
        }
    }
    if token.isCancelled { return "" }
    let text = extract(file.url)
    // Legacy Word/text formats may expose form-feed page separators; otherwise inspect chunks.
    let pages = text.components(separatedBy:"\u{000C}")
    if pages.count > 1 { return namingPageText(count:pages.count,cancelled:{ token.isCancelled },page:{ pages[$0] },enough:enough) }
    let characters = Array(text)
    let chunks = stride(from:0,to:characters.count,by:3000).map { String(characters[$0..<min($0+3000,characters.count)]) }
    return namingPageText(count:chunks.count,cancelled:{ token.isCancelled },page:{ chunks[$0] },enough:enough)
}

func namingReadingTest(root: URL) throws {
    let file = FileItem(path:"/project/响应文件.pdf",project:"/project",text:"",size:1,date:Date())
    func enough(_ text: String) -> Bool { var f = file; f.text = text; return hasNamingIdentity(f) }
    var read: [Int] = []
    let cover = ["响应文件", "项目名称：前两页智慧园区建设项目", "项目名称：后文其他示例项目"]
    let first = namingPageText(count:3,cancelled:{false},page:{ read.append($0); return cover[$0] },enough:enough)
    try verify(read == [0,1] && !first.contains("后文其他"),"Stop after first two pages when project is found")
    read = []
    let later = ["响应文件", "目录", "项目名称：第三页智慧园区建设项目", "后面不必读取"]
    let fallback = namingPageText(count:4,cancelled:{false},page:{ read.append($0); return later[$0] },enough:enough)
    try verify(read == [0,1,2] && fallback.contains("第三页"),"Continue only when first two pages lack identity")
    read = []
    _ = namingPageText(count:3,cancelled:{true},page:{ read.append($0); return cover[$0] },enough:enough)
    try verify(read.isEmpty,"Cancellation must prevent further reads")
    // Exercise PDFKit extraction, rather than just the staged-reading decision.
    let url = root.appendingPathComponent("naming-pages.pdf"); var box = CGRect(x:0,y:0,width:600,height:400)
    if let context = CGContext(url as CFURL,mediaBox:&box,nil) {
        for text in cover {
            context.beginPDFPage(nil); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
            (text as NSString).draw(at:NSPoint(x:30,y:200),withAttributes:[.font:NSFont.systemFont(ofSize:16)])
            NSGraphicsContext.restoreGraphicsState(); context.endPDFPage()
        }
        context.closePDF()
    }
    var pdf = file; pdf.path = url.path
    let text = extractForNaming(pdf,token:IndexCancellation())
    try verify(text.contains("前两页") && !text.contains("后文其他"),"Real PDF extraction must not include later-page examples")
    func wordRead(_ pageTexts: [String]) -> String {
        let xml = "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>" + pageTexts.map { "<w:p><w:r><w:t>"+$0+"</w:t></w:r></w:p>" }.joined(separator:"<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>") + "</w:body></w:document>"
        let reader = NamingWordReader(cancelled:{false},enough:enough); reader.hasPageMarkers = true
        let parser = XMLParser(data:Data(xml.utf8)); parser.delegate = reader; _ = parser.parse(); return reader.text
    }
    try verify(!wordRead(cover).contains("后文其他"),"Word page breaks preserve cover-first extraction")
    try verify(wordRead(later).contains("第三页") && !wordRead(later).contains("后面不必"),"Word missing identity falls back to later page")
    print("PASS: naming reads pages 1–2 first, stops on identity, falls back to later pages, PDFKit and Word page boundaries, cancellation")
}
