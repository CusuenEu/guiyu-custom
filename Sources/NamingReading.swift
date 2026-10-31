import Foundation
import PDFKit
import AppKit

let unpaginatedNamingCharacterLimit = 300

// Naming text is intentionally separate from the full text cache used by archiving.
// Naming has a hard two-page budget, including when no title is found.
func namingPageText(count: Int, cancelled: () -> Bool, page: (Int) -> String, enough: (String) -> Bool) -> String {
    var text = ""
    for i in 0..<min(count,2) {
        if cancelled() { break }
        text += (text.isEmpty ? "" : "\n\u{000C}\n") + page(i)
        if text.count >= 100000 { break }
    }
    return String(text.prefix(100000))
}

private final class NamingWordReader: NSObject, XMLParserDelegate {
    var text = ""; var pages = 1; var paragraphs = 0; var inText = false; var paragraph = ""
    var hasPageMarkers = false
    var openingOnly = false
    var openingCharacterLimit:Int? = nil
    var preserveSoftWrappedTitles = false
    var currentParagraph:String {
        guard preserveSoftWrappedTitles else { return paragraph }
        // A w:br inside one Word paragraph is a soft line break, not another
        // paragraph/title. Preserve real page delimiters independently.
        return paragraph.components(separatedBy:"\u{000C}").map(namingTitleWhitespace).joined(separator:"\n\u{000C}\n")
    }
    private var boundaryKinds = Set<String>()
    private var textSinceBoundary = false
    let cancelled: () -> Bool; let enough: (String) -> Bool
    init(cancelled: @escaping () -> Bool, enough: @escaping (String) -> Bool) { self.cancelled = cancelled; self.enough = enough }
    func boundary(_ parser: XMLParser,kind:String) {
        if !textSinceBoundary, !boundaryKinds.isEmpty, !boundaryKinds.contains(kind) { boundaryKinds.insert(kind); return }
        if kind == "before", pages == 1, (text+paragraph).trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return }
        // Break occurs before the next page: opening-only readers never consume page 3.
        if pages >= 2 && (openingOnly || enough(text + "\n" + paragraph)) { text += "\n" + currentParagraph; paragraph = ""; parser.abortParsing(); return }
        pages += 1; paragraph += "\n\u{000C}\n"; boundaryKinds = [kind]; textSinceBoundary = false
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String:String]) {
        if cancelled() || text.count+paragraph.count >= (openingCharacterLimit ?? (openingOnly ? 12000 : 100000)) { parser.abortParsing(); return }
        if elementName == "w:t" { inText = true }
        if elementName == "w:tab" { paragraph += " " }
        if elementName == "w:lastRenderedPageBreak" { boundary(parser,kind:"rendered") }
        if elementName == "w:br" && attributes["w:type"] == "page" { boundary(parser,kind:"manual") }
        if elementName == "w:br" && attributes["w:type"] != "page" { paragraph += "\n" }
        if elementName == "w:pageBreakBefore" && attributes["w:val"] != "0" && attributes["w:val"] != "false" { boundary(parser,kind:"before") }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText {
            if let limit = openingCharacterLimit { paragraph += string.prefix(max(0,limit-text.count-paragraph.count)) }
            else { paragraph += string }
            if !string.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { textSinceBoundary = true }
        }
        if openingOnly && text.count+paragraph.count >= (openingCharacterLimit ?? 12000) { parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "w:t" { inText = false }
        if elementName == "w:p" {
            text += "\n" + currentParagraph; paragraph = ""; paragraphs += 1
            // Unpaginated Word has no reliable physical pages. Use a bounded opening excerpt.
            if let limit = openingCharacterLimit {
                if text.count >= limit { parser.abortParsing() }
            } else if !hasPageMarkers && (paragraphs >= 60 || text.count >= 6000) && (openingOnly || enough(text)) { parser.abortParsing() }
        }
    }
}

