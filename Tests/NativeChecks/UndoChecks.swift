import AppKit
import PathfindCore

/// A throwaway Trash folder and store, so checks never touch the real Trash.
private func scratchTrash(_ label: String) throws -> (root: URL, trash: URL, store: TrashStore, cleanup: () -> Void) {
    let suite = "Explorer\(label)." + UUID().uuidString
    let preferences = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite), trash = root.appendingPathComponent("trash")
    try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    let store = TrashStore(defaults: preferences, directories: { [trash] }, trashOperation: { source in
        let destination = FileSystem.itemExists(trash.appendingPathComponent(source.lastPathComponent))
            ? FileSystem.availableDestination(for: source, in: trash) : trash.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.moveItem(at: source, to: destination); return destination
    })
    return (root, trash, store, { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) })
}

/// The Trash opens like Finder's: details with Date Deleted, newest first, its own hidden-file setting on.
func checkTrashView() throws {
    let suite = "ExplorerTrashView." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var saved = FolderViewPreferences(); saved.mode = .icons
    defaults.set(try JSONEncoder().encode([TrashStore.location.absoluteString: saved]), forKey: "folderViews")
    let views = FolderViewStore(defaults: defaults)
    let trashView = views.view(for: TrashStore.location)
    try require(!views.hasOverride(for: TrashStore.location), "A Trash view saved before its default existed is reset once")
    try require(trashView.mode == .details && trashView.sort == .deleted && !trashView.ascending && !trashView.foldersFirst
                && trashView.columnOrder.prefix(2) == ["name", "deleted"], "The Trash defaults to details, newest deleted first")
    try require(views.view(for: FileManager.default.temporaryDirectory).sort == .name, "Other folders keep the normal default")
    views.save(saved, for: TrashStore.location)
    try require(FolderViewStore(defaults: defaults).view(for: TrashStore.location).mode == .icons, "The one-time reset doesn't undo later choices")
    views.makeDefault(trashView)
    try require(views.defaultView.sort == .modified && !views.defaultView.columnOrder.contains("deleted"), "Date Deleted never becomes every folder's default")

    let hidden = HiddenFileStore(defaults: defaults)
    try require(hidden.hasOverride(for: TrashStore.location) && hidden.showsHidden(in: TrashStore.location), "The Trash has its own hidden-file setting, on")
    hidden.set(false, for: TrashStore.location)
    try require(!HiddenFileStore(defaults: defaults).showsHidden(in: TrashStore.location), "Turning hidden files off in the Trash sticks")

    // Items carry the date they went into the Trash, and sort newest first.
    let (root, _, store, cleanup) = try scratchTrash("TrashDates")
    defer { cleanup() }
    for name in ["older.txt", "newer.txt"] {
        let file = root.appendingPathComponent(name)
        try Data(name.utf8).write(to: file); try store.trash(file)
        Thread.sleep(forTimeInterval: 1.1)
    }
    let entries = try store.contents(showHidden: true)
    try require(entries.allSatisfy { $0.deleted != nil }, "Every Trash item has a date deleted")
    let newestFirst = FileSystem.sorted(entries, by: .deleted, ascending: false, foldersFirst: false).map(\.name)
    try require(newestFirst == ["newer.txt", "older.txt"], "Sorting by Date Deleted puts the latest first: \(newestFirst)")

    let browser = BrowserController(tabs: BrowserTabs(url: TrashStore.location), trashStore: store)
    browser.showWindow(nil); defer { browser.window?.close() }
    try waitUntil { browser.window?.representedURL == TrashStore.location }
    let table = descendants(browser.window!.contentView!).compactMap { $0 as? NSTableView }.first { $0.tableColumns.contains { $0.identifier.rawValue == "name" } }!
    try require(table.tableColumns.contains { $0.identifier.rawValue == "deleted" && $0.title == "Date Deleted" }, "The Trash shows a Date Deleted column")
    browser.navigate(root)
    try waitUntil { browser.window?.representedURL == root }
    try require(!table.tableColumns.contains { $0.identifier.rawValue == "deleted" }, "Other folders have no Date Deleted column")
    print("PASS: The Trash opens in details with Date Deleted, newest first, and its own hidden-file setting")
}

