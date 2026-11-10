import AppKit
import PathfindCore

func checkFilePreviews() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-Previews-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    let views = FolderViewStore()
    views.save(FolderViewPreferences(), for: folder)
    defer {
        views.restoreDefault(for: folder)
        try? FileManager.default.removeItem(at: folder)
    }
    let url = folder.appendingPathComponent("sample.png")
    let sample = NSImage(size: NSSize(width: 80, height: 48), flipped: false) { rect in
        NSColor.red.setFill()
        rect.fill()
        return true
    }
    let bitmap = NSBitmapImageRep(data: sample.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)

    let browser = BrowserController(tabs: BrowserTabs(url: folder))
    defer { browser.close() }
    browser.showWindow(nil)
    try waitUntil { browser.window?.representedURL == folder }
    let controls = descendants(browser.window!.contentView!)
    let mode = controls.compactMap { $0 as? NSSegmentedControl }.first!
    let table = controls.compactMap { $0 as? NSTableView }.first { $0.tableColumns.contains { $0.identifier.rawValue == "name" } }!
    let collection = controls.compactMap { $0 as? IconCollectionView }.first!
    func showsSample(_ imageView: NSImageView) -> Bool {
        guard let data = imageView.image?.tiffRepresentation, let pixels = NSBitmapImageRep(data: data),
              let color = pixels.colorAt(x: pixels.pixelsWide / 2, y: pixels.pixelsHigh / 2)?.usingColorSpace(.sRGB)
        else { return false }
        return color.redComponent > 0.8 && color.greenComponent < 0.2 && color.blueComponent < 0.2
    }

    mode.selectedSegment = 1; mode.sendAction(mode.action, to: mode.target)
    let nameColumn = table.column(withIdentifier: .init("name"))
    let listCell = table.view(atColumn: nameColumn, row: 0, makeIfNecessary: true)!
    let listIcon = descendants(listCell).compactMap { $0 as? NSImageView }.first!
    try waitUntil { showsSample(listIcon) }

    mode.selectedSegment = 0; mode.sendAction(mode.action, to: mode.target)
    collection.layoutSubtreeIfNeeded()
    let index = IndexPath(item: 0, section: 0)
    try waitUntil { collection.item(at: index) != nil }
    let gridIcon = collection.item(at: index)!.imageView!
    try waitUntil { showsSample(gridIcon) }

    // Activation refreshes the folder, replacing its cells even if the files are unchanged.
    mode.selectedSegment = 1; mode.sendAction(mode.action, to: mode.target)
    let beforeRefresh = table.view(atColumn: nameColumn, row: 0, makeIfNecessary: true)!
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApplication.shared)
    try waitUntil { table.view(atColumn: nameColumn, row: 0, makeIfNecessary: true) !== beforeRefresh }
    let refreshedListCell = browser.tableView(table, viewFor: table.tableColumns[nameColumn], row: 0)!
    let refreshedListIcon = descendants(refreshedListCell).compactMap { $0 as? NSImageView }.first!
    try require(showsSample(refreshedListIcon), "A new list cell must display its cached thumbnail on first configuration")

    mode.selectedSegment = 0; mode.sendAction(mode.action, to: mode.target)
    collection.layoutSubtreeIfNeeded()
    try require(collection.item(at: index)?.imageView.map(showsSample) == true,
                "A reloaded grid item must display its cached thumbnail on first configuration")

    let entry = try FileSystem.contents(of: folder, showHidden: false).first!
    let recycled = FilePreviewImageView()
    let changed = FileEntry(url: entry.url, isDirectory: false, isHidden: false, size: entry.size,
                            modified: entry.modified.addingTimeInterval(1), kind: entry.kind)
    recycled.configure(for: changed, size: CGFloat(views.view(for: folder).iconSize), scale: browser.window!.backingScaleFactor)
    try require(!showsSample(recycled), "A changed file must not reuse its previous thumbnail")
    recycled.configure(for: FileEntry(url: folder, isDirectory: true, isHidden: false, size: 0, modified: Date(), kind: "Folder"), size: 64, scale: 2)
    let folderIcon = recycled.image
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    try require(folderIcon != nil && recycled.image === folderIcon, "A previous thumbnail must not replace a folder icon in a reused view")
    print("PASS: List and grid show PNG thumbnails immediately after activation refresh, invalidate changed files, and guard reused views")
}
