import AppKit
import PathfindCore

func checkSearchAndHeaderFocus() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let browser = BrowserController(tabs: BrowserTabs(url: root))
    browser.showWindow(nil)
    defer { browser.window?.close() }
    try waitUntil { browser.window?.representedURL == root }
    let views = descendants(browser.window!.contentView!)
    let fields = views.compactMap { $0 as? HeaderTextField }
    let path = fields.first { $0.accessibilityLabel() == "Current folder path" }!
    let search = fields.first { $0 !== path }!
    let table = views.compactMap { $0 as? FileTableView }.first!
    let mode = views.compactMap { $0 as? NSSegmentedControl }.first!
    mode.selectedSegment = 0; mode.sendAction(mode.action, to: mode.target)
    let normalCount = table.numberOfRows
    func mouse(_ point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: browser.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }
    let blank = NSPoint(x: 8, y: path.convert(path.bounds, to: nil).midY)
    for field in [path, search] {
        browser.window!.makeFirstResponder(field)
        try require(field.currentEditor() != nil, "Input must begin editing")
        if field === search { try require(field.placeholderString == nil, "Focusing search must hide its placeholder before typing") }
        browser.releaseInputFocusForHeaderClick(mouse(field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)))
        try require(field.currentEditor() != nil, "Clicks within an input must keep editing focus")
        browser.releaseInputFocusForHeaderClick(mouse(blank))
        try require(field.currentEditor() == nil, "Blank header clicks must release path and search focus")
        if field === search { try require(field.placeholderString == "Search this folder and subfolders", "Leaving an empty search must restore its placeholder") }
    }
    let expected = root.appendingPathComponent("Sources/Pathfind/HeaderTextField.swift")
    search.stringValue = "HeaderTextField"
    browser.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
    try require(table.tableColumns.map(\.title) == ["Name", "Full Path"], "Search must use its special two-column Details view")
    try require(!table.isHiddenOrHasHiddenAncestor && !mode.isEnabled, "Search must show Details even when the folder uses Icons")
    if NSMetadataItem(url: expected)?.value(forAttribute: NSMetadataItemFSNameKey) != nil {
        try waitUntil { table.numberOfRows > 0 }
        let pathColumn = table.tableColumns.first { $0.identifier.rawValue == "path" }!
        let foundPaths = (0..<table.numberOfRows).map { row -> String in
            let cell = browser.tableView(table, viewFor: pathColumn, row: row) as! NSTableCellView
            return cell.textField!.stringValue
        }
        try require(foundPaths.contains(expected.path), "Spotlight must find an item below the root's immediate children")
        try require(foundPaths.allSatisfy { $0.hasPrefix(root.path + "/") }, "Indexed results must remain inside the chosen folder")
        table.selectRowIndexes(IndexSet(integer: foundPaths.firstIndex(of: expected.path)!), byExtendingSelection: false)
        let menu = NSMenu(); browser.menuNeedsUpdate(menu)
        try require(menu.items.contains { $0.title == "Copy Path" } && !menu.items.contains { $0.title.hasPrefix("New Folder") }, "Search results must retain item-specific file actions")
        table.sortDescriptors = [NSSortDescriptor(key: "path", ascending: false)]
    } else { print("SKIP: Source fixture is not indexed by Spotlight") }
    search.stringValue = ""
    browser.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
    try require(table.tableColumns.count == 4 && table.numberOfRows == normalCount, "Clearing search must restore normal folder contents and columns")
    try require(mode.isEnabled && mode.selectedSegment == 0 && table.isHiddenOrHasHiddenAncestor, "Clearing search must restore the original Icons view")
    print("PASS: Header focus release, indexed descendant search, full result paths, file actions, sorting, and normal-view restoration")
}
