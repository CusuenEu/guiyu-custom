import SwiftUI
import AppKit

@MainActor final class IndexProgress: ObservableObject { @Published var message = "" }
struct WorkspaceStatus: View {
    @ObservedObject var progress: IndexProgress; let busy: Bool; let count: Int?
    var body: some View {
        HStack(spacing:7) { Circle().fill(busy ? Color.orange : accent).frame(width:6,height:6); Text(busy ? "正在读取文件…" : "本地工作空间"); Spacer(); if busy { Text(progress.message).lineLimit(1) }; if let count { Text("\(count) 项") } }.font(.caption).foregroundStyle(.secondary).padding(.horizontal,22).frame(height:32)
    }
}

final class PreviewLoadGate {
    private var url: URL?; private var version: Date?
    func shouldLoad(url: URL, version: Date) -> Bool {
        guard self.url != url || self.version != version else { return false }
        self.url = url; self.version = version; return true
    }
}
@MainActor func interactionTest() throws {
    let gate = PreviewLoadGate(); let a = URL(fileURLWithPath:"/tmp/preview-a.pdf"), date = Date()
    try verify(gate.shouldLoad(url:a,version:date))
    for _ in 0..<1000 { try verify(!gate.shouldLoad(url:a,version:date),"Background redraw must not reload preview") }
    try verify(gate.shouldLoad(url:a,version:date.addingTimeInterval(1)),"A saved new version must refresh preview")
    var selected: String?
    let rows = (0..<4000).map { FileItem(path:"/tmp/file-\($0).txt",project:"",text:"",size:1,date:date) }
    let browserRows = rows.map { BrowserRow(id:$0.path,title:$0.name,file:$0) }
    let parent = BrowserTable(rows:browserRows,selection:Binding(get:{selected},set:{selected=$0}),activate:{_ in},rename:{_ in})
    let c = parent.makeCoordinator(); c.rows = browserRows
    let table = NSTableView(); table.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier("file"))); table.dataSource = c; table.reloadData()
    let start = Date()
    for index in [0,2000,3999,3,5] {
        table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)
        c.tableViewSelectionDidChange(Notification(name:NSTableView.selectionDidChangeNotification,object:table))
        try verify(selected == rows[index].path,"Native selection must update on the first selection event")
    }
    print("Native table selection fixture (4000 rows, 5 selections): \(Int(Date().timeIntervalSince(start)*1000)) ms; preview duplicate loads: 0/1000")
}
