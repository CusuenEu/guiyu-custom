import AppKit
import SwiftUI

private struct IconManifest: Decodable {
    struct Kind: Decodable { let id: String; let extensions: [String] }
    let types: [Kind]
    static func load() throws -> IconManifest {
        guard let url = Bundle.main.url(forResource:"FileTypeIcons-manifest",withExtension:"json") else { throw namingError("缺少文件图标清单") }
        return try JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
    }
}

@MainActor func fileTypeIconsTests(root: URL) throws {
    let manifest = try IconManifest.load()
    try verify(manifest.types.count == 45,"Package all 45 icon families")
    var aliases = 0
    for kind in manifest.types {
        let name = "file-type-"+kind.id
        guard let raw = WorkspaceFileIcons.catalogImage(named:name) else { throw namingError("缺少图标："+name) }
        try verify(raw.representations.compactMap { ($0 as? NSBitmapImageRep)?.pixelsWide }.sorted() == [32,64,96],"Keep all catalog scales: "+name)
        for ext in kind.extensions {
            let row = BrowserRow(id:"/not-a-real-user-file/示例."+ext.uppercased(),title:"合同.pdf")
            try verify(WorkspaceFileIcons.assetName(for:row) == name,"Shared extension map: "+ext)
            guard let image = WorkspaceFileIcons.image(for:row) else { throw namingError("图标未加载："+name) }
            try verify(image.isValid && !image.isTemplate && image.size == NSSize(width:32,height:32),"Colored catalog image: "+name)
            try verify(WorkspaceFileIcons.image(for:row) === image,"Reuse cached images")
            aliases += 1
        }
        if Bundle.main.url(forResource:"Assets",withExtension:"car") != nil {
            try verify(NSImage(named:NSImage.Name(name)) != nil,"Load compiled asset by name: "+name)
        }
    }
    try verify(aliases == 334,"Match all 334 extension aliases")
    for (name,id) in [("项目计划.xlsx","excel"),("进度.mpp","project"),("归档.TAR.GZ","archive"),("网页.HTML","html"),("未知.zzz","unknown"),("没有后缀","unknown"),("setup.exe","application"),("系统.dmg","disk")] {
        try verify(FileTypeIcons.iconID(for:name) == id,"Use actual format: "+name)
    }
    for name in ["普通目录","目录.docx","目录.pdf"] {
        let row = BrowserRow(id:"/fixture/"+name,title:name,folder:true)
        try verify(WorkspaceFileIcons.assetName(for:row) == nil && WorkspaceFileIcons.image(for:row) === WorkspaceTheme.folder,"Preserve ordinary folder icons")
    }
    for (name,id) in [("归屿.app","application"),("演示.key","powerpoint"),("文稿.pages","word")] {
        try verify(WorkspaceFileIcons.assetName(for:BrowserRow(id:"/fixture/"+name,title:name,folder:true)) == "file-type-"+id,"Recognize document bundles")
    }
    let original = root.appendingPathComponent("图标测试.pdf"), alias = root.appendingPathComponent("图标测试替身")
    try Data("fixture".utf8).write(to:original)
    let bookmark = try original.bookmarkData(options:.suitableForBookmarkFile,includingResourceValuesForKeys:nil,relativeTo:nil)
    try URL.writeBookmarkData(bookmark,to:alias)
    guard let entry = browserEntry(alias.path), let listed = try directoryEntries(path:root.path,project:root.path).first(where:{$0.id == alias.path}) else { throw namingError("替身元数据未读取") }
    try verify(entry.isAlias && listed.isAlias && WorkspaceFileIcons.assetName(for:listed) == "file-type-shortcut","Pass real Finder alias metadata without resolving the target")
    try verify(WorkspaceFileIcons.image(for:BrowserRow(id:"header",title:"分类",header:true)) == nil,"Preserve category disclosure arrows")
    print("PASS: 45 catalog icons, 334 shared aliases, all scales, cache, unknown files, folders, bundles and real Finder aliases")
}

@MainActor func fileTypeIconsUIReview() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let manifest = try IconManifest.load()
    let rows = manifest.types.map { kind in
        let ext = kind.extensions.first ?? "unknown-format"
        return BrowserRow(id:"/fixture/示例."+ext,title:kind.id+" · 示例."+ext)
    }
        + [BrowserRow(id:"/fixture/普通目录",title:"普通目录",folder:true),BrowserRow(id:"/fixture/归屿.app",title:"归屿.app",folder:true),BrowserRow(id:"/fixture/替身",title:"Finder 替身",isAlias:true)]
    let out = URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent(".impeccable/review/file-type-icons")
    try fm.createDirectory(at:out,withIntermediateDirectories:true)
    func capture<V: View>(_ view: V, size:NSSize, name:String) throws {
        let host = NSHostingView(rootView:view.preferredColorScheme(.light)); host.frame = NSRect(origin:.zero,size:size)
        let window = NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:size.width,height:size.height),styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView = host; window.orderBack(nil); defer { window.orderOut(nil) }
        RunLoop.current.run(until:Date().addingTimeInterval(0.5)); host.layoutSubtreeIfNeeded()
        func tables(_ view:NSView) -> [NSTableView] { (view as? NSTableView).map{[$0]} ?? view.subviews.flatMap{tables($0)} }
        for table in tables(host) {
            for i in 0..<table.numberOfRows {
                guard let cell = table.view(atColumn:0,row:i,makeIfNecessary:true) as? BrowserCell,
                      let coordinator = table.delegate as? BrowserTable.Coordinator else { throw namingError("未生成原生文件列表") }
                let row = coordinator.rows[i]
                try verify(cell.icon.image === WorkspaceFileIcons.image(for:row),"Native cells use shared catalog icons")
                if WorkspaceFileIcons.assetName(for:row) != nil { try verify(cell.iconWidth.constant == 24 && cell.iconHeight.constant == 24,"File icons render as 24pt squares") }
            }
        }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw namingError("图标预览缓冲区不可用") }
        host.cacheDisplay(in:host.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(name))
    }
    try capture(HStack(spacing:16) {
        ForEach(0..<3) { group in BrowserTable(rows:Array(rows[(group*16)..<(group*16+16)]),selection:.constant(nil),activate:{_ in},rename:{_ in}) }
    }.padding(20).background(Color(nsColor:WorkspaceTheme.paper)),size:NSSize(width:1120,height:910),name:"native-file-icons.png")
    try capture(VStack(spacing:16) {
        SmartDialogFileSummary(rows:[BrowserRow(id:"/fixture/示例合同.docx",title:"示例合同.docx")])
        SmartDialogFileSummary(rows:[BrowserRow(id:"/fixture/未知格式.xyz",title:"未知格式.xyz")])
        SmartDialogFileSummary(rows:[BrowserRow(id:"/fixture/普通目录",title:"普通目录",folder:true)])
    }.padding(24).background(Color(nsColor:WorkspaceTheme.paper)),size:NSSize(width:640,height:330),name:"archive-summary-icons.png")
    print("PASS: native lists and archive summaries render catalog icons; captures in "+out.path)
}
