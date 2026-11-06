import AppKit

/// A marker distinguishes intentional secondary-button moves from ordinary copy drags.
enum FileTransfer {
    static let moveType = NSPasteboard.PasteboardType("local.pathfind.move")
    static func urls(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
    static func dragOperation(_ info: NSDraggingInfo) -> NSDragOperation {
        guard !urls(info).isEmpty else { return [] }
        let operation: NSDragOperation = info.draggingPasteboard.string(forType: moveType) == "true" ? .move : .copy
        return info.draggingSourceOperationMask.contains(operation) ? operation : []
    }
    static func accept(_ info: NSDraggingInfo, destination: URL, perform: (([URL], URL, Bool) -> Void)?) -> Bool {
        let operation = dragOperation(info)
        guard !operation.isEmpty, let perform else { return false }
        let folder = destination.resolvingSymlinksInPath().standardizedFileURL
        let sources = urls(info).filter { url in
            let source = url.resolvingSymlinksInPath().standardizedFileURL
            let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            return source.path != folder.path && parent.path != folder.path
        }
        // Dropping an item on itself or back into its own folder is a no-op.
        if !sources.isEmpty { perform(sources, destination, operation == .move) }
        return true
    }
    static func trackRightMouse(in view: NSView, event: NSEvent, beginDrag: (NSEvent) -> Void) {
        guard let window = view.window else { return }
        while let next = window.nextEvent(matching: [.rightMouseDragged, .rightMouseUp]) {
            if next.type == .rightMouseUp {
                if let menu = view.menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: view) }
                return
            }
            let dx = next.locationInWindow.x - event.locationInWindow.x
            let dy = next.locationInWindow.y - event.locationInWindow.y
            if hypot(dx, dy) > 5 { beginDrag(next); return }
        }
    }
}

final class FileDragSource: NSObject, NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func begin(urls: [URL], in view: NSView, event: NSEvent) {
        guard !urls.isEmpty else { return }
        let origin = view.convert(event.locationInWindow, from: nil)
        let items = urls.enumerated().map { index, url -> NSDraggingItem in
            let writer = NSPasteboardItem()
            writer.setString(url.absoluteString, forType: .fileURL)
            writer.setString("true", forType: FileTransfer.moveType)
            let item = NSDraggingItem(pasteboardWriter: writer)
            item.setDraggingFrame(NSRect(x: origin.x + CGFloat(index * 3), y: origin.y, width: 40, height: 40), contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }
        view.beginDraggingSession(with: items, event: event, source: self)
    }
}

final class FileTableView: NSTableView {
    var onRightDrag: ((NSEvent) -> Void)?
    private func selectContextRow(_ event: NSEvent) {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 {
            if !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        } else { deselectAll(nil) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        selectContextRow(event)
        return super.menu(for: event)
    }
    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        selectContextRow(event)
        FileTransfer.trackRightMouse(in: self, event: event) { [weak self] drag in self?.onRightDrag?(drag) }
    }
}
