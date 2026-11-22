import AppKit
import UniformTypeIdentifiers

/// A throwaway defaults domain, so checks never read or change the user's Open With recents.
private func scratchDefaults() -> (UserDefaults, () -> Void) {
    let suite = "Explorer-OpenWith-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    return (defaults, { defaults.removePersistentDomain(forName: suite) })
}

private func openWithCollection(_ item: NSMenuItem) -> NSCollectionView {
    let content = item.submenu!.items[0].view!
    let scroll = descendants(content).compactMap { $0 as? NSScrollView }.first!
    content.layoutSubtreeIfNeeded(); scroll.tile()
    let collection = scroll.documentView as! NSCollectionView
    collection.layoutSubtreeIfNeeded()
    return collection
}

/// The app names in one section, as their rows read them out.
private func appNames(_ collection: NSCollectionView, section: Int) -> [String] {
    (0..<collection.numberOfItems(inSection: section)).map {
        let item = collection.dataSource!.collectionView(collection, itemForRepresentedObjectAt: IndexPath(item: $0, section: section))
        return item.view.accessibilityLabel() ?? ""
    }
}

private func hasHeader(_ collection: NSCollectionView, section: Int) -> Bool {
    collection.collectionViewLayout!.layoutAttributesForSupplementaryView(ofKind: NSCollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: section)) != nil
}

/// Open With always shows three columns, whichever scroller style macOS picks.
func checkOpenWithColumns() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-OpenWith-\(UUID()).txt")
    try Data().write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let (defaults, cleanup) = scratchDefaults()
    defer { cleanup() }
    for style in [NSScroller.Style.legacy, .overlay] {
        let item = OpenWithMenu(defaults: defaults).makeMenuItem(for: file, defaultApplication: nil) { _, _, _ in }
        let content = item.submenu!.items[0].view!
        let scroll = descendants(content).compactMap { $0 as? NSScrollView }.first!
        scroll.scrollerStyle = style
        content.layoutSubtreeIfNeeded(); scroll.tile()
        let collection = scroll.documentView as! NSCollectionView
        collection.layoutSubtreeIfNeeded()
        // Nothing recent and no default: every app is in the second section.
        let section = 1
        let frames = (0..<min(9, collection.numberOfItems(inSection: section))).map { collection.layoutAttributesForItem(at: IndexPath(item: $0, section: section))!.frame }
        try require(frames.count == 9, "Open With needs installed apps to lay out")
        let columns = Set(frames.map(\.minX)).sorted()
        try require(columns.count == 3, "Open With must show three columns with \(style == .legacy ? "legacy" : "overlay") scrollers, got \(columns), grid \(collection.frame.width), clip \(scroll.contentView.bounds.width), item \(frames[0].width)")
        let gap = columns[1] - (columns[0] + frames[0].width)
        try require(gap == 8 && frames.allSatisfy { $0.maxX <= collection.bounds.width }, "Open With columns must sit close together and fit, gap \(gap)")
        try require(collection.frame.height >= CGFloat(3) * frames[0].height, "Open With must grow tall enough to scroll through every app")
    }
    print("PASS: Open With shows three tightly spaced columns with legacy and overlay scrollers")
}

/// The default and every app chosen before sit in a titled Recent section, and only there.
func checkOpenWithRecents() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-OpenWith-\(UUID()).txt")
    try Data().write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let (defaults, cleanup) = scratchDefaults()
    defer { cleanup() }
    let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
    let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

    let menu = OpenWithMenu(defaults: defaults)
    var collection = openWithCollection(menu.makeMenuItem(for: file, defaultApplication: nil) { _, _, _ in })
    try require(collection.numberOfItems(inSection: 0) == 0 && !hasHeader(collection, section: 0) && !hasHeader(collection, section: 1),
                "With nothing recent, Open With must show one untitled list")

    defaults.set([textEdit.path], forKey: OpenWithMenu.recentsKey)
    var chosen: URL?
    collection = openWithCollection(menu.makeMenuItem(for: file, defaultApplication: calculator) { _, app, _ in chosen = app })
    let recent = appNames(collection, section: 0)
    try require(recent == ["Calculator (current default)", "TextEdit"], "Recent must list the default, then used apps, got \(recent)")
    try require(hasHeader(collection, section: 0) && hasHeader(collection, section: 1), "Both Open With sections must be titled")
    let rest = appNames(collection, section: 1)
    try require(!rest.contains { $0.hasPrefix("Calculator") || $0 == "TextEdit" }, "Recent apps must not repeat in the lower section")
    let headerFrame = collection.collectionViewLayout!.layoutAttributesForSupplementaryView(ofKind: NSCollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 1))!.frame
    let lastRecent = collection.layoutAttributesForItem(at: IndexPath(item: recent.count - 1, section: 0))!.frame
    try require(headerFrame.minY >= lastRecent.maxY, "The second title must sit below the Recent apps")

    // Choosing an app from the lower section moves it to the front of Recent.
    let pick = collection.dataSource!.collectionView(collection, itemForRepresentedObjectAt: IndexPath(item: 0, section: 1))
    _ = pick.view.accessibilityPerformPress()
    try require(chosen != nil, "Pressing an Open With row must choose its app")
    collection = openWithCollection(menu.makeMenuItem(for: file, defaultApplication: calculator) { _, _, _ in })
    let updated = appNames(collection, section: 0)
    try require(updated == ["Calculator (current default)", rest[0], "TextEdit"], "A chosen app must join Recent, newest first, got \(updated)")
    try require(!appNames(collection, section: 1).contains(rest[0]), "A chosen app must leave the lower section")
    print("PASS: Open With lists the default and used apps under Recent, and the rest below")
}

