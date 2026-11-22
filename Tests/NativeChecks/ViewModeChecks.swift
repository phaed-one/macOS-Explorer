import AppKit
import PathfindCore

/// A folder's saved view mode must survive opening a new window on it (as happens on relaunch),
/// and each mode must keep its own spacing.
func checkFolderViewModePersistence() throws {
    let defaults = UserDefaults.standard
    let saved = defaults.object(forKey: "folderViews")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-ViewMode-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for index in 0..<60 { try Data().write(to: folder.appendingPathComponent(String(format: "file-%02d.txt", index))) }
    // One long name partway through, so its column is wider than the others.
    try Data().write(to: folder.appendingPathComponent("file-30 with a much longer name than the rest.txt"))
    defer {
        try? FileManager.default.removeItem(at: folder)
        if let saved { defaults.set(saved, forKey: "folderViews") } else { defaults.removeObject(forKey: "folderViews") }
    }
    let store = FolderViewStore()
    for mode in [FolderViewMode.list, .details, .icons] {
        var view = FolderViewPreferences(); view.mode = mode; view.listSpacing = 24; view.iconSpacing = 6
        store.save(view, for: folder)
        let browser = BrowserController(tabs: BrowserTabs(url: folder))
        browser.showWindow(nil)
        try waitUntil { browser.window?.representedURL == folder }
        browser.window!.setContentSize(NSSize(width: 1300, height: 760))
        browser.window!.contentView!.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let toggle = descendants(browser.window!.contentView!).compactMap { $0 as? NSSegmentedControl }.first { $0.accessibilityLabel() == "Folder view" }!
        let expected = mode == .icons ? 0 : mode == .list ? 1 : 2
        try require(toggle.selectedSegment == expected, "Reopening a folder must show its saved \(mode) view, got segment \(toggle.selectedSegment)")
        try require(store.view(for: folder).mode == mode, "Opening a window must not overwrite the folder's saved \(mode) view")
        browser.close()
    }

    var view = FolderViewPreferences(); view.mode = .icons; view.iconSpacing = 6; view.listSpacing = 24
    store.save(view, for: folder)
    let browser = BrowserController(tabs: BrowserTabs(url: folder))
    defer { browser.close() }
    browser.showWindow(nil)
    try waitUntil { browser.window?.representedURL == folder }
    let controls = descendants(browser.window!.contentView!)
    let toggle = controls.compactMap { $0 as? NSSegmentedControl }.first { $0.accessibilityLabel() == "Folder view" }!
    let spacing = controls.compactMap { $0 as? LiveSlider }.first { $0.accessibilityLabel() == "Icon spacing" }!
    let collection = controls.compactMap { $0 as? IconCollectionView }.first!
    func icons(_ view: NSView) -> NSRect { view.enclosingScrollView!.contentView.bounds }
    try require(spacing.doubleValue == 6, "Icons must load their own spacing")
    toggle.selectedSegment = 1; toggle.sendAction(toggle.action, to: toggle.target)
    try require(spacing.doubleValue == 24 && !spacing.isHidden, "List must load its own spacing")
    browser.window!.setContentSize(NSSize(width: 1100, height: 560))
    browser.window!.contentView!.layoutSubtreeIfNeeded()
    func frames() -> [NSRect] {
        collection.layoutSubtreeIfNeeded()
        return (0..<collection.numberOfItems(inSection: 0)).map { collection.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))!.frame }
    }
    func columns(_ frames: [NSRect]) -> [[NSRect]] {
        Dictionary(grouping: frames, by: \.minX).sorted { $0.key < $1.key }.map(\.value)
    }
    var list = frames()
    try require(list[1].minX == list[0].minX && list[1].minY > list[0].minY, "List names must fill down a column before starting the next")
    var cols = columns(list)
    try require(cols.count >= 3, "List must wrap into several columns at this height, got \(cols.count)")
    let widths = cols.map { $0.map(\.width).max()! }
    try require(Set(widths).count > 1, "Each List column must be as wide as its own widest name, got \(widths)")
    for index in 1..<cols.count {
        try require(cols[index][0].minX - (cols[index - 1][0].minX + widths[index - 1]) == 24, "The spacing setting must be the gap between List columns")
    }
    let rowPitch = list[1].minY - list[0].minY
    spacing.setAccessibilityValue(30)
    list = frames(); cols = columns(list)
    try require(cols[1][0].minX - (cols[0][0].minX + cols[0].map(\.width).max()!) == 30, "Changing List spacing must change the column gap")
    try require(list[1].minY - list[0].minY == rowPitch, "List spacing changes columns only, not rows")
    try require(collection.frame.width > icons(collection).width, "List must extend sideways past the window and scroll horizontally")
    let rows = cols[0].count
    collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
    collection.moveDown(nil)
    try require(collection.selectionIndexPaths == [IndexPath(item: 1, section: 0)], "Down arrow must move to the next name in the List column")
    collection.moveRight(nil)
    try require(collection.selectionIndexPaths == [IndexPath(item: 1 + rows, section: 0)], "Right arrow must move to the same row in the next List column")
    collection.selectionIndexPaths = [IndexPath(item: 2, section: 0)]
    spacing.setAccessibilityValue(12)
    try require(collection.selectionIndexPaths == [IndexPath(item: 2, section: 0)], "Changing List spacing must keep the selection")
    toggle.selectedSegment = 0; toggle.sendAction(toggle.action, to: toggle.target)
    try require(spacing.doubleValue == 6, "Switching back to Icons must restore icon spacing, not List spacing")
    let stored = store.view(for: folder)
    try require(stored.iconSpacing == 6 && stored.listSpacing == 12, "Icon and List spacing must be saved separately")
    for segment in [0, 1, 2] {
        toggle.selectedSegment = segment; toggle.sendAction(toggle.action, to: toggle.target)
        browser.window!.contentView!.layoutSubtreeIfNeeded(); collection.layoutSubtreeIfNeeded()
        let names = descendants(browser.window!.contentView!).compactMap { $0 as? NSTextField }
            .filter { $0.stringValue.hasPrefix("file-") && !$0.isHiddenOrHasHiddenAncestor }
        try require(!names.isEmpty && names.allSatisfy { $0 is FileNameLabel && !$0.isSelectable && !$0.isEditable },
                    "File names must not be selectable text (no I-beam cursor) in view \(segment)")
    }
    print("PASS: Folder view mode survives reopening, Icons and List keep separate spacing, and names never take a text cursor")
}
