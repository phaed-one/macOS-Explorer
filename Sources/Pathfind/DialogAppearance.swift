import AppKit

/// Shares the browser's material without replacing a dialog's native content or controls.
enum DialogAppearance {
    static func install(on window: NSWindow, fillTitlebar: Bool = true) {
        if let content = window.contentView { GlassControls.apply(to: content) }
        guard let content = window.contentView,
              !content.subviews.contains(where: { $0.identifier?.rawValue == "ExplorerDialogGlass" }) else { return }
        window.isOpaque = false; window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true
        if fillTitlebar {
            let frame = window.frame
            window.styleMask.insert(.fullSizeContentView)
            let surface = DialogSurface(body: content)
            window.contentView = surface
            surface.attachBody()
            window.setFrame(frame, display: false)
            surface.needsLayout = true
            surface.layoutSubtreeIfNeeded()
            return
        }
        content.addSubview(background(in: content.bounds), positioned: .below, relativeTo: nil)
    }
    fileprivate static func background(in bounds: NSRect) -> WindowBackdrop {
        let background = WindowBackdrop(frame: bounds)
        background.identifier = NSUserInterfaceItemIdentifier("ExplorerDialogGlass")
        background.autoresizingMask = [.width, .height]
        background.layer?.cornerRadius = 12
        return background
    }
    static func setBodySize(_ size: NSSize, on window: NSWindow) {
        let titlebar = window.contentView is DialogSurface ? max(0, (window.contentView?.bounds.height ?? 0) - window.contentLayoutRect.height) : 0
        window.setContentSize(NSSize(width: size.width, height: size.height + titlebar))
    }
}

private final class DialogSurface: NSView {
    private let body: NSView
    init(body: NSView) {
        self.body = body
        super.init(frame: body.bounds)
        addSubview(DialogAppearance.background(in: bounds))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func attachBody() { body.autoresizingMask = []; addSubview(body); needsLayout = true }
    override var mouseDownCanMoveWindow: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if window?.sheetParent == nil, isBackground(hit) { return self }
        return hit
    }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func scrollWheel(with event: NSEvent) {
        var view = super.hitTest(convert(event.locationInWindow, from: nil))
        while let current = view, current !== self {
            if let scroll = current as? NSScrollView { scroll.scrollWheel(with: event); return }
            view = current.superview
        }
        super.scrollWheel(with: event)
    }
    override func layout() {
        super.layout()
        if let window { body.frame = convert(window.contentLayoutRect, from: nil) }
    }
    private func isBackground(_ hit: NSView) -> Bool {
        var view: NSView? = hit
        while let current = view, current !== self {
            if let label = current as? NSTextField, !label.isEditable && !label.isSelectable {
                view = current.superview; continue
            }
            if current is NSControl || current is NSTextView || current is NSCollectionView { return false }
            view = current.superview
        }
        return true
    }
}

extension NSAlert {
    func prepareGlassAppearance() { layout(); DialogAppearance.install(on: window, fillTitlebar: false) }
    @discardableResult func runGlassModal() -> NSApplication.ModalResponse {
        prepareGlassAppearance()
        return runModal()
    }
    func beginGlassSheetModal(for sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        prepareGlassAppearance()
        beginSheetModal(for: sheetWindow, completionHandler: handler)
    }
}
