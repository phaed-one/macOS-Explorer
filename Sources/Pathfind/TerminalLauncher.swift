import AppKit

enum TerminalApp: String, CaseIterable {
    case terminal = "com.apple.Terminal"
    case warp = "dev.warp.Warp-Stable"
    case warpPreview = "dev.warp.Warp-Preview"
    case iterm = "com.googlecode.iterm2"
    case ghostty = "com.mitchellh.ghostty"
    case kitty = "net.kovidgoyal.kitty"
    case alacritty = "org.alacritty"
    case wezterm = "com.github.wez.wezterm"
    case hyper = "co.zeit.hyper"
    case tabby = "org.tabby"
    case rio = "com.raphaelamorim.rio"
    case contour = "org.contourterminal.contour"
    case coolRetroTerm = "com.yourcompany.cool-retro-term"
    case cmux = "com.cmuxterm.app"

    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .warp: return "Warp"
        case .warpPreview: return "Warp Preview"
        case .iterm: return "iTerm2"
        case .ghostty: return "Ghostty"
        case .kitty: return "kitty"
        case .alacritty: return "Alacritty"
        case .wezterm: return "WezTerm"
        case .hyper: return "Hyper"
        case .tabby: return "Tabby"
        case .rio: return "Rio"
        case .contour: return "Contour"
        case .coolRetroTerm: return "Cool Retro Term"
        case .cmux: return "cmux"
        }
    }
    var applicationNames: [String] {
        switch self {
        case .terminal: return ["Terminal.app"]
        case .iterm: return ["iTerm.app", "iTerm2.app"]
        case .coolRetroTerm: return ["cool-retro-term.app"]
        default: return [title + ".app", title.lowercased() + ".app"]
        }
    }
    func applicationURL(workspace: NSWorkspace = .shared) -> URL? {
        if let url = workspace.urlForApplication(withBundleIdentifier: rawValue), FileManager.default.fileExists(atPath: url.path) { return url }
        let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/Applications/Utilities"),
                     URL(fileURLWithPath: "/System/Applications/Utilities"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        // Some Qt builds use generated bundle IDs. Also find their standard app bundles.
        return roots.flatMap { root in applicationNames.map { root.appendingPathComponent($0) } }.first {
            FileManager.default.fileExists(atPath: $0.path) && Bundle(url: $0)?.bundleURL.pathExtension == "app"
        }
    }
    func arguments(for folder: URL) -> [String]? {
        switch self {
        case .kitty: return ["--directory", folder.path]
        case .alacritty: return ["--working-directory", folder.path]
        case .wezterm: return ["start", "--cwd", folder.path]
        case .tabby: return ["open", folder.path]
        case .rio: return ["--working-dir", folder.path]
        case .contour: return ["terminal", "working-directory", folder.path]
        case .coolRetroTerm: return ["--workdir", folder.path]
        default: return nil
        }
    }
    func destination(for folder: URL) -> URL {
        guard self == .warp || self == .warpPreview else { return folder }
        var components = URLComponents()
        components.scheme = self == .warp ? "warp" : "warppreview"
        components.host = "action"; components.path = "/new_window"
        components.queryItems = [URLQueryItem(name: "path", value: folder.path)]
        // Warp treats query strings as form data, where an unescaped + is a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }
}

/// Opens directories through terminal apps' URL handlers, without running shell text.
final class TerminalLauncher: NSObject {
    static let shared = TerminalLauncher()
    struct Request { let folder: URL; let terminal: TerminalApp }
    static var installed: [TerminalApp] {
        TerminalApp.allCases.filter { $0.applicationURL() != nil }
    }
    func appendItem(to menu: NSMenu, folder: URL, applications: [TerminalApp] = TerminalLauncher.installed) {
        guard folder.isFileURL else { return }
        let item = menu.addItem(withTitle: "Open in Terminal", action: nil, keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier("openTerminalHere")
        let alternatives = applications.filter { $0 != .terminal }
        if alternatives.count > 1 {
            let submenu = NSMenu(title: "Open in Terminal")
            for terminal in applications {
                let child = submenu.addItem(withTitle: terminal.title, action: #selector(openFromMenu(_:)), keyEquivalent: "")
                child.target = self; child.representedObject = Request(folder: folder, terminal: terminal)
                child.image = terminal.applicationURL().map { NSWorkspace.shared.icon(forFile: $0.path) }
                child.image?.size = NSSize(width: 16, height: 16)
            }
            item.submenu = submenu
        } else {
            let terminal = alternatives.first ?? .terminal
            item.title = "Open in \(terminal.title)"
            item.target = self; item.action = #selector(openFromMenu(_:))
            item.representedObject = Request(folder: folder, terminal: terminal)
            item.isEnabled = !applications.isEmpty
        }
    }
    @objc private func openFromMenu(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? Request else { return }
        open(request.folder, in: request.terminal, relativeTo: NSApp.keyWindow)
    }
    func open(_ folder: URL, in terminal: TerminalApp, relativeTo window: NSWindow?) {
        func show(_ error: Error) {
            let alert = NSAlert(error: error)
            if let window { alert.beginSheetModal(for: window) }
            else { alert.runModal() }
        }
        guard folder.isFileURL, (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            show(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError,
                         userInfo: [NSLocalizedDescriptionKey: "This folder is no longer available."]))
            return
        }
        guard let application = terminal.applicationURL() else {
            show(NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError,
                         userInfo: [NSLocalizedDescriptionKey: "\(terminal.title) is no longer installed. Reopen the context menu to choose another terminal."]))
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        let completion: (NSRunningApplication?, Error?) -> Void = { _, error in
            if let error { DispatchQueue.main.async { show(error) } }
        }
        if let arguments = terminal.arguments(for: folder) {
            configuration.arguments = arguments
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: application, configuration: configuration, completionHandler: completion)
        } else {
            NSWorkspace.shared.open([terminal.destination(for: folder)], withApplicationAt: application,
                                    configuration: configuration, completionHandler: completion)
        }
    }
}
