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

func checkStartupPreferences() throws {
    let suite = "PathfindStartup." + UUID().uuidString
    let session = UserDefaults(suiteName: suite)!
    let standard = UserDefaults.standard
    let keys = ["startupRestoresFrame", "startupRestoresTabs", "startupFolder"]
    let saved = keys.map { standard.object(forKey: $0) }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite).resolvingSymlinksInPath()
    let first = root.appendingPathComponent("first"), second = root.appendingPathComponent("second"), chosen = root.appendingPathComponent("chosen")
    for folder in [first, second, chosen] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    defer {
        for (key, value) in zip(keys, saved) { if let value { standard.set(value, forKey: key) } else { standard.removeObject(forKey: key) } }
        session.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root)
    }
    keys.forEach(standard.removeObject(forKey:))
    func path(_ url: URL?) -> String? { url?.resolvingSymlinksInPath().path }
    // A session with two tabs and a custom frame.
    let original = BrowserWorkspace(defaults: session)
    let browser = original.newWindow(at: first)
    browser.receiveTab(BrowserTab(url: second), before: nil)
    let screen = (browser.window!.screen ?? NSScreen.screens[0]).visibleFrame
    let frame = NSRect(x: screen.minX + 70, y: screen.minY + 50, width: 960, height: 500)
    browser.window!.setFrame(frame, display: true)
    try waitUntil { path(browser.window?.representedURL) == path(second) }
    original.prepareToTerminate()
    browser.window?.close()
    // Closing a window saves the session again, so every launch starts from the same saved one.
    let savedSession = session.data(forKey: "browserWorkspace")

    func launch(_ check: (BrowserController) throws -> Void) throws {
        session.set(savedSession, forKey: "browserWorkspace")
        let workspace = BrowserWorkspace(defaults: session)
        workspace.restore()
        let windows = Array(workspace.browsers.values)
        defer { windows.forEach { $0.window?.close() } }
        try require(windows.count == 1, "Startup must open one window here, not \(windows.count)")
        try check(windows[0])
    }
    try launch { restored in
        try require(restored.sessionTabs.items.count == 2 && restored.window!.frame == frame, "By default, startup restores the tabs, size and position")
        try require(path(restored.sessionTabs.current.url) == path(second), "By default, the last opened folder comes back")
    }
    standard.set(false, forKey: "startupRestoresTabs")
    try launch { restored in
        try require(restored.sessionTabs.items.count == 1 && path(restored.sessionTabs.current.url) == path(second),
            "Without tab restore, only the active tab comes back")
    }
    standard.set(true, forKey: "startupRestoresTabs"); standard.set(false, forKey: "startupRestoresFrame")
    try launch { restored in
        try require(restored.window!.frame.size == NSSize(width: 1120, height: 740), "Without size restore, the window opens at its default size: \(restored.window!.frame)")
    }
    standard.set(true, forKey: "startupRestoresFrame"); standard.set(chosen.path, forKey: "startupFolder")
    try launch { restored in
        let tabs = restored.sessionTabs
        try require(path(tabs.current.url) == path(chosen) && tabs.items.count == 2 && tabs.items.contains { path($0.url) == path(first) },
            "A chosen startup folder opens in the active tab while other tabs keep theirs")
    }
    // Settings shows the choices.
    let settings = SettingsController()
    defer { settings.close() }
    let controls = descendants(settings.window!.contentView!)
    let folderMenu = controls.compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Startup folder" }!
    try require(folderMenu.titleOfSelectedItem == "chosen" && folderMenu.itemTitles.contains("Last opened folder") && folderMenu.itemTitles.contains("Choose…"),
        "The startup folder menu must show the chosen folder, the last-opened option and Choose…: \(folderMenu.itemTitles)")
    folderMenu.selectItem(withTitle: "Last opened folder"); folderMenu.sendAction(folderMenu.action, to: folderMenu.target)
    try require(standard.string(forKey: "startupFolder") == nil, "Choosing Last opened folder must clear the startup folder")
    let boxes = controls.compactMap { $0 as? NSButton }
    let tabsBox = boxes.first { $0.title == "Restore open tabs" }!, frameBox = boxes.first { $0.title == "Restore size and position" }!
    tabsBox.performClick(nil); frameBox.performClick(nil)
    try require(!StartupPreferences.restoresTabs && !StartupPreferences.restoresFrame, "The Startup checkboxes must save their choices")
    print("PASS: Startup restores size, position and tabs as chosen, and opens the last or a chosen folder")
}
