import AppKit

enum GlassControls {
    static func apply(to view: NSView) {
        guard #available(macOS 26, *) else { return }
        if let popup = view as? NSPopUpButton { popup.isBordered = true }
        if let button = view as? NSButton, !(button is GlassToolbarButton), button.isBordered, button.bezelStyle != .glass {
            button.bezelStyle = .glass
        }
        for child in view.subviews { apply(to: child) }
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
        let surface = surface(for: field, cornerRadius: 10, clear: true)
        surface.heightAnchor.constraint(equalToConstant: 36).isActive = true
        tintFieldSurface(surface)
        return surface
    }
    static func tintFieldSurface(_ surface: NSView) {
        if #available(macOS 26, *), let glass = surface as? NSGlassEffectView {
            glass.tintColor = BrowserTheme.field.withAlphaComponent(0.4)
        }
    }
}
