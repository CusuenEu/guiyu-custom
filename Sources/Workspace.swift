import SwiftUI
import AppKit
import QuickLookUI

struct BrowserRow: Identifiable, Equatable {
    var id: String; var title: String; var subtitle: String? = nil; var date: Date? = nil; var file: FileItem? = nil; var folder = false; var header = false; var count = 0; var expanded = true; var categoryID: String? = nil
}
enum BrowserTableAppearance { case files, projects }

private enum CategoryDisclosureImages {
    static let expanded = make(expanded:true)
    static let collapsed = make(expanded:false)
    private static func make(expanded:Bool) -> NSImage {
        let symbol = NSImage(systemSymbolName:"chevron.down",accessibilityDescription:"展开或收起")!
        let side:CGFloat = 12
        let scale = min(side/symbol.size.width,side/symbol.size.height)
        let size = NSSize(width:symbol.size.width*scale,height:symbol.size.height*scale)
        let image = NSImage(size:NSSize(width:side,height:side),flipped:false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform()
            transform.translateX(by:side/2,yBy:side/2)
            if !expanded { transform.rotate(byDegrees:90) }
            transform.concat()
            symbol.draw(in:NSRect(x:-size.width/2,y:-size.height/2,width:size.width,height:size.height))
            return true
        }
        image.isTemplate = true
        return image
    }
    static func image(expanded:Bool) -> NSImage { expanded ? self.expanded : collapsed }
}

