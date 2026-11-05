import AppKit
import Darwin

enum DiskAccessStatus { case granted, denied, unknown }

/// Public filesystem operations test effective access; there is no public FDA status API.
/// Never inspect TCC databases or read the contents of a user's protected files.
enum DiskAccessProbe {
    static var directories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Library/Mail", "Library/Messages", "Library/Safari"].map { home.appendingPathComponent($0, isDirectory: true) }
    }
    static func status(directories: [URL] = directories, attempt: (URL) -> Int32? = directoryError) -> DiskAccessStatus {
        var privacyDenied = false
        for directory in directories {
            guard let error = attempt(directory) else { return .granted }
            if error == EPERM { privacyDenied = true }
        }
        // Missing paths and ordinary UNIX permission failures do not prove FDA is off.
        return privacyDenied ? .denied : .unknown
    }
    static func directoryError(_ url: URL) -> Int32? {
        guard let directory = opendir(url.path) else { return errno }
        defer { closedir(directory) }
        errno = 0
        _ = readdir(directory)
        return errno == 0 ? nil : errno
    }
}

final class DiskAccessController: NSWindowController, NSWindowDelegate {
    private let probe: () -> DiskAccessStatus
    private let onAccessGranted: () -> Void
    private let queue = DispatchQueue(label: "explorer.disk-access", qos: .userInitiated)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let restartButton = NSButton(title: "Restart Explorer", target: nil, action: nil)
    private var timer: Timer?
    private(set) var isChecking = false
    private var started = false
    private var dismissedForSession = false
    private var closingAfterGrant = false
    private(set) var status: DiskAccessStatus = .unknown

    private let spinner = NSProgressIndicator()
    private static let width: CGFloat = 620

    init(probe: @escaping () -> DiskAccessStatus = { DiskAccessProbe.status() }, onAccessGranted: @escaping () -> Void = {}) {
        self.probe = probe; self.onAccessGranted = onAccessGranted
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 380),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isFloatingPanel = false; panel.level = .normal; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.title = "Enable Full Disk Access"; panel.delegate = self
        let inner = Self.width - 48

