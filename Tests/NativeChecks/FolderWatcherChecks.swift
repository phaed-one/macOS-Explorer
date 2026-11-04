import AppKit
import PathfindCore

func checkLiveFolderUpdates() throws {
    func waitFor(_ stage: String, _ condition: () -> Bool) throws {
        do { try waitUntil(condition) }
        catch { throw NativeCheckError.failed("Automatic folder update timed out: \(stage)") }
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ExplorerWatcherChecks-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let browser = BrowserController(tabs: BrowserTabs(url: root))
    browser.showWindow(nil)
    defer { browser.window?.close() }
    try waitFor("initial folder") { browser.window?.representedURL == root }
    let views = descendants(browser.window!.contentView!)
    let collection = views.compactMap { $0 as? IconCollectionView }.first!
    let icons = collection.delegate as! IconBrowser
    let table = views.compactMap { $0 as? FileTableView }.first!
    let mode = views.compactMap { $0 as? NSSegmentedControl }.first!
    mode.selectedSegment = 1; mode.sendAction(mode.action, to: mode.target)
    let file = root.appendingPathComponent("watched.txt")
    try Data("one".utf8).write(to: file)
    try waitFor("external create") { icons.entries.contains { $0.name == "watched.txt" } }
    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    try Data("updated contents".utf8).write(to: file)
    try waitFor("external content edit") { icons.entries.first?.size == 16 }
    try require(table.selectedRowIndexes == IndexSet(integer: 0), "Automatic metadata refresh must preserve the selected file")
    let renamed = root.appendingPathComponent("renamed.txt")
    try FileManager.default.moveItem(at: file, to: renamed)
    try waitFor("external rename") { icons.entries.first?.name == "renamed.txt" }
    mode.selectedSegment = 0; mode.sendAction(mode.action, to: mode.target)
    try FileManager.default.removeItem(at: renamed)
    try waitFor("external delete") { icons.entries.isEmpty }
    let next = root.appendingPathComponent("next")
    try FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
    browser.navigate(next)
    try waitFor("navigation") { browser.window?.representedURL == next }
    try Data().write(to: next.appendingPathComponent("new.txt"))
    try waitFor("changed watched directory") { icons.entries.first?.name == "new.txt" }
    try require(browser.sessionTabs.current.history.locations.filter { $0 == next }.count == 1, "Automatic refresh must not add navigation history entries")
    print("PASS: External create, content edit, rename, delete, selection preservation, and folder watcher switching in both views")
}
