import AppKit

func checkSettingsReset() throws {
    let defaults = UserDefaults.standard
    let saved = Dictionary(uniqueKeysWithValues: BrowserTheme.appearancePreferenceKeys.map { ($0, defaults.object(forKey: $0)) })
    let favorites = defaults.stringArray(forKey: "favorites")
    let views = defaults.data(forKey: "folderViews")
    let manager = DefaultFileManager.isDefault
    defer {
        for key in BrowserTheme.appearancePreferenceKeys {
            if let value = saved[key] ?? nil { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    BrowserTheme.setThemed(false, forKey: "frostedPanes")
    BrowserTheme.setThemed(0.2, forKey: "paneOpacity"); BrowserTheme.setThemed(GlassStyle.vivid.rawValue, forKey: "glassStyle"); BrowserTheme.setThemed(true, forKey: "glassTintEnabled")
    BrowserTheme.setThemed(false, forKey: "titlebarTintEnabled"); BrowserTheme.setThemed(0.1, forKey: "titlebarOpacity")
    BrowserTheme.setThemed(true, forKey: "windowOutlineEnabled")
    for key in ["glassTint", "titlebarTint", "accentColor", "windowOutlineColor"] { defaults.set([1.0, 0.2, 0.3], forKey: key) }
    let settings = SettingsController()
    defer { settings.close() }
    let controls = descendants(settings.window!.contentView!)
    let reset = controls.compactMap { $0 as? NSButton }.first { $0.title == "Reset to Defaults" }!
    reset.performClick(nil)
    try require(BrowserTheme.frosted && BrowserTheme.opacity == 0.01 && BrowserTheme.glassStyle == .soft && !BrowserTheme.glassTintEnabled,
        "Reset must restore the default untinted Soft blur glass in dark mode")
    let titlebar = BrowserTheme.titlebarTint.usingColorSpace(.sRGB)!
    try require(BrowserTheme.titlebarTintEnabled && BrowserTheme.titlebarOpacity == 0.38 && !BrowserTheme.outlineEnabled
        && abs(titlebar.redComponent - 0.2403) < 0.001 && abs(titlebar.blueComponent - 0.3082) < 0.001,
        "Reset must restore the default blue-grey titlebar at 38%, with no outline")
    try require(BrowserTheme.accentColor.usingColorSpace(.sRGB) == BrowserTheme.titlebarTint.usingColorSpace(.sRGB), "Reset must restore the default accent color")
    let opacity = controls.compactMap { $0 as? LiveSlider }.first { $0.accessibilityLabel() == "Pane opacity" }!
    try require(opacity.doubleValue == 0.01 && !opacity.isEnabled, "The open Settings controls must immediately reflect the defaults")
    let checkboxes = controls.compactMap { $0 as? NSButton }.filter { ["Liquid Glass backgrounds", "Tint the glass", "Tint the titlebar", "Show window outline"].contains($0.title) }
    try require(checkboxes.count == 4 && checkboxes.allSatisfy { $0.state == (["Tint the glass", "Show window outline"].contains($0.title) ? .off : .on) }, "Appearance checkboxes must refresh after resetting")
    try require(defaults.stringArray(forKey: "favorites") == favorites && defaults.data(forKey: "folderViews") == views && DefaultFileManager.isDefault == manager,
        "Resetting appearance must preserve favorites, folder views and the system file-manager choice")
    print("PASS: Reset to Defaults restores appearance immediately while preserving favorites, folder views and system choices")
    let frame = settings.window!.frame.size
    try require(frame.width > frame.height * 1.25, "Settings must be a wide window: \(frame)")
    try require(!controls.contains { $0 is NSScrollView }, "Every setting must be visible without scrolling")
    let glass = checkboxes.first { $0.title == "Liquid Glass backgrounds" }!
    let opacityLabel = controls.compactMap { $0 as? NSTextField }.first { $0.stringValue == "Opacity" }!
    let tintToggle = checkboxes.first { $0.title == "Tint the glass" }!
    let tintWell = controls.compactMap { $0 as? NSColorWell }.first { $0.action == NSSelectorFromString("tintChanged") }!
    let glassStyle = controls.compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Glass style" }!
    let backdrop = WindowBackdrop(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    func tintAlpha() -> CGFloat { NSColor(cgColor: backdrop.tint.layer!.backgroundColor!)!.alphaComponent }
    try require(backdrop.isUsingGlass && tintAlpha() == 0 && !tintWell.isEnabled && opacityLabel.textColor == .disabledControlTextColor && glassStyle.isEnabled,
        "By default the glass is untinted, with opacity and tint dimmed and the style available")
    tintToggle.performClick(nil)
    try require(BrowserTheme.glassTintEnabled && opacity.isEnabled && tintWell.isEnabled && abs(tintAlpha() - 0.01) < 0.001,
        "Turning the tint on must enable opacity and color")
    glass.performClick(nil)
    try require(!opacity.isEnabled && opacityLabel.textColor == .disabledControlTextColor && !tintToggle.isEnabled && tintWell.isEnabled,
        "Without glass the window is solid tint color: opacity and the tint toggle dim, the color stays editable")
    glass.performClick(nil)
    try require(opacity.isEnabled && opacityLabel.textColor == .labelColor, "Turning glass back on must restore its rows")
    tintToggle.performClick(nil)
    try require(!BrowserTheme.glassTintEnabled && !opacity.isEnabled && !tintWell.isEnabled && tintAlpha() == 0,
        "Turning the tint off must remove the color layer and dim opacity and the tint color")
    print("PASS: Settings is a wide two-column panel with no scrolling, and switched-off rows dim their labels")
    let well = controls.compactMap { $0 as? NSColorWell }.first { $0.action == NSSelectorFromString("accentChanged") }!
    well.activate(true)
    defer { well.deactivate(); NSColorPanel.shared.orderOut(nil) }
    let picker = NSColorPanel.shared, pickerFrame = picker.contentView!.superview!
    let pickerGlass = pickerFrame.subviews.filter { $0.identifier?.rawValue == "ExplorerDialogGlass" }
    try require(pickerGlass.count == 1 && pickerGlass[0].frame == pickerFrame.bounds && pickerFrame.subviews.first === pickerGlass[0],
        "The color picker's glass must sit behind the whole panel, titlebar and picker tabs included")
    try require(!picker.contentView!.subviews.contains { $0.identifier?.rawValue == "ExplorerDialogGlass" } && picker.titlebarAppearsTransparent,
        "The color picker must not get a second glass layer inside its content")
    well.deactivate(); well.activate(true)
    try require(pickerFrame.subviews.filter { $0.identifier?.rawValue == "ExplorerDialogGlass" }.count == 1, "Reopening the picker must not stack glass")
    print("PASS: The color picker's glass covers the whole panel, including its titlebar")
}
