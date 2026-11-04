import AppKit
import Darwin

private final class AccessFixture {
    private let lock = NSLock()
    private var value: DiskAccessStatus
    init(_ value: DiskAccessStatus) { self.value = value }
    func set(_ value: DiskAccessStatus) { lock.lock(); self.value = value; lock.unlock() }
    func read() -> DiskAccessStatus { lock.lock(); defer { lock.unlock() }; return value }
}

func checkDiskAccessOnboarding() throws {
    let first = URL(fileURLWithPath: "/first"), second = URL(fileURLWithPath: "/second")
    let paths = [first, second]
    try require(DiskAccessProbe.status(directories: paths, attempt: { _ in EPERM }) == .denied, "A privacy denial must trigger onboarding")
    try require(DiskAccessProbe.status(directories: paths, attempt: { $0 == first ? EPERM : nil }) == .granted, "A readable protected folder must establish effective access")
    try require(DiskAccessProbe.status(directories: paths, attempt: { _ in ENOENT }) == .unknown, "Missing protected folders must not imply disabled permission")
    try require(DiskAccessProbe.status(directories: paths, attempt: { _ in EACCES }) == .unknown, "Ordinary UNIX access restrictions must not be misreported as Full Disk Access being off")
    try require(DiskAccessProbe.status(directories: [], attempt: { _ in nil }) == .unknown, "An unavailable probe must remain unknown")
    let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-Access-\(UUID())")
    try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fixture) }
    try require(DiskAccessProbe.directoryError(fixture) == nil, "Directory probes must handle empty accessible directories")
    try require(DiskAccessProbe.directoryError(fixture.appendingPathComponent("missing")) == ENOENT, "Directory probes must preserve the actual filesystem error")

    let value = AccessFixture(.denied)
    var refreshes = 0
    let controller = DiskAccessController(probe: { value.read() }, onAccessGranted: { refreshes += 1 })
    defer { controller.close() }
    controller.start()
    try waitUntil { controller.status == .denied && controller.window?.isVisible == true }
    let content = controller.window!.contentView!
    let buttons = descendants(content).compactMap { $0 as? NSButton }
    try require(buttons.contains { $0.title == "Open System Settings…" } && buttons.contains { $0.title == "Restart Explorer" }, "Startup must present settings and relaunch actions directly")
    try require(buttons.contains { $0.title == "Continue with Limited Access" }, "Users must be able to continue if they cannot grant access")
    content.layoutSubtreeIfNeeded()
    for button in buttons {
        try require(content.bounds.contains(button.convert(button.bounds, to: content)), "Permission actions must fit inside the popup")
    }
    value.set(.granted)
    // No explicit check: the visible prompt must close itself when access works.
    try waitUntil { controller.status == .granted && controller.window?.isVisible == false && refreshes == 1 }
    value.set(.denied); controller.check()
    try waitUntil { controller.status == .denied && controller.window?.isVisible == true }
    controller.close(); controller.check()
    try waitUntil { !controller.isChecking }
    try require(controller.window?.isVisible == false, "Dismissing the prompt must not reopen it repeatedly during the same session")

    for status in [DiskAccessStatus.granted, .unknown] {
        let silent = DiskAccessController(probe: { status })
        silent.start()
        try waitUntil { !silent.isChecking }
        try require(silent.window?.isVisible == false, "Granted and unverifiable access must not show a false denial popup")
        silent.close()
    }
    let settings = SettingsController()
    defer { settings.close() }
    let labels = descendants(settings.window!.contentView!).compactMap { ($0 as? NSTextField)?.stringValue }
    try require(!labels.contains("Filesystem Access"), "Permission setup must no longer be hidden in Settings")
    print("PASS: Privacy/UNIX/missing-path classification, startup prompt, automatic grant dismissal, browser refresh callback, one-session dismissal, and no false permission popup")
}
