import AppKit
import PathfindCore

func checkThemeMode() throws {
    let defaults = UserDefaults.standard
    let keys = ["appearanceMode", "chromeDarkColor", "chromeLightColor"]
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
    BrowserTheme.resetAppearance()
    try require(BrowserTheme.darkMode && NSApp.appearance?.name == .darkAqua, "Reset to Defaults must return to dark")
    print("PASS: Theme switches Explorer between its own light and dark looks, each with its own header color, repainting tabs live")
}
