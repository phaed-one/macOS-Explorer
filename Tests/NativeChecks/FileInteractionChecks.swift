import AppKit
import PathfindCore

func checkFileDropNoOps() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-Drops-\(UUID())")
    let folder = root.appendingPathComponent("folder"), other = root.appendingPathComponent("other")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let local = folder.appendingPathComponent("local.txt"), incoming = other.appendingPathComponent("incoming.txt")
    try Data("local".utf8).write(to: local)
    try Data("incoming".utf8).write(to: incoming)
    let link = folder.appendingPathComponent("link.txt")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: incoming)
    let alias = root.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: folder)
    for move in [false, true] {
        let drag = TestDrag()
        drag.draggingPasteboard.writeObjects([local as NSURL, folder as NSURL, link as NSURL])
        if move { drag.draggingPasteboard.setString("true", forType: FileTransfer.moveType) }
        var calls = 0
        let perform: ([URL], URL, Bool) -> Void = { _, _, _ in calls += 1 }
        try require(FileTransfer.accept(drag, destination: folder, perform: perform), "No-op drops must be consumed")
        try require(FileTransfer.accept(drag, destination: alias, perform: perform), "Aliased same-folder drops must be consumed")
        try require(calls == 0, "Same-folder and self drops must never start an operation or show a dialog")
        let browser = IconBrowser()
        browser.currentFolder = folder
        browser.onDrop = perform
        try require(browser.collectionView(browser.collection, acceptDrop: drag, indexPath: IndexPath(item: 0, section: 0), dropOperation: .before), "The icon browser must consume a background same-folder drop")
        try require(calls == 0, "The icon browser must not forward same-folder drops")
        drag.draggingPasteboard.clearContents()
        drag.draggingPasteboard.writeObjects([local as NSURL, incoming as NSURL])
        if move { drag.draggingPasteboard.setString("true", forType: FileTransfer.moveType) }
        var received: [URL] = []
        try require(FileTransfer.accept(drag, destination: folder) { urls, destination, moving in
            received = urls
            calls += 1
            assert(destination == folder && moving == move)
        }, "Mixed drops must still be accepted")
        try require(calls == 1 && received == [incoming], "Mixed drops must transfer only items from other folders")
    }
    let contents = try Data(contentsOf: local)
    try require(contents == Data("local".utf8), "No-op drops must preserve source bytes")
    print("PASS: Copy/move same-folder, self, aliased and mixed file drops")
}

func checkLiveIconHighlight() throws {
    let browser = IconBrowser()
    let entry = FileEntry(url: URL(fileURLWithPath: "/tmp/highlight.txt"), isDirectory: false, isHidden: false, size: 0, modified: Date(), kind: "Text")
    browser.entries = [entry]
    let item = browser.collectionView(browser.collection, itemForRepresentedObjectAt: IndexPath(item: 0, section: 0))
    func isHighlighted() -> Bool { (item.view.layer?.backgroundColor?.alpha ?? 0) > 0 }
    item.isSelected = false
    item.highlightState = .forSelection
    try require(!item.isSelected && isHighlighted(), "Marquee candidates must be blue before mouse-up commits selection")
    item.highlightState = .none
    try require(!isHighlighted(), "Moving the marquee away must clear the preview")
    item.isSelected = true
    try require(isHighlighted(), "Committed selection must remain highlighted")
    item.highlightState = .forDeselection
    try require(!isHighlighted(), "Marquee deselection must preview before mouse-up")
    item.highlightState = .none
    try require(isHighlighted(), "Cancelling deselection must restore the selected appearance")
    item.isSelected = false
    try require(!isHighlighted(), "Final deselection must clear the highlight")
    print("PASS: Live icon selection/deselection previews and committed selection")
}
