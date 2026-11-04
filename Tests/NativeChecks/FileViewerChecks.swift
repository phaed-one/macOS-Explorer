import AppKit
import CoreServices
import PathfindCore

func checkFileViewerRequests() throws {
    func event(_ object: NSAppleEventDescriptor?) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor.appleEvent(withEventClass: AEEventClass(kAEMiscStandards),
            eventID: AEEventID(kAEMakeObjectsVisible), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let object { event.setParam(object, forKeyword: AEKeyword(keyDirectObject)) }
        return event
    }
    func descriptor(_ url: URL) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(descriptorType: DescType(typeFileURL), data: url.dataRepresentation)!
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer Reveal \(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("space and ünicode.txt")
    let second = root.appendingPathComponent(".hidden")
    try Data().write(to: first); try Data().write(to: second)
    try require(FileViewerRequest.urls(in: event(descriptor(first))) == [first.standardizedFileURL], "Reveal must decode a single file URL with spaces and Unicode")
    let list = NSAppleEventDescriptor.list()
    list.insert(descriptor(first), at: 1); list.insert(descriptor(second), at: 2)
    try require(FileViewerRequest.urls(in: event(list)) == [first.standardizedFileURL, second.standardizedFileURL], "Reveal must decode multiple files")
    try require(FileViewerRequest.urls(in: event(nil)).isEmpty, "Missing reveal targets must be rejected")
    try require(FileViewerRequest.urls(in: event(NSAppleEventDescriptor.list())).isEmpty, "Empty reveal lists must be rejected")
    try require(FileViewerRequest.urls(in: event(descriptor(URL(string: "https://example.com")!))).isEmpty, "Reveal must reject non-file URLs")

    let browser = BrowserController(tabs: BrowserTabs(url: root))
    defer { browser.close() }
    let store = FolderViewStore()
    var preferences = FolderViewPreferences()
    preferences.filter = "no target will match this search"
    store.save(preferences, for: root)
    defer { store.restoreDefault(for: root) }
    let hidden = HiddenFileStore()
    hidden.set(false, for: root)
    defer { hidden.useDefault(for: root) }
    let views = descendants(browser.window!.contentView!)
    let table = views.compactMap { $0 as? FileTableView }.first!
    let collection = views.compactMap { $0 as? NSCollectionView }.first!
    browser.navigate(root, selecting: [first, second])
    try waitUntil { table.selectedRowIndexes.count == 2 && collection.selectionIndexPaths.count == 2 }
    try require(browser.window?.representedURL == root, "Reveal must open the containing folder")
    try require(hidden.showsHidden(in: root), "Revealing a hidden file must enable the folder's hidden-file control")
    // A later navigation must cancel selection from an earlier asynchronous reveal.
    browser.navigate(root, selecting: [first])
    browser.navigate(root)
    try waitUntil { table.numberOfRows > 0 && table.selectedRowIndexes.isEmpty && collection.selectionIndexPaths.isEmpty }
    print("PASS: File viewer URL events, multi-file reveal, hidden targets, and cancelled navigation")
}
