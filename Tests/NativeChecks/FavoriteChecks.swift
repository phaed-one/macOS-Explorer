import AppKit

func checkInitialFavoriteOrder() throws {
    let defaults = UserDefaults.standard
    let keys = ["favorites", "homeFirstFavoriteOrderApplied"]
    let saved = keys.map { defaults.object(forKey: $0) }
    defer {
        for (key, value) in zip(keys, saved) {
            if let value { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
    }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    keys.forEach { defaults.removeObject(forKey: $0) }
    let fresh = Sidebar().favorites.map(\.path)
    try require(fresh.first == home && fresh.dropFirst().first == "/Applications", "Home must be first and Applications second for new users: \(fresh)")
    defaults.removeObject(forKey: keys[1])
    defaults.set(["/tmp/Custom-A", "/Applications", home, "/tmp/Custom-B"], forKey: "favorites")
    let migrated = Sidebar().favorites.map(\.path)
    try require(migrated == [home, "/tmp/Custom-A", "/Applications", "/tmp/Custom-B"], "Upgrade must move Home first and keep everything else in order: \(migrated)")
    let reordered = ["/Applications", home, "/tmp/Custom-A"]
    defaults.set(reordered, forKey: "favorites")
    try require(Sidebar().favorites.map(\.path) == reordered, "After the upgrade, manual favorite ordering must remain available")
    defaults.removeObject(forKey: keys[1])
    defaults.set(["/tmp/Only-Custom"], forKey: "favorites")
    try require(Sidebar().favorites.map(\.path) == ["/tmp/Only-Custom"], "Upgrade must not re-add removed favorites")
    print("PASS: Home first by default and on upgrade; custom favorites and later reordering preserved")
}

func checkFavoriteReordering() throws {
    let defaults = UserDefaults.standard
    let saved = defaults.object(forKey: "favorites")
    defer {
        if let saved { defaults.set(saved, forKey: "favorites") }
        else { defaults.removeObject(forKey: "favorites") }
    }
    let paths = ["/tmp/Favorite-A", "/tmp/Favorite-B", "/tmp/Favorite-C"]
    defaults.set(paths, forKey: "favorites")
    let sidebar = Sidebar(), other = Sidebar()
    let outline = sidebar.outline
    func group(_ sidebar: Sidebar) -> FolderNode {
        sidebar.outlineView(sidebar.outline, child: 0, ofItem: nil) as! FolderNode
    }
    func drag(_ childIndex: Int) throws -> TestDrag {
        let node = group(sidebar).children![childIndex]
        guard let writer = sidebar.outlineView(outline, pasteboardWriterForItem: node) else {
            throw NativeCheckError.failed("Favorites must provide a drag writer")
        }
        let info = TestDrag()
        info.draggingSource = outline
        info.draggingPasteboard.writeObjects([writer])
        try require(FileTransfer.urls(info).isEmpty, "Favorite drags must never expose a file transfer")
        return info
    }
    var fileTransfers = 0
    sidebar.onDrop = { _, _, _ in fileTransfers += 1 }
    let down = try drag(0)
    try require(sidebar.outlineView(outline, validateDrop: down, proposedItem: group(sidebar), proposedChildIndex: 3) == .move, "Moving to the end must be accepted")
    try require(sidebar.outlineView(outline, acceptDrop: down, item: group(sidebar), childIndex: 3), "Downward reorder must succeed")
    try require(sidebar.favorites.map(\.path) == [paths[1], paths[2], paths[0]], "Downward insertion must adjust for the removed row")
    try require(group(other).children!.compactMap { $0.url?.path } == sidebar.favorites.map(\.path), "Other sidebars must refresh immediately")
    let up = try drag(2)
    try require(sidebar.outlineView(outline, validateDrop: up, proposedItem: group(sidebar).children![0], proposedChildIndex: -1) == .move, "Dropping on a favorite must show an insertion")
    try require(sidebar.outlineView(outline, acceptDrop: up, item: group(sidebar), childIndex: 0), "Upward reorder must succeed")
    try require(sidebar.favorites.map(\.path) == paths, "Upward reorder must restore the original order")
    let unchanged = try drag(1)
    try require(sidebar.outlineView(outline, acceptDrop: unchanged, item: group(sidebar), childIndex: 2), "Adjacent self-drop must succeed without changing order")
    try require(sidebar.favorites.map(\.path) == paths, "Self-drop must preserve the order")
    let mac = sidebar.outlineView(outline, child: 1, ofItem: nil) as! FolderNode
    try require(sidebar.outlineView(outline, validateDrop: unchanged, proposedItem: mac.children!.first!, proposedChildIndex: -1).isEmpty, "Favorite reordering must reject filesystem destinations")
    try require(!sidebar.outlineView(outline, acceptDrop: unchanged, item: mac.children!.first!, childIndex: -1), "An invalid drop must not transfer the folder")
    let treeWriter = sidebar.outlineView(outline, pasteboardWriterForItem: mac.children!.first!) as? NSPasteboardItem
    try require(treeWriter != nil && !treeWriter!.types.contains(.init("com.pathfind.favorite")) && !treeWriter!.types.contains(.fileURL),
        "Filesystem rows must drag only as tree folders, never as favorites or files")
    let append = try drag(0)
    try require(sidebar.outlineView(outline, acceptDrop: append, item: group(sidebar), childIndex: -1), "Dropping on the Favorites header must append")
    let restarted = Sidebar()
    try require(group(restarted).children!.compactMap { $0.url?.path } == [paths[1], paths[2], paths[0]], "Favorite order must survive sidebar recreation")
    try require(fileTransfers == 0, "Reordering favorites must never invoke a file transfer")

    let files = TestDrag()
    files.draggingPasteboard.writeObjects([URL(fileURLWithPath: "/tmp/test-file") as NSURL])
    let target = group(sidebar).children![0]
    try require(!sidebar.outlineView(outline, validateDrop: files, proposedItem: target, proposedChildIndex: -1).isEmpty, "Normal file drops onto favorites must remain supported")
    try require(sidebar.outlineView(outline, acceptDrop: files, item: target, childIndex: -1), "Normal file transfers must remain supported")
    try require(fileTransfers == 1, "A file drop must still invoke the transfer handler")
    print("PASS: Favorite dragging reorders up/down, persists, synchronizes sidebars, and preserves file drops")
}

func checkFolderDropsAddFavorites() throws {
    let defaults = UserDefaults.standard
    let saved = defaults.object(forKey: "favorites")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PathfindFavoriteDrops-\(UUID().uuidString)").standardizedFileURL
    defer {
        if let saved { defaults.set(saved, forKey: "favorites") }
        else { defaults.removeObject(forKey: "favorites") }
        try? FileManager.default.removeItem(at: root)
    }
    let a = root.appendingPathComponent("A"), b = root.appendingPathComponent("B"), c = root.appendingPathComponent("C")
    let app = root.appendingPathComponent("Tool.app"), file = root.appendingPathComponent("notes.txt")
    for folder in [a, b, c, app] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    try Data().write(to: file)
    defaults.set([a.path, b.path], forKey: "favorites")
    let sidebar = Sidebar()
    let outline = sidebar.outline
    var fileTransfers = 0
    sidebar.onDrop = { _, _, _ in fileTransfers += 1 }
    func group() -> FolderNode { sidebar.outlineView(outline, child: 0, ofItem: nil) as! FolderNode }
    func drag(_ urls: [URL]) -> TestDrag {
        let info = TestDrag()
        info.draggingPasteboard.writeObjects(urls.map { $0 as NSURL })
        return info
    }

    let between = drag([c])
    try require(sidebar.outlineView(outline, validateDrop: between, proposedItem: group(), proposedChildIndex: 1) == .copy, "A folder dragged between favorites must be accepted")
    try require(sidebar.outlineView(outline, acceptDrop: between, item: group(), childIndex: 1), "Dropping a folder between favorites must succeed")
    try require(sidebar.favorites.map(\.path) == [a.path, c.path, b.path], "A dropped folder must be inserted where it was dropped")

    defaults.set([a.path], forKey: "favorites"); sidebar.reload()
    let header = drag([b, c])
    try require(sidebar.outlineView(outline, acceptDrop: header, item: group(), childIndex: -1), "Dropping folders on the Favorites header must succeed")
    try require(sidebar.favorites.map(\.path) == [a.path, b.path, c.path], "Header drops must append every new folder")

    let duplicate = drag([a])
    try require(sidebar.outlineView(outline, validateDrop: duplicate, proposedItem: group(), proposedChildIndex: 0).isEmpty, "A folder that is already a favorite must not be added again")
    try require(sidebar.outlineView(outline, validateDrop: drag([app]), proposedItem: group(), proposedChildIndex: 0).isEmpty, "App bundles must not become favorites")
    try require(sidebar.outlineView(outline, validateDrop: drag([file]), proposedItem: group(), proposedChildIndex: 0).isEmpty, "Files must not become favorites")
    try require(sidebar.outlineView(outline, validateDrop: drag([c, file]), proposedItem: group(), proposedChildIndex: 0).isEmpty, "A mixed folder and file drag must not become favorites")

    defaults.set([a.path], forKey: "favorites"); sidebar.reload()
    let onto = drag([c])
    try require(sidebar.outlineView(outline, acceptDrop: onto, item: group().children![0], childIndex: -1), "Dropping a folder onto a favorite must still copy into it")
    try require(fileTransfers == 1 && sidebar.favorites.map(\.path) == [a.path], "Dropping onto a favorite must copy, not add a favorite")
    print("PASS: Folders dropped on the Favorites header or between favorites are added there; drops onto a favorite still copy")
}

func checkTreeHidingAndFavoriteDrops() throws {
    let defaults = UserDefaults.standard
    let keys = ["favorites", "hiddenVolumes"]
    let saved = keys.map { defaults.object(forKey: $0) }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PathfindTree-\(UUID().uuidString)").standardizedFileURL
    defer {
        for (key, value) in zip(keys, saved) {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        try? FileManager.default.removeItem(at: root)
    }
    defaults.set([NSHomeDirectory()], forKey: "favorites")
    defaults.removeObject(forKey: "hiddenVolumes")
    let sidebar = Sidebar()
    let outline = sidebar.outline
    func group(_ index: Int) -> FolderNode { sidebar.outlineView(outline, child: index, ofItem: nil) as! FolderNode }
    let mac = group(1), filesystem = mac.children!.first!
    // THIS MAC header icons.
    let header = sidebar.outlineView(outline, viewFor: outline.tableColumns[0], item: mac)!
    let icons = descendants(header).compactMap { $0 as? NSButton }
    let hide = icons.first { $0.accessibilityLabel() == "Hide the selected folder from the tree" }
    let unhideAll = icons.first { $0.accessibilityLabel() == "Show all hidden folders" }
    try require(hide != nil && unhideAll != nil, "THIS MAC must show hide and unhide-all icons: \(icons.map { $0.accessibilityLabel() ?? "" })")
    try require(unhideAll!.isHidden, "Unhide all must only appear while something is hidden")
    outline.deselectAll(nil)
    try require(!hide!.isEnabled, "Hide needs a selected THIS MAC folder")
    let row = outline.row(forItem: filesystem)
    outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    try require(hide!.isEnabled, "Selecting a THIS MAC folder must enable Hide")
    hide!.performClick(nil)
    try require((defaults.stringArray(forKey: "hiddenVolumes") ?? []) == ["/"], "Hide must hide the selected folder")
    let reloaded = group(1)
    try require(!(reloaded.children ?? []).contains { $0.url?.path == "/" }, "A hidden folder must leave the tree")
    let newHeader = sidebar.outlineView(outline, viewFor: outline.tableColumns[0], item: reloaded)!
    let newUnhide = descendants(newHeader).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Show all hidden folders" }!
    try require(!newUnhide.isHidden, "Unhide all must appear once something is hidden")
    // The header's right-click menu can bring back one folder.
    let menu = NSMenu()
    sidebar.setHidden(root, true)
    sidebar.appendHiddenFolderItems(to: menu)
    try require(menu.items.contains { $0.title == "Show Filesystem /" } && menu.items.contains { $0.title == "Show \(root.path)" }, "The header menu must list each hidden folder: \(menu.items.map(\.title))")
    let showOne = menu.items.first { $0.title == "Show \(root.path)" }!
    NSApp.sendAction(showOne.action!, to: showOne.target, from: showOne)
    try require((defaults.stringArray(forKey: "hiddenVolumes") ?? []) == ["/"], "Showing one hidden folder must leave the others hidden")
    newUnhide.performClick(nil)
    try require((defaults.stringArray(forKey: "hiddenVolumes") ?? []).isEmpty && group(1).children!.contains { $0.url?.path == "/" }, "Unhide all must bring every folder back")

    // Dragging a tree folder into Favorites.
    let fs = group(1).children!.first!
    let writer = sidebar.outlineView(outline, pasteboardWriterForItem: fs) as! NSPasteboardItem
    let drag = TestDrag(); drag.draggingSource = outline
    drag.draggingPasteboard.writeObjects([writer])
    try require(sidebar.outlineView(outline, validateDrop: drag, proposedItem: group(0), proposedChildIndex: 1) == .move, "A tree folder must be droppable into Favorites")
    try require(sidebar.outlineView(outline, validateDrop: drag, proposedItem: fs, proposedChildIndex: -1).isEmpty, "A tree folder must not be droppable anywhere but Favorites")
    try require(sidebar.outlineView(outline, acceptDrop: drag, item: group(0), childIndex: 1), "Dropping a tree folder into Favorites must succeed")
    try require(sidebar.favorites.map(\.path) == [NSHomeDirectory(), "/"], "The dropped folder must be added where it was dropped: \(sidebar.favorites.map(\.path))")
    try require(sidebar.outlineView(outline, validateDrop: drag, proposedItem: group(0), proposedChildIndex: 0).isEmpty, "A folder that is already a favorite must not be added twice")
    print("PASS: THIS MAC hides any selected folder, unhides one or all from its header, and tree folders drag into Favorites only")
}
