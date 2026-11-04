import AppKit

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
    try require(sidebar.outlineView(outline, pasteboardWriterForItem: mac.children!.first!) == nil, "Filesystem rows must not become favorite reorder sources")
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
