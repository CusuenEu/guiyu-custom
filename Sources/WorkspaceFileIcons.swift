import AppKit

// Presentation only: use the shared suffix map, never open the user's document.
enum WorkspaceFileIcons {
    private static var cache: [String:NSImage] = [:]
    static func assetName(for row: BrowserRow) -> String? {
        FileTypeIcons.assetName(for:URL(fileURLWithPath:row.id),isDirectory:row.folder,isAlias:row.isAlias)
    }
    static func image(for row: BrowserRow) -> NSImage? {
        guard !row.header else { return nil }
        guard let name = assetName(for:row) else { return WorkspaceTheme.folder }
        if let image = cache[name] { return image }
        // Xcode builds use Assets.car. Command Line Tools builds load the same
        // catalog's 1x/2x/3x representations, with no separate extension table.
        guard let image = NSImage(named:NSImage.Name(name)) ?? catalogImage(named:name) else {
            return NSImage(systemSymbolName:"doc",accessibilityDescription:"文件")
        }
        image.isTemplate = false
        cache[name] = image
        return image
    }
    static func catalogImage(named name: String) -> NSImage? {
        guard name.hasPrefix("file-type-"), !name.contains("/"),
              let root = Bundle.main.resourceURL else { return nil }
        let set = root.appendingPathComponent("FileTypeIcons.xcassets").appendingPathComponent(name+".imageset")
        guard let data = try? Data(contentsOf:set.appendingPathComponent("Contents.json")),
              let contents = try? JSONDecoder().decode(ImageSet.self,from:data) else { return nil }
        let image = NSImage(size:NSSize(width:32,height:32))
        for item in contents.images {
            guard let filename = item.filename, !filename.contains("/"), !filename.contains("\\"),
                  let data = try? Data(contentsOf:set.appendingPathComponent(filename)),
                  let representation = NSBitmapImageRep(data:data) else { continue }
            representation.size = image.size
            image.addRepresentation(representation)
        }
        return image.representations.isEmpty ? nil : image
    }
    private struct ImageSet: Decodable {
        struct Item: Decodable { let filename: String? }
        let images: [Item]
    }
}
