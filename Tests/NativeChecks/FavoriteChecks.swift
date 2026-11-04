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
