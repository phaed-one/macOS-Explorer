import AppKit

struct TabTransfer: Codable {
    static let pasteboardType = NSPasteboard.PasteboardType("local.pathfind.tab")
    let windowID: UUID
    let tabID: UUID
    static func read(_ sender: NSDraggingInfo) -> TabTransfer? {
        sender.draggingPasteboard.data(forType: pasteboardType).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }
}

final class TabSelectButton: NSButton {
    var onPointerDown: ((NSEvent) -> Void)?
    override func mouseDown(with event: NSEvent) {
        if let onPointerDown { onPointerDown(event) } else { super.mouseDown(with: event) }
    }
}
