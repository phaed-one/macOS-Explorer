import AppKit
import PathfindCore

func checkHalfThicknessScrollbars() throws {
    func paintedThickness(_ scroller: NSScroller, horizontal: Bool) -> Int {
        let image = NSImage(size: scroller.bounds.size, flipped: false) { _ in scroller.drawKnob(); return true }
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        var occupied = Set<Int>()
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where bitmap.colorAt(x: x, y: y)!.alphaComponent > 0.1 {
                occupied.insert(horizontal ? y : x)
            }
        }
        return occupied.count
    }
    for horizontal in [false, true] {
        let frame = horizontal ? NSRect(x: 0, y: 0, width: 200, height: 15) : NSRect(x: 0, y: 0, width: 15, height: 200)
        let original = NSScroller(frame: frame), thin = HalfThicknessScroller(frame: frame)
        for scroller in [original, thin] {
            scroller.scrollerStyle = .overlay; scroller.controlSize = .small
            scroller.knobStyle = .light; scroller.doubleValue = 0.5; scroller.knobProportion = 0.3
        }
        let before = paintedThickness(original, horizontal: horizontal), after = paintedThickness(thin, horizontal: horizontal)
        try require(after > 0 && after < before && after <= Int(ceil(Double(before) / 2)) + 1, "Scrollbar painting must halve native thickness in both axes: \(before) → \(after)")
    }
    let scroll = BrowserScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    scroll.scrollerStyle = .overlay; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
    scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 1000))
    scroll.tile()
    for scroller in [scroll.verticalScroller!, scroll.horizontalScroller!] {
        try require(scroller.target === scroll && scroller.action != nil, "Thinner scrollbars must retain native action wiring")
        let knob = scroller.rect(for: .knob)
        let point = scroller.convert(NSPoint(x: knob.midX, y: knob.midY), to: nil)
        try require(scroller.testPart(point) == .knob, "The full native thumb must remain draggable")
    }
    print("PASS: Half-thickness scrollbar painting, native action wiring, and full thumb hit areas in both axes")
}

