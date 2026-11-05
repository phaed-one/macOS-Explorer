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
    defaults.set(false, forKey: "frostedPanes")
    defaults.set(0.2, forKey: "paneOpacity"); defaults.set(0.9, forKey: "glassFrosting")
    defaults.set(false, forKey: "titlebarTintEnabled"); defaults.set(0.1, forKey: "titlebarOpacity")
    defaults.set(false, forKey: "windowOutlineEnabled")
    for key in ["glassTint", "titlebarTint", "accentColor", "windowOutlineColor"] { defaults.set([1.0, 0.2, 0.3], forKey: key) }
    let settings = SettingsController()
    defer { settings.close() }
    let controls = descendants(settings.window!.contentView!)
    let reset = controls.compactMap { $0 as? NSButton }.first { $0.title == "Reset to Defaults" }!
    reset.performClick(nil)
    try require(BrowserTheme.frosted && BrowserTheme.opacity == 0.8 && BrowserTheme.frosting == 0,
        "Reset must restore default pane appearance")
    try require(BrowserTheme.titlebarTintEnabled && BrowserTheme.titlebarOpacity == 0.65 && BrowserTheme.outlineEnabled,
        "Reset must restore default titlebar and outline settings")
    try require(BrowserTheme.accentColor.usingColorSpace(.sRGB) == BrowserTheme.titlebarTint.usingColorSpace(.sRGB), "Reset must restore the default accent color")
    let opacity = controls.compactMap { $0 as? LiveSlider }.first { $0.accessibilityLabel() == "Pane opacity" }!
    try require(opacity.doubleValue == 0.8 && opacity.isEnabled, "The open Settings controls must immediately reflect the defaults")
    let checkboxes = controls.compactMap { $0 as? NSButton }.filter { ["Liquid Glass pane backgrounds", "Enable titlebar tint", "Show window outline"].contains($0.title) }
    try require(checkboxes.count == 3 && checkboxes.allSatisfy { $0.state == .on }, "Appearance checkboxes must refresh after resetting")
    try require(defaults.stringArray(forKey: "favorites") == favorites && defaults.data(forKey: "folderViews") == views && DefaultFileManager.isDefault == manager,
        "Resetting appearance must preserve favorites, folder views and the system file-manager choice")
    print("PASS: Reset to Defaults restores appearance immediately while preserving favorites, folder views and system choices")
}
