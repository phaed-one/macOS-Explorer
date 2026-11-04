import AppKit

@MainActor func checkUpdateInterface() throws {
    let updates = UpdateStatusView()
    let button = updates.arrangedSubviews.compactMap { $0 as? NSButton }.first!
    func text() -> String { updates.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: " ") }
    updates.render(.checking)
    try require(!button.isEnabled && text().contains("Checking for updates"), "Quiet checks must show progress only inside Settings")
    updates.render(.available("0.1.5"))
    try require(button.isEnabled && button.title == "Update" && text().contains("0.1.5 is available"), "An available release must expose an Update action and version")
    try require(AppUpdater.State.available("0.1.5").hasUpdate && !AppUpdater.State.current.hasUpdate, "Only available or installing updates should show the Settings badge")
    updates.render(.installing)
    try require(!button.isEnabled && button.title == "Updating…", "Installing must prevent duplicate update actions")
    updates.render(.current)
    try require(button.title == "Check for Updates" && text().contains("up to date"), "Current versions must still allow manual checks")
    updates.render(.failed("Network is offline"))
    try require(button.isEnabled && button.title == "Try Again" && text().contains("Network is offline"), "Offline checks must remain retryable without opening an alert")
    let badge = UpdateBadgeView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
    try require(badge.hitTest(NSPoint(x: 4, y: 4)) == nil, "The update dot must not intercept Settings clicks")
    let settings = SettingsController()
    defer { settings.close() }
    let stack = descendants(settings.window!.contentView!).compactMap { $0 as? NSStackView }.first { $0.arrangedSubviews.first is UpdateStatusView }
    try require(stack != nil, "The Updates section must be at the very top of Settings")
    let idle = AppUpdater.shared.state == .idle
    try require(idle, "Creating windows and settings must not start update checks or popups; startup owns the first probe")
    print("PASS: Quiet update progress, available/current/offline states, Update action, top-of-Settings placement, and non-blocking badge")
}
