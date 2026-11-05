import AppKit

func checkDialogAppearance() throws {
    let defaults = UserDefaults.standard
    let keys = ["paneOpacity", "frostedPanes", "glassStyle", "glassTintEnabled"].map { BrowserTheme.themedKey($0) }
    let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
    defer {
        for key in keys {
            if let value = saved[key] ?? nil { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    BrowserTheme.setThemed(true, forKey: "frostedPanes"); BrowserTheme.setThemed(true, forKey: "glassTintEnabled"); BrowserTheme.setThemed(0.35, forKey: "paneOpacity")
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-Glass-\(UUID()).txt")
    try Data("Glass dialog check".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let controllers: [NSWindowController] = [SettingsController(), ServerConnectionController(onConnected: { _ in }),
        DiskAccessController(probe: { .granted }), try FileInfoController(url: file), try PermissionsController(urls: [file])]
    defer { controllers.forEach { $0.close() } }
    func background(_ window: NSWindow) throws -> WindowBackdrop {
        guard let view = window.contentView?.subviews.first as? WindowBackdrop else {
            throw NativeCheckError.failed("Every app-owned dialog must use the shared glass background")
        }
        try require(!window.isOpaque && window.backgroundColor == .clear && view.isUsingGlass, "Dialog glass must remain transparent to the desktop")
        if #available(macOS 26, *) {
            try require(descendants(view).contains { $0 is NSGlassEffectView }, "macOS 26 dialogs must use Liquid Glass")
        }
        return view
    }
    for controller in controllers {
        let window = controller.window!
        let view = try background(window)
        window.contentView!.layoutSubtreeIfNeeded()
        try require(view.frame == window.contentView!.bounds, "Glass must fill the dialog without moving its controls")
        try require(window.styleMask.contains(.fullSizeContentView) && window.isMovableByWindowBackground,
            "App dialogs must extend glass through the titlebar and allow background dragging")
        guard let body = window.contentView?.subviews.last else { throw NativeCheckError.failed("Missing dialog body") }
        try require(body.frame.maxY <= window.contentLayoutRect.maxY + 1,
            "Dialog controls must remain below the native titlebar")
        let root = window.contentView!
        let blank = root.convert(NSPoint(x: 4, y: window.contentLayoutRect.midY), to: root.superview)
        try require(root.hitTest(blank) === root && root.mouseDownCanMoveWindow, "Empty dialog space must reach the window-dragging view")
        for button in descendants(body).compactMap({ $0 as? NSButton }) where !button.isHiddenOrHasHiddenAncestor && button.isEnabled {
            let center = NSPoint(x: button.bounds.midX, y: button.bounds.midY)
            guard button.visibleRect.contains(center) else { continue }
            let point = button.convert(center, to: root.superview)
            let hit = root.hitTest(point)
            try require(hit === button || hit?.isDescendant(of: button) == true, "Background drag intercepted \(window.title): \(button.title) / \(button.accessibilityLabel() ?? "") at \(point); hit \(String(describing: hit))")
        }
        if #available(macOS 26, *) {
            let buttons = descendants(body).compactMap { $0 as? NSButton }.filter { $0.isBordered && !($0 is GlassToolbarButton) }
            try require(buttons.allSatisfy { $0.bezelStyle == .glass }, "Dialog push buttons must use their native glass alternative")
        }
        DialogAppearance.install(on: window)
        try require(window.contentView!.subviews.filter { $0 is WindowBackdrop }.count == 1, "Repeated presentation must not stack duplicate glass materials")
    }
    BrowserTheme.setThemed(0.65, forKey: "paneOpacity")
    NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    for controller in controllers {
        let view = try background(controller.window!)
        let tint = NSColor(cgColor: view.tint.layer!.backgroundColor!)!
        try require(abs(tint.alphaComponent - 0.65) < 0.001, "Open dialogs must follow appearance slider changes immediately")
    }
    let alert = NSAlert()
    alert.messageText = "Test dialog"; alert.addButton(withTitle: "Cancel")
    alert.prepareGlassAppearance(); alert.prepareGlassAppearance()
    _ = try background(alert.window)
    try require(alert.buttons.count == 1 && alert.buttons[0].title == "Cancel", "Glass must preserve native alert buttons and behavior")
    print("PASS: Settings, connection, access, file information, permissions and alerts share Liquid Glass, update live, and retain native controls")
}
