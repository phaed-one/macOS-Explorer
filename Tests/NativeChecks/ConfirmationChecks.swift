import AppKit
import PathfindCore

func checkConfirmationPreferences() throws {
    let defaults = UserDefaults.standard
    let saved = ConfirmationPreference.allCases.map { ($0, defaults.object(forKey: $0.rawValue)) }
    defer {
        for (preference, value) in saved {
            if let value { defaults.set(value, forKey: preference.rawValue) }
            else { defaults.removeObject(forKey: preference.rawValue) }
        }
    }
    for preference in ConfirmationPreference.allCases {
        defaults.removeObject(forKey: preference.rawValue)
        try require(preference.isEnabled, "Confirmations must start enabled")
    }
    let settings = SettingsController()
    defer { settings.close() }
    let buttons = descendants(settings.window!.contentView!).compactMap { $0 as? NSButton }
    for preference in ConfirmationPreference.allCases {
        let button = buttons.first { $0.identifier?.rawValue == preference.rawValue }!
        try require(button.state == .on, "Settings must reflect confirmation defaults")
        button.performClick(nil)
        try require(!preference.isEnabled, "Turning off a confirmation must persist immediately")
    }
    let reopened = SettingsController()
    defer { reopened.close() }
    let reopenedButtons = descendants(reopened.window!.contentView!).compactMap { $0 as? NSButton }
    try require(ConfirmationPreference.allCases.allSatisfy { preference in
        reopenedButtons.first { $0.identifier?.rawValue == preference.rawValue }?.state == .off
    }, "Reopened settings must remember disabled confirmations")

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-Confirmations-\(UUID())").standardizedFileURL
    let folder = root.appendingPathComponent("folder"), trash = root.appendingPathComponent("trash")
    for url in [folder, trash] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    let suite = "Explorer-Confirmations-\(UUID())"
    let storeDefaults = UserDefaults(suiteName: suite)!
    defer { storeDefaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let source = folder.appendingPathComponent("test.txt")
    try Data("test".utf8).write(to: source)
    let store = TrashStore(defaults: storeDefaults, directories: { [trash] }, trashOperation: { url in
        let target = trash.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: target)
        return target
    })
    let browser = BrowserController(tabs: BrowserTabs(url: folder), trashStore: store)
    browser.showWindow(nil)
    defer { browser.window?.close() }
    let window = browser.window!
    try waitUntil { window.representedURL == folder }
    let mode = descendants(window.contentView!).compactMap { $0 as? NSSegmentedControl }.first!
    mode.selectedSegment = 0; mode.sendAction(mode.action, to: mode.target)
    let collection = descendants(window.contentView!).compactMap { $0 as? IconCollectionView }.first!
    collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
    ConfirmationPreference.moveToTrash.isEnabled = true
    browser.perform(NSSelectorFromString("trash"))
    try waitUntil { window.attachedSheet != nil }
    try require(FileManager.default.fileExists(atPath: source.path), "Enabled delete confirmation must wait before moving files")
    window.endSheet(window.attachedSheet!, returnCode: .alertSecondButtonReturn)
    try waitUntil { window.attachedSheet == nil }
    ConfirmationPreference.moveToTrash.isEnabled = false
    browser.perform(NSSelectorFromString("trash"))
    try require(window.attachedSheet == nil, "Disabled delete confirmation must not show a sheet")
    try waitUntil { !FileManager.default.fileExists(atPath: source.path) && browser.canTransferTabs }
    let trashed = trash.appendingPathComponent("test.txt")
    try require(FileManager.default.fileExists(atPath: trashed.path), "Delete without confirmation must still move items to Trash")

    let actions = TrashActions(store: store)
    var cleared = false
    let perform: TrashActions.Perform = { operation in
        do { try operation(); cleared = true } catch { assertionFailure("Clear failed: \(error)") }
    }
    ConfirmationPreference.clearTrash.isEnabled = true
    actions.clear(on: window, perform: perform)
    try waitUntil { window.attachedSheet != nil }
    try require(!cleared, "Enabled clear confirmation must wait for approval")
    window.endSheet(window.attachedSheet!, returnCode: .alertFirstButtonReturn)
    try waitUntil { window.attachedSheet == nil }
    try require(!cleared && FileManager.default.fileExists(atPath: trashed.path), "Cancel must preserve Trash")
    ConfirmationPreference.clearTrash.isEnabled = false
    actions.clear(on: window, perform: perform)
    try require(cleared && window.attachedSheet == nil && !FileManager.default.fileExists(atPath: trashed.path), "Disabled clear confirmation must clear Trash without a sheet")
    print("PASS: Confirmation settings persist and independently control Move to Trash and Clear Trash")
}
