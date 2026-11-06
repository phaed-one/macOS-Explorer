import AppKit

protocol SettingsPresenting: AnyObject { func showSettings() }

final class SettingsController: NSWindowController {
    private let opacity = LiveSlider(value: BrowserTheme.opacity, minValue: 0.01, maxValue: 1, target: nil, action: nil)
    private let percentage = NSTextField(labelWithString: "")
    private let glassStyle = NSPopUpButton(frame: .zero, pullsDown: false)
    private let tintColor = AnchoredColorWell()
    private let titlebarColor = AnchoredColorWell()
    private let accentColor = AnchoredColorWell()
    private let titlebarOpacity = LiveSlider(value: BrowserTheme.titlebarOpacity, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let titlebarPercentage = NSTextField(labelWithString: "")
    private let resetTitlebarButton = NSButton(title: "Reset", target: nil, action: nil)
    private let outlineColor = AnchoredColorWell()
    private let restoreFrame = NSButton(checkboxWithTitle: "Restore size and position", target: nil, action: nil)
    private let restoreTabs = NSButton(checkboxWithTitle: "Restore open tabs", target: nil, action: nil)
    private let startupFolder = NSPopUpButton(frame: .zero, pullsDown: false)
    private static let startupFolders: [(String, URL?)] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [("Last opened folder", nil), ("Home", home), ("Applications", URL(fileURLWithPath: "/Applications")),
                ("Desktop", home.appendingPathComponent("Desktop")), ("Documents", home.appendingPathComponent("Documents")),
                ("Downloads", home.appendingPathComponent("Downloads"))]
    }()
    private let themeMode = NSSegmentedControl(labels: ["Light", "Dark"], trackingMode: .selectOne, target: nil, action: nil)
    private let chromeColor = AnchoredColorWell()
    private let defaultManagerStatus = NSTextField(wrappingLabelWithString: "")
    private let defaultManagerButton = NSButton(title: "Use Explorer", target: nil, action: nil)
    private let restoreFinderButton = NSButton(title: "Use Finder", target: nil, action: nil)
    private let glass = NSButton(checkboxWithTitle: "Liquid Glass backgrounds", target: nil, action: nil)
    private let enableTitlebar = NSButton(checkboxWithTitle: "Tint the titlebar", target: nil, action: nil)
    private let enableGlassTint = NSButton(checkboxWithTitle: "Tint the glass", target: nil, action: nil)
    private let resetTintButton = NSButton(title: "Reset", target: nil, action: nil)
    private let tintLabel = SettingsController.rowLabel("Tint")
    private let enableOutline = NSButton(checkboxWithTitle: "Show window outline", target: nil, action: nil)
    private let enableFieldTint = NSButton(checkboxWithTitle: "Tint path and search fields", target: nil, action: nil)
    private let fieldTintColor = AnchoredColorWell()
    private let opacityLabel = SettingsController.rowLabel("Opacity")
    private let glassStyleLabel = SettingsController.rowLabel("Style")
    private let titlebarColorLabel = SettingsController.rowLabel("Color")
    private let titlebarOpacityLabel = SettingsController.rowLabel("Opacity")
    private static let columnWidth: CGFloat = 300, appearanceWidth: CGFloat = 450
    init() {
        BrowserTheme.initializeAccent()
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 820, height: 480), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isFloatingPanel = false
        window.becomesKeyOnlyIfNeeded = true
        super.init(window: window)
        window.title = "Explorer Settings"
        let inner = Self.columnWidth - 2 * SettingsCard.padding

