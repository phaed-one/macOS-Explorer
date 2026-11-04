import AppKit
import Sparkle

/// Owns update checks. Probing checks never display Sparkle's update UI.
@MainActor final class AppUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()
    static let changed = Notification.Name("ExplorerUpdateStateChanged")
    enum State: Equatable {
        case idle, checking, current, available(String), installing, failed(String)
        var hasUpdate: Bool { if case .available = self { return true }; return self == .installing }
    }
    private(set) var state: State = .idle {
        didSet { NotificationCenter.default.post(name: Self.changed, object: self) }
    }
    private var started = false
    private lazy var driver = SPUStandardUserDriver(hostBundle: .main, delegate: nil)
    private lazy var updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
    func start() {
        guard !started else { return }
        do {
            try updater.start()
            started = true
            checkQuietly()
        } catch { state = .failed(error.localizedDescription) }
    }
    func checkQuietly() {
        guard started else { start(); return }
        guard !updater.sessionInProgress else { return }
        state = .checking
        updater.checkForUpdateInformation()
    }
    func installUpdate() {
        guard started, updater.canCheckForUpdates else { return }
        updater.checkForUpdates()
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        state = .available(item.displayVersionString)
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) { state = .current }
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        state = .installing
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error, state != .current { state = .failed(error.localizedDescription) }
        else if state == .checking { state = .current }
    }
}

@MainActor final class UpdateStatusView: NSStackView {
    private let message = NSTextField(wrappingLabelWithString: "")
    private let action = NSButton(title: "Check for Updates", target: nil, action: nil)
    init() {
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 10
        let heading = NSTextField(labelWithString: "Updates")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
        let current = NSTextField(labelWithString: "Installed: Explorer \(version)")
        current.textColor = .secondaryLabelColor
        action.target = self; action.action = #selector(clicked)
        action.setAccessibilityLabel("Software update action")
        message.maximumNumberOfLines = 2
        message.heightAnchor.constraint(equalToConstant: 36).isActive = true
        for view in [heading, current, message, action] { addArrangedSubview(view) }
        message.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: AppUpdater.changed, object: nil)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func refresh() { render(AppUpdater.shared.state) }
    func render(_ state: AppUpdater.State) {
        action.isEnabled = true; action.title = "Check for Updates"
        message.toolTip = nil
        switch state {
        case .idle: message.stringValue = "Explorer checks quietly for updates when it starts."
        case .checking: message.stringValue = "Checking for updates…"; action.isEnabled = false
        case .current: message.stringValue = "You’re up to date."
        case .available(let version): message.stringValue = "Explorer \(version) is available."; action.title = "Update"
        case .installing: message.stringValue = "Updating Explorer…"; action.title = "Updating…"; action.isEnabled = false
        case .failed(let reason): message.stringValue = "Couldn’t check for updates. \(reason)"; message.toolTip = reason; action.title = "Try Again"
        }
    }
    @objc private func clicked() {
        if AppUpdater.shared.state.hasUpdate { AppUpdater.shared.installUpdate() }
        else { AppUpdater.shared.checkQuietly() }
    }
}

final class UpdateBadgeView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemOrange.setFill(); NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
    }
}
