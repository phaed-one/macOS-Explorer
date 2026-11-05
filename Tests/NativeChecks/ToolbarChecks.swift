import AppKit
import PathfindCore

func checkMomentaryButtonHighlight() throws {
    let button = GlassToolbarButton(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
    button.title = ""; button.isBordered = false
    button.setButtonType(.momentaryPushIn)
    func backgroundAlpha() -> CGFloat {
        let image = NSImage(size: button.bounds.size, flipped: false) { rect in button.draw(rect); return true }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.colorAt(x: 15, y: 15)!.alphaComponent
    }
    button.performClick(nil)
    try require(!button.isHighlighted && backgroundAlpha() < 0.01, "A clicked momentary icon must not retain a selected background")
    let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
    button.mouseEntered(with: event)
    try require(backgroundAlpha() > 0.9, "Hover must still show the glass background")
    button.mouseExited(with: event)
    try require(backgroundAlpha() < 0.01, "Leaving a clicked icon must remove its hover background")
    button.setButtonType(.toggle); button.state = .on
    let selectedAlpha = backgroundAlpha()
    if #available(macOS 26, *) {
        try require(button.bezelStyle == .glass && button.isBordered, "Active toggles must use the native Liquid Glass bezel")
    } else { try require(selectedAlpha > 0.9, "Actual toggles must retain their selected background") }
    button.state = .off
    _ = backgroundAlpha()
    try require(!button.isBordered, "Inactive icons must return to their unbordered appearance")
    print("PASS: Momentary icon highlights clear after clicks and mouse exit; actual toggles retain selection")
}