struct BrowserTable: NSViewRepresentable {
    let rows: [BrowserRow]; @Binding var selection: String?
    var multipleSelection: Binding<Set<String>>? = nil
    var batchRename: (([BrowserRow],Bool) -> Void)? = nil
    var batchCategoryOptions: ([BrowserRow]) -> [WorkspaceCategory] = { _ in [] }
    var moveCategories: ([BrowserRow],String) -> Void = { _,_ in }
    var dragScope = ""; var dragging: (Bool) -> Void = { _ in }
    var dataset = ""
    var appearance: BrowserTableAppearance = .files
    var activate: (BrowserRow) -> Void; var rename: (BrowserRow) -> Void
    var directRename: ((BrowserRow) -> Void)? = nil
    var quickArchive: (([BrowserRow]) -> Void)? = nil
    var trash: (([BrowserRow]) -> Void)? = nil
    var categoryOptions: (BrowserRow) -> [WorkspaceCategory] = { _ in [] }
    var moveCategory: (BrowserRow,String) -> Void = { _,_ in }
    var toggle: (BrowserRow) -> Void = { _ in }; var preview: () -> Void = {}; var previewRequest: Binding<Bool>? = nil
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context:Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true
        let table = BrowserNSTable(); let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier("name")); column.resizingMask = .autoresizingMask
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 52; table.intercellSpacing = NSSize(width:0,height:1)
        table.allowsMultipleSelection = multipleSelection != nil
        table.registerForDraggedTypes([categoryDragType]); table.setDraggingSourceOperationMask(.move,forLocal:true)
        table.style = .fullWidth; table.backgroundColor = appearance == .projects ? WorkspaceTheme.projectPaper : WorkspaceTheme.paper; scroll.backgroundColor = table.backgroundColor
        table.delegate = context.coordinator; table.dataSource = context.coordinator; table.target = context.coordinator
        table.action = #selector(Coordinator.clicked(_:)); table.doubleAction = #selector(Coordinator.open(_:)); table.onSpace = { context.coordinator.previewSelection() }
        table.onTrash = trash == nil ? nil : { context.coordinator.trashSelection() }
        table.onRename = { context.coordinator.renameSelection() }
        table.onOpen = { context.coordinator.openSelection() }
        table.onCopy = { [weak table] in
            guard let table else { return }
            context.coordinator.copySelection(to:table.copyPasteboard)
        }
        table.onColumnWidthChange = { [weak coordinator = context.coordinator] in coordinator?.projectWidthChanged() }
        let menu = NSMenu(); menu.delegate = context.coordinator; table.menu = menu
        scroll.documentView = table; return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        guard let table = scroll.documentView as? BrowserNSTable else { return }
        let c = context.coordinator; c.parent = self; c.updating = true
        table.allowsMultipleSelection = multipleSelection != nil
        table.onTrash = trash == nil ? nil : { c.trashSelection() }
        let changedDataset = c.dataset != dataset; c.dataset = dataset
        let signature = rows.map { row in
            [row.id,row.title,String(row.date?.timeIntervalSince1970 ?? 0),String(row.count),String(row.expanded),row.subtitle ?? ""].joined(separator:"|")
        }
        if signature != c.signature { c.signature = signature; c.rows = rows; c.projectHeights.removeAll(); table.reloadData() }
        let ids = multipleSelection?.wrappedValue ?? Set(selection.map { [$0] } ?? [])
        let indexes = IndexSet(c.rows.indices.filter { ids.contains(c.rows[$0].id) && !c.rows[$0].header })
        if table.selectedRowIndexes != indexes { table.selectRowIndexes(indexes,byExtendingSelection:false) }
        if changedDataset { scroll.contentView.scroll(to:.zero); scroll.reflectScrolledClipView(scroll.contentView) }
        c.updating = false
        if previewRequest?.wrappedValue == true {
            DispatchQueue.main.async { guard c.parent.previewRequest?.wrappedValue == true else { return }; c.parent.previewRequest?.wrappedValue = false; c.previewSelection() }
        }
    }
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
        var parent: BrowserTable; var rows: [BrowserRow] = []; var signature: [String] = []; var dataset = ""; var updating = false; weak var table: NSTableView?; var contextRow: BrowserRow?; var contextRows: [BrowserRow] = []
        init(_ parent:BrowserTable) { self.parent = parent }
        // Cache only this table's current dataset and width; no filesystem work during layout.
        var projectHeights: [Int:CGFloat] = [:]
        func projectTitleHeight(_ row:Int, width:CGFloat) -> CGFloat {
            if let height = projectHeights[row] { return height }
            let value = rows[row]
            let textWidth = max(1,width - 76 - (value.date == nil ? 0 : 112))
            let cell = NSTextFieldCell(textCell:value.title)
            cell.font = .systemFont(ofSize:14); cell.usesSingleLineMode = false; cell.wraps = true; cell.isScrollable = false
            cell.lineBreakMode = .byWordWrapping
            let measured = cell.cellSize(forBounds:NSRect(x:0,y:0,width:textWidth,height:.greatestFiniteMagnitude)).height
            let height: CGFloat = measured > 22 ? 38 : 20
            projectHeights[row] = height
            return height
        }
        func projectWidthChanged() {
            guard parent.appearance == .projects, let table else { return }
            projectHeights.removeAll()
            table.noteHeightOfRows(withIndexesChanged:IndexSet(rows.indices))
            table.enumerateAvailableRowViews { _, row in
                if let cell = table.view(atColumn:0,row:row,makeIfNecessary:false) as? BrowserCell {
                    cell.titleHeight.constant = self.projectTitleHeight(row,width:table.tableColumns[0].width)
                }
            }
        }
        func numberOfRows(in tableView:NSTableView) -> Int { table = tableView; return rows.count }
        func tableView(_ tableView:NSTableView,rowViewForRow row:Int) -> NSTableRowView? { let view = BrowserRowView(); view.groupHeader = rows[row].header; view.projectStyle = parent.appearance == .projects; return view }
        func tableView(_ tableView:NSTableView,heightOfRow row:Int) -> CGFloat {
            parent.appearance == .projects ? (projectTitleHeight(row,width:tableView.tableColumns[0].width) > 20 ? 60 : 44) : rows[row].header ? 40 : 52
        }
        func tableView(_ tableView:NSTableView,shouldSelectRow row:Int) -> Bool { rows.indices.contains(row) && !rows[row].header }
        func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
            let id = NSUserInterfaceItemIdentifier("BrowserCell")
            let cell = (tableView.makeView(withIdentifier:id,owner:self) as? BrowserCell) ?? BrowserCell(); cell.identifier = id
            let value = rows[row]; let projectStyle = parent.appearance == .projects
            cell.title.font = .systemFont(ofSize:14,weight:value.header ? .semibold : .regular)
            cell.title.textColor = NSColor(WorkspaceTheme.ink)
            cell.title.cell?.usesSingleLineMode = !projectStyle
            cell.title.cell?.wraps = projectStyle
            cell.title.cell?.isScrollable = !projectStyle
            cell.title.maximumNumberOfLines = projectStyle ? 2 : 1
            cell.title.lineBreakMode = projectStyle ? .byWordWrapping : .byTruncatingMiddle
            cell.titleHeight.constant = projectStyle ? projectTitleHeight(row,width:tableColumn?.width ?? tableView.bounds.width) : value.header ? 18 : 22
            cell.iconWidth.constant = value.header ? 12 : 22
            cell.iconHeight.constant = value.header ? 12 : 24
            if value.header {
                let title = NSMutableAttributedString(string:value.title + "  ",attributes:[.font:NSFont.systemFont(ofSize:14,weight:.semibold),.foregroundColor:NSColor(WorkspaceTheme.ink)])
                title.append(NSAttributedString(string:String(value.count),attributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor(WorkspaceTheme.secondary)]))
                cell.title.attributedStringValue = title
            } else { cell.title.stringValue = value.title }
            cell.subtitle.stringValue = value.subtitle ?? ""; cell.subtitle.isHidden = value.subtitle == nil
            cell.titleCenter.constant = value.subtitle == nil ? 0 : -7
            cell.dateWidth.constant = value.date != nil && !value.header ? 112 : 0
            cell.date.stringValue = value.header ? "" : value.date?.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute()) ?? ""
            let symbol = value.folder ? "folder.fill" : value.file?.symbol ?? "doc"
            cell.icon.imageScaling = value.header ? .scaleNone : .scaleProportionallyUpOrDown
            cell.icon.image = value.header ? CategoryDisclosureImages.image(expanded:value.expanded) : value.folder ? WorkspaceTheme.folder : WorkspaceFileIcons.image(for:value.file) ?? NSImage(systemSymbolName:symbol,accessibilityDescription:"文件")
            cell.icon.contentTintColor = value.header ? NSColor(WorkspaceTheme.secondary) : nil
            cell.toolTip = value.title + (value.subtitle.map { "\n所属项目："+$0 } ?? ""); return cell
        }
        func tableViewSelectionDidChange(_ notification:Notification) {
            guard !updating, let t = notification.object as? NSTableView else { return }
            let selected = t.selectedRowIndexes.compactMap { rows.indices.contains($0) && !rows[$0].header ? rows[$0].id : nil }
            if parent.multipleSelection?.wrappedValue != Set(selected) { parent.multipleSelection?.wrappedValue = Set(selected) }
            let id = selected.count == 1 ? selected.first : nil
            if parent.selection != id { parent.selection = id }
        }
        var selectedRows: [BrowserRow] { guard let table else { return [] }; return table.selectedRowIndexes.compactMap { rows.indices.contains($0) && !rows[$0].header ? rows[$0] : nil } }
        func previewSelection() {
            guard let table = table as? BrowserNSTable, let window = table.window, window.attachedSheet == nil else { return }
            if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible { panel.orderOut(nil); return }
            table.quickLook.urls = selectedRows.map { URL(fileURLWithPath:$0.id) }
            guard !table.quickLook.urls.isEmpty else { return }
            window.makeFirstResponder(table)
            let panel = QLPreviewPanel.shared(); panel?.updateController(); panel?.makeKeyAndOrderFront(nil); panel?.reloadData(); panel?.currentPreviewItemIndex = 0
        }
        func trashSelection() { parent.trash?(selectedRows) }
        func renameSelection() { if selectedRows.count == 1 { parent.directRename?(selectedRows[0]) } else if !selectedRows.isEmpty { parent.batchRename?(selectedRows,false) } }
        func openSelection() { for row in selectedRows { parent.activate(row) } }
        func copySelection(to pasteboard:NSPasteboard) { copyFileRows(selectedRows,to:pasteboard) }
        @objc func clicked(_ sender:NSTableView) { if rows.indices.contains(sender.clickedRow), rows[sender.clickedRow].header { parent.toggle(rows[sender.clickedRow]) } }
        @objc func open(_ sender:NSTableView) { if rows.indices.contains(sender.clickedRow), !rows[sender.clickedRow].header { parent.activate(rows[sender.clickedRow]) } }
        func menuNeedsUpdate(_ menu:NSMenu) {
            menu.removeAllItems(); contextRow = nil
            guard let t = table, rows.indices.contains(t.clickedRow), !rows[t.clickedRow].header else { return }
            let row = rows[t.clickedRow]; contextRow = row
            contextRows = t.selectedRowIndexes.contains(t.clickedRow) ? t.selectedRowIndexes.compactMap { rows.indices.contains($0) && !rows[$0].header ? rows[$0] : nil } : [row]
            if parent.quickArchive != nil {
                let quick = NSMenuItem(title:"智能归档…",action:#selector(quickArchiveClicked),keyEquivalent:""); quick.target = self; menu.addItem(quick); menu.addItem(.separator())
            }
            if contextRows.count > 1, parent.batchRename != nil {
                let recommended = NSMenuItem(title:"批量智能命名（\(contextRows.count)项）…",action:#selector(batchRecommendClicked),keyEquivalent:""); recommended.target = self; menu.addItem(recommended)
                let manual = NSMenuItem(title:"批量更改名称…",action:#selector(batchManualClicked),keyEquivalent:""); manual.target = self; menu.addItem(manual)
            } else {
            let item = NSMenuItem(title:"智能命名…",action:#selector(renameClicked),keyEquivalent:""); item.target = self; menu.addItem(item)
            if parent.directRename != nil {
                let manual = NSMenuItem(title:"更改名称…",action:#selector(directRenameClicked),keyEquivalent:""); manual.target = self; menu.addItem(manual)
            }
            }
            let categories = contextRows.count > 1 ? parent.batchCategoryOptions(contextRows) : parent.categoryOptions(row)
            if !categories.isEmpty {
                menu.addItem(.separator())
                for category in categories {
                    let move = NSMenuItem(title:"移动到「"+category.name+"」",action:#selector(categoryClicked(_:)),keyEquivalent:"")
                    move.target = self; move.representedObject = category.id; menu.addItem(move)
                }
            }
            menu.addItem(.separator())
            let reveal = NSMenuItem(title:"在 Finder 中显示",action:#selector(revealClicked),keyEquivalent:""); reveal.target = self; menu.addItem(reveal)
        }
        @objc func quickArchiveClicked() { parent.quickArchive?(contextRows) }
        @objc func batchRecommendClicked() { parent.batchRename?(contextRows,true) }
        @objc func batchManualClicked() { parent.batchRename?(contextRows,false) }
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard !parent.dragScope.isEmpty, rows.indices.contains(row), !rows[row].header, let identity = fileIdentity(rows[row].id) else { return nil }
            let item = NSPasteboardItem()
            guard let data = try? JSONEncoder().encode(CategoryDragItem(path:rows[row].id,identity:identity,scope:parent.dragScope)) else { return nil }
            item.setData(data,forType:categoryDragType)
            return item
        }
        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) { parent.dragging(true) }
        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { parent.dragging(false) }
        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
            guard rows.indices.contains(row), rows[row].categoryID != nil, let values = categoryDropRows(info.draggingPasteboard,scope:parent.dragScope,rows:rows), !values.isEmpty else { return [] }
            tableView.setDropRow(row,dropOperation:.on); return .move
        }
        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            guard rows.indices.contains(row), let id = rows[row].categoryID, let values = categoryDropRows(info.draggingPasteboard,scope:parent.dragScope,rows:rows) else { return false }
            parent.moveCategories(values,id); return true
        }
        @objc func renameClicked() { if let row = contextRow { parent.rename(row) } }
        @objc func directRenameClicked() { if let row = contextRow { parent.directRename?(row) } }
        @objc func categoryClicked(_ item: NSMenuItem) { if let row = contextRow, let id = item.representedObject as? String { if contextRows.count > 1 { parent.moveCategories(contextRows,id) } else { parent.moveCategory(row,id) } } }
        @objc func revealClicked() { if let row = contextRow { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:row.id)]) } }

    }
}
final class BrowserRowView: NSTableRowView {
    var groupHeader = false; var projectStyle = false
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override func drawBackground(in dirtyRect:NSRect) {
        (projectStyle ? WorkspaceTheme.projectPaper : WorkspaceTheme.paper).setFill(); bounds.fill()
        if groupHeader { WorkspaceTheme.section.setFill(); NSBezierPath(roundedRect:bounds.insetBy(dx:12,dy:3),xRadius:8,yRadius:8).fill() }
        else {
            NSColor(WorkspaceTheme.line).withAlphaComponent(0.55).setFill()
            NSRect(x:52,y:bounds.maxY-0.5,width:max(0,bounds.width-68),height:0.5).fill()
        }
    }
    override func drawSelection(in dirtyRect:NSRect) {
        WorkspaceTheme.selection.setFill(); NSBezierPath(roundedRect:bounds.insetBy(dx:6,dy:2),xRadius:9,yRadius:9).fill()
    }
}
final class BrowserNSTable: NSTableView {
    var onSpace: (() -> Void)?; var onTrash: (() -> Void)?; var onRename: (() -> Void)?; var onOpen: (() -> Void)?; var onCopy: (() -> Void)?
    var copyPasteboard: NSPasteboard = .general
    var onColumnWidthChange: (() -> Void)?
    private var measuredColumnWidth: CGFloat = -1
    override func layout() {
        super.layout()
        let width = tableColumns.first?.width ?? 0
        if abs(width-measuredColumnWidth) > 0.5 {
            measuredColumnWidth = width
            onColumnWidthChange?()
        }
    }
    let quickLook = FileQuickLook()
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { !quickLook.urls.isEmpty }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = quickLook; panel.delegate = quickLook }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil; panel.delegate = nil }
    func performFileShortcut(_ event: NSEvent) -> Bool {
        guard let window, window.firstResponder === self, window.attachedSheet == nil, let action = fileShortcut(for:event) else { return false }
        let handler: (() -> Void)?
        switch action { case .preview: handler = onSpace; case .trash: handler = onTrash; case .rename: handler = onRename; case .open: handler = onOpen; case .copy: handler = onCopy }
        guard let handler else { return false }; handler(); return true
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { performFileShortcut(event) || super.performKeyEquivalent(with:event) }
    override func keyDown(with event:NSEvent) { if !performFileShortcut(event) { super.keyDown(with:event) } }
    @objc func copy(_ sender:Any?) {
        guard let window,window.firstResponder === self,window.attachedSheet == nil else { return }
        onCopy?()
    }
}
final class BrowserCell: NSTableCellView {
    let icon = NSImageView(); let title = NSTextField(labelWithString:""); let subtitle = NSTextField(labelWithString:""); let date = NSTextField(labelWithString:""); var dateWidth: NSLayoutConstraint!; var titleHeight: NSLayoutConstraint!
    var iconWidth: NSLayoutConstraint!; var iconHeight: NSLayoutConstraint!; var titleCenter: NSLayoutConstraint!
    init() {
        super.init(frame:.zero); title.lineBreakMode = .byTruncatingMiddle; date.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular); date.textColor = NSColor(WorkspaceTheme.secondary); date.alignment = .right; icon.imageScaling = .scaleProportionallyUpOrDown
        subtitle.font = .systemFont(ofSize:11); subtitle.textColor = NSColor(WorkspaceTheme.secondary); subtitle.lineBreakMode = .byTruncatingMiddle; subtitle.isHidden = true
        for v in [icon,title,subtitle,date] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        dateWidth = date.widthAnchor.constraint(equalToConstant:112)
        titleHeight = title.heightAnchor.constraint(equalToConstant:22)
        iconWidth = icon.widthAnchor.constraint(equalToConstant:22)
        iconHeight = icon.heightAnchor.constraint(equalToConstant:24)
        titleCenter = title.centerYAnchor.constraint(equalTo:centerYAnchor)
        NSLayoutConstraint.activate([subtitle.leadingAnchor.constraint(equalTo:title.leadingAnchor),subtitle.trailingAnchor.constraint(equalTo:title.trailingAnchor),subtitle.centerYAnchor.constraint(equalTo:centerYAnchor,constant:13),subtitle.heightAnchor.constraint(equalToConstant:14),icon.leadingAnchor.constraint(equalTo:leadingAnchor,constant:16),icon.centerYAnchor.constraint(equalTo:centerYAnchor),iconWidth!,iconHeight!,title.leadingAnchor.constraint(equalTo:icon.trailingAnchor,constant:12),titleCenter!,title.trailingAnchor.constraint(equalTo:date.leadingAnchor,constant:-10),titleHeight,date.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-16),date.centerYAnchor.constraint(equalTo:centerYAnchor),dateWidth])
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not used") }
}

