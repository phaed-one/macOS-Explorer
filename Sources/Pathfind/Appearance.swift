import AppKit

enum BrowserTheme {
    static let appearancePreferenceKeys = ["frostedPanes", "paneOpacity", "glassTint", "glassFrosting", "titlebarTint", "titlebarOpacity", "titlebarTintEnabled", "accentColor", "windowOutlineEnabled", "windowOutlineColor"]
    static func resetAppearance() {
        for key in appearancePreferenceKeys { UserDefaults.standard.removeObject(forKey: key) }
        initializeAccent()
        NotificationCenter.default.post(name: changed, object: nil)
    }
    static let changed = Notification.Name("PathfindAppearanceChanged")
    static var frosted: Bool { UserDefaults.standard.object(forKey: "frostedPanes") as? Bool ?? true }
    static var frosting: Double { min(1, max(0, UserDefaults.standard.double(forKey: "glassFrosting"))) }
    static var opacity: Double {
        guard UserDefaults.standard.object(forKey: "paneOpacity") != nil else { return 0.80 }
        return min(1, max(0.01, UserDefaults.standard.double(forKey: "paneOpacity")))
    }
    static func shade(dark: CGFloat, light: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            NSColor(white: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light, alpha: 1)
        }
    }
    static var chrome: NSColor { shade(dark: 0, light: 1) }
    static var outlineEnabled: Bool { UserDefaults.standard.object(forKey: "windowOutlineEnabled") as? Bool ?? true }
    static var outlineColor: NSColor {
        if let rgb = UserDefaults.standard.array(forKey: "windowOutlineColor") as? [Double], rgb.count == 3 {
            return NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        }
        return .black
    }
    static var titlebarTintEnabled: Bool {
        UserDefaults.standard.object(forKey: "titlebarTintEnabled") as? Bool ?? true
    }
    static var titlebarTint: NSColor {
        if let rgb = UserDefaults.standard.array(forKey: "titlebarTint") as? [Double], rgb.count == 3 {
            return NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        }
        return NSColor(srgbRed: 59.0 / 255, green: 59.0 / 255, blue: 63.0 / 255, alpha: 1)
    }
    static var accentColor: NSColor {
        if let rgb = UserDefaults.standard.array(forKey: "accentColor") as? [Double], rgb.count == 3 {
            return NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        }
        return titlebarTint
    }
    static func initializeAccent() {
        guard UserDefaults.standard.object(forKey: "accentColor") == nil,
              let color = titlebarTint.usingColorSpace(.sRGB) else { return }
        UserDefaults.standard.set([Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)], forKey: "accentColor")
    }
    static var titlebarOpacity: Double {
        guard UserDefaults.standard.object(forKey: "titlebarOpacity") != nil else { return 0.65 }
        return min(1, max(0, UserDefaults.standard.double(forKey: "titlebarOpacity")))
    }
    static var pane: NSColor {
        if let rgb = UserDefaults.standard.array(forKey: "glassTint") as? [Double], rgb.count == 3 {
            return NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        }
        return shade(dark: 0, light: 1)
    }
    static var field: NSColor {
        let accent = accentColor.usingColorSpace(.sRGB) ?? .black
        return NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(calibratedHue: accent.hueComponent,
                           saturation: accent.saturationComponent,
                           brightness: dark ? 0.105 : 0.955, alpha: 1)
        }
    }
    static var tab: NSColor { shade(dark: 0.12, light: 0.92) }
    static var row: NSColor { frosted ? .clear : pane }
    static func paint(_ view: NSView, color: NSColor) {
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
    }
}

