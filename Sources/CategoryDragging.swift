import SwiftUI
import AppKit

let categoryDragType = NSPasteboard.PasteboardType("local.guiyu.category-entries")
struct CategoryDragItem: Codable { let path: String; let identity: String; let scope: String }
func categoryDropRows(_ pasteboard: NSPasteboard, scope: String, rows: [BrowserRow]) -> [BrowserRow]? {
    guard !scope.isEmpty, let items = pasteboard.pasteboardItems, !items.isEmpty else { return nil }
    var result: [BrowserRow] = []; var seen = Set<String>()
    for item in items {
        guard let data = item.data(forType:categoryDragType), let value = try? JSONDecoder().decode(CategoryDragItem.self,from:data), value.scope == scope,
              let row = rows.first(where:{$0.id == value.path && !$0.header}), fileIdentity(value.path) == value.identity else { return nil }
        if seen.insert(row.id).inserted { result.append(row) }
    }
    return result.isEmpty ? nil : result
}
struct CategoryDropTarget: NSViewRepresentable {
    let category: WorkspaceCategory; let scope: String; let rows: [BrowserRow]; let accept: ([BrowserRow]) -> Void
    func makeNSView(context: Context) -> CategoryDropView { let view = CategoryDropView(); updateNSView(view,context:context); return view }
    func updateNSView(_ view: CategoryDropView, context: Context) { view.category = category; view.scope = scope; view.rows = rows; view.accept = accept; view.needsDisplay = true }
}
final class CategoryDropView: NSView {
    var category = WorkspaceCategory(id:"",name:""); var scope = ""; var rows: [BrowserRow] = []; var accept: ([BrowserRow]) -> Void = { _ in }; var targeted = false
    override init(frame: NSRect) { super.init(frame:frame); registerForDraggedTypes([categoryDragType]) }
    required init?(coder: NSCoder) { fatalError("unused") }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:6,yRadius:6)
        NSColor(calibratedRed:0.14,green:0.38,blue:0.30,alpha:targeted ? 0.22 : 0.08).setFill(); shape.fill()
        let text = category.name as NSString
        let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.labelColor]
        let size = text.size(withAttributes:attributes); text.draw(at:NSPoint(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2),withAttributes:attributes)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        targeted = categoryDropRows(sender.draggingPasteboard,scope:scope,rows:rows) != nil; needsDisplay = true; return targeted ? .move : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { targeted = false; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        targeted = false; needsDisplay = true
        guard let values = categoryDropRows(sender.draggingPasteboard,scope:scope,rows:rows) else { return false }
        accept(values); return true
    }
}
