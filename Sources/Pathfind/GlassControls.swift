import AppKit

enum GlassControls {
    static func apply(to view: NSView, excluding excluded: [NSView] = []) {
        guard !excluded.contains(where: { $0 === view }) else { return }
        guard #available(macOS 26, *) else { return }
        if let popup = view as? NSPopUpButton { popup.isBordered = true }
        if let button = view as? NSButton, !(button is GlassToolbarButton), button.isBordered, button.bezelStyle != .glass {
            button.bezelStyle = .glass
        }
        for child in view.subviews { apply(to: child, excluding: excluded) }
    }

    static func surface(for content: NSView, cornerRadius: CGFloat, clear: Bool = false) -> NSView {
        let surface: NSView
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: content.bounds)
            glass.style = clear ? .clear : .regular; glass.cornerRadius = cornerRadius
            glass.contentView = content
            surface = glass
        } else {
            let blur = NSVisualEffectView(frame: content.bounds)
            blur.material = .popover; blur.state = .active
            blur.wantsLayer = true; blur.layer?.cornerRadius = cornerRadius; blur.layer?.masksToBounds = true
            content.autoresizingMask = [.width, .height]; blur.addSubview(content)
            surface = blur
        }
        return surface
    }

    static func fieldSurface(for field: NSTextField) -> NSView {
        guard #available(macOS 26, *) else { return field }
        field.isBezeled = false; field.drawsBackground = false
        let surface = TextInputGlassSurface(field: field)
        surface.heightAnchor.constraint(equalToConstant: 36).isActive = true
        tintFieldSurface(surface)
        return surface
    }
    /// macOS drops a glass tint while the window is active, so the color is painted under the text instead.
    static func tintFieldSurface(_ surface: NSView) {
        if #available(macOS 26, *), let surface = surface as? TextInputGlassSurface {
            surface.tintColor = nil
            surface.fill = BrowserTheme.fieldTintEnabled ? BrowserTheme.fieldTint.withAlphaComponent(0.9) : nil
        }
    }
}

@available(macOS 26, *)
final class TextInputGlassSurface: NSGlassEffectView {
    private weak var field: NSTextField?
    private var cursorArea: NSTrackingArea?
    private let backing = NSView()
    /// The color painted behind the text, or nil for plain glass.
    var fill: NSColor? { didSet { backing.layer?.backgroundColor = fill?.cgColor } }
    init(field: NSTextField) {
        self.field = field
        super.init(frame: field.bounds)
        style = .clear; cornerRadius = 10
        backing.wantsLayer = true
        backing.layer?.cornerRadius = 10; backing.layer?.cornerCurve = .continuous
        field.translatesAutoresizingMaskIntoConstraints = false
        backing.addSubview(field)
        NSLayoutConstraint.activate([field.leadingAnchor.constraint(equalTo: backing.leadingAnchor), field.trailingAnchor.constraint(equalTo: backing.trailingAnchor),
                                     field.centerYAnchor.constraint(equalTo: backing.centerYAnchor)])
        contentView = backing
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func resetCursorRects() {
        super.resetCursorRects()
        if field?.isEnabled == true && field?.isEditable == true { addCursorRect(bounds, cursor: .iBeam) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorArea { removeTrackingArea(cursorArea) }
        let area = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area); cursorArea = area
    }
    override func cursorUpdate(with event: NSEvent) {
        if field?.isEnabled == true && field?.isEditable == true { NSCursor.iBeam.set() }
        else { super.cursorUpdate(with: event) }
    }
}