final class WindowBackdrop: NSView {
    let contentView = NSView()
    private let effect: NSView
    private let frost = NSVisualEffectView()
    let tint = NSView()
    private var foreground: [NSView] = []
    var isUsingGlass: Bool { glassAttached }
    private var glassAttached = false
    override init(frame frameRect: NSRect) {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .clear; glass.cornerRadius = 0; glass.tintColor = .clear
            effect = glass
        } else {
            let blur = NSVisualEffectView()
            blur.blendingMode = .behindWindow; blur.material = .underWindowBackground; blur.state = .active
            effect = blur
        }
        super.init(frame: frameRect)
        wantsLayer = true; layer?.cornerRadius = 20; layer?.masksToBounds = true
        frost.blendingMode = .behindWindow
        frost.material = .underWindowBackground
        frost.state = .active
        frost.frame = bounds; frost.autoresizingMask = [.width, .height]
        addSubview(frost)
        effect.frame = bounds; effect.autoresizingMask = [.width, .height]
        addSubview(effect)
        contentView.frame = bounds; contentView.autoresizingMask = [.width, .height]
        if #available(macOS 26, *), let glass = effect as? NSGlassEffectView {
            glass.contentView = contentView
        } else { effect.addSubview(contentView) }
        tint.frame = contentView.bounds; tint.autoresizingMask = [.width, .height]
        addSubview(tint)
        foreground = [tint]
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? {
        // The material is decorative. Foreground controls own mouse input,
        // regardless of AppKit's elevated glass rendering hierarchy.
        for view in foreground.reversed() where view !== tint && !view.isHidden {
            guard let parent = view.superview else { continue }
            let translated = parent.convert(point, from: superview)
            if let hit = view.hitTest(translated) { return hit }
        }
        return super.hitTest(point)
    }
    override func layout() {
        super.layout()
        sizeContent()
    }
    private func sizeContent() {
        // Crop the material's built-in rim. Foreground views remain siblings with
        // exact window bounds, so material sizing cannot feed back into UI layout.
        let materialFrame = bounds.insetBy(dx: -3, dy: -3)
        if effect.frame != materialFrame { effect.frame = materialFrame }
        if frost.frame != bounds { frost.frame = bounds }
        for child in foreground {
            let target = bounds
            if child.frame != target { child.frame = target }
        }
    }
    func install(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]
        view.frame = contentView.bounds
        foreground.append(view)
        addSubview(view)
        needsLayout = true
    }
    func refresh() {
        let opacity = BrowserTheme.frosted ? BrowserTheme.opacity : 1
        let useGlass = opacity > 0 && opacity < 1
        // Keep layout and input outside the material's managed content hierarchy.
        // Switching opacity only affects the decorative backdrop, never the UI tree.
        glassAttached = useGlass
        effect.isHidden = !useGlass
        frost.isHidden = !useGlass || BrowserTheme.frosting == 0
        frost.alphaValue = BrowserTheme.frosting
        BrowserTheme.paint(tint, color: BrowserTheme.pane.withAlphaComponent(opacity))
        sizeContent()
        needsLayout = true
        needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh() }
}

/// A transparent viewport; the window supplies the single material behind it.
final class BrowserViewport: NSView {
    private var fillingViews: [NSView] = []
    private var header: NSView?
    var headerHeight: CGFloat = 0 { didSet { if oldValue != headerHeight { needsLayout = true } } }
    func install(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]
        view.frame = bounds
        fillingViews.append(view)
        addSubview(view)
    }
    func installHeader(_ view: NSView) {
        header?.removeFromSuperview(); header = view
        addSubview(view); needsLayout = true
    }
    override func layout() {
        super.layout()
        let body = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(0, bounds.height - headerHeight))
        for child in fillingViews where child.frame != body { child.frame = body }
        if let header {
            let hidden = headerHeight == 0
            if header.isHidden != hidden { header.isHidden = hidden }
            let frame = NSRect(x: bounds.minX, y: bounds.maxY - headerHeight, width: bounds.width, height: headerHeight)
            if header.frame != frame { header.frame = frame }
        }
    }
}

/// Accessibility value changes are user input and must invoke the same action as dragging.
final class LiveSlider: NSSlider {
    override var acceptsFirstResponder: Bool { true }
    override func setAccessibilityValue(_ accessibilityValue: Any?) {
        if let value = accessibilityValue as? NSNumber {
            doubleValue = min(maxValue, max(minValue, value.doubleValue))
        } else { super.setAccessibilityValue(accessibilityValue) }
        sendAction(action, to: target)
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 115: doubleValue = minValue
        case 119: doubleValue = maxValue
        default: super.keyDown(with: event); return
        }
        sendAction(action, to: target)
    }
}

final class ChromeView: NSView {
    var onAppearanceChange: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { onAppearanceChange?() }
    }
}

/// Preserve the accent when a selected row loses keyboard/window emphasis.
class AccentRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        if isEmphasized { super.drawSelection(in: dirtyRect) }
        else {
            BrowserTheme.accentColor.setFill()
            bounds.fill()
        }
    }
}

final class WindowOutlineView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard BrowserTheme.outlineEnabled else { return }
        BrowserTheme.outlineColor.setStroke()
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 19.5, yRadius: 19.5)
        outline.lineWidth = 1; outline.stroke()
    }
}

/// A custom-framed window keeps its outline under app control using public APIs.
final class BrowserWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isOpaque = false; backgroundColor = .clear
        // Explicitly opt the transparent custom frame into mouse input. The
        // default value alone leaves transparent resize pixels click-through.
        ignoresMouseEvents = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    // perform* expects titlebar-owned buttons; the custom frame has none.
    override func performClose(_ sender: Any?) { close() }
    override func performMiniaturize(_ sender: Any?) { miniaturize(sender) }
    override func performZoom(_ sender: Any?) { zoom(sender) }
}