        // Left column: what Explorer does.
        let updates = UpdateStatusView()
        updates.widthAnchor.constraint(equalToConstant: inner).isActive = true
        defaultManagerButton.target = self; defaultManagerButton.action = #selector(useDefaultManager)
        restoreFinderButton.target = self; restoreFinderButton.action = #selector(restoreFinder)
        defaultManagerStatus.widthAnchor.constraint(equalToConstant: inner).isActive = true
        let managerHint = Self.hint("Folders opened from the desktop or Dock still use Finder; macOS doesn’t let any app change that. Reopen other apps after switching.", width: inner)
        // Theme: Explorer's own light or dark look, and the header color for each.
        themeMode.target = self; themeMode.action = #selector(themeModeChanged)
        themeMode.setAccessibilityLabel("Theme")
        chromeColor.target = self; chromeColor.action = #selector(chromeColorChanged)
        chromeColor.setAccessibilityLabel("Header color")
        chromeColor.widthAnchor.constraint(equalToConstant: 44).isActive = true
        chromeColor.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let resetChrome = NSButton(title: "Reset", target: self, action: #selector(resetChromeColor))
        resetChrome.setAccessibilityLabel("Use default header color")
        let themeHint = Self.hint("Every Appearance setting is saved separately for light and dark.", width: 320)
        // Startup: what Explorer brings back when it opens.
        restoreFrame.target = self; restoreFrame.action = #selector(startupOptionChanged(_:))
        restoreTabs.target = self; restoreTabs.action = #selector(startupOptionChanged(_:))
        startupFolder.target = self; startupFolder.action = #selector(startupFolderChanged)
        startupFolder.setAccessibilityLabel("Startup folder")
        rebuildStartupFolderMenu()
        let startupGrid = NSGridView(views: [[Self.rowLabel("Window"), restoreFrame], [Self.rowLabel("Tabs"), restoreTabs],
                                             [Self.rowLabel("Folder"), startupFolder]])
        startupGrid.rowSpacing = 8; startupGrid.columnSpacing = 12
        startupGrid.column(at: 0).xPlacement = .trailing
        startupGrid.column(at: 0).width = 52
        for index in 0..<startupGrid.numberOfRows { startupGrid.row(at: index).yPlacement = .center }
        let startupCard = SettingsCard(title: "Startup", width: Self.columnWidth, content: [startupGrid])
        let confirmations = ConfirmationPreference.allCases.map { preference in
            let button = NSButton(checkboxWithTitle: preference.title, target: self, action: #selector(confirmationChanged(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(preference.rawValue)
            button.state = preference.isEnabled ? .on : .off
            return button
        }
        let confirmationCard = SettingsCard(title: "Confirmations", width: Self.columnWidth, content: confirmations + [
            Self.hint("Clearing Trash permanently deletes its contents.", width: inner)])
        let finderCard = SettingsCard(title: "Show in Finder", width: Self.columnWidth, fillsHeight: true, content: [
            defaultManagerStatus, NSStackView(views: [defaultManagerButton, restoreFinderButton]), managerHint])
        // Left column: what Explorer does. Right column: how it looks, per theme.
        let general = NSStackView(views: [SettingsCard(title: nil, width: Self.columnWidth, content: [updates]), startupCard, confirmationCard, finderCard])
        general.orientation = .vertical; general.alignment = .leading; general.spacing = 16
        general.distribution = .fill
        updateDefaultManagerStatus()

        // Right column: how Explorer looks.
        glass.target = self; glass.action = #selector(toggleGlass(_:))
        opacity.target = self; opacity.action = #selector(opacityChanged)
        opacity.setAccessibilityLabel("Pane opacity")
        glassStyle.addItems(withTitles: GlassStyle.allCases.map(\.title))
        glassStyle.target = self; glassStyle.action = #selector(glassStyleChanged)
        glassStyle.setAccessibilityLabel("Glass style")
        ToolbarHelp.install(on: glassStyle, text: "How the window glass looks. Bright and Dark are Liquid Glass; the others are classic blurs.")
        tintColor.target = self; tintColor.action = #selector(tintChanged)
        tintColor.setAccessibilityLabel("Glass tint color")
        resetTintButton.target = self; resetTintButton.action = #selector(resetTint)
        resetTintButton.setAccessibilityLabel("Use system glass tint")
        enableGlassTint.target = self; enableGlassTint.action = #selector(toggleGlassTint(_:))
        enableTitlebar.target = self; enableTitlebar.action = #selector(toggleTitlebarTint(_:))
        titlebarColor.target = self; titlebarColor.action = #selector(titlebarTintChanged)
        titlebarColor.setAccessibilityLabel("Titlebar tint color")
        resetTitlebarButton.target = self; resetTitlebarButton.action = #selector(resetTitlebar)
        resetTitlebarButton.setAccessibilityLabel("Use default titlebar tint")
        titlebarOpacity.target = self; titlebarOpacity.action = #selector(titlebarOpacityChanged)
        titlebarOpacity.setAccessibilityLabel("Titlebar tint opacity")
        accentColor.target = self; accentColor.action = #selector(accentChanged)
        accentColor.setAccessibilityLabel("Accent color")
        let matchTitlebar = NSButton(title: "Match Titlebar", target: self, action: #selector(useTitlebarAccent))
        enableOutline.target = self; enableOutline.action = #selector(toggleOutline(_:))
        enableFieldTint.target = self; enableFieldTint.action = #selector(toggleFieldTint(_:))
        fieldTintColor.target = self; fieldTintColor.action = #selector(fieldTintColorChanged)
        fieldTintColor.setAccessibilityLabel("Field color")
        outlineColor.target = self; outlineColor.action = #selector(outlineColorChanged)
        outlineColor.setAccessibilityLabel("Window outline color")
        for slider in [opacity, titlebarOpacity] {
            slider.isContinuous = true
            slider.widthAnchor.constraint(equalToConstant: 230).isActive = true
        }
        for well in [tintColor, titlebarColor, accentColor, outlineColor, fieldTintColor] {
            well.widthAnchor.constraint(equalToConstant: 44).isActive = true
            well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        for amount in [percentage, titlebarPercentage] {
            amount.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            amount.alignment = .right
            amount.widthAnchor.constraint(equalToConstant: 40).isActive = true
        }
        let empty = NSGridCell.emptyContentView
        let accentHint = Self.hint("Button highlights and inactive selections", width: 300)
        let grid = NSGridView(views: [
            [Self.groupHeader("Theme"), empty],
            [Self.rowLabel("Mode"), themeMode],
            [empty, themeHint],
            [Self.rowLabel("Header"), Self.row(chromeColor, resetChrome)],
            [Self.groupHeader("Window Glass"), empty],
            [empty, glass],
            [glassStyleLabel, glassStyle],
            [empty, enableGlassTint],
            [opacityLabel, Self.row(opacity, percentage)],
            [tintLabel, Self.row(tintColor, resetTintButton)],
            [Self.groupHeader("Titlebar"), empty],
            [empty, enableTitlebar],
            [titlebarColorLabel, Self.row(titlebarColor, resetTitlebarButton)],
            [titlebarOpacityLabel, Self.row(titlebarOpacity, titlebarPercentage)],
            [Self.groupHeader("Highlights"), empty],
            [Self.rowLabel("Accent"), Self.row(accentColor, matchTitlebar)],
            [empty, accentHint],
            [Self.rowLabel("Fields"), Self.row(enableFieldTint, fieldTintColor)],
            [Self.rowLabel("Outline"), Self.row(enableOutline, outlineColor)],
        ])
        grid.rowSpacing = 10; grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 70
        for index in 0..<grid.numberOfRows { grid.row(at: index).yPlacement = .center }
        for index in [0, 4, 10, 14] {
            let row = grid.row(at: index)
            row.mergeCells(in: NSRange(location: 0, length: 2))
            row.cell(at: 0).xPlacement = .leading
            if index > 0 { row.topPadding = 10 }
        }
        grid.row(at: 2).topPadding = -6
        grid.row(at: 16).topPadding = -6
        let reset = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetToDefaults))
        let appearance = SettingsCard(title: "Appearance", accessory: reset, width: Self.appearanceWidth, fillsHeight: true, content: [grid])

        let columns = NSStackView(views: [general, appearance])
        columns.orientation = .horizontal; columns.alignment = .top; columns.spacing = 20
        columns.edgeInsets = NSEdgeInsets(top: 8, left: 24, bottom: 24, right: 24)
        columns.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(columns)
        NSLayoutConstraint.activate([columns.topAnchor.constraint(equalTo: content.topAnchor),
                                     columns.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                                     general.heightAnchor.constraint(equalTo: appearance.heightAnchor)])
        syncAppearanceControls()
        window.setContentSize(columns.fittingSize)
        window.center()
        DialogAppearance.install(on: window)
    }
    private static func rowLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        return label
    }
    private static func groupHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }
    private static func hint(_ text: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = width
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }
    private static func row(_ views: NSView...) -> NSStackView {
        let row = NSStackView(views: views)
        row.spacing = 10
        return row
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func confirmationChanged(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue, let preference = ConfirmationPreference(rawValue: key) else { return }
        preference.isEnabled = sender.state == .on
    }
    @objc private func resetToDefaults() {
        for well in [tintColor, titlebarColor, accentColor, outlineColor, chromeColor, fieldTintColor] { well.deactivate() }
        NSColorPanel.shared.orderOut(nil)
        BrowserTheme.resetAppearance()
        syncAppearanceControls()
    }
    private func syncAppearanceControls() {
        restoreFrame.state = StartupPreferences.restoresFrame ? .on : .off
        restoreTabs.state = StartupPreferences.restoresTabs ? .on : .off
        themeMode.selectedSegment = BrowserTheme.darkMode ? 1 : 0
        chromeColor.color = BrowserTheme.chromeColor(dark: BrowserTheme.darkMode)
        glass.state = BrowserTheme.frosted ? .on : .off
        opacity.doubleValue = BrowserTheme.opacity
        percentage.stringValue = "\(Int(BrowserTheme.opacity * 100))%"
        glassStyle.selectItem(at: GlassStyle.allCases.firstIndex(of: BrowserTheme.glassStyle) ?? 0)
        enableGlassTint.state = BrowserTheme.glassTintEnabled ? .on : .off
        tintColor.color = BrowserTheme.pane
        enableTitlebar.state = BrowserTheme.titlebarTintEnabled ? .on : .off
        titlebarColor.color = BrowserTheme.titlebarTint
        titlebarOpacity.doubleValue = BrowserTheme.titlebarOpacity
        titlebarPercentage.stringValue = "\(Int(BrowserTheme.titlebarOpacity * 100))%"
        accentColor.color = BrowserTheme.accentColor
        enableOutline.state = BrowserTheme.outlineEnabled ? .on : .off
        enableFieldTint.state = BrowserTheme.fieldTintEnabled ? .on : .off
        fieldTintColor.color = BrowserTheme.fieldTint
        outlineColor.color = BrowserTheme.outlineColor
        updateEnabledStates()
    }
    /// Controls under a switched-off checkbox dim along with their labels.
    private func updateEnabledStates() {
        let glassOn = BrowserTheme.frosted, titlebarOn = BrowserTheme.titlebarTintEnabled
        // Untinted glass has no color layer; without glass the window is a solid fill of the tint color.
        let opacityOn = glassOn && BrowserTheme.glassTintEnabled, tintColorOn = !glassOn || BrowserTheme.glassTintEnabled
        for control in [glassStyle, enableGlassTint] as [NSControl] { control.isEnabled = glassOn }
        opacity.isEnabled = opacityOn
        for control in [tintColor, resetTintButton] as [NSControl] { control.isEnabled = tintColorOn }
        for control in [titlebarColor, titlebarOpacity, resetTitlebarButton] as [NSControl] { control.isEnabled = titlebarOn }
        outlineColor.isEnabled = BrowserTheme.outlineEnabled
        fieldTintColor.isEnabled = BrowserTheme.fieldTintEnabled
        glassStyleLabel.textColor = glassOn ? .labelColor : .disabledControlTextColor
        for label in [opacityLabel, percentage] { label.textColor = opacityOn ? .labelColor : .disabledControlTextColor }
        tintLabel.textColor = tintColorOn ? .labelColor : .disabledControlTextColor
        for label in [titlebarColorLabel, titlebarOpacityLabel, titlebarPercentage] { label.textColor = titlebarOn ? .labelColor : .disabledControlTextColor }
    }
    private func updateDefaultManagerStatus() {
        let active = DefaultFileManager.isDefault
        defaultManagerStatus.stringValue = active ? "“Show in Finder” requests from other apps open in Explorer." : "“Show in Finder” requests from other apps open in Finder."
        defaultManagerButton.isEnabled = !active
        restoreFinderButton.isEnabled = active
    }
    @objc private func useDefaultManager() {
        do { try DefaultFileManager.useExplorer(); updateDefaultManagerStatus() }
        catch { NSAlert(error: error).runGlassModal() }
    }
    @objc private func restoreFinder() {
        do { try DefaultFileManager.restoreFinder(); updateDefaultManagerStatus() }
        catch { NSAlert(error: error).runGlassModal() }
    }
    @objc private func toggleGlass(_ sender: NSButton) {
        BrowserTheme.setThemed(sender.state == .on, forKey: "frostedPanes")
        updateEnabledStates()
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func opacityChanged() {
        BrowserTheme.setThemed(opacity.doubleValue, forKey: "paneOpacity")
        percentage.stringValue = "\(Int(opacity.doubleValue * 100))%"
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func toggleGlassTint(_ sender: NSButton) {
        BrowserTheme.setThemed(sender.state == .on, forKey: "glassTintEnabled")
        updateEnabledStates()
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func glassStyleChanged() {
        let style = GlassStyle.allCases[max(0, glassStyle.indexOfSelectedItem)]
        BrowserTheme.setThemed(style.rawValue, forKey: "glassStyle")
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func tintChanged() {
        guard let color = tintColor.color.usingColorSpace(.sRGB) else { return }
        BrowserTheme.setThemed([Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)], forKey: "glassTint")
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func resetTint() {
        BrowserTheme.setThemed(nil, forKey: "glassTint")
        tintColor.color = BrowserTheme.pane
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func titlebarTintChanged() {
        guard let color = titlebarColor.color.usingColorSpace(.sRGB) else { return }
        BrowserTheme.setThemed([Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)], forKey: "titlebarTint")
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func toggleTitlebarTint(_ sender: NSButton) {
        BrowserTheme.setThemed(sender.state == .on, forKey: "titlebarTintEnabled")
        updateEnabledStates()
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func titlebarOpacityChanged() {
        BrowserTheme.setThemed(titlebarOpacity.doubleValue, forKey: "titlebarOpacity")
        titlebarPercentage.stringValue = "\(Int(titlebarOpacity.doubleValue * 100))%"
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func resetTitlebar() {
        BrowserTheme.setThemed(nil, forKey: "titlebarTint")
        BrowserTheme.setThemed(nil, forKey: "titlebarOpacity")
        titlebarColor.color = BrowserTheme.titlebarTint
        titlebarOpacity.doubleValue = BrowserTheme.titlebarOpacity
        titlebarPercentage.stringValue = "\(Int(BrowserTheme.titlebarOpacity * 100))%"
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func toggleOutline(_ sender: NSButton) {
        BrowserTheme.setThemed(sender.state == .on, forKey: "windowOutlineEnabled")
        updateEnabledStates()
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func accentChanged() {
        guard let color = accentColor.color.usingColorSpace(.sRGB) else { return }
        BrowserTheme.setThemed([Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)], forKey: "accentColor")
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func useTitlebarAccent() {
        accentColor.color = BrowserTheme.titlebarTint
        accentChanged()
    }
    /// Lists the preset startup folders, plus a chosen one when it isn't a preset.
    private func rebuildStartupFolderMenu() {
        let menu = NSMenu()
        let chosen = StartupPreferences.folder?.standardizedFileURL
        var selected: NSMenuItem?
        for (index, (title, url)) in Self.startupFolders.enumerated() {
            if index == 1 { menu.addItem(.separator()) }
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = url
            menu.addItem(item)
            if url?.standardizedFileURL == chosen { selected = item }
        }
        if let chosen, selected == nil {
            let item = NSMenuItem(title: chosen.lastPathComponent, action: nil, keyEquivalent: "")
            item.representedObject = chosen; item.toolTip = chosen.path
            menu.addItem(item); selected = item
        }
        menu.addItem(.separator())
        let choose = NSMenuItem(title: "Choose…", action: nil, keyEquivalent: "")
        choose.identifier = NSUserInterfaceItemIdentifier("chooseStartupFolder")
        menu.addItem(choose)
        startupFolder.menu = menu
        startupFolder.select(selected ?? menu.items.first)
    }
    @objc private func startupOptionChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: sender === restoreFrame ? "startupRestoresFrame" : "startupRestoresTabs")
    }
    @objc private func startupFolderChanged() {
        guard let item = startupFolder.selectedItem else { return }
        if item.identifier?.rawValue == "chooseStartupFolder" {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
            panel.prompt = "Open at Startup"
            panel.directoryURL = StartupPreferences.folder ?? FileManager.default.homeDirectoryForCurrentUser
            let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                if response == .OK, let url = panel.url { UserDefaults.standard.set(url.path, forKey: "startupFolder") }
                self?.rebuildStartupFolderMenu()
            }
            if let window { panel.beginSheetModal(for: window, completionHandler: finish) } else { finish(panel.runModal()) }
            return
        }
        if let url = item.representedObject as? URL { UserDefaults.standard.set(url.path, forKey: "startupFolder") }
        else { UserDefaults.standard.removeObject(forKey: "startupFolder") }
    }
    @objc private func toggleFieldTint(_ sender: NSButton) {
        BrowserTheme.setThemed(sender.state == .on, forKey: "fieldTintEnabled")
        updateEnabledStates()
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func fieldTintColorChanged() {
        guard let color = fieldTintColor.color.usingColorSpace(.sRGB) else { return }
        BrowserTheme.setThemed([Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)], forKey: "fieldTintColor")
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func themeModeChanged() {
        UserDefaults.standard.set(themeMode.selectedSegment == 1 ? "dark" : "light", forKey: "appearanceMode")
        BrowserTheme.applyAppearanceMode()
        // Every Appearance control shows the values saved for the theme now showing.
        BrowserTheme.initializeAccent()
        syncAppearanceControls()
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    /// The header color well edits the color of the mode that's showing.
    @objc private func chromeColorChanged() {
        guard let color = chromeColor.color.usingColorSpace(.sRGB) else { return }
        UserDefaults.standard.set([Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)],
                                  forKey: BrowserTheme.chromeColorKey(dark: BrowserTheme.darkMode))
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func resetChromeColor() {
        UserDefaults.standard.removeObject(forKey: BrowserTheme.chromeColorKey(dark: BrowserTheme.darkMode))
        chromeColor.color = BrowserTheme.chromeColor(dark: BrowserTheme.darkMode)
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func outlineColorChanged() {
        guard let color = outlineColor.color.usingColorSpace(.sRGB) else { return }
        BrowserTheme.setThemed([Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)], forKey: "windowOutlineColor")
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
}

/// A titled, lightly filled group so related settings read as one block. Also used by other dialogs.
final class SettingsCard: NSView {
    static let padding: CGFloat = 16
    /// A card that `fillsHeight` keeps its content at the top and absorbs spare column height below it.
    init(title: String?, accessory: NSView? = nil, width: CGFloat, fillsHeight: Bool = false, content: [NSView]) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let title {
            let heading = NSTextField(labelWithString: title)
            heading.font = .systemFont(ofSize: 13, weight: .semibold)
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let header = NSStackView(views: [heading, spacer] + (accessory.map { [$0] } ?? []))
            header.widthAnchor.constraint(equalToConstant: width - 2 * Self.padding).isActive = true
            stack.addArrangedSubview(header)
        }
        content.forEach(stack.addArrangedSubview)
        addSubview(stack)
        let bottom = fillsHeight
            ? stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -Self.padding)
            : stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.padding)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.padding),
            bottom])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { GlassCard.paint(self) }
}

private final class AnchoredColorWell: NSColorWell {
    override func activate(_ exclusive: Bool) {
        super.activate(exclusive)
        guard let owner = window else { return }
        let picker = NSColorPanel.shared
        DialogAppearance.installBehindFrame(on: picker)
        let screen = owner.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? owner.frame
        let size = picker.frame.size
        var x = owner.frame.maxX + 10
        if x + size.width > screen.maxX { x = owner.frame.minX - size.width - 10 }
        if x < screen.minX { x = owner.frame.midX - size.width / 2 }
        let y = owner.frame.maxY - size.height
        picker.setFrameOrigin(NSPoint(
            x: max(screen.minX, min(x, screen.maxX - size.width)),
            y: max(screen.minY, min(y, screen.maxY - size.height))))
        if picker.parent !== owner {
            picker.parent?.removeChildWindow(picker)
            owner.addChildWindow(picker, ordered: .above)
        }
        picker.orderFront(nil)
    }
}
