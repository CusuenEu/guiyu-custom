import AppKit

// Publish file objects, not filename text or document contents. Finder performs
// the actual copy when the user pastes into a destination.
@discardableResult func copyFilePaths(_ paths:[String],to pasteboard:NSPasteboard = .general) -> Bool {
    var seen = Set<String>()
    let urls = paths.filter { seen.insert($0).inserted }.map { URL(fileURLWithPath:$0) }
    guard !urls.isEmpty, paths.allSatisfy({$0.hasPrefix("/")}), urls.allSatisfy({
        fm.fileExists(atPath:$0.path) || (try? fm.destinationOfSymbolicLink(atPath:$0.path)) != nil
    }) else { return false }
    pasteboard.clearContents()
    return pasteboard.writeObjects(urls.map{$0 as NSURL})
}

@discardableResult func copyFileRows(_ rows:[BrowserRow],to pasteboard:NSPasteboard = .general) -> Bool {
    copyFilePaths(rows.filter{!$0.header}.map(\.id),to:pasteboard)
}