final class TestDrag: NSObject, NSDraggingInfo {
    let draggingPasteboard = NSPasteboard(name: .init(UUID().uuidString))
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = [.copy, .move]
    var draggingLocation = NSPoint.zero
    var draggedImageLocation = NSPoint.zero
    var draggedImage: NSImage? { nil }
    var draggingSource: Any?
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

func checkWindowTransfers() throws {
    let suite = "PathfindWorkspaceChecks." + UUID().uuidString
    let preferences = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    let a = root.appendingPathComponent("A"), b = root.appendingPathComponent("B"), child = a.appendingPathComponent("child")
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
    let workspace = BrowserWorkspace(defaults: preferences)
    defer {
        workspace.prepareToTerminate()
        for browser in Array(workspace.browsers.values) { browser.window?.close() }
        preferences.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
    let first = workspace.newWindow(at: a), second = workspace.newWindow(at: b)
    try waitUntil { first.window?.representedURL == a && second.window?.representedURL == b }
    let copied = a.appendingPathComponent("copy.txt"), moved = a.appendingPathComponent("move.txt")
    try Data("copy".utf8).write(to: copied); try Data("move".utf8).write(to: moved)
    let table = descendants(second.window!.contentView!).compactMap { $0 as? FileTableView }.first!
    let drag = TestDrag(); drag.draggingDestinationWindow = second.window
    drag.draggingPasteboard.writeObjects([copied as NSURL])
    try require(second.tableView(table, acceptDrop: drag, row: -1, dropOperation: .above), "A window must accept a file from another window")
    try waitUntil { FileManager.default.fileExists(atPath: b.appendingPathComponent("copy.txt").path) && second.canTransferTabs }
    try require(FileManager.default.fileExists(atPath: copied.path), "An ordinary cross-window drop must copy")
    drag.draggingPasteboard.clearContents(); drag.draggingPasteboard.writeObjects([moved as NSURL])
    drag.draggingPasteboard.setString("true", forType: FileTransfer.moveType)
    try require(second.tableView(table, acceptDrop: drag, row: -1, dropOperation: .above), "A window must accept a right-drag move")
    try waitUntil { FileManager.default.fileExists(atPath: b.appendingPathComponent("move.txt").path) && second.canTransferTabs }
    try require(!FileManager.default.fileExists(atPath: moved.path), "A right-button cross-window drop must move")
    first.navigate(child)
    try waitUntil { first.window?.representedURL == child }
    let originalTab = first.sessionTabs.current
    let strip = descendants(second.window!.contentView!).compactMap { $0 as? TabStrip }.first!
    let tabDrag = TestDrag()
    tabDrag.draggingPasteboard.setData(try JSONEncoder().encode(TabTransfer(windowID: first.windowID, tabID: originalTab.id)), forType: TabTransfer.pasteboardType)
    try require(strip.performDragOperation(tabDrag), "A real tab strip must accept another window's tab payload")
    try waitUntil { second.window?.representedURL == child }
    try require(workspace.browsers.count == 1 && second.sessionTabs.items.count == 2 && second.sessionTabs.current.history.locations == originalTab.history.locations, "Moving the final tab closes its old window and preserves its history")
    workspace.detachTab(TabTransfer(windowID: second.windowID, tabID: originalTab.id), at: NSPoint(x: 300, y: 600))
    try require(workspace.browsers.count == 2, "Detaching creates another window")
    let detached = workspace.browsers.values.first { $0 !== second }!
    try waitUntil { detached.window?.representedURL == child && second.window?.representedURL == b }
    try require(detached.sessionTabs.current.id == originalTab.id, "Detaching moves the existing tab rather than cloning it")
    let tabFile = child.appendingPathComponent("onto-tab.txt")
    try Data("tab".utf8).write(to: tabFile)
    let targetButton = descendants(second.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.accessibilityHelp() == b.path }!
    let fileOnTab = TestDrag(); fileOnTab.draggingPasteboard.writeObjects([tabFile as NSURL])
    var dropTarget: NSView? = targetButton
    while let view = dropTarget, !view.registeredDraggedTypes.contains(.fileURL) { dropTarget = view.superview }
    try require(dropTarget?.performDragOperation(fileOnTab) == true, "A tab title must accept files from another window")
    try waitUntil { FileManager.default.fileExists(atPath: b.appendingPathComponent("onto-tab.txt").path) && second.canTransferTabs }
    let before = Set(workspace.browsers.keys)
    workspace.prepareToTerminate()
    for browser in workspace.browsers.values { browser.window?.close() }
    let restored = BrowserWorkspace(defaults: preferences)
    restored.restore()
    defer { restored.prepareToTerminate(); for browser in restored.browsers.values { browser.window?.close() } }
    try require(Set(restored.browsers.keys) == before && restored.browsers.values.flatMap(\.sessionTabs.items).count == 2, "All windows and tabs restore exactly once")
    for id in before.union([first.windowID]) {
        for key in ["explicitExpandedTreePaths", "collapsedTreeGroups", "selectedTreeItem", "sidebarWidth"] { UserDefaults.standard.removeObject(forKey: id.uuidString + "." + key) }
    }
    print("PASS: Native cross-window file copies/moves, tab drops, detaching, file drops onto tabs, and session restoration")
}

func checkTrashInterface() throws {
    let suite = "PathfindTrashInterface." + UUID().uuidString
    let preferences = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite), trash = root.appendingPathComponent("trash")
    try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let store = TrashStore(defaults: preferences, directories: { [trash] }, trashOperation: { source in
        let destination = trash.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.moveItem(at: source, to: destination); return destination
    })
    let original = root.appendingPathComponent("restore-me.txt")
    try Data("restore".utf8).write(to: original); try store.trash(original)
    let browser = BrowserController(tabs: BrowserTabs(url: TrashStore.location), trashStore: store)
    browser.showWindow(nil); defer { browser.window?.close() }
    try waitUntil { browser.window?.representedURL == TrashStore.location }
    let mode = descendants(browser.window!.contentView!).compactMap { $0 as? NSSegmentedControl }.first!
    mode.selectedSegment = 0; mode.sendAction(mode.action, to: mode.target)
    let collection = descendants(browser.window!.contentView!).compactMap { $0 as? IconCollectionView }.first!
    collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
    let menu = collection.menu!; browser.menuNeedsUpdate(menu)
    let restore = menu.items.first { $0.title == "Restore" }!
    NSApp.sendAction(restore.action!, to: restore.target, from: restore)
    try waitUntil { FileManager.default.fileExists(atPath: original.path) && browser.canTransferTabs }
    collection.deselectAll(nil); browser.menuNeedsUpdate(menu)
    try require(menu.items.map(\.title) == ["Clear Trash…", "Refresh"], "Trash background must offer only appropriate commands")
    let clear = menu.items[0]
    NSApp.sendAction(clear.action!, to: clear.target, from: clear)
    try waitUntil { browser.window?.attachedSheet != nil }
    let sheet = browser.window!.attachedSheet!
    try require(descendants(sheet.contentView!).compactMap { ($0 as? NSTextField)?.stringValue }.contains { $0.contains("cannot be undone") }, "Clear Trash must explain permanent deletion before doing it")
    browser.window!.endSheet(sheet, returnCode: .alertFirstButtonReturn)
    let sidebar = Sidebar()
    let group = (0..<sidebar.outline.numberOfRows).compactMap { sidebar.outline.item(atRow: $0) as? FolderNode }.first { $0.title == "THIS MAC" }!
    try require(group.children?.last?.url == TrashStore.location, "Trash must be the final item under This Mac")
    print("PASS: Trash browsing, Restore context action, permanent-deletion confirmation, and final sidebar placement")
}
