import AppKit

func checkDialogAppearance() throws {
    let defaults = UserDefaults.standard
    let keys = ["paneOpacity", "frostedPanes", "glassFrosting"]
    let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
    defer {
        for key in keys {
            if let value = saved[key] ?? nil { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    }
    defaults.set(true, forKey: "frostedPanes"); defaults.set(0.35, forKey: "paneOpacity")
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
        DialogAppearance.install(on: window)
        try require(window.contentView!.subviews.filter { $0 is WindowBackdrop }.count == 1, "Repeated presentation must not stack duplicate glass materials")
    }
    defaults.set(0.65, forKey: "paneOpacity")
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
