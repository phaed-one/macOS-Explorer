import Foundation
import PathfindCore

struct CheckFailure: Error { let message: String }
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw CheckFailure(message: message) }
}
func fixture(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}

func checkListing() throws {
    try fixture { root in
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Z folder"), withIntermediateDirectories: false)
        for name in ["file10.txt", "file2.txt", ".secret"] {
            try Data("test".utf8).write(to: root.appendingPathComponent(name))
        }
        let entries = try FileSystem.contents(of: root, showHidden: false)
        try expect(FileSystem.sorted(entries, by: .name, ascending: true).map(\.name) == ["Z folder", "file2.txt", "file10.txt"], "Natural ordering and hidden exclusion")
        for sort in FileSort.allCases {
            for ascending in [true, false] {
                try expect(FileSystem.sorted(entries, by: sort, ascending: ascending).first?.isDirectory == true, "Folders first for every column/direction")
            }
        }
        try expect(try FileSystem.contents(of: root, showHidden: true).contains { $0.name == ".secret" && $0.isHidden }, "Hidden file inclusion")
    }
}
func checkSymlinks() throws {
    try fixture { root in
        let folder = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: folder)
        try expect(try FileSystem.contents(of: root, showHidden: false).first { $0.name == "link" }?.isDirectory == true, "Directory symlink traversal")
    }
}
func checkPaths() throws {
    let base = URL(fileURLWithPath: "/Users/example/Documents")
    try expect(FileSystem.resolve("../Downloads", relativeTo: base).path == "/Users/example/Downloads", "Relative path")
    try expect(FileSystem.resolve("/tmp", relativeTo: base).path == "/tmp", "Absolute path")
    try expect(FileSystem.resolve("~", relativeTo: base).path == FileManager.default.homeDirectoryForCurrentUser.path, "Home expansion")
}
func checkHistory() throws {
    var history = NavigationHistory()
    let a = URL(fileURLWithPath: "/a"), b = URL(fileURLWithPath: "/b"), c = URL(fileURLWithPath: "/c")
    history.visit(a); history.visit(b); history.visit(b)
    try expect(history.locations.count == 2, "Refresh preserves history")
    try expect(history.back() == a, "Back navigation")
    try expect(history.canGoForward, "Forward available")
    history.visit(c)
    try expect(!history.canGoForward, "New visit truncates forward branch")
    try expect(history.back() == a, "Branch back navigation")
    try expect(history.back() == nil, "Back boundary")
    try expect(history.forward() == c, "Forward navigation")
}
func checkMissingDirectory() throws {
    do {
        _ = try FileSystem.contents(of: URL(fileURLWithPath: "/does-not-exist-\(UUID().uuidString)"), showHidden: true)
    } catch { return }
    throw CheckFailure(message: "Missing directory should report an error")
}