struct ProjectWorkspace: View {
    @StateObject var search = WorkspaceSearchController()
    @StateObject var store = Store(); @State var year = ""; @State var projectPath: String?; @State var filePath: String?; @State var query = ""; @State var mode = "按类别"
    @State var collapsed = Set<String>(); @State var sourceFolder = ""; @State var sourceRows: [BrowserRow] = []; @State var naming: NamingTarget?; @State var manualNaming: NamingTarget?
    @State var fileSelections = Set<String>(); @State var isDragging = false; @State var batchNaming: BatchNamingRequest?; @State var processedRenameCount = 0
    @State var settingsDestination: SettingsSection?
     @State var showPreview = false; @State var showPending = false
    @State var sourceLoading = false; @State var sourceError = ""; @State var sourceGeneration = UUID()
    @State var projectOrder = "月份倒序"; @State var archiveSourceID: String?; @State var quickArchiveRequest: QuickArchiveRequest?
    @State var searchFocused = false
    @State var sidebarPreviewFraction: Double?; @State var sidebarDragOrigin: CGFloat?
    @State var searchFolderToOpen: String?
    @State private var archiveAfterNaming:QuickArchiveRequest?
    var isScopeSearch: Bool { archiveSourceID == nil && !FilenameQuery(query).tokens.isEmpty }
    var activeSourceRows: [BrowserRow] { isScopeSearch ? search.output.searchEntries : sourceRows }
    var activeDragScope: String { isScopeSearch ? "search:"+(selectedDirectory?.path ?? year) : sourceFolder }
    var years: [String] { store.orderedDirectories.map(\.scopeID) }
    var selectedDirectory: Project? { store.settings.projects.first { $0.shallow == true && $0.scopeID == year } }
    var project: Project? { store.settings.projects.first { $0.path == projectPath && $0.shallow != true && $0.scopeID == year } }
    var selectedFile: FileItem? { guard fileSelections.count <= 1 else { return nil }; return store.files.first { $0.path == filePath } ?? activeSourceRows.first { $0.id == filePath }?.file }
    var projectRows: [BrowserRow] { search.output.projectRows }
    var fileRows: [BrowserRow] { search.output.fileRows }
    func refreshSearch() {
        search.submit(index:store.filenameIndex,query:query,scope:year,projects:store.settings.projects,files:store.files,sourceRows:sourceRows,byMonth:projectOrder == "月份倒序",mode:mode,collapsed:collapsed,categories:store.workspaceCategories,assignments:store.workspaceAssignments,aggregateThirdLevel:isScopeSearch,metadataRevision:store.searchRevision+store.fileOperationRevision)
    }
    var body: some View {
        VStack(spacing:0) {
            HSplitView {
                yearsPane.frame(minWidth:200,idealWidth:220,maxWidth:280)
                VStack(spacing:0) {
                    listToolbar
                    if let source = store.availableArchiveSources.first(where:{$0.id == archiveSourceID}) { ArchiveSourcePane(store:store,source:source).id(source.id) }
                    else { projectsPane }
                }.background(WorkspaceTheme.projectCanvas).frame(minWidth:340,idealWidth:390,maxWidth:.infinity)
                VStack(spacing:0) {
                    if store.workspaceCategories.isEmpty { CategorySetupPlaceholder { settingsDestination = .categories } }
                    else if archiveSourceID == nil && (project != nil || isScopeSearch) { filesPane }
                    else { WorkspaceTheme.canvas }
                    Divider()
                    WorkspaceStatus(progress:store.progress,busy:store.busy,count:isScopeSearch ? activeSourceRows.count : (project != nil && archiveSourceID == nil ? sourceRows.count : nil))
                }.frame(minWidth:store.workspaceCategories.isEmpty || (archiveSourceID == nil && (project != nil || isScopeSearch)) ? 430 : 0,idealWidth:570,maxWidth:.infinity)
            }.background(WorkspaceSplitLayout())
        }.frame(minWidth:1060,minHeight:700).background(WorkspaceTheme.canvas).tint(accent).ignoresSafeArea(.container,edges:.top)
        .onAppear { processedRenameCount = store.settings.renames?.count ?? 0; if !years.contains(year) { year = years.first ?? "" }; refreshSearch() }
        .onChange(of:query) { _ in fileSelections = []; filePath = nil; refreshSearch() }
        .onChange(of:store.searchRevision) { _ in refreshSearch() }
        .onChange(of:sourceRows) { _ in refreshSearch() }
        .onChange(of:collapsed) { _ in refreshSearch() }
        .onChange(of:store.workspaceCategories) { _ in refreshSearch() }
        .onChange(of:store.workspaceAssignments) { _ in refreshSearch() }
        .onChange(of:projectOrder) { _ in refreshSearch() }
        .onChange(of:archiveSourceID) { _ in refreshSearch() }
        .onChange(of:store.settings.archiveSources) { _ in if let id = archiveSourceID, !store.availableArchiveSources.contains(where:{$0.id == id}) { archiveSourceID = nil } }
        .onChange(of:store.settings.projects) { _ in
            if !years.contains(year) { year = years.first ?? "" }
            if let path = projectPath, !store.settings.projects.contains(where:{$0.path == path}) {
                if let change = store.settings.renames?.last, path == change.source { projectPath = change.destination } else { projectPath = nil; filePath = nil }
            }
            refreshSearch()
        }
        .onChange(of:year) { _ in projectPath = nil; filePath = nil; fileSelections = []; sourceRows = []; sourceFolder = ""; loadSource(); refreshSearch() }
        .onChange(of:projectPath) { path in if path != nil { archiveSourceID = nil }; filePath = nil; fileSelections = []; sourceRows = []; sourceFolder = searchFolderToOpen ?? projectPath ?? ""; searchFolderToOpen = nil; loadSource() }
        .onChange(of:mode) { _ in filePath = nil; fileSelections = []; collapsed = []; refreshSearch() }
        .onChange(of:store.fileOperationRevision) { _ in fileSelections = []; filePath = nil; loadSource() }
        .onChange(of:store.metadataReady) { ready in if ready { loadSource() } }
        .onChange(of:store.settings.renames?.count) { _ in
            for last in (store.settings.renames ?? []).dropFirst(processedRenameCount) {
                projectPath = projectPath.map { remapPath($0,source:last.source,destination:last.destination,folder:last.folder) }
                fileSelections = Set(fileSelections.map { remapPath($0,source:last.source,destination:last.destination,folder:last.folder) })
                filePath = filePath.map { remapPath($0,source:last.source,destination:last.destination,folder:last.folder) }
                sourceFolder = remapPath(sourceFolder,source:last.source,destination:last.destination,folder:last.folder)
            }
            processedRenameCount = store.settings.renames?.count ?? 0; loadSource()
        }
        .sheet(item:$quickArchiveRequest) { QuickArchiveDialog(store:store,request:$0) }
        .sheet(item:$naming,onDismiss:{
            if let request = archiveAfterNaming { archiveAfterNaming = nil;quickArchiveRequest = request }
        }) { RenameDialog(store:store,target:$0,onArchive:{archiveAfterNaming = $0}) }
        .sheet(item:$batchNaming) { BatchRenameDialog(store:store,request:$0) }
        .sheet(item:$manualNaming) { DirectRenameDialog(store:store,target:$0) }
        .sheet(item:$settingsDestination) { destination in workspaceSettings(destination) }
        .sheet(isPresented:$showPending) { PendingDialog(store:store) }
        .alert("操作未完成",isPresented:Binding(get:{!store.error.isEmpty && archiveSourceID == nil && naming == nil && manualNaming == nil && batchNaming == nil && quickArchiveRequest == nil && settingsDestination == nil},set:{if !$0 { store.error = "" }})) { Button("知道了") { store.error = "" } } message: { Text(store.error) }
    }
    var sidebarHeader: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(spacing:10) {
                if let logo = NSImage(named:"GuiyuLogo") { Image(nsImage:logo).resizable().scaledToFit().frame(width:54,height:56).accessibilityLabel("归屿小鸡") }
                Text("归屿").font(.system(size:22,weight:.semibold,design:.rounded))
            }
            HStack(spacing:9) {
                Image(systemName:"magnifyingglass").font(.system(size:14))
                SidebarSearchField(text:$query,focused:$searchFocused).frame(height:20)
            }.foregroundStyle(WorkspaceTheme.sidebarText).padding(.horizontal,12).frame(height:36)
                .background(Color.black.opacity(0.08),in:RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).stroke(searchFocused ? WorkspaceTheme.sidebarText : WorkspaceTheme.sidebarMuted.opacity(0.4),lineWidth:searchFocused ? 2 : 1))
        }.padding(.top,20)
    }
    var listToolbar: some View {
        HStack(spacing:8) {
            Spacer(minLength:0)
            Button { refreshWorkspace() } label: { Label("刷新",systemImage:"arrow.clockwise") }
                .buttonStyle(SoftWorkspaceButton()).disabled(store.busy).help("刷新全部项目和当前文件列表，不自动归档")
            Menu {
                Button("月份倒序") { projectOrder = "月份倒序" }
                Button("最近修改") { projectOrder = "最近修改" }
            } label: {
                HStack(spacing:14) { Text(projectOrder); Image(systemName:"chevron.down").font(.system(size:10,weight:.semibold)) }
                    .font(.system(size:13,weight:.medium)).foregroundStyle(WorkspaceTheme.ink)
            }.menuStyle(.button).buttonStyle(SoftWorkspaceButton()).menuIndicator(.hidden).fixedSize()
        }.padding(.horizontal,14).frame(height:56).background(WorkspaceTheme.projectCanvas)
    }
    func refreshWorkspace() {
        guard !store.busy else { return }
        store.refresh()
        store.globalRefreshRevision += 1
        loadSource()
    }
    var sidebarPreferredProjectHeight: CGFloat {
        let roots = store.settings.activeProjectRoots
        let rows = CGFloat(store.orderedDirectories.count)*DirectoryOrderRowView.dropHeight
        let groupHeadings = roots.count > 1 ? CGFloat(roots.count)*21+CGFloat(max(0,roots.count-1))*12 : 0
        return 50+max(0,rows-CGFloat(roots.count)*DirectoryOrderRowView.dropPadding*2)+groupHeadings
    }
    var yearsPane: some View {
        VStack(alignment:.leading,spacing:20) {
            sidebarHeader
            GeometryReader { geometry in
                let total = geometry.size.height
                let height = SidebarSectionsLayout.projectHeight(total:total,fraction:sidebarPreviewFraction ?? store.settings.sidebarProjectsFraction,preferred:sidebarPreferredProjectHeight)
                VStack(spacing:0) {
                    VStack(alignment:.leading,spacing:18) {
                        projectDirectoryHeading
                        ScrollView { projectDirectoryList.padding(.vertical,1) }
                    }.frame(height:height)
                    SidebarSectionDivider(fraction:SidebarSectionsLayout.fraction(height:height,total:total),begin:{ sidebarDragOrigin = height },change:{ delta in
                        let value = SidebarSectionsLayout.projectHeight(total:total,fraction:SidebarSectionsLayout.fraction(height:(sidebarDragOrigin ?? height)+delta,total:total),preferred:sidebarPreferredProjectHeight)
                        sidebarPreviewFraction = SidebarSectionsLayout.fraction(height:value,total:total)
                    },finish:{
                        if let fraction = sidebarPreviewFraction { _ = store.saveSidebarFraction(fraction) }
                        sidebarPreviewFraction = nil; sidebarDragOrigin = nil
                    },cancel:{ sidebarPreviewFraction = nil; sidebarDragOrigin = nil },nudge:{ delta in
                        let value = SidebarSectionsLayout.projectHeight(total:total,fraction:SidebarSectionsLayout.fraction(height:height+delta,total:total),preferred:sidebarPreferredProjectHeight)
                        _ = store.saveSidebarFraction(SidebarSectionsLayout.fraction(height:value,total:total))
                    }).frame(height:SidebarSectionsLayout.dividerHeight)
                    VStack(alignment:.leading,spacing:18) {
                        archiveSourcesHeading.padding(.top,8)
                        ScrollView { archiveSourcesList.padding(.vertical,1) }
                    }.frame(maxHeight:.infinity,alignment:.top)
                }
            }
            Button { settingsDestination = .locations } label: { HStack(spacing:12) { Image(systemName:"gearshape").font(.system(size:19)); Text("设置"); Spacer() }.frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle()) }.buttonStyle(.plain).padding(.horizontal,12)
                .background(Color.white.opacity(0.10),in:RoundedRectangle(cornerRadius:10))
        }.padding(16).foregroundStyle(WorkspaceTheme.sidebarText).background(WorkspaceTheme.sidebar)
    }
    var projectDirectoryHeading: some View {
        HStack {
                Text("项目目录").font(.system(size:12,weight:.semibold)).foregroundStyle(WorkspaceTheme.sidebarMuted)
                Spacer()
                Button { store.chooseProjectRoots() } label: { Image(systemName:"plus").frame(width:24,height:24) }.buttonStyle(.plain).help("关联项目总目录，可添加多个").accessibilityLabel("关联项目总目录")
            }.padding(.top,6)
    }
    var projectDirectoryList: some View {
        VStack(alignment:.leading,spacing:12) {
                ForEach(store.settings.activeProjectRoots,id:\.self) { root in
                    VStack(alignment:.leading,spacing:8) {
                        if store.settings.activeProjectRoots.count > 1 {
                            Text(store.rootDisplayName(root)+(store.unavailableProjectRoots.contains(root) ? " · 暂不可访问" : "")).font(.system(size:11,weight:.medium)).foregroundStyle(WorkspaceTheme.sidebarMuted).lineLimit(1).help(root)
                                .contextMenu { Button("在 Finder 中显示") { NSWorkspace.shared.selectFile(nil,inFileViewerRootedAtPath:root) }; Button("移除关联") { _ = store.removeProjectRoot(root) } }
                        }
                        VStack(spacing:0) {
                            ForEach(store.directories(in:root)) { directory in
                                DirectoryOrderRow(store:store,directory:directory,selected:year == directory.scopeID && archiveSourceID == nil) {
                                    archiveSourceID = nil; projectPath = nil; year = directory.scopeID
                                }.frame(height:DirectoryOrderRowView.dropHeight)
                            }
                        }.padding(.vertical,-DirectoryOrderRowView.dropPadding)
                    }
                }
            }
    }
    var archiveSourcesHeading: some View {
        HStack { Text("可归档目录").font(.system(size:12,weight:.semibold)).foregroundStyle(WorkspaceTheme.sidebarMuted); Spacer(); Button { if let id = store.chooseArchiveSource() { archiveSourceID = id; projectPath = nil } } label: { Image(systemName:"plus").frame(width:24,height:24) }.buttonStyle(.plain).help("关联文件夹") }
    }
    var archiveSourcesList: some View {
        VStack(alignment:.leading,spacing:18) {
            ForEach(store.availableArchiveSources) { source in
                Button { projectPath = nil; archiveSourceID = source.id } label: {
                    HStack(spacing:10) { Image(systemName:source.kind == "recent" ? "clock" : "tray.and.arrow.down").font(.system(size:18)).foregroundStyle(WorkspaceTheme.sidebarText); Text(source.name).lineLimit(1); Spacer() }
                        .padding(.horizontal,9)
                        .frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
                        .foregroundStyle(WorkspaceTheme.sidebarText)
                        .background(archiveSourceID == source.id ? WorkspaceTheme.sidebarSelection : .clear,in:RoundedRectangle(cornerRadius:12))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).help(source.kind == "recent" ? "系统最近使用的文件" : source.path)
            }
        }
    }
    var projectsPane: some View {
        VStack(alignment:.leading,spacing:0) {
            if projectRows.isEmpty { VStack(spacing:14) { Spacer(); Image(systemName:"folder").font(.largeTitle).foregroundStyle(accent); Text(store.busy ? "正在读取项目目录…" : (!store.settings.hasProjectRoots ? "在设置中选择项目总目录，开始浏览" : "当前目录没有匹配的项目或文件")).foregroundStyle(.secondary); if !store.settings.hasProjectRoots { Button("打开设置") { settingsDestination = .locations }.buttonStyle(.borderedProminent); Button("体验示例空间") { store.demo() } }; Spacer() }.frame(maxWidth:.infinity) }
            else { BrowserTable(rows:projectRows,selection:$projectPath,dataset:year,appearance:.projects,activate:{ row in if row.folder { query = ""; projectPath = row.id } else if let file = row.file { NSWorkspace.shared.open(file.url) } },rename:{ requestRename($0.id,folder:$0.folder) },directRename:{ requestDirectRename($0) },trash:{ _ = store.moveToTrash($0,undoManager:NSApplication.shared.keyWindow?.undoManager) }) }
        }
    }
    var filesPane: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:2) {
                ForEach(["按类别","按时间","源文档"],id:\.self) { value in
                    Button { mode = value } label: {
                        Text(value).font(.system(size:13,weight:mode == value ? .semibold : .medium))
                            .foregroundStyle(mode == value ? accent : WorkspaceTheme.ink)
                            .frame(width:76,height:32)
                            .background(mode == value ? Color.white : Color.clear,in:RoundedRectangle(cornerRadius:7))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(mode == value ? .isSelected : [])
                }
            }.padding(3).background(Color(nsColor:NSColor(white:0.95,alpha:1)),in:RoundedRectangle(cornerRadius:9))
                .padding(.horizontal,20).frame(height:56)
            if isScopeSearch {
                HStack { Text("搜索结果 · 全部项目").font(.caption); Spacer(); Text("\(activeSourceRows.count) 项").font(.caption) }.foregroundStyle(WorkspaceTheme.secondary).padding(.horizontal,20).padding(.bottom,10)
                if !search.output.unavailableProjects.isEmpty { Text("部分项目无法读取，已显示其余结果；请检查访问权限后刷新。").font(.caption).foregroundStyle(.secondary).padding(.horizontal,20).padding(.bottom,8) }
            }
            if !isScopeSearch, let p = project, sourceFolder != p.path {
                DirectoryBreadcrumbBar(root:p.path,current:sourceFolder,rootTitle:"项目根目录",navigate:navigateSource).padding(.horizontal,20).padding(.bottom,8)
            }
            if fileSelections.count > 1 { HStack(spacing:10) {
                Text("已选 \(fileSelections.count) 项").font(.caption).foregroundStyle(.secondary)
                    Button("全选") { fileSelections = Set(fileRows.filter { !$0.header }.map(\.id)) }
                    Button("取消选择") { fileSelections = []; filePath = nil }
                    Menu("批量操作") {
                        Button("批量智能命名…") { requestBatchNaming(selectedRows,recommended:true) }
                        Button("批量更改名称…") { requestBatchNaming(selectedRows,recommended:false) }
                        ForEach(batchCategoryDestinations(selectedRows,categories:store.workspaceCategories,assignments:store.workspaceAssignments)) { category in Button("移动到「"+category.name+"」") { _ = store.assignCategories(selectedRows,to:category.id) } }
                    }.disabled(fileSelections.isEmpty)
                Spacer()
            }.padding(.horizontal,20).padding(.vertical,8) }
            if isDragging {
                ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:8) { ForEach(store.workspaceCategories) { category in
                    CategoryDropTarget(category:category,scope:activeDragScope,rows:activeSourceRows) { rows in _ = store.assignCategories(rows,to:category.id) }.frame(width:max(76,CGFloat(category.name.count)*13+24),height:30)
                } } }.padding(.horizontal,20).padding(.bottom,8)
            }
            Divider()
            if isScopeSearch && search.isSearching { VStack { Spacer(); ProgressView("正在搜索…"); Spacer() }.frame(maxWidth:.infinity) }
            else if isScopeSearch && activeSourceRows.isEmpty { VStack { Spacer(); Text("没有匹配的三级文件或文件夹").foregroundStyle(.secondary); Spacer() }.frame(maxWidth:.infinity) }
            else if project == nil && !isScopeSearch { VStack { Spacer(); Text("在中间选择项目，查看其中的资料").foregroundStyle(.secondary); Spacer() }.frame(maxWidth:.infinity) }
            else if sourceLoading && !isScopeSearch { VStack { Spacer(); ProgressView("正在读取当前目录…"); Spacer() }.frame(maxWidth:.infinity) }
            else if !sourceError.isEmpty && !isScopeSearch { VStack { Spacer(); Text(sourceError).foregroundStyle(.secondary); Button("重试") { loadSource() }; Spacer() }.padding().frame(maxWidth:.infinity) }
            else { BrowserTable(rows:fileRows,selection:$filePath,multipleSelection:$fileSelections,batchRename:{ rows,recommended in requestBatchNaming(rows,recommended:recommended) },batchCategoryOptions:{ rows in batchCategoryDestinations(rows,categories:store.workspaceCategories,assignments:store.workspaceAssignments) },moveCategories:{ rows,id in _ = store.assignCategories(rows,to:id) },dragScope:activeDragScope,dragging:{ isDragging = $0 },dataset:(isScopeSearch ? "search:"+year : (project?.path ?? ""))+"|"+mode+"|"+(isScopeSearch ? query : sourceFolder),activate:{ row in if isScopeSearch && row.folder { openSearchFolder(row) } else if row.folder { if store.settings.projects.contains(where:{$0.path == row.id && $0.shallow != true}) { projectPath = row.id } else { sourceFolder = row.id; filePath = nil; loadSource() } } else if let f = row.file { NSWorkspace.shared.open(f.url) } },rename:{ requestRename($0.id,folder:$0.folder) },directRename:{ requestDirectRename($0) },quickArchive:{ quickArchiveRequest = QuickArchiveRequest(rows:$0) },trash:{ _ = store.moveToTrash($0,undoManager:NSApplication.shared.keyWindow?.undoManager) },categoryOptions:{ categoryDestinations($0,categories:store.workspaceCategories,assignments:store.workspaceAssignments) },moveCategory:{ row,id in _ = store.assignCategory(row,to:id) },toggle:{ row in if collapsed.contains(row.id) { collapsed.remove(row.id) } else { collapsed.insert(row.id) } },previewRequest:$showPreview) }
        }
    }
    var selectedRows: [BrowserRow] { activeSourceRows.filter { fileSelections.contains($0.id) } }
    func requestBatchNaming(_ rows: [BrowserRow], recommended: Bool) {
        guard !rows.isEmpty else { return }
        batchNaming = BatchNamingRequest(rows:rows,projectPath:project?.path ?? sourceFolder,recommended:recommended)
    }
    func openSearchFolder(_ row:BrowserRow) {
        guard let owner = projectOwnerPath(row.id,projects:store.settings.projects) else { return }
        query = ""; filePath = nil; fileSelections = []
        if projectPath == owner { sourceFolder = row.id; loadSource() }
        else { searchFolderToOpen = row.id; projectPath = owner }
    }
    func navigateSource(to path:String) {
        guard let p = project, let destination = DirectoryBreadcrumb.destination(path,root:p.path,current:sourceFolder) else { return }
        filePath = nil; fileSelections = []; showPreview = false
        sourceFolder = destination; loadSource()
    }
    func requestDirectRename(_ row: BrowserRow) { manualNaming = NamingTarget(path:row.id,folder:row.folder,projectPath:row.file?.project ?? projectOwnerPath(row.id,projects:store.settings.projects) ?? project?.path ?? row.id) }
    func requestRename(_ path: String, folder: Bool) { naming = NamingTarget(path:path,folder:folder,projectPath:projectOwnerPath(path,projects:store.settings.projects) ?? project?.path ?? selectedDirectory?.path ?? path) }
    func loadSource() {
        let generation = UUID(); sourceGeneration = generation
        guard let p = project else { sourceRows = []; sourceLoading = false; sourceError = ""; return }
        if sourceFolder.isEmpty { sourceFolder = p.path }
        let path = sourceFolder; sourceLoading = true; sourceError = ""
        DispatchQueue.global(qos:.userInitiated).async {
            let result = Result { try directoryEntries(path:path,project:p.path) }
            DispatchQueue.main.async {
                guard sourceGeneration == generation, sourceFolder == path, project?.path == p.path else { return }
                sourceLoading = false
                switch result {
                case .success(let rows): sourceRows = rows
                case .failure(let error): sourceRows = []; sourceError = "无法读取当前目录："+error.localizedDescription
                }
            }
        }
    }
    func workspaceSettings(_ destination:SettingsSection) -> some View {
        WorkspaceSettingsView(store:store,close:{ settingsDestination = nil },openPending:{
            settingsDestination = nil
            DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { showPending = true }
        },section:destination)
    }

}
struct PendingDialog: View {
    @Environment(\.dismiss) var dismiss; @ObservedObject var store: Store; @State var selected: String?; @State var project = ""
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("待确认文件").font(.title2.bold()); Spacer(); Button("关闭") { dismiss() } }
            BrowserTable(rows:store.incoming.map { BrowserRow(id:$0.path,title:$0.name,date:$0.date,file:$0) },selection:$selected,activate:{ if let f = $0.file { NSWorkspace.shared.open(f.url) } },rename:{ _ in }).frame(height:280)
            HStack { Picker("归入项目",selection:$project) { Text("选择项目").tag(""); ForEach(store.settings.projects.filter{$0.shallow != true}) { Text(($0.group.map{$0+" / "} ?? "")+$0.name).tag($0.path) } }; Button("确认归档") { if let f = store.incoming.first(where:{$0.path == selected}), let p = store.settings.projects.first(where:{$0.path == project}) { store.archive(f,to:p) } }.disabled(selected == nil || project.isEmpty || store.busy) }
            Divider(); Text("最近归档").font(.headline)
            ScrollView { ForEach(Array(store.settings.moves.prefix(12))) { move in HStack { VStack(alignment:.leading) { Text(URL(fileURLWithPath:move.destination).lastPathComponent).lineLimit(1); Text(move.date.formatted()).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(move.undone ? "已撤销" : "撤销") { store.undo(move) }.disabled(move.undone) }.padding(.vertical,5) } }.frame(height:160)
        }.padding(24).frame(width:740)
    }
}