func checkFavoriteAndVisibilityControls() throws {
    let defaults = UserDefaults.standard
    let keys = ["favorites", "defaultShowHiddenFiles", "folderHiddenFiles"]
    let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ExplorerToolbarChecks-" + UUID().uuidString)
    let a = root.appendingPathComponent("A"), b = a.appendingPathComponent("0 Folder")
    try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
    try Data().write(to: a.appendingPathComponent("1 file.txt"))
    try Data().write(to: a.appendingPathComponent(".hidden"))
    try Data().write(to: b.appendingPathComponent("visible.txt"))
    try Data().write(to: b.appendingPathComponent(".hidden"))
    defer {
        for key in keys {
            if let value = saved[key] ?? nil { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        try? FileManager.default.removeItem(at: root)
    }
    let visibility = HiddenFileStore()
    visibility.defaultShowsHidden = false; visibility.set(false, for: a)
    let browser = BrowserController(tabs: BrowserTabs(url: a))
    browser.showWindow(nil); defer { browser.window?.close() }
    try waitUntil { browser.window?.representedURL == a }
    let all = descendants(browser.window!.contentView!)
    let table = all.compactMap { $0 as? FileTableView }.first!
    let mode = all.compactMap { $0 as? NSSegmentedControl }.first!
    mode.selectedSegment = 1; mode.sendAction(mode.action, to: mode.target)
    browser.window!.contentView!.layoutSubtreeIfNeeded()
    let ancestorBar = all.compactMap { $0 as? AncestorPathBar }.first!
    let up = descendants(ancestorBar).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Go to parent folder" }!
    func ancestorButtons() -> [NSButton] { descendants(ancestorBar).compactMap { $0 as? NSButton }.filter { $0.accessibilityLabel()?.hasPrefix("Go to ancestor folder:") == true } }
    let parentButton = ancestorButtons().last!
    try require(ancestorButtons().first?.title == "/" && parentButton.title == root.lastPathComponent && ancestorButtons().allSatisfy { $0.image == nil && $0.bezelColor == nil }, "Details must show neutral ancestor buttons from root to parent without arrows")
    try require(!ancestorButtons().contains { $0.title == a.lastPathComponent }, "The current folder must not appear among its ancestors")
    NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    try require((ancestorButtons() + [up]).allSatisfy { $0.bezelStyle == .rounded }, "Path buttons and the parent button must stay flat, not glass, even after an appearance change")
    let removedActions = ["goBack", "goForward", "goUp", "refresh"].map(NSSelectorFromString)
    try require(!all.compactMap { $0 as? NSButton }.contains { $0.action.map(removedActions.contains) == true }, "Back, Forward, Up, and Refresh buttons must be absent from the toolbar")
    let parentFrame = parentButton.convert(parentButton.bounds, to: browser.window!.contentView!)
    let upFrame = up.convert(up.bounds, to: ancestorBar)
    let rootFrame = ancestorButtons().first!.convert(ancestorButtons().first!.bounds, to: ancestorBar)
    try require(up.image != nil && up.isEnabled && upFrame.maxX < rootFrame.minX, "Parent chevron must precede the root path button")
    let columnFrame = table.headerView!.convert(table.headerView!.bounds, to: browser.window!.contentView!)
    try require(parentFrame.minY > columnFrame.maxY, "The parent button must sit in reserved space above the column headers")
    let star = all.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("toggleSelectedFavorite") }!
    try require(!star.isEnabled, "Favorite must be dimmed without a right-pane selection")
    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    try require(star.isEnabled, "Selecting a folder in Details must enable Favorite")
    let outlineIcon = star.image!.tiffRepresentation!
    star.performClick(nil)
    let savedFavorites = (defaults.stringArray(forKey: "favorites") ?? []).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
    try require(savedFavorites.contains(b.resolvingSymlinksInPath().path) && !savedFavorites.contains(a.resolvingSymlinksInPath().path), "Star must add the selected child folder, not the folder being browsed")
    try require(star.isEnabled && star.state == .on && star.image!.tiffRepresentation! == outlineIcon && star.accessibilityLabel() == "Remove selected folder from Favorites", "A favorite must select the outlined star button without filling its icon")
    star.performClick(nil)
    try require(star.isEnabled && star.state == .off && star.image!.tiffRepresentation! == outlineIcon && star.accessibilityHelp() == "Add selected folder to Favorites", "Removing a favorite must unselect the button while retaining the outlined icon")
    let selectedURL = b.resolvingSymlinksInPath()
    let anotherSidebar = Sidebar()
    anotherSidebar.saveFavorite(selectedURL)
    try require(star.isEnabled && star.state == .on && star.accessibilityHelp() == "Remove selected folder from Favorites", "Changes from another window must update the selected star immediately")
    anotherSidebar.toggleFavorite(selectedURL)
    try require(star.isEnabled && star.state == .off && star.image!.tiffRepresentation! == outlineIcon, "Removing a favorite elsewhere must unselect the button")
    table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    try require(!star.isEnabled && star.state == .off, "Selecting a file must dim and unselect Favorite")
    mode.selectedSegment = 0; mode.sendAction(mode.action, to: mode.target)
    browser.window!.contentView!.layoutSubtreeIfNeeded()
    try require(!ancestorButtons().last!.isHiddenOrHasHiddenAncestor, "Icons must also show the ancestor folder buttons")
    let collection = all.compactMap { $0 as? IconCollectionView }.first!
    collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
    (collection.delegate as! IconBrowser).collectionView(collection, didSelectItemsAt: collection.selectionIndexPaths)
    try require(star.isEnabled, "Selecting a folder in Icons must also enable Favorite")
    collection.deselectAll(nil)
    (collection.delegate as! IconBrowser).collectionView(collection, didDeselectItemsAt: [])
    try require(!star.isEnabled, "Deselecting the folder must dim Favorite")
    mode.selectedSegment = 1; mode.sendAction(mode.action, to: mode.target)
    let localEye = all.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("toggleFolderHidden") }!
    let globalEye = all.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("toggleHidden") }!
    localEye.performClick(nil)
    try waitUntil { table.numberOfRows == 3 }
    browser.navigate(b)
    try waitUntil { browser.window?.representedURL == b && table.numberOfRows == 1 }
    try require(localEye.state == .off, "Showing hidden files in A must not affect B")
    try require(ancestorButtons().last?.title == a.lastPathComponent, "The ancestor buttons must follow navigation")
    up.performClick(nil)
    try waitUntil { browser.window?.representedURL?.path == a.path }
    browser.navigate(a)
    try waitUntil { browser.window?.representedURL == a && table.numberOfRows == 3 }
    try require(localEye.state == .on, "Returning to A must restore its visibility choice")
    globalEye.performClick(nil)
    browser.navigate(b)
    try waitUntil { browser.window?.representedURL == b && table.numberOfRows == 2 }
    localEye.performClick(nil)
    try waitUntil { table.numberOfRows == 1 }
    let inherit = localEye.menu!.items.first!
    NSApp.sendAction(inherit.action!, to: inherit.target, from: inherit)
    try waitUntil { table.numberOfRows == 2 }
    let restarted = BrowserController(tabs: BrowserTabs(url: a))
    defer { restarted.window?.close() }
    try waitUntil { restarted.window?.representedURL == a }
    let restartedEye = descendants(restarted.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("toggleFolderHidden") }!
    try require(restartedEye.state == .on, "A newly created browser must restore per-folder visibility")
    for control in all.compactMap({ $0 as? NSControl }) where control is GlassToolbarButton || control is NSPopUpButton || control is NSSegmentedControl || control is LiveSlider {
        try require(control.accessibilityHelp()?.isEmpty == false, "All toolbar controls must have a tooltip description")
    }
    let hover = star.subviews.compactMap { $0 as? HoverHelpView }.first!
    try require(hover.hitTest(.zero) == nil, "Tooltip tracking must not intercept button clicks")
    let start = Date()
    hover.beginHover(at: .zero)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    try require(!HelpPopup.shared.isVisible, "Tooltips must not appear immediately")
    try waitUntil { HelpPopup.shared.isVisible }
    try require(Date().timeIntervalSince(start) >= 0.95, "Tooltips must wait one second")
    hover.endHover()
    try require(!HelpPopup.shared.isVisible, "Leaving a control must dismiss its tooltip")
    browser.navigate(URL(fileURLWithPath: "/"))
    try waitUntil { browser.window?.representedURL?.path == "/" }
    try require(!up.isEnabled && ancestorButtons().isEmpty, "Parent navigation must be disabled at the filesystem root")
    print("PASS: Favorite states, per-folder visibility, ancestor navigation in both views, simplified toolbar, and one-second tooltips")
}