/// A file with no extension lists the app macOS really opens it with: one saved on the file, then
/// the app remembered for its name, then the plain-text default when it is empty or ASCII text.
func checkDefaultApplicationTargets() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-Defaults-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    func file(_ name: String, _ bytes: [UInt8], in directory: URL? = nil) throws -> URL {
        let url = (directory ?? folder).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: url)
        return url
    }
    let text = try file(".env", Array("KEY=value\n".utf8)), empty = try file(".gitkeep", [])
    let binary = try file(".bindot", [0x00, 0x01, 0xFF]), toml = try file("settings.toml", Array("a = 1\n".utf8))
    try require(DefaultApplication.opensAsPlainText(text) && DefaultApplication.opensAsPlainText(empty), "Empty and ASCII files with no extension open as plain text")
    try require(!DefaultApplication.opensAsPlainText(binary) && !DefaultApplication.isPlainASCII(Data("café".utf8)), "Other files with no extension open as data")
    try require([text, empty, binary].allSatisfy { DefaultApplication.target(for: $0) == .sameName }, "Files with no extension take a default by name")
    try require(DefaultApplication.target(for: toml) == .fileType, "Files with an extension keep their own default")

    let (defaults, cleanup) = scratchDefaults()
    defer { cleanup() }
    let names = SameNameDefaults(defaults: defaults, home: folder) { _, _, done in done(nil) }
    if let plainText = NSWorkspace.shared.urlForApplication(toOpen: .plainText) {
        try require(DefaultApplication.application(for: text, names: names) == plainText, "A text file with no extension lists the plain-text default")
    }
    let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
    defaults.set([".env": calculator.path], forKey: SameNameDefaults.key)
    try require(DefaultApplication.application(for: text, names: names) == calculator, "An app remembered for the name wins over the plain-text default")

    // Saving the choice: the chosen file first, then every same-named file outside skipped folders.
    let nested = try file(".env", [], in: folder.appendingPathComponent("project/api"))
    let skipped = try [folder.appendingPathComponent("node_modules/pkg"), folder.appendingPathComponent("Library/App"), folder.appendingPathComponent(".git/x")]
        .map { try file(".env", [], in: $0) }
    var saved: [URL] = []
    let saving = SameNameDefaults(defaults: defaults, home: folder) { _, url, done in saved.append(url.standardizedFileURL); done(nil) }
    let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    var savedError: Error?? = .none, sweptCount: Int?
    saving.set(textEdit, for: text, saved: { savedError = .some($0) }, swept: { sweptCount = $0 })
    try waitUntil { sweptCount != nil }
    try require(savedError != nil && savedError! == nil, "Saving the chosen file's app must report success")
    try require(saved.first == text.standardizedFileURL && Set(saved) == [text.standardizedFileURL, nested.standardizedFileURL] && sweptCount == 1,
                "Every other same-named file in the home folder gets the app, outside Library, node_modules and hidden folders: \(saved), skipped \(skipped.count)")
    try require(saving.application(forName: ".env") == textEdit, "The app is remembered for the name")

    // Files listed later get the remembered app, unless they already have one of their own.
    saved = []
    let later = try file(".env", [], in: folder.appendingPathComponent("later")), own = try file(".env", [], in: folder.appendingPathComponent("own"))
    try require(setxattr(own.path, DefaultApplication.fileChoiceAttribute, [0x01], 1, 0, 0) == 0, "The check needs a saved choice on a file")
    saving.adopt([later, own, toml])
    try require(saved == [later.standardizedFileURL], "Only same-named files without an app of their own adopt the remembered one, got \(saved)")

    let menu = OpenWithMenu(defaults: defaults)
    func checkbox(_ url: URL) -> NSButton {
        let content = menu.makeMenuItem(for: url, defaultApplication: nil) { _, _, _ in }.submenu!.items[0].view!
        return descendants(content).compactMap { $0 as? NSButton }.first { $0.title.hasPrefix("Set as default") }!
    }
    // The menu reuses one checkbox, so read each file's state before configuring the next.
    let textBox = checkbox(text)
    try require(textBox.isEnabled && textBox.title.contains("for all .env files"), "Files with no extension set a default for their name, and say so: \(textBox.title)")
    try require(checkbox(binary).isEnabled, "Binary files with no extension can set a default by name too")
    let tomlBox = checkbox(toml)
    try require(tomlBox.isEnabled && tomlBox.title == "Set as default", "Typed files offer a plain Set as default")
    print("PASS: Files with no extension list the app they really open with, and set defaults by name")
}
