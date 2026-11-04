import AppKit

func checkPathCompletion() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ExplorerCompletionChecks-" + UUID().uuidString)
    let alpha = root.appendingPathComponent("Alpha"), beta = root.appendingPathComponent("Beta")
    try FileManager.default.createDirectory(at: alpha.appendingPathComponent("Child"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: beta, withIntermediateDirectories: true)
    try Data().write(to: root.appendingPathComponent("not-a-folder.txt"))
    defer { try? FileManager.default.removeItem(at: root) }
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 700, height: 450), styleMask: [.titled], backing: .buffered, defer: false)
    let field = HeaderTextField()
    field.frame = NSRect(x: 20, y: 350, width: 650, height: 36)
    window.contentView!.addSubview(field)
    let completion = PathCompletionController(field: field, baseURL: { root })
    window.makeKeyAndOrderFront(nil)
    defer { completion.dismiss(); window.close() }
    window.makeFirstResponder(field)
    let editor = field.currentEditor() as! NSTextView
    func type(_ text: String) {
        field.stringValue = text; editor.string = text
        editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        completion.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    }
    func dropdown() -> NSWindow? { window.childWindows?.first { $0.identifier?.rawValue == "pathCompletions" && $0.isVisible } }
    func list() -> NSTableView { descendants(dropdown()!.contentView!).compactMap { $0 as? NSTableView }.first! }
    type(root.path + "/")
    try waitUntil { dropdown() != nil }
    try require(list().numberOfRows == 2, "Path completion must show folders and exclude files")
    try require(abs(dropdown()!.frame.width - field.bounds.width) < 0.5, "Dropdown must span the entire input width")
    try require(window.firstResponder === editor, "The dropdown must preserve path editing focus")
    try require(completion.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))), "Down must select a suggestion")
    try require(list().selectedRow == 0, "Down must select the first folder from an unselected list")
    try require(completion.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))), "Enter must accept a selected folder")
    try require(field.stringValue == alpha.path + "/", "Accepting a folder must append its name and a slash")
    try waitUntil { dropdown() != nil && list().numberOfRows == 1 }
    dropdown()!.contentView!.layoutSubtreeIfNeeded()
    try require(list().visibleRect.contains(list().rect(ofRow: 0)), "A single completion row must remain fully visible")
    let rowFrame = list().convert(list().rect(ofRow: 0), to: dropdown()!.contentView!)
    try require(rowFrame.minY >= 7 && dropdown()!.contentView!.bounds.maxY - rowFrame.maxY >= 7, "A single row needs padding above and below")
    let label = list().view(atColumn: 0, row: 0, makeIfNecessary: true) as! NSTableCellView
    try require(label.textField?.stringValue == "Child", "Accepting a folder must show its next-level folders")
    type(root.path + "/b")
    try waitUntil { dropdown() != nil && list().numberOfRows == 1 }
    try require((list().view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue == "Beta", "Typing must filter folders without case sensitivity")
    try require(completion.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))), "Escape must dismiss suggestions")
    try require(dropdown() == nil && field.stringValue.hasSuffix("/b"), "Dismissing must preserve the typed path")
    type(root.path + "/")
    try waitUntil { dropdown() != nil }
    try require(!completion.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))), "Enter without a selected suggestion must retain normal path navigation")
    type(root.path + "/missing/")
    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    try require(dropdown() == nil, "Unavailable folders must not leave a stale dropdown")
    print("PASS: Full-width path completion, folder-only filtering, keyboard acceptance, chained levels, focus, and dismissal")
}