func checkFolderViews() throws {
    let suite = "PathfindChecks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let a = URL(fileURLWithPath: "/one"), b = URL(fileURLWithPath: "/two")
    let store = FolderViewStore(defaults: defaults)
    var custom = FolderViewPreferences()
    custom.iconSize = 120; custom.sort = .modified; custom.ascending = false; custom.foldersFirst = false
    custom.columnWidths = ["name": 420]
    store.save(custom, for: a)
    try expect(store.view(for: b) == FolderViewPreferences(), "Unconfigured folders inherit the initial default")
    let reopened = FolderViewStore(defaults: defaults)
    try expect(reopened.view(for: a) == custom, "Per-folder settings survive store recreation")
    try expect(reopened.view(for: a).iconSpacing == nil, "Older saved views without spacing retain their existing preferences")
    custom.iconSpacing = 28; reopened.save(custom, for: a)
    try expect(FolderViewStore(defaults: defaults).view(for: a).iconSpacing == 28, "Icon spacing survives store recreation")
    var newDefault = FolderViewPreferences(); newDefault.mode = .details; newDefault.sort = .size
    reopened.makeDefault(newDefault)
    try expect(reopened.view(for: b) == newDefault, "Unconfigured folders inherit the new default")
    try expect(reopened.view(for: a) == custom, "Setting a default preserves folder overrides")
    reopened.restoreDefault(for: a)
    try expect(!reopened.hasOverride(for: a) && reopened.view(for: a) == newDefault, "Restore removes the override")
    newDefault.iconSize = 90; reopened.makeDefault(newDefault)
    try expect(reopened.view(for: a).iconSize == 90, "Restored folders continue inheriting future defaults")
}
func checkTransfers() throws {
    try fixture { root in
        let source = root.appendingPathComponent("sample.txt"), target = root.appendingPathComponent("target")
        try Data("original".utf8).write(to: source)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileSystem.transfer(source, into: target, move: false)
        try expect(FileManager.default.fileExists(atPath: source.path), "Copy retains original")
        try expect(try Data(contentsOf: target.appendingPathComponent("sample.txt")) == Data("original".utf8), "Copy preserves bytes")
        do { try FileSystem.transfer(source, into: target, move: true); throw CheckFailure(message: "Must reject existing destination") }
        catch is CheckFailure { throw CheckFailure(message: "Must reject existing destination") }
        catch {}
        try expect(FileManager.default.fileExists(atPath: source.path), "Failed move retains source")
        let moved = root.appendingPathComponent("moved")
        try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: false)
        try FileSystem.transfer(source, into: moved, move: true)
        try expect(!FileManager.default.fileExists(atPath: source.path), "Move removes original after success")
        let child = target.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        do { try FileSystem.transfer(target, into: child, move: false); throw CheckFailure(message: "Must reject recursive copy") }
        catch is CheckFailure { throw CheckFailure(message: "Must reject recursive copy") }
        catch {}
    }
}
func checkNameConflicts() throws {
    try fixture { root in
        let fm = FileManager.default
        let incoming = root.appendingPathComponent("incoming"), target = root.appendingPathComponent("target")
        for folder in [incoming, target] { try fm.createDirectory(at: folder, withIntermediateDirectories: false) }
        let source = incoming.appendingPathComponent("Tool.app"), existing = target.appendingPathComponent("Tool.app")
        for (bundle, text) in [(source, "new"), (existing, "old")] {
            try fm.createDirectory(at: bundle, withIntermediateDirectories: false)
            try Data(text.utf8).write(to: bundle.appendingPathComponent("version"))
        }
        func version(_ bundle: URL) throws -> String { String(decoding: try Data(contentsOf: bundle.appendingPathComponent("version")), as: UTF8.self) }
        var trashed: [String] = []
        let trash: (URL) throws -> Void = { url in trashed.append(try version(url)); try fm.removeItem(at: url) }

        try FileSystem.transfer(source, into: target, move: false, conflict: .keepBoth, trash: trash)
        try expect(try version(target.appendingPathComponent("Tool 2.app")) == "new", "Keep Both numbers the name before the extension")
        try FileSystem.transfer(source, into: target, move: false, conflict: .keepBoth, trash: trash)
        try expect(fm.fileExists(atPath: target.appendingPathComponent("Tool 3.app").path), "Keep Both skips names already taken")
        try expect(try version(existing) == "old" && trashed.isEmpty, "Keep Both never touches the existing item")

        try FileSystem.transfer(source, into: target, move: false, conflict: .replace, trash: trash)
        try expect(try version(existing) == "new" && trashed == ["old"], "Replace hands the old item to the trash and puts the copy in its place")
        try expect(fm.fileExists(atPath: source.path), "A replacing copy keeps the source")
        let leftovers = try fm.contentsOfDirectory(atPath: target.path).filter { $0.hasPrefix(".") }
        try expect(leftovers.isEmpty, "Replace leaves no staged item behind")

        try Data("newer".utf8).write(to: source.appendingPathComponent("version"))
        let failing: (URL) throws -> Void = { _ in throw CheckFailure(message: "trash unavailable") }
        do { try FileSystem.transfer(source, into: target, move: true, conflict: .replace, trash: failing); throw CheckFailure(message: "A failed trash must fail the replace") }
        catch let failure as CheckFailure where failure.message == "A failed trash must fail the replace" { throw failure }
        catch {}
        try expect(try version(existing) == "new" && (try version(source)) == "newer", "A failed replace keeps both the existing item and the source")
        try expect(try fm.contentsOfDirectory(atPath: target.path).filter { $0.hasPrefix(".") }.isEmpty, "A failed replace cleans up its staged item")

        try FileSystem.transfer(source, into: target, move: true, conflict: .replace, trash: trash)
        try expect(try version(existing) == "newer" && !fm.fileExists(atPath: source.path), "A replacing move removes the source")

        let outer = root.appendingPathComponent("outer"), inner = outer.appendingPathComponent("outer")
        try fm.createDirectory(at: inner, withIntermediateDirectories: true)
        do { try FileSystem.transfer(inner, into: root, move: false, conflict: .replace, trash: trash); throw CheckFailure(message: "Must not replace a folder that holds the source") }
        catch let failure as CheckFailure where failure.message == "Must not replace a folder that holds the source" { throw failure }
        catch {}
        try expect(fm.fileExists(atPath: inner.path), "Refusing that replace keeps the source")
    }
}
func checkPermissionModes() throws {
    try expect(try PermissionMode.parse("chmod 0755", original: 0o600, isDirectory: false) == 0o755, "Octal chmod input")
    try expect(try PermissionMode.parse("u+rwx,g-w,o=rx", original: 0o664, isDirectory: false) == 0o745, "Symbolic mode clauses")
    try expect(try PermissionMode.parse("a+X", original: 0o644, isDirectory: false) == 0o644, "Conditional execute on non-executable file")
    try expect(try PermissionMode.parse("a+X", original: 0o644, isDirectory: true) == 0o755, "Conditional execute on directory")
    try expect(try PermissionMode.parse("g=u", original: 0o740, isDirectory: false) == 0o770, "Copy permission class")
    try expect(try PermissionMode.parse("u+s,o+t", original: 0o755, isDirectory: false) == 0o5755, "Special permission bits")
    for invalid in ["888", "chmod 755 /tmp", "u+z", "u+r; rm -rf /", "", "u+r,"] {
        do { _ = try PermissionMode.parse(invalid, original: 0o644, isDirectory: false); throw CheckFailure(message: "Invalid mode accepted: \(invalid)") }
        catch is CheckFailure { throw CheckFailure(message: "Invalid mode accepted: \(invalid)") }
        catch {}
    }
    try fixture { root in
        let url = root.appendingPathComponent("permissions.txt")
        try Data().write(to: url)
        try FileSystem.setPermissions(0o640, for: url)
        try expect(try FileSystem.permissions(for: url) == 0o640, "Apply and read POSIX bits")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        do { try FileSystem.setPermissions(0o777, for: link); throw CheckFailure(message: "Symlink must not change target implicitly") }
        catch is CheckFailure { throw CheckFailure(message: "Symlink must not change target implicitly") }
        catch {}
        try expect(try FileSystem.permissions(for: url) == 0o640, "Target permissions stay unchanged")
    }
}
func checkOptionalFolderGrouping() throws {
    try fixture { root in
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Z folder"), withIntermediateDirectories: false)
        try Data().write(to: root.appendingPathComponent("A file"))
        let entries = try FileSystem.contents(of: root, showHidden: false)
        try expect(FileSystem.sorted(entries, by: .name, ascending: true, foldersFirst: false).map(\.name) == ["A file", "Z folder"], "Folders First can be disabled")
        try expect(FileSystem.sorted(entries, by: .name, ascending: true, foldersFirst: true).map(\.name) == ["Z folder", "A file"], "Folders First can be enabled")
    }
}
func checkTabSessions() throws {
    let suite = "PathfindTabChecks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let home = URL(fileURLWithPath: "/home"), other = URL(fileURLWithPath: "/other")
    var tabs = BrowserTabs(url: home)
    let firstID = tabs.activeID
    tabs.open(other)
    let secondID = tabs.activeID
    tabs.current.history.visit(URL(fileURLWithPath: "/child"))
    tabs.current.url = URL(fileURLWithPath: "/child")
    tabs.save(to: defaults)
    var restored = BrowserTabs.restore(from: defaults, fallback: home)
    try expect(restored.items.count == 2 && restored.activeID == secondID, "Tabs and active selection survive restart")
    try expect(restored.current.url.path == "/child", "Active folder survives restart")
    try expect(restored.current.history.back() == other, "Per-tab navigation history survives restart")
    restored.select(firstID)
    try expect(restored.current.url == home, "Switching tabs retains independent folders")
    try expect(restored.close(firstID) && restored.activeID == secondID, "Closing active tab selects its neighbor")
    try expect(!restored.close(secondID), "Last tab is retained until window close")
    defaults.set(Data("invalid".utf8), forKey: "browserTabs")
    try expect(BrowserTabs.restore(from: defaults, fallback: home).current.url == home, "Invalid saved state recovers to a usable tab")
}
func checkTreeBranchMemory() throws {
    var state = TreeExpansionState()
    state.setExpanded(true, path: "/FOLDER1")
    try expect(!state.isExpanded("/FOLDER1/A") && !state.isExpanded("/FOLDER1/C"), "Opening a parent never opens all children")
    state.setExpanded(true, path: "/FOLDER1/C")
    state.setExpanded(false, path: "/FOLDER1")
    try expect(state.isExpanded("/FOLDER1/C"), "Collapsing a parent preserves child expansion")
    state = TreeExpansionState(paths: Array(state.paths))
    state.setExpanded(true, path: "/FOLDER1")
    try expect(state.isExpanded("/FOLDER1/C") && !state.isExpanded("/FOLDER1/A"), "Reopening after restart restores only the expanded child")
    state.setExpanded(false, path: "/FOLDER1/C")
    state.setExpanded(false, path: "/FOLDER1"); state.setExpanded(true, path: "/FOLDER1")
    try expect(!state.isExpanded("/FOLDER1/C"), "Explicitly collapsed children stay collapsed")
}

