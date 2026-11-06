import Foundation

@MainActor func archiveMatchingTest() throws {
    let paperless = Project(path:"/archive/paperless",name:"53-2023年至2025年（24个月）黔南独山县机关事务服务中心无纸化办公系统项目")
    let unrelated = [
        Project(path:"/archive/closed",name:"已解决的 cd 类"),
        Project(path:"/archive/qingxiu",name:"青秀 2046"),
        Project(path:"/archive/fuel",name:"惠水加油站"),
    ]
    let paperlessFile = BrowserRow(id:"/inbox/paperless.docx",title:"法律意见书暨仲裁预案-无纸化办公.docx")
    let index = ArchiveProjectIndex(projects:unrelated+[paperless])
    let screenshot = index.recommendations(for:[paperlessFile],token:IndexCancellation())
    try verify(screenshot.map(\.id) == [paperless.path] && screenshot.first?.score == 5,"Only the paperless project shares letters with the screenshot filename; the extension never contributes")
    try verify(index.search("惠水").map(\.path) == [unrelated[2].path],"An unrelated destination remains accessible through manual search")
    let unknown = BrowserRow(id:"/inbox/unknown.txt",title:"甲乙丙.txt")
    try verify(index.recommendations(for:[unknown],token:IndexCancellation()).isEmpty,"Zero common characters produces an empty list")

    let ordered = Project(path:"/archive/ordered",name:"甲乙丙丁")
    let reordered = Project(path:"/archive/reordered",name:"丙丁甲乙")
    let fewer = Project(path:"/archive/fewer",name:"甲乙丙")
    let keywordOnly = Project(path:"/archive/keyword",name:"财务资料",keywords:"甲乙丙丁")
    let orderIndex = ArchiveProjectIndex(projects:[reordered,fewer,ordered,keywordOnly])
    let sequence = BrowserRow(id:"/inbox/sequence.pdf",title:"甲—乙丙丁.pdf")
    let ranks = orderIndex.recommendations(for:[sequence],token:IndexCancellation())
    try verify(ranks.map(\.id) == [ordered.path,reordered.path,fewer.path] && ranks.map(\.score) == [4,4,3],"Shared count sorts first; equal counts favor matching character order, and keywords alone do not qualify")
    try verify(orderIndex.search("甲乙丙丁").contains { $0.path == keywordOnly.path },"Manual search still accepts configured keywords")

    let repeated = Project(path:"/archive/repeated",name:"纸纸办公")
    let single = Project(path:"/archive/single",name:"纸办公")
    let coded = Project(path:"/archive/coded",name:"A2046")
    let more = ArchiveProjectIndex(projects:[single,repeated,coded])
    let repeatedFile = BrowserRow(id:"/inbox/repeated",title:"纸纸纸办公.txt")
    try verify(more.recommendations(for:[repeatedFile],token:IndexCancellation()).map(\.score) == [4,3],"Repeated characters count at most as often as they occur in both names")
    let folder = BrowserRow(id:"/inbox/folder",title:"文件.ａ２０４６",folder:true)
    let combined = more.recommendations(for:[repeatedFile,folder],token:IndexCancellation())
    try verify(combined.map(\.id) == [coded.path,repeated.path,single.path] && combined.first?.score == 5,"Batch totals, folder names with dots, digits and case/width normalization")
    let cancelled = IndexCancellation(); cancelled.cancel()
    try verify(more.recommendations(for:[repeatedFile],token:cancelled).isEmpty,"Cancellation prevents publication of matches")
    print("PASS: archive ranking by shared count and order, zero-overlap filtering, extension exclusion, repeats, batch totals, manual search and cancellation")
}
