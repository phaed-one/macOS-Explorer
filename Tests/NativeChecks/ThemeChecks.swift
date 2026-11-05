import AppKit
import PathfindCore

func checkThemeMode() throws {
    let defaults = UserDefaults.standard
    let keys = ["appearanceMode", "chromeDarkColor", "chromeLightColor", "fieldTintEnabled.dark", "fieldTintEnabled.light", "fieldTintColor.dark", "fieldTintColor.light"]
    let saved = keys.map { defaults.object(forKey: $0) }
    let savedAppearance = NSApp.appearance
    defer {
        for (key, value) in zip(keys, saved) { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
        NSApp.appearance = savedAppearance
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    keys.forEach(defaults.removeObject(forKey:))
    try require(BrowserTheme.darkMode, "Explorer must default to its own dark look")
    let settings = SettingsController()
    defer { settings.close() }
    let browser = BrowserController(tabs: BrowserTabs(url: URL(fileURLWithPath: NSHomeDirectory())))
    browser.showWindow(nil); defer { browser.window?.close() }
    let controls = descendants(settings.window!.contentView!)
    let mode = controls.compactMap { $0 as? NSSegmentedControl }.first { $0.accessibilityLabel() == "Theme" }!
    let well = controls.compactMap { $0 as? NSColorWell }.first { $0.accessibilityLabel() == "Header color" }!
    func select(_ segment: Int) { mode.selectedSegment = segment; mode.sendAction(mode.action, to: mode.target) }
    func setWell(_ color: NSColor) { well.color = color; well.sendAction(well.action, to: well.target) }
    func rgb(_ color: NSColor) -> [Int] { let c = color.usingColorSpace(.sRGB)!; return [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) } }
    func selectedTabColor() -> NSColor? {
        let tab = descendants(browser.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel()?.hasPrefix("Tab:") == true }?.superview
        return tab?.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
    }

    select(0)
    try require(!BrowserTheme.darkMode && NSApp.appearance?.name == .aqua, "Light must switch Explorer to the light appearance regardless of macOS")
    try require(rgb(well.color) == [255, 255, 255], "Light starts with a white header")
    setWell(NSColor(srgbRed: 0.9, green: 0.8, blue: 0.7, alpha: 1))
    select(1)
    try require(BrowserTheme.darkMode && NSApp.appearance?.name == .darkAqua, "Dark must switch Explorer to the dark appearance")
    try require(rgb(well.color) == [0, 0, 0], "Dark keeps its own black header while light has a custom one: \(rgb(well.color))")
    setWell(NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1))
    try require(rgb(BrowserTheme.chromeColor(dark: false)) == [230, 204, 179] && rgb(BrowserTheme.chromeColor(dark: true)) == [26, 51, 77],
        "Light and dark must each keep the color set while they were showing")
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    try require(selectedTabColor().map(rgb) == [26, 51, 77], "The selected tab must repaint in the dark header color: \(String(describing: selectedTabColor().map(rgb)))")
    select(0)
    try require(rgb(well.color) == [230, 204, 179], "Switching back to light must show light's own color")
    let reset = controls.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Use default header color" }!
    reset.performClick(nil)
    try require(rgb(BrowserTheme.chromeColor(dark: false)) == [255, 255, 255] && rgb(BrowserTheme.chromeColor(dark: true)) == [26, 51, 77],
        "Reset must only restore the showing mode's header color")
    // Field tint: on in light, off in dark, and it follows a live theme switch.
    if #available(macOS 26, *) {
        let path = descendants(browser.window!.contentView!).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Current folder path" }!
        var view: NSView? = path.superview
        while let current = view, !(current is TextInputGlassSurface) { view = current.superview }
        let glass = view as! TextInputGlassSurface
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let lightTint = glass.fill?.usingColorSpace(.sRGB)
        try require(BrowserTheme.fieldTintEnabled && lightTint.map(rgb) == [236, 236, 236] && glass.tintColor == nil,
            "Light fields default to a light grey, painted under the text: \(String(describing: lightTint.map(rgb)))")
        let fieldTint = controls.compactMap { $0 as? NSButton }.first { $0.title == "Tint path and search fields" }!
        let well = controls.compactMap { $0 as? NSColorWell }.first { $0.accessibilityLabel() == "Field color" }!
        try require(fieldTint.state == .on && well.isEnabled && rgb(well.color) == [236, 236, 236], "The field controls must show the light default")
        well.color = NSColor(srgbRed: 1, green: 0.9, blue: 0.8, alpha: 1); well.sendAction(well.action, to: well.target)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        try require(glass.fill.flatMap { $0.usingColorSpace(.sRGB) }.map(rgb) == [255, 230, 204], "Picking a field color must repaint the fields")
        fieldTint.performClick(nil)
        try require(!BrowserTheme.fieldTintEnabled && glass.fill == nil && !well.isEnabled, "Turning the field tint off must leave plain glass")
        fieldTint.performClick(nil)
        select(1)
        try require(!BrowserTheme.fieldTintEnabled && glass.fill == nil && fieldTint.state == .off, "The field tint is saved per theme, so dark starts untinted")
        fieldTint.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let darkTint = glass.fill?.usingColorSpace(.sRGB)
        try require(darkTint != nil && darkTint!.brightnessComponent < 0.3, "A dark-mode field tint must be dark after switching live: \(String(describing: darkTint))")
        select(0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        try require(glass.fill.flatMap { $0.usingColorSpace(.sRGB) }.map(rgb) == [255, 230, 204], "Switching back to light must restore light's own field color")
    }
    // Inactive selection stays readable in light mode.
    let row = AccentRowView(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
    row.isSelected = true; row.isEmphasized = false; row.selectionHighlightStyle = .regular
    func selectionColor(_ name: NSAppearance.Name) -> NSColor {
        row.appearance = NSAppearance(named: name)
        var color: NSColor!
        row.effectiveAppearance.performAsCurrentDrawingAppearance {
            let image = NSImage(size: row.bounds.size, flipped: false) { rect in row.drawSelection(in: rect); return true }
            color = NSBitmapImageRep(data: image.tiffRepresentation!)!.colorAt(x: 20, y: 12)!.usingColorSpace(.sRGB)!
        }
        return color
    }
    try require(selectionColor(.aqua).brightnessComponent > selectionColor(.darkAqua).brightnessComponent + 0.3,
        "Light mode must lighten the inactive selection so dark text stays readable")
    // Light mode's own defaults: a grey titlebar at 60%, the blue-grey accent, and grey fields.
    BrowserTheme.appearancePreferenceKeys.filter { $0.hasSuffix(".light") }.forEach(defaults.removeObject(forKey:))
    BrowserTheme.themedKeys.forEach(defaults.removeObject(forKey:))
    select(0)
    try require(rgb(BrowserTheme.titlebarTint) == [184, 184, 184] && BrowserTheme.titlebarOpacity == 0.6 && rgb(BrowserTheme.accentColor) == [61, 65, 79]
        && BrowserTheme.glassStyle == .smoke && !BrowserTheme.glassTintEnabled && BrowserTheme.fieldTintEnabled && rgb(BrowserTheme.fieldTint) == [236, 236, 236]
        && !BrowserTheme.outlineEnabled,
        "Light must default to a grey titlebar at 60%, blue-grey accent, untinted Smoke glass, light grey fields and no outline")
    BrowserTheme.resetAppearance()
    try require(BrowserTheme.darkMode && NSApp.appearance?.name == .darkAqua, "Reset to Defaults must return to dark")
    try require(BrowserTheme.titlebarOpacity == 0.38 && BrowserTheme.glassStyle == .soft, "Dark keeps its own defaults")
    print("PASS: Theme switches Explorer between its own light and dark looks, each with its own header color, field tint and readable inactive selection")
}
