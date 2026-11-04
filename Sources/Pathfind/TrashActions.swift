import AppKit
import PathfindCore

/// Trash dialogs share the browser's existing asynchronous file-operation path.
final class TrashActions {
    private let store: TrashStore
    init(store: TrashStore) { self.store = store }
    typealias Perform = (@escaping () throws -> Void) -> Void
    func restore(_ urls: [URL], on window: NSWindow, perform: @escaping Perform) {
        guard !urls.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let destinations = Dictionary(uniqueKeysWithValues: urls.compactMap { url in self.store.originalURL(for: url).map { (url, $0) } })
            DispatchQueue.main.async {
                if destinations.count == urls.count {
                    perform { for url in urls { try self.store.restore(url, to: destinations[url]) } }
                    return
                }
                let panel = NSOpenPanel()
                panel.title = "Restore Items"
                panel.message = "Some original locations are unavailable. Choose a folder for those items; other items will return to their original locations."
                panel.prompt = "Restore Here"
                panel.canChooseFiles = false; panel.canChooseDirectories = true
                panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
                panel.beginSheetModal(for: window) { response in
                    guard response == .OK, let folder = panel.url else { return }
                    perform {
                        for url in urls { try self.store.restore(url, to: destinations[url] ?? folder.appendingPathComponent(url.lastPathComponent)) }
                    }
                }
            }
        }
    }
    func clear(on window: NSWindow, perform: @escaping Perform) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear Trash?"
        alert.informativeText = "All items in the Trash on connected drives will be permanently deleted. This cannot be undone."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear Trash")
        alert.beginSheetModal(for: window) { response in
            if response == .alertSecondButtonReturn { perform { try self.store.clear() } }
        }
    }
}
