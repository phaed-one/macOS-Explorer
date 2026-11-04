import AppKit

enum ToolbarImages {
    static var folderEye: NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 22), flipped: false) { _ in
            NSImage(systemSymbolName: "eye", accessibilityDescription: nil)!.draw(in: NSRect(x: 0, y: 6, width: 22, height: 15))
            NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)!.draw(in: NSRect(x: 14, y: 0, width: 10, height: 9))
            return true
        }
        image.isTemplate = true
        return image
    }
}
