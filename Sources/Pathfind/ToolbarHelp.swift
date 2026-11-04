import AppKit

/// AppKit has no public per-control tooltip delay; these hints use a fixed second.
enum ToolbarHelp {
    static let delay: TimeInterval = 1
    static func install(on view: NSView, text: String, textAtPoint: ((NSPoint) -> String)? = nil) {
        view.subviews.compactMap { $0 as? HoverHelpView }.forEach { $0.removeFromSuperview() }
        view.toolTip = nil
        view.setAccessibilityHelp(text)
        let help = HoverHelpView(text: text, textAtPoint: textAtPoint)
        help.frame = view.bounds; help.autoresizingMask = [.width, .height]
        view.addSubview(help)
    }
    static func update(on view: NSView, text: String) {
        view.setAccessibilityHelp(text)
        if let help = view.subviews.compactMap({ $0 as? HoverHelpView }).first { help.setText(text) }
        else { install(on: view, text: text) }
    }
}

/// Decorative tracking only: all clicks and drags continue to the actual control.
final class HoverHelpView: NSView {
    private var text: String
    private let textAtPoint: ((NSPoint) -> String)?
    private var area: NSTrackingArea?
    private var currentText: String?
    init(text: String, textAtPoint: ((NSPoint) -> String)?) {
        self.text = text; self.textAtPoint = textAtPoint
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { HelpPopup.shared.cancel(for: self) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        if let area { removeTrackingArea(area) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(tracking); area = tracking
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { beginHover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { beginHover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { endHover() }
    func beginHover(at point: NSPoint) {
        let value = textAtPoint?(point) ?? text
        guard currentText != value else { return }
        currentText = value
        HelpPopup.shared.schedule(for: self, text: value)
    }
    func endHover() { currentText = nil; HelpPopup.shared.cancel(for: self) }
    func setText(_ text: String) {
        guard self.text != text else { return }
        self.text = text; endHover()
    }
}

final class HelpPopup {
    static let shared = HelpPopup()
    private weak var owner: NSView?
    private var timer: Timer?
    private var panel: NSPanel?
    private var monitor: Any?
    var isVisible: Bool { panel?.isVisible == true }
    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            self?.hide(); return event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(hide), name: NSWindow.didResignKeyNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(hide), name: NSApplication.didResignActiveNotification, object: nil)
    }
    func schedule(for view: NSView, text: String) {
        hide(); owner = view
        let timer = Timer(timeInterval: ToolbarHelp.delay, repeats: false) { [weak self, weak view] _ in
            guard let view, view.window?.isVisible == true, !view.isHiddenOrHasHiddenAncestor else { return }
            self?.show(text, beside: view)
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func cancel(for view: NSView) { if owner === view { hide() } }
    @objc private func hide() { timer?.invalidate(); timer = nil; panel?.orderOut(nil); owner = nil }
    private func show(_ text: String, beside view: NSView) {
        guard let window = view.window else { return }
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let size = NSSize(width: min(500, ceil(label.intrinsicContentSize.width) + 16), height: ceil(label.intrinsicContentSize.height) + 12)
        let hint = panel ?? NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hint.level = .popUpMenu; hint.ignoresMouseEvents = true; hint.hidesOnDeactivate = true
        hint.isOpaque = false; hint.backgroundColor = .clear; hint.hasShadow = true
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .popover; background.state = .active
        background.wantsLayer = true; background.layer?.cornerRadius = 6; background.layer?.masksToBounds = true
        label.frame = background.bounds.insetBy(dx: 8, dy: 6)
        background.addSubview(label); hint.contentView = background
        let control = window.convertToScreen(view.convert(view.bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let x = max(screen.minX, min(control.midX - size.width / 2, screen.maxX - size.width))
        let y = control.minY - size.height - 6 >= screen.minY ? control.minY - size.height - 6 : control.maxY + 6
        hint.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel = hint; hint.orderFront(nil)
    }
}
