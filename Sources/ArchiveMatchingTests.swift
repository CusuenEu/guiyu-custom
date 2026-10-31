import Foundation
import AppKit

@MainActor func archiveMatchingTest(root: URL) throws {
    let projects = [Project(path:"/archive/municipal",name:"10月 贵州省民政厅厅机关网络运维及网络安全运维项目"),
                    Project(path:"/archive/douyin",name:"10 抖音"),
                    Project(path:"/archive/water",name:"9月 水利投资舆情监测服务项目")]
    let index = ArchiveProjectIndex(projects:projects)
    let exact = BrowserRow(id:"/inbox/抖音集团机房招采文件.pdf",title:"抖音集团机房招采文件.pdf")
    let generic = BrowserRow(id:"/inbox/input.pdf",title:"input.pdf")
    var reads: [String] = []; var updates: [([ProjectArchiveChoice],Bool,String)] = []
    matchArchiveRows([exact],index:index,token:IndexCancellation(),readOpening:{ row in reads.append(row.id); return "项目名称：水利投资舆情监测服务项目" }) { updates.append(($0,$1,$2)) }
    try verify(reads.isEmpty && updates.count == 1 && updates[0].1 && updates[0].0.first?.id == projects[1].path,"Clear filename matches finish without opening any source or project document")
    reads = []; updates = []
    matchArchiveRows([generic],index:index,token:IndexCancellation(),readOpening:{ row in
        try! verify(!updates.isEmpty && !updates[0].1,"Publish filename results before source extraction")
        reads.append(row.id); return "项目名称：水利投资舆情监测服务项目"
    }) { updates.append(($0,$1,$2)) }
    try verify(reads == [generic.id] && updates.last?.0.first?.id == projects[2].path && updates.last?.1 == true,"Generic filenames read only their own opening pages and then finish")
    reads = []; updates = []
    matchArchiveRows([exact,generic],index:index,token:IndexCancellation(),readOpening:{ row in reads.append(row.id); return "抖音集团机房建设项目" }) { updates.append(($0,$1,$2)) }
    try verify(reads == [generic.id] && updates.last?.0.first?.id == projects[1].path,"Mixed selections only read the unresolved item")
    let ambiguous = ArchiveProjectIndex(projects:[projects[1],Project(path:"/archive/douyin2",name:"9 抖音")])
    try verify(!clearArchiveMatch(ambiguous.choices(input:"抖音招标文件",origin:"文件名")),"Tied filename matches require opening-page evidence and never choose automatically")
    try verify(index.choices(input:"招标文件 方案 采购项目",origin:"文件名").isEmpty,"Generic document labels alone do not recommend projects")
    let fuzzy = index.choices(input:"民政厅网络安全运维采购需求",origin:"文件名")
    try verify(fuzzy.first?.id == projects[0].path,"Distinctive Chinese keywords match shortened, reordered project names")
    try verify(index.search("民政 运维").first?.path == projects[0].path,"Manual search accepts multiple separated keywords")
    let metadata = FileItem(path:"/archive/short/贵阳智慧园区招标文件.pdf",project:"/archive/short",text:"",size:1,date:Date())
    let short = ArchiveProjectIndex(projects:[Project(path:"/archive/short",name:"A")],references:[metadata])
    try verify(short.choices(input:"贵阳智慧园区响应文件",origin:"文件名").first?.id == "/archive/short","Loaded filenames identify abbreviated project folders without reading their contents")
    let genericReference = FileItem(path:"/archive/generic/机房.pdf",project:"/archive/generic",text:"",size:1,date:Date())
    let genericIndex = ArchiveProjectIndex(projects:[Project(path:"/archive/generic",name:"202206")],references:[genericReference])
    try verify(genericIndex.choices(input:"抖音集团2026年机房租赁招采项目",origin:"文件名").isEmpty,"Year-only folders and generic short reference filenames must not add unrelated recommendations")
    let cancelled = IndexCancellation(); cancelled.cancel(); reads = []; updates = []
    matchArchiveRows([generic],index:index,token:cancelled,readOpening:{ row in reads.append(row.id); return "" }) { updates.append(($0,$1,$2)) }
    try verify(reads.isEmpty && updates.isEmpty,"Cancellation prevents reads and publication")
    let cancellation = IndexCancellation(); reads = []; updates = []
    matchArchiveRows([generic],index:index,token:cancellation,readOpening:{ row in reads.append(row.id); return "" }) { values,done,message in updates.append((values,done,message)); cancellation.cancel() }
    try verify(reads.isEmpty && updates.count == 1,"Closing after the first filename result prevents content fallback")

    var pages: [Int] = []
    let opening = archiveFirstPages(count:500,token:IndexCancellation()) { i in pages.append(i); return ["封面无项目名称","第二页也无名称","第三页不得读取"][min(i,2)] }
    try verify(pages == [0,1] && !opening.contains("不得读取"),"Archive never scans later pages even when the first two contain no identity")
    let document = root.appendingPathComponent("archive-three-pages.pdf"); var box = CGRect(x:0,y:0,width:600,height:400)
    if let context = CGContext(document as CFURL,mediaBox:&box,nil) {
        for text in ["FIRST PAGE ordinary opening text","SECOND PAGE ordinary opening text","THIRD PAGE MUST NOT BE READ"] {
            context.beginPDFPage(nil); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
            (text as NSString).draw(at:NSPoint(x:30,y:200),withAttributes:[.font:NSFont.systemFont(ofSize:16)])
            NSGraphicsContext.restoreGraphicsState(); context.endPDFPage()
        }; context.closePDF()
    }
    let pdf = FileItem(path:document.path,project:"",text:"",size:1,date:Date())
    let excerpt = extractArchiveOpening(pdf,token:IndexCancellation())
    try verify(excerpt.contains("FIRST PAGE") && excerpt.contains("SECOND PAGE") && !excerpt.contains("THIRD PAGE"),"Real PDFKit reading is limited to two pages")
    let textFile = root.appendingPathComponent("archive-open.txt")
    try "第一页\u{000C}第二页\u{000C}第三页不得读取".write(to:textFile,atomically:true,encoding:.utf8)
    let file = FileItem(path:textFile.path,project:"",text:"",size:1,date:Date())
    try verify(!extractArchiveOpening(file,token:IndexCancellation()).contains("不得读取"),"Explicit text page boundaries have the same two-page limit")
    let package = root.appendingPathComponent("ArchiveWord/word"); try fm.createDirectory(at:package,withIntermediateDirectories:true)
    let xml = "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:r><w:t>第一页没有名称</w:t></w:r></w:p><w:p><w:r><w:br w:type=\"page\"/></w:r></w:p><w:p><w:r><w:t>第二页没有名称</w:t></w:r></w:p><w:p><w:r><w:br w:type=\"page\"/></w:r></w:p><w:p><w:r><w:t>第三页不得读取</w:t></w:r></w:p></w:body></w:document>"
    try xml.write(to:package.appendingPathComponent("document.xml"),atomically:true,encoding:.utf8)
    let zipper = Process(); zipper.executableURL = URL(fileURLWithPath:"/usr/bin/zip"); zipper.arguments = ["-qr","opening.docx","word"]; zipper.currentDirectoryURL = package.deletingLastPathComponent(); try zipper.run(); zipper.waitUntilExit()
    let word = FileItem(path:package.deletingLastPathComponent().appendingPathComponent("opening.docx").path,project:"",text:"",size:1,date:Date())
    let wordText = extractArchiveOpening(word,token:IndexCancellation())
    try verify(wordText.contains("第二页") && !wordText.contains("不得读取"),"Real zipped Word XML stops at the third-page boundary even without project identity")

    let many = (0..<1000).map { Project(path:"/benchmark/\($0)",name:"10月 测试客户编号\($0)云网设备改造项目") }
    let started = Date(); let benchmark = ArchiveProjectIndex(projects:many)
    let buildMS = Date().timeIntervalSince(started)*1000
    var elapsed: [Double] = []
    for number in [123,456,789,654,321] {
        let before = Date(); let values = benchmark.choices(input:"测试客户编号\(number)云网设备改造招标文件",origin:"文件名")
        elapsed.append(Date().timeIntervalSince(before)*1000)
        try verify(values.first?.id == many[number].path && clearArchiveMatch(values),"A full specific filename outranks fuzzy near-duplicates and requires no content fallback")
    }
    let median = elapsed.sorted()[elapsed.count/2]
    try verify(median < 500,"In-memory matching must not behave like sequential document extraction")
    print(String(format:"Archive matching benchmark: 1000 projects; index %.1f ms; median query %.1f ms (no filesystem/content reads)",buildMS,median))
    print("PASS: filename-first zero-read matches, unresolved-only source fallback, Chinese fuzzy/multi-keyword search, metadata-only short projects, ambiguity, cancellation and strict PDF/Word/text two-page budget")
}
