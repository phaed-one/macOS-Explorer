import Foundation
import PathfindCore

func checkTabTransfer() throws {
    var source = BrowserTabs(url: URL(fileURLWithPath: "/a"))
    var tab = source.current
    tab.history.visit(URL(fileURLWithPath: "/a/child")); tab.url = URL(fileURLWithPath: "/a/child")
    source.current = tab; source.open(URL(fileURLWithPath: "/b"))
    var target = BrowserTabs(url: URL(fileURLWithPath: "/c"))
    let before = target.current.id
    target.insert(tab, before: before)
    try expect(target.items.first?.id == tab.id && target.current.history.locations == tab.history.locations, "Transfer retains identity, folder, history, and activation")
    try expect(source.close(tab.id) && source.items.count == 1, "Only the transferred tab leaves its source")
    target.move(tab.id, before: nil)
    try expect(target.items.last?.id == tab.id && target.activeID == tab.id, "Reordering preserves selection")
    target.insert(tab)
    try expect(target.items.count == 2, "A tab cannot appear twice in a window")
}

func checkTrash() throws {
    try fixture { root in
        let trash = root.appendingPathComponent("trash"), originals = root.appendingPathComponent("originals")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let suite = "PathfindTrashChecks." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let operation: (URL) throws -> URL = { source in
            let destination = trash.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination); return destination
        }
        let store = TrashStore(defaults: preferences, directories: { [trash] }, trashOperation: operation)
        let missing = TrashStore(defaults: preferences, directories: { [root.appendingPathComponent("not-created")] }, trashOperation: operation)
        try expect(try missing.contents(showHidden: true).isEmpty, "A not-yet-created Trash folder is empty")
        let original = originals.appendingPathComponent("résumé.txt")
        try Data("kept".utf8).write(to: original)
        let trashed = try store.trash(original)
        try expect(!FileManager.default.fileExists(atPath: original.path) && store.originalURL(for: trashed) == original, "Trashing saves the original Unicode location")
        let reopened = TrashStore(defaults: preferences, directories: { [trash] }, trashOperation: operation)
        try expect(reopened.originalURL(for: trashed) == original, "Put-back information survives restart")
        try Data("replacement".utf8).write(to: original)
        do { try reopened.restore(trashed); throw CheckFailure(message: "Restore overwrote an existing file") }
        catch is CheckFailure { throw CheckFailure(message: "Restore overwrote an existing file") } catch {}
        try expect(try String(contentsOf: original, encoding: .utf8) == "replacement" && FileManager.default.fileExists(atPath: trashed.path), "A collision preserves both items")
        try FileManager.default.removeItem(at: original)
        try reopened.restore(trashed)
        try expect(try String(contentsOf: original, encoding: .utf8) == "kept", "Restore returns the original contents to the original path")
        let renamed = trash.appendingPathComponent("renamed in trash.txt")
        try Data("Finder item".utf8).write(to: renamed)
        let metadata = makeTrashMetadata(name: renamed.lastPathComponent, parent: originals.path, originalName: "before trash.txt")
        try metadata.write(to: trash.appendingPathComponent(".DS_Store"))
        try expect(reopened.originalURL(for: renamed) == originals.appendingPathComponent("before trash.txt"), "Finder metadata restores the original name and parent")
        try reopened.restore(renamed)
        try expect(FileManager.default.fileExists(atPath: originals.appendingPathComponent("before trash.txt").path), "Restore Finder-trashed items without a Pathfind journal")
        try Data("hidden".utf8).write(to: trash.appendingPathComponent(".hidden item"))
        try FileManager.default.createDirectory(at: trash.appendingPathComponent("folder"), withIntermediateDirectories: false)
        try expect(try reopened.contents(showHidden: true).count == 2, "Trash metadata is never listed as a user item")
        try reopened.clear()
        try expect(try reopened.contents(showHidden: true).isEmpty && FileManager.default.fileExists(atPath: original.path) && FileManager.default.fileExists(atPath: trash.appendingPathComponent(".DS_Store").path), "Clear removes only trash contents, including hidden items, and preserves metadata and restored files")
        for length in [0, 8, 35, 500, 3000] {
            do { _ = try TrashMetadata.read(metadata.prefix(length)); throw CheckFailure(message: "Accepted truncated metadata") }
            catch is CheckFailure { throw CheckFailure(message: "Accepted truncated metadata") } catch {}
        }
    }
}

/// A minimal live B-tree with put-back records; unused bytes include a stale record.
func makeTrashMetadata(name: String, parent: String, originalName: String) -> Data {
    func integer(_ value: Int) -> Data { var value = UInt32(value).bigEndian; return withUnsafeBytes(of: &value) { Data($0) } }
    func unicode(_ text: String) -> Data { let bytes = text.data(using: .utf16BigEndian)!; return integer(bytes.count / 2) + bytes }
    func record(_ code: String, _ value: String) -> Data { unicode(name) + Data(code.utf8) + Data("ustr".utf8) + unicode(value) }
    var file = Data(repeating: 0, count: 8196)
    func write(_ data: Data, _ offset: Int) { file.replaceSubrange(offset..<(offset + data.count), with: data) }
    write(integer(1) + Data("Bud1".utf8) + integer(2048) + integer(1264) + integer(2048), 0)
    write(integer(3) + integer(0) + integer(2048 | 11) + integer(32 | 5) + integer(4096 | 12), 2052)
    write(integer(1) + Data([4]) + Data("DSDB".utf8) + integer(1), 2052 + 1032)
    write(integer(2) + integer(1) + integer(2) + integer(1) + integer(4096), 36)
    write(integer(0) + integer(2) + record("ptbL", parent) + record("ptbN", originalName), 4100)
    write(record("ptbL", "/wrong/stale/location"), 7000)
    return file
}
