import Foundation

// Parse ZIP members as streams: stop worksheet parsing at the header budget,
// without converting workbook body cells into naming text or executing formulas.
private func parseNamingZIP(_ path:String,_ member:String,delegate:XMLParserDelegate) {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/unzip"); process.arguments = ["-p",path,member]
    process.standardOutput = pipe; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
    do {
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+15,execute:timeout)
        defer { timeout.cancel(); try? pipe.fileHandleForReading.close(); if process.isRunning { process.terminate() }; process.waitUntilExit() }
        guard let stream = InputStream(fileAtPath:"/dev/fd/\(pipe.fileHandleForReading.fileDescriptor)") else { return }
        let parser = XMLParser(stream:stream); parser.delegate = delegate; parser.shouldResolveExternalEntities = false
        _ = parser.parse(); stream.close()
    } catch { return }
}
private func xmlName(_ name:String) -> String { String(name.split(separator:":").last ?? "") }
private final class NamingWorkbook: NSObject,XMLParserDelegate {
    var sheets:[(String,String)] = []; var relations:[String:String] = [:]
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        switch xmlName(name) {
        case "sheet":
            if sheets.count < 20, attributes["state"] != "hidden", attributes["state"] != "veryHidden", let title = attributes["name"], let id = attributes["r:id"] { sheets.append((title,id)) }
        case "Relationship":
            if attributes["TargetMode"] != "External", let id = attributes["Id"], let target = attributes["Target"], !target.contains("..") {
                let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/"+target
                if path.hasPrefix("xl/worksheets/"), path.hasSuffix(".xml") { relations[id] = path }
            }
        default: break
        }
    }
}
private struct NamingCell {
    let row:Int; let column:Int; let style:Int; let kind:String
    var value:String
}
private final class NamingSheetHeader:NSObject,XMLParserDelegate {
    var cells:[NamingCell] = []; var current:NamingCell?; var row = 0; var inValue = false; var visited = 0
    let token:IndexCancellation
    init(_ token:IndexCancellation) { self.token = token }
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        guard !token.isCancelled else { parser.abortParsing(); return }
        switch xmlName(name) {
        case "row":
            row = Int(attributes["r"] ?? "") ?? row+1
            if row > 30 { parser.abortParsing() }
        case "c":
            visited += 1; if visited > 2000 { parser.abortParsing(); return }
            let reference = attributes["r"] ?? ""
            let letters = reference.prefix(while:{$0.isLetter})
            guard letters.count <= 3, letters.uppercased().utf8.allSatisfy({$0 >= 65 && $0 <= 90}) else { current = nil; return }
            let column = letters.uppercased().utf8.reduce(0) { $0*26+Int($1)-64 }
            let cellRow = Int(reference.dropFirst(letters.count)) ?? row
            if cellRow <= 30, column >= 1, (cellRow <= 8 && column <= 16) || column <= 3 {
                current = NamingCell(row:cellRow,column:column,style:Int(attributes["s"] ?? "") ?? 0,kind:attributes["t"] ?? "",value:"")
            } else { current = nil }
        case "v","t": inValue = current != nil
        default: break
        }
    }
    func parser(_ parser:XMLParser,foundCharacters string:String) {
        if inValue { current?.value += string; if (current?.value.count ?? 0) > 2000 { parser.abortParsing() } }
    }
    func parser(_ parser:XMLParser,didEndElement name:String,namespaceURI:String?,qualifiedName:String?) {
        switch xmlName(name) {
        case "v","t": inValue = false
        case "c": if let current { cells.append(current) }; current = nil
        default: break
        }
    }
}
private final class NamingSharedStrings:NSObject,XMLParserDelegate {
    let needed:Set<Int>; let token:IndexCancellation
    var values:[Int:String] = [:]; var index = -1; var inText = false; var value = ""
    init(_ needed:Set<Int>,token:IndexCancellation) { self.needed = needed; self.token = token }
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        if token.isCancelled { parser.abortParsing(); return }
        if xmlName(name) == "si" { index += 1; value = ""; if index > 100000 { parser.abortParsing() } }
        if xmlName(name) == "t" { inText = needed.contains(index) }
    }
    func parser(_ parser:XMLParser,foundCharacters string:String) { if inText { value += string; if value.count > 2000 { parser.abortParsing() } } }
    func parser(_ parser:XMLParser,didEndElement name:String,namespaceURI:String?,qualifiedName:String?) {
        if xmlName(name) == "t" { inText = false }
        if xmlName(name) == "si" {
            if needed.contains(index) { values[index] = value }
            if index >= (needed.max() ?? -1) { parser.abortParsing() }
        }
    }
}
private final class NamingStyles:NSObject,XMLParserDelegate {
    var fonts:[(Double,Bool)] = []; var styles:[Int] = []
    var inFont = false; var inCellXfs = false; var size:Double = 11; var bold = false
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        switch xmlName(name) {
        case "font": inFont = true; size = 11; bold = false
        case "sz": if inFont { size = Double(attributes["val"] ?? "") ?? 11 }
        case "b": if inFont { bold = attributes["val"] != "0" && attributes["val"] != "false" }
        case "cellXfs": inCellXfs = true
        case "xf": if inCellXfs, styles.count < 10000 { styles.append(Int(attributes["fontId"] ?? "") ?? 0) }
        default: break
        }
        if fonts.count > 10000 { parser.abortParsing() }
    }
    func parser(_ parser:XMLParser,didEndElement name:String,namespaceURI:String?,qualifiedName:String?) {
        if xmlName(name) == "font" { fonts.append((size,bold)); inFont = false }
        if xmlName(name) == "cellXfs" { inCellXfs = false }
    }
    func prominent(_ style:Int) -> Bool {
        guard styles.indices.contains(style), fonts.indices.contains(styles[style]) else { return false }
        let font = fonts[styles[style]]; return font.0 >= 14 || font.1
    }
}
func spreadsheetNamingTitles(_ file:FileItem,token:IndexCancellation) -> [Suggestion] {
    let book = NamingWorkbook()
    parseNamingZIP(file.path,"xl/workbook.xml",delegate:book)
    parseNamingZIP(file.path,"xl/_rels/workbook.xml.rels",delegate:book)
    let styles = NamingStyles(); parseNamingZIP(file.path,"xl/styles.xml",delegate:styles)
    var worksheets:[(String,[NamingCell])] = []
    for (title,id) in book.sheets {
        guard !token.isCancelled else { return [] }
        guard let path = book.relations[id] else { continue }
        let reader = NamingSheetHeader(token); parseNamingZIP(file.path,path,delegate:reader)
        worksheets.append((title,reader.cells))
    }
    var indices = Set<Int>()
    for (_,cells) in worksheets {
        for cell in cells where cell.kind == "s" {
            if let index = Int(cell.value), index >= 0, index <= 100000 { indices.insert(index) }
        }
    }
    let shared = NamingSharedStrings(indices,token:token)
    if !indices.isEmpty { parseNamingZIP(file.path,"xl/sharedStrings.xml",delegate:shared) }
    var result:[Suggestion] = []
    for (sheet,raw) in worksheets {
        let cells:[NamingCell] = raw.compactMap { cell -> NamingCell? in
            var value = cell
            if cell.kind == "s" { guard let index = Int(cell.value), let text = shared.values[index] else { return nil }; value.value = text }
            else if cell.kind != "inlineStr" && cell.kind != "str" { return nil }
            guard !value.value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        let firstRow:Int = cells.map { $0.row }.min() ?? 0
        let topCount = cells.filter{$0.row == firstRow}.count
        let lines = cells.filter { $0.row <= 8 }.map { cell in
            NamingTitleLine(text:cell.value,prominent:styles.prominent(cell.style) || (cell.row == firstRow && topCount <= 2 && cell.value.count >= 5))
        }
        let titles = namingTitleSuggestions(pages:[NamingTitlePage(index:0,lines:lines)],source:file.name+" · "+sheet)
        result += titles.map { Suggestion(name:$0.name,evidence:$0.evidence.replacingOccurrences(of:"首页",with:"Excel 表头")) }
        func appendRuns(_ values:[NamingCell],direction:String) {
            var run:[NamingCell] = []
            func emit() {
                let title = run.map(\.value).joined()
                if title.count >= 4, title.unicodeScalars.contains(where:{$0.value >= 0x3400 && $0.value <= 0x9fff}), looksLikeNamingTitle(title) {
                    result.append(Suggestion(name:cleanNamingTitle(title),evidence:direction+"表头 · "+file.name+" · "+sheet))
                }
            }
            for cell in values {
                let value = cell.value.trimmingCharacters(in:.whitespacesAndNewlines)
                let adjacent = run.last.map { direction == "横向" ? cell.column == $0.column+1 : cell.row == $0.row+1 } ?? true
                if value.count == 1, value.first?.isLetter == true, adjacent { var next = cell; next.value = value; run.append(next) }
                else { emit(); run = []; if value.count == 1, value.first?.isLetter == true { var next = cell; next.value = value; run = [next] } }
            }
            emit()
        }
        for row in 1...8 {
            let band:[NamingCell] = cells.filter { $0.row == row }.sorted { $0.column < $1.column }
            appendRuns(band,direction:"横向")
        }
        for column in 1...3 {
            let band:[NamingCell] = cells.filter { $0.column == column }.sorted { $0.row < $1.row }
            appendRuns(band,direction:"纵向")
        }
    }
    var seen = Set<String>()
    return result.filter { seen.insert(FilenameQuery.normalize($0.name)).inserted }.prefix(12).map{$0}
}
