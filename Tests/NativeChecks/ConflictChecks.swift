import AppKit
import PathfindCore

func checkNameConflictPrompts() throws {
    let suite = "PathfindConflicts." + UUID().uuidString
    let preferences = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite).standardizedFileURL
    let trash = root.appendingPathComponent("trash"), target = root.appendingPathComponent("target"), incoming = root.appendingPathComponent("incoming")
    for folder in [trash, target, incoming] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let store = TrashStore(defaults: preferences, directories: { [trash] }, trashOperation: { source in
        let destination = trash.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.moveItem(at: source, to: destination); return destination
    })
    let names = ["a.txt", "b.txt", "c.txt"]
    for name in names {
        try Data("new".utf8).write(to: incoming.appendingPathComponent(name))
        try Data("old".utf8).write(to: target.appendingPathComponent(name))
    }
    let fresh = incoming.appendingPathComponent("fresh.txt")
    try Data("new".utf8).write(to: fresh)
    let browser = BrowserController(tabs: BrowserTabs(url: target), trashStore: store)
    browser.showWindow(nil); defer { browser.window?.close() }
    try waitUntil { browser.window?.representedURL == target }
    let window = browser.window!
    var answered: NSWindow?
    func sheetButtons() throws -> [String] {
        try waitUntil { window.attachedSheet != nil && window.attachedSheet !== answered }
        return descendants(window.attachedSheet!.contentView!).compactMap { ($0 as? NSButton)?.title }
    }
    func answer(_ button: Int, applyToAll: Bool = false) {
        let sheet = window.attachedSheet!
        answered = sheet
        if applyToAll, let box = descendants(sheet.contentView!).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Apply to All" }) { box.state = .on }
        window.endSheet(sheet, returnCode: NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + button))
    }

    var plan: [(source: URL, conflict: NameConflict)]?
    browser.resolveNameConflicts([fresh], into: target) { plan = $0 }
    try require(window.attachedSheet == nil && plan?.map(\.source) == [fresh], "Items without a clash must go ahead without asking")

    plan = nil
    let one = incoming.appendingPathComponent(names[0])
    browser.resolveNameConflicts([one], into: target) { plan = $0 }
    let single = try sheetButtons()
    try require(single.contains("Replace") && single.contains("Keep Both") && single.contains("Stop") && !single.contains("Skip") && !single.contains("Apply to All"), "A single clash must offer Replace, Keep Both and Stop")
    answer(3 - 1)
    try waitUntil { window.attachedSheet == nil }
    try require(plan == nil, "Stop must cancel the operation")

    plan = nil
    let all = names.map { incoming.appendingPathComponent($0) } + [fresh]
    browser.resolveNameConflicts(all, into: target) { plan = $0 }
    let several = try sheetButtons()
    try require(several.contains("Skip") && several.contains("Apply to All"), "Several clashes must offer Skip and Apply to All")
    answer(2)
    _ = try sheetButtons()
    answer(1, applyToAll: true)
    try waitUntil { plan != nil }
    try require(plan!.map(\.source) == Array(all.dropFirst()), "Skip must leave the item out of the plan")
    try require(plan!.map(\.conflict) == [.keepBoth, .keepBoth, .fail], "Apply to All must answer every remaining clash, and items without a clash must not be changed")

    let table = descendants(window.contentView!).compactMap { $0 as? NSTableView }.first!
    let drag = TestDrag()
    drag.draggingPasteboard.writeObjects([one as NSURL])
    try require(browser.tableView(table, acceptDrop: drag, row: -1, dropOperation: .on), "Dropping onto the folder must be accepted")
    _ = try sheetButtons()
    answer(0)
    let existing = target.appendingPathComponent(names[0])
    try waitUntil { (try? String(contentsOf: existing, encoding: .utf8)) == "new" && browser.canTransferTabs }
    try require((try? String(contentsOf: trash.appendingPathComponent(names[0]), encoding: .utf8)) == "old", "Replace must move the old item to the Trash")
    try require(FileManager.default.fileExists(atPath: one.path), "A replacing copy keeps the source")
    print("PASS: Name clashes ask Replace / Keep Both / Skip / Stop, Apply to All covers the rest, and Replace sends the old item to the Trash")
}
