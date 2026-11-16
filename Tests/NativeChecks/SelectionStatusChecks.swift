import AppKit
import PathfindCore

func checkSelectionStatus() throws {
    let defaults = UserDefaults.standard
    let saved = defaults.object(forKey: "folderViews")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-Selection-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("folder"), withIntermediateDirectories: true)
    try Data(repeating: 0, count: 1_100_000).write(to: folder.appendingPathComponent("large.txt"))
    try Data(repeating: 0, count: 2_340).write(to: folder.appendingPathComponent("small.txt"))
    try Data().write(to: folder.appendingPathComponent("empty.txt"))
    defer {
        try? FileManager.default.removeItem(at: folder)
        if let saved { defaults.set(saved, forKey: "folderViews") } else { defaults.removeObject(forKey: "folderViews") }
    }
    let browser = BrowserController(tabs: BrowserTabs(url: folder))
    defer { browser.close() }
    browser.showWindow(nil)
    let views = descendants(browser.window!.contentView!)
    let table = views.compactMap { $0 as? FileTableView }.first!
    let collection = views.compactMap { $0 as? IconCollectionView }.first!
    let mode = views.compactMap { $0 as? NSSegmentedControl }.first!
    try waitUntil { table.numberOfRows == 4 }
    let status = views.compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("4 items") }!
    let nameColumn = table.tableColumns.first { $0.identifier.rawValue == "name" }!
    let rows = Dictionary(uniqueKeysWithValues: (0..<table.numberOfRows).map { row in
        let cell = browser.tableView(table, viewFor: nameColumn, row: row) as! NSTableCellView
        return (cell.textField!.stringValue, row)
    })
    let cases: [([String], Int64?)] = [
        ([], nil), (["large.txt"], 1_100_000), (["small.txt"], 2_340),
        (["empty.txt"], 0), (["large.txt", "small.txt"], 1_102_340),
        (["folder"], nil), (["folder", "small.txt"], nil),
        (["large.txt", "small.txt", "empty.txt"], 1_102_340), ([], nil)
    ]
    for segment in [1, 0] {
        mode.selectedSegment = segment; mode.sendAction(mode.action, to: mode.target)
        for (names, size) in cases {
            let indexes = names.map { rows[$0]! }
            if segment == 1 {
                table.selectRowIndexes(IndexSet(indexes), byExtendingSelection: false)
            } else {
                let paths = Set(indexes.map { IndexPath(item: $0, section: 0) })
                collection.selectionIndexPaths = paths
                collection.delegate?.collectionView?(collection, didSelectItemsAt: paths)
            }
            var expected = "4 items"
            if !names.isEmpty { expected += " · \(names.count) selected" }
            if let size { expected += " · " + ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
            expected += "    ·    \(BrowserLocation.path(folder))"
            try require(status.stringValue == expected, "Selection footer must show only file totals in mode \(segment): \(status.stringValue)")
        }
    }
    print("PASS: Selection footer totals for single/multiple/empty files, folders, mixed selections, and deselection in Details and Icons")
}