        // Header: what's needed, and why.
        let symbol = NSImageView(image: NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)!)
        symbol.symbolConfiguration = .init(pointSize: 22, weight: .semibold)
        symbol.contentTintColor = .white
        let badge = Self.circle(diameter: 44, color: .controlAccentColor, holding: symbol)
        let title = NSTextField(labelWithString: "Explorer needs Full Disk Access")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "macOS blocks protected folders, such as Mail, Messages and Safari, until you allow it.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.preferredMaxLayoutWidth = inner - 58
        let titles = NSStackView(views: [title, subtitle])
        titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 3
        let header = NSStackView(views: [badge, titles])
        header.alignment = .centerY; header.spacing = 14

        // Steps: each action sits next to the step it belongs to.
        restartButton.target = self; restartButton.action = #selector(restart)
        let steps = [
            ("Open Privacy & Security → Full Disk Access.", NSButton(title: "Open System Settings…", target: self, action: #selector(openSettings))),
            ("Turn on Explorer. If it isn’t listed, click + and add Explorer.app.", NSButton(title: "Show Explorer.app", target: self, action: #selector(revealApp))),
            ("If macOS asks, choose Quit & Reopen. Otherwise, restart Explorer.", restartButton)]
        let grid = NSGridView(views: steps.enumerated().map { index, step in
            let label = NSTextField(wrappingLabelWithString: step.0)
            label.preferredMaxLayoutWidth = inner - 32 - 24 - 200 - 24
            return [Self.stepNumber(index + 1), label, step.1]
        })
        grid.rowSpacing = 14; grid.columnSpacing = 12
        grid.column(at: 1).width = inner - 32 - 24 - 200 - 24
        grid.column(at: 2).xPlacement = .trailing
        grid.column(at: 2).width = 200
        for index in 0..<grid.numberOfRows { grid.row(at: index).yPlacement = .center }
        let stepsCard = SettingsCard(title: nil, width: inner, content: [grid])

        // Status: the window closes itself once access works.
        spinner.style = .spinning; spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        statusLabel.font = .systemFont(ofSize: 12); statusLabel.textColor = .secondaryLabelColor
        statusLabel.preferredMaxLayoutWidth = inner - 24
        statusLabel.stringValue = "Waiting for access… This window closes on its own once it works."
        let status = NSStackView(views: [spinner, statusLabel])
        status.alignment = .centerY; status.spacing = 8

        // Footer: where the app is (for the + button), and a way out.
        let appPath = NSTextField(labelWithString: Bundle.main.bundleURL.path)
        appPath.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        appPath.textColor = .tertiaryLabelColor; appPath.isSelectable = true
        appPath.lineBreakMode = .byTruncatingMiddle
        appPath.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let later = NSButton(title: "Continue with Limited Access", target: self, action: #selector(continueForNow))
        let footer = NSStackView(views: [appPath, later])
        footer.alignment = .centerY; footer.spacing = 16
        footer.widthAnchor.constraint(equalToConstant: inner).isActive = true

        let stack = NSStackView(views: [header, stepsCard, status, footer])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.setCustomSpacing(20, after: header)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = panel.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24)])
        content.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: Self.width, height: stack.fittingSize.height + 36))
        panel.center()
        DialogAppearance.install(on: panel)
    }
    /// A filled circle with a view centered in it.
    private static func circle(diameter: CGFloat, color: NSColor, holding inner: NSView) -> NSView {
        let circle = NSView()
        circle.wantsLayer = true; circle.layer?.cornerRadius = diameter / 2
        circle.layer?.backgroundColor = color.cgColor
        circle.translatesAutoresizingMaskIntoConstraints = false
        inner.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(inner)
        NSLayoutConstraint.activate([circle.widthAnchor.constraint(equalToConstant: diameter), circle.heightAnchor.constraint(equalToConstant: diameter),
            inner.centerXAnchor.constraint(equalTo: circle.centerXAnchor), inner.centerYAnchor.constraint(equalTo: circle.centerYAnchor)])
        return circle
    }
    private static func stepNumber(_ number: Int) -> NSView {
        let digit = NSTextField(labelWithString: "\(number)")
        digit.font = .systemFont(ofSize: 12, weight: .bold)
        digit.textColor = .controlAccentColor
        return circle(diameter: 24, color: NSColor.controlAccentColor.withAlphaComponent(0.18), holding: digit)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate(); NotificationCenter.default.removeObserver(self) }
    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(self, selector: #selector(check), name: NSApplication.didBecomeActiveNotification, object: nil)
        check()
    }
    @objc func check() {
        guard !isChecking else { return }
        isChecking = true
        let probe = self.probe
        queue.async { [weak self] in
            let result = probe()
            DispatchQueue.main.async { self?.apply(result) }
        }
    }
    private func apply(_ result: DiskAccessStatus) {
        isChecking = false
        let previous = status
        status = result
        if result == .granted {
            timer?.invalidate(); timer = nil
            closingAfterGrant = true; close(); closingAfterGrant = false
            if previous == .denied { onAccessGranted() }
        } else if result == .denied, !dismissedForSession {
            statusLabel.stringValue = "Waiting for access… This window closes on its own once it works."
            spinner.startAnimation(nil)
            if timer == nil {
                showWindow(nil); window?.makeKeyAndOrderFront(nil)
                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
                self.timer = timer; RunLoop.main.add(timer, forMode: .common)
            }
        } else if result == .unknown, window?.isVisible == true {
            statusLabel.stringValue = "Couldn’t confirm access yet. If you already turned it on, restart Explorer."
            spinner.stopAnimation(nil)
        }
    }
    func windowWillClose(_ notification: Notification) {
        timer?.invalidate(); timer = nil
        spinner.stopAnimation(nil)
        if !closingAfterGrant { dismissedForSession = true }
    }
    @objc private func continueForNow() { close() }
    @objc private func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        if !NSWorkspace.shared.open(url) { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
    }
    @objc private func revealApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    @objc private func restart() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { statusLabel.stringValue = "Quit and reopen Explorer to apply the new permission."; return }
        restartButton.isEnabled = false
        let configuration = NSWorkspace.OpenConfiguration(); configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error { self?.statusLabel.stringValue = error.localizedDescription; self?.restartButton.isEnabled = true }
                else { NSApp.terminate(nil) }
            }
        }
    }
}
