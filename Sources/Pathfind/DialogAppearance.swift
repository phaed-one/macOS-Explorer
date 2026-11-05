import AppKit

/// Shares the browser's material without replacing a dialog's native content or controls.
enum DialogAppearance {
    static func install(on window: NSWindow) {
        guard let content = window.contentView,
              !content.subviews.contains(where: { $0.identifier?.rawValue == "ExplorerDialogGlass" }) else { return }
        let background = WindowBackdrop(frame: content.bounds)
        background.identifier = NSUserInterfaceItemIdentifier("ExplorerDialogGlass")
        background.autoresizingMask = [.width, .height]
        background.layer?.cornerRadius = 12
        content.addSubview(background, positioned: .below, relativeTo: nil)
        window.isOpaque = false; window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.ignoresMouseEvents = false
    }
}

extension NSAlert {
    func prepareGlassAppearance() { layout(); DialogAppearance.install(on: window) }
    @discardableResult func runGlassModal() -> NSApplication.ModalResponse {
        prepareGlassAppearance()
        return runModal()
    }
    func beginGlassSheetModal(for sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        prepareGlassAppearance()
        beginSheetModal(for: sheetWindow, completionHandler: handler)
    }
}
