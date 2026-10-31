import Foundation
import AppKit
import PDFKit

@MainActor func namingPolicyTest(root:URL) throws {
    let dir = root.appendingPathComponent("naming-policy"); try fm.createDirectory(at:dir,withIntermediateDirectories:true)
    let url = dir.appendingPathComponent("原文档.PDF")
    var box = CGRect(x:0,y:0,width:600,height:800)
    guard let context = CGContext(url as CFURL,mediaBox:&box,nil) else { throw namingError("PDF 测试创建失败") }
    for index in 0..<3 {
        context.beginPDFPage(nil); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
        let title = ["文件标题：云业务安全实施方案","标题：第二页备选名称","标题：禁止读取的第三页标题"][index]
        (title as NSString).draw(at:NSPoint(x:40,y:690),withAttributes:[.font:NSFont.systemFont(ofSize:24)])
        ("项目名称：某个采购项目" as NSString).draw(at:NSPoint(x:40,y:640),withAttributes:[.font:NSFont.systemFont(ofSize:12)])
        NSGraphicsContext.restoreGraphicsState(); context.endPDFPage()
    }
    context.closePDF()
    let file = FileItem(path:url.path,project:dir.path,text:"",size:1,date:Date())
    let titles = recognizeNamingTitles(file,token:IndexCancellation())
    try verify(titles.first?.name == "云业务安全实施方案" && titles.contains(where:{$0.name == "第二页备选名称"}),"Homepage explicit title wins while page-two alternatives remain selectable")
    try verify(!titles.contains(where:{$0.name.contains("第三页")}) && !extractForNaming(file,token:IndexCancellation()).contains("第三页"),"Real PDF readers must never use page three")
    try verify(!titles.contains(where:{$0.name.hasPrefix("文件标题-") || $0.name.hasPrefix("标题-")}),"Explicit field labels never leak into title candidates")
    let wrapped = namingTitleSuggestions(pages:[NamingTitlePage(index:0,lines:[NamingTitleLine(text:"云业务",prominent:true,joinsNext:true),NamingTitleLine(text:"安全服务",prominent:true,joinsNext:true),NamingTitleLine(text:"实施方案",prominent:true)])],source:"封面")
    try verify(wrapped.first?.name == "云业务安全服务实施方案","A complete wrapped cover title ranks ahead of its individual fragments")
    var visits:[Int] = []
    _ = namingPageText(count:100,cancelled:{false},page:{visits.append($0);return "目录"},enough:{_ in false})
    try verify(visits == [0,1],"The two-page budget is hard even without a usable title")
    try verify(cleanNamingTitle("  云业务\n安全承诺书  ") == "云业务安全承诺书","Wrapped Chinese titles retain words while removing layout line breaks")
    try verify(cleanNamingTitle("《技术方案》  2026：部署/验收") == "《技术方案》 2026-部署-验收","Only whitespace and filename-unsafe characters are cleaned; title words and book-title punctuation survive")

    let package = dir.appendingPathComponent("workbook")
    for name in ["xl/worksheets","xl/_rels"] { try fm.createDirectory(at:package.appendingPathComponent(name),withIntermediateDirectories:true) }
    try """
    <workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="横向" sheetId="1" r:id="r1"/><sheet name="纵向" sheetId="2" r:id="r2"/><sheet name="隐藏" sheetId="3" state="hidden" r:id="r3"/></sheets></workbook>
    """.write(to:package.appendingPathComponent("xl/workbook.xml"),atomically:true,encoding:.utf8)
    try """
    <Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/><Relationship Id="r2" Target="worksheets/sheet2.xml"/><Relationship Id="r3" Target="worksheets/sheet3.xml"/></Relationships>
    """.write(to:package.appendingPathComponent("xl/_rels/workbook.xml.rels"),atomically:true,encoding:.utf8)
    try "<sst><si><t>正文中不得使用的标题报告</t></si><si><t>2026年网络安全预算表</t></si></sst>".write(to:package.appendingPathComponent("xl/sharedStrings.xml"),atomically:true,encoding:.utf8)
    try "<styleSheet><fonts><font><sz val=\"20\"/><b/></font></fonts><cellXfs><xf fontId=\"0\"/></cellXfs></styleSheet>".write(to:package.appendingPathComponent("xl/styles.xml"),atomically:true,encoding:.utf8)
    try "<worksheet><sheetData><row r=\"1\"><c r=\"A1\" t=\"s\"><v>1</v></c></row><row r=\"20\"><c r=\"A20\" t=\"inlineStr\"><is><t>不许读取的正文报告</t></is></c></row><row r=\"31\"><c r=\"A31\" t=\"inlineStr\"><is><t>不许读取的正文表</t></is></c></row></sheetData></worksheet>".write(to:package.appendingPathComponent("xl/worksheets/sheet1.xml"),atomically:true,encoding:.utf8)
    let vertical = Array("安全检查记录表").enumerated().map { index,char in "<row r=\"\(index+1)\"><c r=\"A\(index+1)\" t=\"inlineStr\"><is><t>\(char)</t></is></c></row>" }.joined()
    try ("<worksheet><sheetData>"+vertical+"</sheetData></worksheet>").write(to:package.appendingPathComponent("xl/worksheets/sheet2.xml"),atomically:true,encoding:.utf8)
    try "<worksheet><sheetData><row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>不许读取的隐藏标题表</t></is></c></row></sheetData></worksheet>".write(to:package.appendingPathComponent("xl/worksheets/sheet3.xml"),atomically:true,encoding:.utf8)
    func zip(_ path:URL,_ name:String,_ items:[String]) throws -> URL {
        let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/zip"); process.currentDirectoryURL = path; process.arguments = ["-qr",name]+items
        try process.run(); process.waitUntilExit(); try verify(process.terminationStatus == 0); return path.appendingPathComponent(name)
    }
    let workbook = try zip(package,"headers.xlsx",["xl"])
    let sheetFile = FileItem(path:workbook.path,project:dir.path,text:"",size:1,date:Date())
    let headers = recognizeNamingTitles(sheetFile,token:IndexCancellation())
    try verify(headers.contains(where:{$0.name == "2026年网络安全预算表"}) && headers.contains(where:{$0.name == "安全检查记录表"}),"Real XLSX shared/inline header cells produce both horizontal and vertical title choices")
    try verify(!headers.contains(where:{$0.name.contains("不得") || $0.name.contains("不许")}),"Body rows, unused shared strings and hidden worksheets never become candidates")

    let word = dir.appendingPathComponent("wordpkg/word"); try fm.createDirectory(at:word,withIntermediateDirectories:true)
    let wordPages = ["标题：第一页原始方案","标题：第二页候选方案","标题：第三页不许出现方案"]
    let xml = "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>"+wordPages.map { "<w:p><w:r><w:t>"+$0+"</w:t></w:r></w:p>" }.joined(separator:"<w:p><w:r><w:lastRenderedPageBreak/></w:r></w:p>")+"</w:body></w:document>"
    try xml.write(to:word.appendingPathComponent("document.xml"),atomically:true,encoding:.utf8)
    let wordURL = try zip(word.deletingLastPathComponent(),"paged.docx",["word"])
    let wordFile = FileItem(path:wordURL.path,project:dir.path,text:"",size:1,date:Date())
    let wordTitles = recognizeNamingTitles(wordFile,token:IndexCancellation())
    try verify(wordTitles.first?.name == "第一页原始方案" && !wordTitles.contains(where:{$0.name.contains("第三页")}),"Cached Word page boundaries enforce the same strict title budget")
    try xml.replacingOccurrences(of:"<w:lastRenderedPageBreak/>",with:"<w:br w:type=\"page\"/><w:lastRenderedPageBreak/>").write(to:word.appendingPathComponent("document.xml"),atomically:true,encoding:.utf8)
    let pairedURL = try zip(word.deletingLastPathComponent(),"paired.docx",["word"])
    var paired = wordFile; paired.path = pairedURL.path
    let pairedTitles = recognizeNamingTitles(paired,token:IndexCancellation())
    try verify(pairedTitles.contains(where:{$0.name == "第二页候选方案"}) && !pairedTitles.contains(where:{$0.name.contains("第三页")}),"Manual and rendered markers for one boundary must not count as two pages")
    let blankXML = xml.replacingOccurrences(of:"标题：第一页原始方案",with:"")
    try blankXML.write(to:word.appendingPathComponent("document.xml"),atomically:true,encoding:.utf8)
    let blankURL = try zip(word.deletingLastPathComponent(),"blank-cover.docx",["word"])
    var blank = wordFile;blank.path = blankURL.path
    let blankTitles = recognizeNamingTitles(blank,token:IndexCancellation())
    try verify(blankTitles.first?.name == "第二页候选方案" && !blankTitles.contains(where:{$0.name.contains("第三页")}),"A blank first Word page still consumes one of the two permitted pages")
    try xml.replacingOccurrences(of:"<w:lastRenderedPageBreak/>",with:"").write(to:word.appendingPathComponent("document.xml"),atomically:true,encoding:.utf8)
    let unpagedURL = try zip(word.deletingLastPathComponent(),"unpaged.docx",["word"])
    var unpaged = wordFile; unpaged.path = unpagedURL.path
    let excerptTitles = recognizeNamingTitles(unpaged,token:IndexCancellation())
    try verify(excerptTitles.first?.name == "第一页原始方案" && excerptTitles.allSatisfy{$0.evidence.contains("Word 开头节选")},"Unpaginated Word uses the user-authorized bounded opening excerpt, clearly identified as an excerpt")
    for (index,content,expected) in [
        (0,"标题：智慧园区建设项目</w:t><w:br/><w:t>网络安全实施方案","智慧园区建设项目网络安全实施方案"),
        (1,"智慧园区</w:t><w:br/><w:t>建设项目","智慧园区建设项目")
    ] {
        let wrappedXML = "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:r><w:t>"+content+"</w:t></w:r></w:p></w:body></w:document>"
        try wrappedXML.write(to:word.appendingPathComponent("document.xml"),atomically:true,encoding:.utf8)
        let wrappedURL = try zip(word.deletingLastPathComponent(),"soft-wrap-\(index).docx",["word"])
        var wrappedFile = wordFile;wrappedFile.path = wrappedURL.path
        try verify(recognizeNamingTitles(wrappedFile,token:IndexCancellation()).first?.name == expected,"A real Word title retains same-paragraph soft-wrapped words, with or without a title field")
    }
    let longOpening = String(repeating:"正文内容。",count:65)+"\n标题：超过节选上限的标题报告"
    let longXML = "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:r><w:t>"+longOpening+"</w:t></w:r></w:p></w:body></w:document>"
    try longXML.write(to:word.appendingPathComponent("document.xml"),atomically:true,encoding:.utf8)
    let limitedURL = try zip(word.deletingLastPathComponent(),"limited.docx",["word"])
    var limited = wordFile;limited.path = limitedURL.path
    let limitedText = extractForNaming(limited,token:IndexCancellation())
    try verify(limitedText.count <= 300 && !limitedText.contains("超过节选") && recognizeNamingTitles(limited,token:IndexCancellation()).isEmpty,"Unpaginated Word stops at 300 characters and never uses a title just beyond that limit")
    let legacyText = dir.appendingPathComponent("legacy.txt")
    try ("标题：旧版文档安全方案\n"+longOpening).write(to:legacyText,atomically:true,encoding:.utf8)
    let legacyURL = dir.appendingPathComponent("legacy.doc")
    _ = run("/usr/bin/textutil",["-convert","doc","-output",legacyURL.path,legacyText.path])
    let legacyFile = FileItem(path:legacyURL.path,project:dir.path,text:"",size:1,date:Date())
    let legacyTitles = recognizeNamingTitles(legacyFile,token:IndexCancellation())
    let legacyOpening = extractForNaming(legacyFile,token:IndexCancellation())
    try verify(legacyTitles.first?.name == "旧版文档安全方案" && legacyOpening.count <= 300 && !legacyOpening.contains("超过节选") && !legacyOpening.contains("�"),"Legacy Word also stops at 300 characters without splitting UTF-8 Chinese characters")
    let cancelled = IndexCancellation(); cancelled.cancel()
    try verify(recognizeNamingTitles(sheetFile,token:cancelled).isEmpty,"Cancellation prevents opening a workbook")
    let store = Store(stateURL:dir.appendingPathComponent("state/settings.json"),loadOnLaunch:false)
    let target = NamingTarget(path:url.path,folder:false,projectPath:dir.path)
    try verify(store.titleProposedName("云业务安全实施方案",target:target,date:Date()) == "云业务安全实施方案.PDF","The naming formatter preserves the complete title and exact original extension case")
    try verify((store.settings.renames ?? []).isEmpty && fm.fileExists(atPath:url.path),"Reading candidates never renames the source")
    print("PASS: cover-first full-title candidates, hard two-page PDF/paginated-Word cap without later fallback, user-authorized bounded Word excerpts, XLSX horizontal/vertical header-only choices, hidden/body/unused-string exclusion, sanitation, extension preservation, cancellation and no pre-confirm rename")
}