func checkDuplicate() throws {
    try fixture { root in
        let original = root.appendingPathComponent("notes.txt")
        try Data("original".utf8).write(to: original)
        let first = try FileSystem.duplicate(original)
        let second = try FileSystem.duplicate(original)
        try expect(first.lastPathComponent == "notes copy.txt" && second.lastPathComponent == "notes copy 2.txt", "Duplicate must preserve extensions and choose an unused name")
        try expect(try Data(contentsOf: original) == Data(contentsOf: second), "Duplicate must preserve the original contents")
        let directory = root.appendingPathComponent("folder.with.dots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data("hidden".utf8).write(to: directory.appendingPathComponent(".hidden"))
        let copy = try FileSystem.duplicate(directory)
        try expect(copy.lastPathComponent == "folder.with.dots copy" && FileManager.default.fileExists(atPath: copy.appendingPathComponent(".hidden").path), "Duplicate folders recursively, preserving their complete names and hidden contents")
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        let linkCopy = try FileSystem.duplicate(link)
        try expect(try FileManager.default.destinationOfSymbolicLink(atPath: linkCopy.path) == original.path, "Duplicate the link without copying or altering its target")
    }
}

let checks: [(String, () throws -> Void)] = [
    ("Listing, hidden files, natural sorting, folders first", checkListing),
    ("Directory symlinks", checkSymlinks), ("Path resolution", checkPaths),
    ("Navigation history", checkHistory), ("Missing directory errors", checkMissingDirectory),
    ("Per-folder preferences and default inheritance", checkFolderViews),
    ("Hidden-file defaults, per-folder overrides, restart, and legacy migration", checkHiddenFiles),
    ("Copy/move safety and collision handling", checkTransfers),
    ("Replace and Keep Both on name clashes", checkNameConflicts),
    ("Safe duplication of files, folders, and symbolic links", checkDuplicate),
    ("Trash journal, restore collisions, Finder metadata, and scoped clearing", checkTrash),
    ("Tab transfer preserves identity and history", checkTabTransfer),
    ("chmod parsing and permissions", checkPermissionModes),
    ("Optional folder grouping", checkOptionalFolderGrouping),
    ("Tab sessions and independent history", checkTabSessions),
    ("Independent tree branch expansion", checkTreeBranchMemory)
]
var failures = 0
for (name, run) in checks {
    do { try run(); print("PASS: \(name)") }
    catch { failures += 1; print("FAIL: \(name): \(error)") }
}
print("\(checks.count - failures)/\(checks.count) checks passed")
exit(failures == 0 ? 0 : 1)
