import AppKit
import PathfindCore

/// Undo and redo for file operations, shared by every browser window, as in Finder.
///
/// An operation records what it changed. Undoing a step performs the reverse of each change, last
/// first, and records those reverses as the step's redo:
/// - `moved` (rename, move): moved back.
/// - `created` (copy, duplicate, new file or folder, alias, archive, restore from the Trash): moved to the Trash.
/// - `trashed`: put back where it was.
final class FileUndo {
    static let shared = FileUndo()

    enum Change: Equatable {
        case moved(from: URL, to: URL)
        case created(URL)
        case trashed(original: URL, inTrash: URL)
    }

    /// Collects one operation's changes as it runs, on any queue.
    final class Log {
        private let lock = NSLock()
        private var list: [Change] = []
        func add(_ change: Change) { lock.lock(); list.append(change); lock.unlock() }
        var changes: [Change] { lock.lock(); defer { lock.unlock() }; return list }
    }

    let manager = UndoManager()
    private let trashStore: TrashStore
    /// Shows a step that could not be undone or redone.
    var onFailure: (Error) -> Void = { error in
        let alert = NSAlert(error: error)
        if let window = NSApp.keyWindow { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    init(trashStore: TrashStore = .shared) {
        self.trashStore = trashStore
        // Each operation is one step; it is registered after the work finishes, outside any event.
        manager.groupsByEvent = false
    }

    /// Makes the finished operation's changes one undo step, named for the Edit menu ("Undo Rename").
    func record(_ changes: [Change], name: String) {
        guard !changes.isEmpty else { return }
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: self) { $0.revert(changes, name: name) }
        manager.setActionName(name)
        manager.endUndoGrouping()
    }

    /// Reverses `changes`, last first. Whatever was reversed before a failure becomes the opposite step.
    private func revert(_ changes: [Change], name: String) {
        var reversed: [Change] = []
        var failure: Error?
        for change in changes.reversed() {
            do { reversed.append(try reverse(change)) } catch { failure = error; break }
        }
        if !reversed.isEmpty {
            manager.registerUndo(withTarget: self) { $0.revert(reversed, name: name) }
            manager.setActionName(name)
        }
        NotificationCenter.default.post(name: .pathfindFilesChanged, object: nil)
        if let failure { onFailure(failure) }
    }

    /// Performs the opposite of `change` and returns the change that undoes that.
    private func reverse(_ change: Change) throws -> Change {
        switch change {
        case .moved(let from, let to):
            guard FileSystem.itemExists(to) else { throw Self.missing(to) }
            // A rename that only changed letter case finds the same item under both names.
            let sameItem = from.standardizedFileURL.path.lowercased() == to.standardizedFileURL.path.lowercased()
            guard sameItem || !FileSystem.itemExists(from) else { throw Self.occupied(from) }
            try FileManager.default.moveItem(at: to, to: from)
            return .moved(from: to, to: from)
        case .created(let url):
            guard FileSystem.itemExists(url) else { throw Self.missing(url) }
            return .trashed(original: url, inTrash: try trashStore.trash(url))
        case .trashed(let original, let inTrash):
            guard FileSystem.itemExists(inTrash) else {
                throw NSError(domain: "Explorer.Undo", code: 1, userInfo: [NSLocalizedDescriptionKey: "“\(original.lastPathComponent)” is no longer in the Trash."])
            }
            guard !FileSystem.itemExists(original) else { throw Self.occupied(original) }
            try trashStore.restore(inTrash, to: original)
            return .created(original)
        }
    }

    private static func missing(_ url: URL) -> NSError {
        NSError(domain: "Explorer.Undo", code: 2, userInfo: [NSLocalizedDescriptionKey: "“\(url.lastPathComponent)” can’t be found, so this can’t be undone."])
    }
    private static func occupied(_ url: URL) -> NSError {
        NSError(domain: "Explorer.Undo", code: 3, userInfo: [NSLocalizedDescriptionKey: "An item named “\(url.lastPathComponent)” is already in “\(url.deletingLastPathComponent().lastPathComponent)”, so this can’t be undone."])
    }
}
