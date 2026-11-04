import AppKit
import PathfindCore

extension Notification.Name { static let pathfindFilesChanged = Notification.Name("PathfindFilesChanged") }

enum BrowserLocation {
    static func title(_ url: URL) -> String {
        if url == TrashStore.location { return "Trash" }
        return url.path == "/" ? "Filesystem" : url.lastPathComponent
    }
    static func path(_ url: URL) -> String { url == TrashStore.location ? "Trash" : url.path }
    static func icon(_ url: URL) -> NSImage {
        if url == TrashStore.location { return NSImage(systemSymbolName: "trash", accessibilityDescription: "Trash")! }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
