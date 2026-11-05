import AppKit
import PathfindCore

func checkWindowReopenRestoresState() throws {
    let suite = "PathfindSession." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    // Resolved, because macOS reports /var/folders windows under /private/var/folders.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    func shows(_ window: NSWindow) -> Bool { window.representedURL?.resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path }
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
    for index in 0..<80 { try Data().write(to: folder.appendingPathComponent(String(format: "file-%02d.txt", index))) }
    func wait(_ stage: String, _ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        try require(condition(), "Timed out: \(stage)")
    }
    let workspace = BrowserWorkspace(defaults: defaults)
    let browser = workspace.newWindow(at: folder)
    let window = browser.window!
    try wait("first load of \(folder.path)") { shows(window) }
    let screen = (window.screen ?? NSScreen.screens[0]).visibleFrame
    let frame = NSRect(x: screen.minX + 60, y: screen.minY + 40, width: 980, height: 520)
    window.setFrame(frame, display: true)
    window.contentView!.layoutSubtreeIfNeeded()
    let views = descendants(window.contentView!)
    let split = views.compactMap { $0 as? NSSplitView }.first!
    split.setPosition(260, ofDividerAt: 0)
    let collection = views.compactMap { $0 as? NSCollectionView }.first!
    let picks = [5, 40]
    collection.selectionIndexPaths = Set(picks.map { IndexPath(item: $0, section: 0) })
    let scroll = collection.enclosingScrollView!
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 300)); scroll.reflectScrolledClipView(scroll.contentView)
    let selectedNames = picks.map { String(format: "file-%02d.txt", $0) }
    let windowID = browser.sessionTabs.activeID
    window.close()
    try wait("window close, \(workspace.browsers.count) left") { workspace.browsers.isEmpty }

    let reopened = workspace.reopenLastClosed()
    let again = reopened.window!
    try wait("reopened load") { shows(again) }
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    defer { again.close() }
    try require(again.frame == frame, "Reopening must restore the window's size and position: \(again.frame) vs \(frame)")
    try require(reopened.sessionTabs.activeID == windowID, "Reopening must bring back the same tabs, not a new window")
    let newViews = descendants(again.contentView!)
    let newSplit = newViews.compactMap { $0 as? NSSplitView }.first!
    try require(abs(newSplit.arrangedSubviews[0].frame.width - 260) < 2, "Reopening must restore the divider position: \(newSplit.arrangedSubviews[0].frame.width)")
    let newCollection = newViews.compactMap { $0 as? NSCollectionView }.first!
    let restored = newCollection.selectionIndexPaths.compactMap { newCollection.item(at: $0)?.textField?.stringValue }.sorted()
    let restoredByIndex = reopened.sessionTabs.current.selection?.map(\.lastPathComponent).sorted() ?? []
    try require(restoredByIndex == selectedNames || restored == selectedNames, "Reopening must restore the selected items: \(restoredByIndex)")
    let offset = newCollection.enclosingScrollView!.contentView.bounds.origin.y
    try require(abs(offset - 300) < 2, "Reopening must restore the scroll position: \(offset)")
    print("PASS: Reopening a closed window restores its size, position, tabs, divider, selection and scroll position")
}
