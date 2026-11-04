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

    init(probe: @escaping () -> DiskAccessStatus = { DiskAccessProbe.status() }, onAccessGranted: @escaping () -> Void = {}) {
        self.probe = probe; self.onAccessGranted = onAccessGranted
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 550, height: 365),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isFloatingPanel = false; panel.level = .normal; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.title = "Enable Full Disk Access"; panel.delegate = self
        let title = NSTextField(wrappingLabelWithString: "Allow Explorer to browse protected folders")
        title.font = .systemFont(ofSize: 19, weight: .semibold)
        let instructions = NSTextField(wrappingLabelWithString: "Explorer needs Full Disk Access to browse folders such as Mail and Messages.\n\n1. Open System Settings below.\n2. Turn on Explorer under Full Disk Access. If it’s missing, add Explorer.app with the + button.\n3. If macOS asks, choose Quit & Reopen.")
        instructions.textColor = .secondaryLabelColor
        let buttons = NSStackView(views: [NSButton(title: "Open System Settings…", target: self, action: #selector(openSettings)),
            NSButton(title: "Show Explorer.app", target: self, action: #selector(revealApp)), restartButton])
        restartButton.target = self; restartButton.action = #selector(restart)
        statusLabel.font = .systemFont(ofSize: 12); statusLabel.textColor = .secondaryLabelColor
        statusLabel.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let appPath = NSTextField(wrappingLabelWithString: Bundle.main.bundleURL.path)
        appPath.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        appPath.textColor = .secondaryLabelColor; appPath.isSelectable = true
        let later = NSButton(title: "Continue with Limited Access", target: self, action: #selector(continueForNow))
        let stack = NSStackView(views: [title, instructions, buttons, statusLabel, appPath, later])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = panel.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24)])
        for label in [title, instructions, statusLabel, appPath] { label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        content.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: 550, height: stack.fittingSize.height + 48))
        panel.center()
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
            statusLabel.stringValue = "This window closes when access works. If you enabled it and it’s still blocked, restart Explorer."
            if timer == nil {
                showWindow(nil); window?.makeKeyAndOrderFront(nil)
                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
                self.timer = timer; RunLoop.main.add(timer, forMode: .common)
            }
        } else if result == .unknown, window?.isVisible == true {
            statusLabel.stringValue = "Couldn’t confirm access yet. If you already enabled it, restart Explorer."
        }
    }
    func windowWillClose(_ notification: Notification) {
        timer?.invalidate(); timer = nil
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