// Word files without rendered pagination use an explicitly bounded opening excerpt.
// This exception is not described as two physical pages.
func wordNamingOpening(_ file:FileItem,token:IndexCancellation) -> (text:String,paginated:Bool) {
    guard !token.isCancelled else { return ("",false) }
    if file.ext == "docx" {
        let xml = run("/usr/bin/unzip",["-p",file.path,"word/document.xml"])
        guard !token.isCancelled else { return ("",false) }
        let paginated = xml.contains("lastRenderedPageBreak")
        let reader = NamingWordReader(cancelled:{token.isCancelled},enough:{_ in false})
        reader.openingOnly = true; reader.hasPageMarkers = paginated;reader.preserveSoftWrappedTitles = true
        if !paginated { reader.openingCharacterLimit = unpaginatedNamingCharacterLimit }
        let parser = XMLParser(data:Data(xml.utf8)); parser.delegate = reader; parser.shouldResolveExternalEntities = false
        _ = parser.parse()
        let text = String((reader.text+"\n"+reader.currentParagraph).prefix(paginated ? 12000 : unpaginatedNamingCharacterLimit))
        return (text,paginated)
    }
    guard ["doc","rtf"].contains(file.ext) else { return ("",false) }
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/textutil"); process.arguments = ["-convert","txt","-stdout",file.path]
    process.standardOutput = pipe; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
    do {
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+15,execute:timeout)
        defer { timeout.cancel(); try? pipe.fileHandleForReading.close(); if process.isRunning { process.terminate() }; process.waitUntilExit() }
        var data = Data()
        func completeUTF8Prefix() -> String {
            for count in 0...min(3,data.count) {
                if let text = String(data:data.dropLast(count),encoding:.utf8) { return text }
            }
            return String(decoding:data,as:UTF8.self)
        }
        while data.count < 32768 && !token.isCancelled {
            guard let part = try pipe.fileHandleForReading.read(upToCount:min(300,32768-data.count)), !part.isEmpty else { break }
            data.append(part)
            if completeUTF8Prefix().count >= unpaginatedNamingCharacterLimit { break }
        }
        return (String(completeUTF8Prefix().prefix(unpaginatedNamingCharacterLimit)),false)
    } catch { return ("",false) }
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
    if ["docx","doc","rtf"].contains(file.ext) { return wordNamingOpening(file,token:token).text }
    guard !token.isCancelled else { return "" }
    if ["png","jpg","jpeg","heic","tiff"].contains(file.ext) { return extract(file.url) }
    guard ["txt","md"].contains(file.ext), let handle = try? FileHandle(forReadingFrom:file.url) else { return "" }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount:32768) else { return "" }
    let text = String(data:data,encoding:.utf8) ?? String(data:data,encoding:.utf16) ?? ""
    let pages = text.components(separatedBy:"\u{000C}")
    return namingPageText(count:pages.count,cancelled:{token.isCancelled},page:{String(pages[$0].prefix(6000))},enough:{_ in false})
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
    try verify(read == [0,1] && !fallback.contains("第三页"),"Never read page three even when the first two lack a title")
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
        let reader = NamingWordReader(cancelled:{false},enough:enough); reader.hasPageMarkers = true; reader.openingOnly = true
        let parser = XMLParser(data:Data(xml.utf8)); parser.delegate = reader; _ = parser.parse(); return reader.text
    }
    try verify(!wordRead(cover).contains("后文其他"),"Word page breaks preserve cover-first extraction")
    try verify(!wordRead(later).contains("第三页"),"Word extraction stops after page two without identity")
    print("PASS: strict naming pages 1–2, no later-page fallback, PDFKit and Word boundaries, cancellation")
}

// Archive extraction retains its own existing two-page opening policy.
func archiveFirstPages(count: Int, token: IndexCancellation, page: (Int) -> String) -> String {
    var values: [String] = []
    for index in 0..<min(count,2) {
        guard !token.isCancelled else { break }
        values.append(String(page(index).prefix(6000)))
    }
    return values.joined(separator:"\n\u{000C}\n")
}
func extractArchiveOpening(_ file: FileItem, token: IndexCancellation) -> String {
    guard !token.isCancelled else { return "" }
    if file.ext == "pdf", let pdf = PDFDocument(url:file.url) {
        return archiveFirstPages(count:pdf.pageCount,token:token) { i in
            guard let page = pdf.page(at:i) else { return "" }
            let text = page.string ?? ""
            if text.trimmingCharacters(in:.whitespacesAndNewlines).count >= 15 { return text }
            guard !token.isCancelled else { return "" }
            let image = page.thumbnail(of:NSSize(width:1400,height:1800),for:.mediaBox)
            guard let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return text }
            return text+"\n"+ocr(cg)
        }
    }
    if file.ext == "docx" {
        let xml = run("/usr/bin/unzip",["-p",file.path,"word/document.xml"])
        guard !xml.isEmpty, !token.isCancelled else { return "" }
        let reader = NamingWordReader(cancelled:{token.isCancelled},enough:{_ in false})
        reader.openingOnly = true
        reader.hasPageMarkers = xml.contains("lastRenderedPageBreak") || xml.range(of:"w:type=[\"']page[\"']|w:pageBreakBefore",options:.regularExpression) != nil
        let parser = XMLParser(data:Data(xml.utf8)); parser.delegate = reader; parser.shouldResolveExternalEntities = false
        _ = parser.parse()
        return String((reader.text+"\n"+reader.paragraph).prefix(reader.hasPageMarkers ? 12000 : 6000))
    }
    let text: String
    if ["txt","md","csv"].contains(file.ext) {
        guard let handle = try? FileHandle(forReadingFrom:file.url) else { return "" }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount:32768) else { return "" }
        if bytes.starts(with:[0xff,0xfe]) { text = String(data:bytes,encoding:.utf16LittleEndian) ?? "" }
        else if bytes.starts(with:[0xfe,0xff]) { text = String(data:bytes,encoding:.utf16BigEndian) ?? "" }
        else { text = String(decoding:bytes,as:UTF8.self) }
    } else {
        // Images have one page; legacy Office conversion exposes an opening text excerpt.
        text = extract(file.url)
    }
    guard !token.isCancelled else { return "" }
    let pages = text.components(separatedBy:"\u{000C}")
    if pages.count > 1 { return archiveFirstPages(count:pages.count,token:token) { pages[$0] } }
    return String(text.prefix(6000))
}
func archiveOpeningText(_ row: BrowserRow, known: [FileItem], token: IndexCancellation) -> String {
    if !row.folder { return row.file.map { extractArchiveOpening($0,token:token) } ?? "" }
    var files = known.filter { $0.path.hasPrefix(row.id+"/") }
    if files.isEmpty, let enumerator = fm.enumerator(at:URL(fileURLWithPath:row.id),includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles,.skipsPackageDescendants]) {
        // Inspect a small source-folder sample, never enumerate project libraries for a match.
        var visited = 0
        while let url = enumerator.nextObject() as? URL, visited < 200, files.count < 16, !token.isCancelled {
            visited += 1
            if supported.contains(url.pathExtension.lowercased()), let file = browserEntry(url.path)?.file { files.append(file) }
        }
    }
    return representativeFiles(files,limit:2).map { file in
        guard !token.isCancelled else { return "" }
        return extractArchiveOpening(file,token:token)
    }.joined(separator:"\n")
}