/// Undo reverses file operations and Redo repeats them, as Finder's Edit menu does.
func checkFileUndo() throws {
    let (root, trash, store, cleanup) = try scratchTrash("Undo")
    defer { cleanup() }
    let undo = FileUndo(trashStore: store)
    var failures: [Error] = []
    undo.onFailure = { failures.append($0) }
    let manager = undo.manager
    func exists(_ url: URL) -> Bool { FileSystem.itemExists(url) }

    // Created items go to the Trash on undo and come back on redo.
    let created = root.appendingPathComponent("New Folder")
    try FileManager.default.createDirectory(at: created, withIntermediateDirectories: false)
    undo.record([.created(created)], name: "New Folder")
    try require(manager.undoMenuItemTitle == "Undo New Folder", "Undo names the step: \(manager.undoMenuItemTitle)")
    manager.undo()
    try require(!exists(created) && exists(trash.appendingPathComponent("New Folder")), "Undoing a new item moves it to the Trash")
    try require(manager.redoMenuItemTitle == "Redo New Folder", "Redo names the step")
    manager.redo()
    try require(exists(created) && !exists(trash.appendingPathComponent("New Folder")), "Redo brings the item back")

    // Renames and moves go back, including a rename that only changes letter case.
    for (old, new) in [("a.txt", "b.txt"), ("case.txt", "CASE.txt")] {
        let from = root.appendingPathComponent(old), to = root.appendingPathComponent(new)
        try Data().write(to: from)
        try FileManager.default.moveItem(at: from, to: to)
        undo.record([.moved(from: from, to: to)], name: "Rename")
        manager.undo()
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        try require(names.contains(old) && !names.contains(new) && failures.isEmpty, "Undoing a rename restores \(old): \(names) \(failures)")
        manager.redo()
        let redone = try FileManager.default.contentsOfDirectory(atPath: root.path)
        try require(redone.contains(new), "Redo renames to \(new) again")
    }

    // Moving to the Trash: undo puts every item back, redo trashes them again, as one step.
    let first = root.appendingPathComponent("one.txt"), second = root.appendingPathComponent("two.txt")
    try Data().write(to: first); try Data().write(to: second)
    let changes = try [first, second].map { FileUndo.Change.trashed(original: $0, inTrash: try store.trash($0)) }
    undo.record(changes, name: "Move to Trash")
    manager.undo()
    try require(exists(first) && exists(second) && manager.redoMenuItemTitle == "Redo Move to Trash", "Undoing Move to Trash puts back every item in one step")
    manager.redo()
    try require(!exists(first) && !exists(second), "Redoing Move to Trash trashes them again")
    manager.undo()

    // A step that can no longer be undone says why and leaves the files alone.
    let gone = root.appendingPathComponent("gone.txt")
    try Data().write(to: gone)
    undo.record([.created(gone)], name: "Duplicate")
    try FileManager.default.removeItem(at: gone)
    manager.undo()
    try require(failures.count == 1 && !manager.canRedo, "An impossible undo reports an error and leaves nothing to redo: \(failures)")

    // In a window, Undo reaches the shared file stack from the file list, while text keeps its own.
    let browser = BrowserController(tabs: BrowserTabs(url: root), trashStore: store)
    browser.showWindow(nil); defer { browser.window?.close() }
    try waitUntil { browser.window?.representedURL == root }
    let window = browser.window!
    let table = descendants(window.contentView!).compactMap { $0 as? NSTableView }.first { $0.tableColumns.contains { $0.identifier.rawValue == "name" } }!
    window.makeFirstResponder(table)
    try require(window.undoManager === FileUndo.shared.manager, "The file list uses the shared file undo stack")
    let from = root.appendingPathComponent("menu.txt"), to = root.appendingPathComponent("menu renamed.txt")
    try Data().write(to: from); try FileManager.default.moveItem(at: from, to: to)
    FileUndo.shared.record([.moved(from: from, to: to)], name: "Rename")
    let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    try require(window.validateUserInterfaceItem(undoItem) && undoItem.title == "Undo Rename", "Edit > Undo names the file step: \(undoItem.title)")
    try require(table.tryToPerform(Selector(("undo:")), with: nil) && exists(from) && !exists(to), "Edit > Undo from the file list reverses the last file operation")
    try require(table.tryToPerform(Selector(("redo:")), with: nil) && !exists(from) && exists(to), "Edit > Redo from the file list repeats it")
    let path = descendants(window.contentView!).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    window.makeFirstResponder(path)
    try require(window.undoManager !== FileUndo.shared.manager, "Text being edited keeps its own undo")
    print("PASS: Undo and Redo reverse and repeat new items, renames, moves and Move to Trash")
}
