import AppKit

/// How the window material looks. The first two are Liquid Glass; the rest are classic
/// behind-window blurs, which also stand in for Liquid Glass before macOS 26.
enum GlassStyle: String, CaseIterable {
    case bright, dark, vivid, soft, smoke
    var title: String {
        switch self {
        case .bright: "Bright glass"
        case .dark: "Dark glass"
        case .vivid: "Vivid blur"
        case .soft: "Soft blur"
        case .smoke: "Smoke"
        }
    }
    var usesLiquidGlass: Bool {
        guard #available(macOS 26, *) else { return false }
        return self == .bright || self == .dark
    }
    var material: NSVisualEffectView.Material {
        switch self {
        case .vivid: .hudWindow
        case .bright, .soft: .fullScreenUI
        case .dark, .smoke: .underWindowBackground
        }
    }
}

enum BrowserTheme {
    /// Every Appearance setting is kept separately for light and dark.
    static let themedKeys = ["frostedPanes", "paneOpacity", "glassTint", "glassTintEnabled", "glassStyle", "titlebarTint",
                             "titlebarOpacity", "titlebarTintEnabled", "accentColor", "windowOutlineEnabled", "windowOutlineColor"]
    static let appearancePreferenceKeys = ["appearanceMode", "chromeDarkColor", "chromeLightColor", "glassFrosted", "glassFrosting"]
        + themedKeys + themedKeys.flatMap { ["\($0).dark", "\($0).light"] }
    static func themedKey(_ key: String, dark: Bool = darkMode) -> String { "\(key).\(dark ? "dark" : "light")" }
    /// This theme's own value; a value saved before settings were per theme still applies until replaced.
    static func themed(_ key: String) -> Any? {
        UserDefaults.standard.object(forKey: themedKey(key)) ?? UserDefaults.standard.object(forKey: key)
    }
    static func setThemed(_ value: Any?, forKey key: String) {
        if let value { UserDefaults.standard.set(value, forKey: themedKey(key)) }
        else { UserDefaults.standard.removeObject(forKey: themedKey(key)) }
    }
    /// Once: drop the old shared values so each theme starts from its own defaults.
    static func migrateToThemedAppearance() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "themedAppearanceMigrated") else { return }
        themedKeys.forEach(defaults.removeObject(forKey:))
        defaults.set(true, forKey: "themedAppearanceMigrated")
    }
    static func resetAppearance() {
        for key in appearancePreferenceKeys { UserDefaults.standard.removeObject(forKey: key) }
        initializeAccent()
        applyAppearanceMode()
        NotificationCenter.default.post(name: changed, object: nil)
    }
    static let changed = Notification.Name("PathfindAppearanceChanged")
    static var frosted: Bool { themed("frostedPanes") as? Bool ?? true }
    /// Off leaves the glass untinted: no color layer, so opacity and tint color don't apply.
    static var glassTintEnabled: Bool { themed("glassTintEnabled") as? Bool ?? false }
    static var glassStyle: GlassStyle {
        (themed("glassStyle") as? String).flatMap(GlassStyle.init(rawValue:)) ?? (darkMode ? .soft : .smoke)
    }
    static var opacity: Double {
        guard let value = themed("paneOpacity") as? Double else { return 0.01 }
        return min(1, max(0.01, value))
    }
    static func shade(dark: CGFloat, light: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            NSColor(white: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light, alpha: 1)
        }
    }
    /// Explorer picks its own light or dark look instead of following macOS.
    static var darkMode: Bool { UserDefaults.standard.string(forKey: "appearanceMode") != "light" }
    static func applyAppearanceMode() {
        NSApp?.appearance = NSAppearance(named: darkMode ? .darkAqua : .aqua)
    }
    static func chromeColorKey(dark: Bool) -> String { dark ? "chromeDarkColor" : "chromeLightColor" }
    /// The header band behind the path bar and toolbar, and the selected tab. Each mode keeps its own color.
    static func chromeColor(dark: Bool) -> NSColor {
        if let rgb = UserDefaults.standard.array(forKey: chromeColorKey(dark: dark)) as? [Double], rgb.count == 3 {
            return NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        }
        return dark ? .black : .white
    }
    static var chrome: NSColor {
        NSColor(name: nil) { appearance in chromeColor(dark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) }
    }
    static var outlineEnabled: Bool { themed("windowOutlineEnabled") as? Bool ?? false }
    static var outlineColor: NSColor {
        if let rgb = themed("windowOutlineColor") as? [Double], rgb.count == 3 {
            return NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        }
        return .black
    }
    static var titlebarTintEnabled: Bool {
        themed("titlebarTintEnabled") as? Bool ?? true
    }
    static var titlebarTint: NSColor {
        if let rgb = themed("titlebarTint") as? [Double], rgb.count == 3 {
            return NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        }
        return NSColor(srgbRed: 0.2403, green: 0.2530, blue: 0.3082, alpha: 1)
    }
    static var accentColor: NSColor {
        if let rgb = themed("accentColor") as? [Double], rgb.count == 3 {
            return NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        }
        return titlebarTint
    }
    static func initializeAccent() {
        guard themed("accentColor") == nil,
              let color = titlebarTint.usingColorSpace(.sRGB) else { return }
        setThemed([Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)], forKey: "accentColor")
    }
    static var titlebarOpacity: Double {
        guard let value = themed("titlebarOpacity") as? Double else { return 0.38 }
        return min(1, max(0, value))
    }
    static var pane: NSColor {
        if let rgb = themed("glassTint") as? [Double], rgb.count == 3 {
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
    private let blur = NSVisualEffectView()
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
        blur.blendingMode = .behindWindow; blur.state = .active
        blur.frame = bounds; blur.autoresizingMask = [.width, .height]
        addSubview(blur)
        effect.frame = bounds; effect.autoresizingMask = [.width, .height]
        addSubview(effect)
        contentView.frame = bounds; contentView.autoresizingMask = [.width, .height]
        if #available(macOS 26, *), let glass = effect as? NSGlassEffectView {
            glass.contentView = contentView
        } else { effect.addSubview(contentView) }
        tint.frame = contentView.bounds; tint.autoresizingMask = [.width, .height]
        addSubview(tint)
        foreground = [tint]
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: BrowserTheme.changed, object: nil)
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
        if blur.frame != bounds { blur.frame = bounds }
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
    @objc func refresh() {
        // Without Liquid Glass the window is solid; untinted glass has no color layer at all.
        let opacity = !BrowserTheme.frosted ? 1 : BrowserTheme.glassTintEnabled ? BrowserTheme.opacity : 0
        let useGlass = BrowserTheme.frosted && opacity < 1
        // Keep layout and input outside the material's managed content hierarchy.
        // Switching opacity only affects the decorative backdrop, never the UI tree.
        glassAttached = useGlass
        let style = BrowserTheme.glassStyle
        effect.isHidden = !useGlass || !style.usesLiquidGlass
        blur.isHidden = !useGlass || style.usesLiquidGlass
        if #available(macOS 26, *), let glass = effect as? NSGlassEffectView {
            glass.style = style == .dark ? .regular : .clear
        }
        blur.material = style.material
        BrowserTheme.paint(tint, color: BrowserTheme.pane.withAlphaComponent(opacity))
        sizeContent()
        needsLayout = true
        needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh() }
    deinit { NotificationCenter.default.removeObserver(self) }
}

/// The translucent fill and hairline edge of a Settings card stacked on the dialog glass.
/// Call it while the view's appearance is current (as in `updateLayer`) so the colors resolve.
enum GlassCard {
    static let cornerRadius: CGFloat = 12
    static func paint(_ view: NSView, cornerRadius: CGFloat = cornerRadius) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        layer.borderColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        layer.borderWidth = 1
    }
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
    /// Clicks on blank chrome, such as the tab strip behind the tabs, arrive here unhandled.
    /// Borderless windows can't rely on AppKit's background dragging, so drag explicitly.
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

/// Preserve the accent when a selected row loses keyboard/window emphasis.
/// Sidebar rows: no separator under the FAVORITES and THIS MAC headers.
final class SidebarRowView: AccentRowView {
    override func drawSeparator(in dirtyRect: NSRect) {}
}

/// The sidebar divider uses the same light hairline as other separators instead of a black line.
final class SidebarSplitView: NSSplitView {
    override var dividerColor: NSColor { .separatorColor }
}

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
