import AppKit

protocol SettingsPresenting: AnyObject { func showSettings() }

final class SettingsController: NSWindowController {
    private let opacity = LiveSlider(value: BrowserTheme.opacity, minValue: 0.01, maxValue: 1, target: nil, action: nil)
    private let percentage = NSTextField(labelWithString: "")
    private let frosting = LiveSlider(value: BrowserTheme.frosting, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let frostingAmount = NSTextField(labelWithString: "")
    private let tintColor = AnchoredColorWell()
    private let titlebarColor = AnchoredColorWell()
    private let accentColor = AnchoredColorWell()
    private let titlebarOpacity = LiveSlider(value: BrowserTheme.titlebarOpacity, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let titlebarPercentage = NSTextField(labelWithString: "")
    private let resetTitlebarButton = NSButton(title: "Use Default Tint", target: nil, action: nil)
    private let outlineColor = AnchoredColorWell()
    private let defaultManagerStatus = NSTextField(wrappingLabelWithString: "")
    private let defaultManagerButton = NSButton(title: "Use Explorer as Default", target: nil, action: nil)
    private let glass = NSButton(checkboxWithTitle: "Liquid Glass pane backgrounds", target: nil, action: nil)
    private let enableTitlebar = NSButton(checkboxWithTitle: "Enable titlebar tint", target: nil, action: nil)
    private let enableOutline = NSButton(checkboxWithTitle: "Show window outline", target: nil, action: nil)
    init() {
        BrowserTheme.initializeAccent()
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 570), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isFloatingPanel = false
        window.becomesKeyOnlyIfNeeded = true
        super.init(window: window)
        window.title = "Explorer Settings"
        let updates = UpdateStatusView()
        let managerTitle = NSTextField(labelWithString: "Default File Manager")
        managerTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        defaultManagerButton.target = self; defaultManagerButton.action = #selector(useDefaultManager)
        let managerButtons = NSStackView(views: [defaultManagerButton,
            NSButton(title: "Restore Finder", target: self, action: #selector(restoreFinder))])
        let managerHint = NSTextField(wrappingLabelWithString: "Send Show in Finder requests from other apps to Explorer. Reopen other apps after changing this; some may require signing out and back in. macOS does not let any app take over opening folders, so double-clicked folders on the desktop and in the Dock still open in Finder. System Open/Save dialogs stay unchanged.")
        managerHint.textColor = .secondaryLabelColor
        updateDefaultManagerStatus()
        let title = NSTextField(labelWithString: "Appearance")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        let reset = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetToDefaults))
        let appearanceHeading = NSStackView(views: [title, reset])
        appearanceHeading.spacing = 20
        glass.target = self; glass.action = #selector(toggleGlass(_:))
        let description = NSTextField(wrappingLabelWithString: "1% keeps the glass lightly tinted. 100% is fully opaque. Glass tint and Accent are independent.")
        description.textColor = .secondaryLabelColor
        opacity.target = self; opacity.action = #selector(opacityChanged)
        opacity.isContinuous = true; opacity.isEnabled = BrowserTheme.frosted
        opacity.setAccessibilityLabel("Pane opacity")
        opacity.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let opacityRow = NSStackView(views: [NSTextField(labelWithString: "Pane opacity"), opacity, percentage])
        frosting.target = self; frosting.action = #selector(frostingChanged)
        frosting.isContinuous = true; frosting.isEnabled = BrowserTheme.frosted
        frosting.setAccessibilityLabel("Glass frosting")
        frosting.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let frostingRow = NSStackView(views: [NSTextField(labelWithString: "Frosting"), frosting, frostingAmount])
        let frostingHint = NSTextField(wrappingLabelWithString: "Clear → Frosted. Blends in native backdrop blur that stays active while you use the window. This is independent of tint opacity.")
        frostingHint.font = .systemFont(ofSize: 11); frostingHint.textColor = .secondaryLabelColor
        tintColor.target = self; tintColor.action = #selector(tintChanged)
        tintColor.setAccessibilityLabel("Glass tint color")
        tintColor.widthAnchor.constraint(equalToConstant: 50).isActive = true
        tintColor.heightAnchor.constraint(equalToConstant: 26).isActive = true
        let resetTint = NSButton(title: "Use System Tint", target: self, action: #selector(resetTint))
        let tintRow = NSStackView(views: [NSTextField(labelWithString: "Glass tint"), tintColor, resetTint])
        let titlebarHeading = NSTextField(labelWithString: "Titlebar Tint")
        titlebarHeading.font = .systemFont(ofSize: 14, weight: .semibold)
        enableTitlebar.target = self; enableTitlebar.action = #selector(toggleTitlebarTint(_:))
        titlebarColor.target = self; titlebarColor.action = #selector(titlebarTintChanged)
        titlebarColor.setAccessibilityLabel("Titlebar tint color")
        titlebarColor.widthAnchor.constraint(equalToConstant: 50).isActive = true
        titlebarColor.heightAnchor.constraint(equalToConstant: 26).isActive = true
        resetTitlebarButton.target = self; resetTitlebarButton.action = #selector(resetTitlebar)
        let titlebarTintRow = NSStackView(views: [NSTextField(labelWithString: "Tint color"), titlebarColor, resetTitlebarButton])
        titlebarOpacity.target = self; titlebarOpacity.action = #selector(titlebarOpacityChanged)
        titlebarOpacity.isContinuous = true
        titlebarOpacity.setAccessibilityLabel("Titlebar tint opacity")
        titlebarOpacity.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let titlebarOpacityRow = NSStackView(views: [NSTextField(labelWithString: "Titlebar opacity"), titlebarOpacity, titlebarPercentage])
        updateTitlebarControls()
        let accentHeading = NSTextField(labelWithString: "Accent Color")
        accentHeading.font = .systemFont(ofSize: 14, weight: .semibold)
        accentColor.target = self; accentColor.action = #selector(accentChanged)
        accentColor.setAccessibilityLabel("Accent color")
        accentColor.widthAnchor.constraint(equalToConstant: 50).isActive = true
        accentColor.heightAnchor.constraint(equalToConstant: 26).isActive = true
        let accentRow = NSStackView(views: [NSTextField(labelWithString: "Accent color"), accentColor,
            NSButton(title: "Use Titlebar Color", target: self, action: #selector(useTitlebarAccent))])
        let accentHint = NSTextField(wrappingLabelWithString: "Used for button hover and pressed colors, and inactive selections. Independent of titlebar tint.")
        accentHint.textColor = .secondaryLabelColor
        let outlineHeading = NSTextField(labelWithString: "Window Outline")
        outlineHeading.font = .systemFont(ofSize: 14, weight: .semibold)
        enableOutline.target = self; enableOutline.action = #selector(toggleOutline(_:))
        outlineColor.target = self; outlineColor.action = #selector(outlineColorChanged)
        outlineColor.isEnabled = BrowserTheme.outlineEnabled
        outlineColor.setAccessibilityLabel("Window outline color")
        outlineColor.widthAnchor.constraint(equalToConstant: 50).isActive = true
        outlineColor.heightAnchor.constraint(equalToConstant: 26).isActive = true
        let outlineRow = NSStackView(views: [NSTextField(labelWithString: "Outline color"), outlineColor])
        let stack = NSStackView(views: [updates, managerTitle, defaultManagerStatus, managerButtons, managerHint, appearanceHeading, glass, opacityRow, frostingRow, frostingHint, tintRow, description, titlebarHeading, enableTitlebar, titlebarTintRow, titlebarOpacityRow, accentHeading, accentRow, accentHint, outlineHeading, enableOutline, outlineRow])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = BrowserScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.automaticallyAdjustsContentInsets = false
        let document = SettingsContentView(frame: window.contentView!.bounds)
        scroll.documentView = document
        window.contentView!.addSubview(scroll)
        document.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24), stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24), description.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        managerHint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        updates.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        defaultManagerStatus.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        frostingHint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        accentHint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        document.layoutSubtreeIfNeeded()
        document.setFrameSize(NSSize(width: document.frame.width, height: max(scroll.contentSize.height, stack.fittingSize.height + 48)))
        window.center()
        syncAppearanceControls()
        DialogAppearance.install(on: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func resetToDefaults() {
        for well in [tintColor, titlebarColor, accentColor, outlineColor] { well.deactivate() }
        NSColorPanel.shared.orderOut(nil)
        BrowserTheme.resetAppearance()
        syncAppearanceControls()
    }
    private func syncAppearanceControls() {
        glass.state = BrowserTheme.frosted ? .on : .off
        opacity.doubleValue = BrowserTheme.opacity; opacity.isEnabled = BrowserTheme.frosted
        percentage.stringValue = "\(Int(BrowserTheme.opacity * 100))%"
        frosting.doubleValue = BrowserTheme.frosting; frosting.isEnabled = BrowserTheme.frosted
        frostingAmount.stringValue = "\(Int(BrowserTheme.frosting * 100))%"
        tintColor.color = BrowserTheme.pane
        enableTitlebar.state = BrowserTheme.titlebarTintEnabled ? .on : .off
        titlebarColor.color = BrowserTheme.titlebarTint
        titlebarOpacity.doubleValue = BrowserTheme.titlebarOpacity
        titlebarPercentage.stringValue = "\(Int(BrowserTheme.titlebarOpacity * 100))%"
        updateTitlebarControls()
        accentColor.color = BrowserTheme.accentColor
        enableOutline.state = BrowserTheme.outlineEnabled ? .on : .off
        outlineColor.color = BrowserTheme.outlineColor; outlineColor.isEnabled = BrowserTheme.outlineEnabled
    }
    private func updateDefaultManagerStatus() {
        let active = DefaultFileManager.isDefault
        defaultManagerStatus.stringValue = active ? "Explorer is your default file manager." : "Explorer is not your default file manager."
        defaultManagerButton.isEnabled = !active
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
        UserDefaults.standard.set(sender.state == .on, forKey: "frostedPanes")
        opacity.isEnabled = sender.state == .on
        frosting.isEnabled = sender.state == .on
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func opacityChanged() {
        UserDefaults.standard.set(opacity.doubleValue, forKey: "paneOpacity")
        percentage.stringValue = "\(Int(opacity.doubleValue * 100))%"
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func frostingChanged() {
        UserDefaults.standard.set(frosting.doubleValue, forKey: "glassFrosting")
        frostingAmount.stringValue = "\(Int(frosting.doubleValue * 100))%"
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func tintChanged() {
        guard let color = tintColor.color.usingColorSpace(.sRGB) else { return }
        UserDefaults.standard.set([Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)], forKey: "glassTint")
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func resetTint() {
        UserDefaults.standard.removeObject(forKey: "glassTint")
        tintColor.color = BrowserTheme.pane
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func titlebarTintChanged() {
        guard let color = titlebarColor.color.usingColorSpace(.sRGB) else { return }
        UserDefaults.standard.set([Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)], forKey: "titlebarTint")
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func toggleTitlebarTint(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "titlebarTintEnabled")
        updateTitlebarControls()
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    private func updateTitlebarControls() {
        let enabled = BrowserTheme.titlebarTintEnabled
        titlebarColor.isEnabled = enabled
        titlebarOpacity.isEnabled = enabled
        resetTitlebarButton.isEnabled = enabled
        titlebarPercentage.textColor = enabled ? .labelColor : .disabledControlTextColor
    }
    @objc private func titlebarOpacityChanged() {
        UserDefaults.standard.set(titlebarOpacity.doubleValue, forKey: "titlebarOpacity")
        titlebarPercentage.stringValue = "\(Int(titlebarOpacity.doubleValue * 100))%"
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func resetTitlebar() {
        UserDefaults.standard.removeObject(forKey: "titlebarTint")
        UserDefaults.standard.removeObject(forKey: "titlebarOpacity")
        titlebarColor.color = BrowserTheme.titlebarTint
        titlebarOpacity.doubleValue = BrowserTheme.titlebarOpacity
        titlebarPercentage.stringValue = "\(Int(BrowserTheme.titlebarOpacity * 100))%"
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func toggleOutline(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "windowOutlineEnabled")
        outlineColor.isEnabled = sender.state == .on
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func accentChanged() {
        guard let color = accentColor.color.usingColorSpace(.sRGB) else { return }
        UserDefaults.standard.set([Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)], forKey: "accentColor")
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    @objc private func useTitlebarAccent() {
        accentColor.color = BrowserTheme.titlebarTint
        accentChanged()
    }
    @objc private func outlineColorChanged() {
        guard let color = outlineColor.color.usingColorSpace(.sRGB) else { return }
        UserDefaults.standard.set([Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)], forKey: "windowOutlineColor")
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
}

private final class SettingsContentView: NSView {
    override var isFlipped: Bool { true }
}

private final class AnchoredColorWell: NSColorWell {
    override func activate(_ exclusive: Bool) {
        super.activate(exclusive)
        guard let owner = window else { return }
        let picker = NSColorPanel.shared
        DialogAppearance.install(on: picker, fillTitlebar: false)
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
