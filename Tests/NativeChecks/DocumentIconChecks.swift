import AppKit

private func render(_ image: NSImage, side: Int = 128) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Files macOS has no type for get a page badged with their default app; typed files keep macOS's icon.
func checkDocumentIcons() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-DocumentIcons-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let toml = folder.appendingPathComponent("settings.toml"), dotfile = folder.appendingPathComponent(".gitignore")
    let png = folder.appendingPathComponent("picture.png"), subfolder = folder.appendingPathComponent("folder.toml")
    for file in [toml, dotfile, png] { try Data("a = 1\n".utf8).write(to: file) }
    try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: false)

    try require(DocumentIcon.isUntyped(toml) && DocumentIcon.isUntyped(dotfile), "An unknown extension and a dotfile have no macOS type")
    try require(!DocumentIcon.isUntyped(png) && !DocumentIcon.isUntyped(subfolder), "Typed files and folders keep macOS's icon")
    try require(DocumentIcon.defaultAppIcon(forFile: png) == nil && DocumentIcon.defaultAppIcon(forFile: subfolder) == nil, "Only untyped files take their default app's icon")
    if NSWorkspace.shared.urlForApplication(toOpen: toml) != nil {
        try require(DocumentIcon.defaultAppIcon(forFile: toml) != nil, "An untyped file with a default app must take its icon from that app")
    }

    // An app that ships a document icon for an extension supplies it straight from its bundle.
    let app = folder.appendingPathComponent("Fake.app")
    let resources = app.appendingPathComponent("Contents/Resources")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    let info: [String: Any] = ["CFBundleIdentifier": "test.explorer.fake-\(UUID())", "CFBundleDocumentTypes": [
        ["CFBundleTypeName": "Fake", "CFBundleTypeExtensions": ["TOML"], "CFBundleTypeIconFile": "fake-doc"]
    ]]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
    let redDocument = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }
    try NSBitmapImageRep(data: redDocument.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: resources.appendingPathComponent("fake-doc.png"))
    let shipped = DocumentIcon.documentIcon(in: app, forExtension: "toml").map { render($0) }?.colorAt(x: 64, y: 64)?.usingColorSpace(.sRGB)
    try require(shipped.map { $0.redComponent > 0.8 && $0.greenComponent < 0.2 } == true, "An app's own document icon for an extension must be used")
    try require(DocumentIcon.documentIcon(in: app, forExtension: "properties") == nil, "An app with no icon for an extension supplies none")

    let red = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }
    let labeled = render(DocumentIcon.draw(badge: red, label: "TOML")), bare = render(DocumentIcon.draw(badge: red, label: ""))
    let middle = labeled.colorAt(x: 64, y: 64)!.usingColorSpace(.sRGB)!
    try require(middle.redComponent > 0.8 && middle.greenComponent < 0.2, "The default app's icon must sit in the middle of the page")
    let labelRow = 128 - Int(128 * 0.17)
    try require((30..<98).contains { labeled.colorAt(x: $0, y: labelRow) != bare.colorAt(x: $0, y: labelRow) }, "The extension must be written near the page's foot")
    let small = render(DocumentIcon.draw(badge: red, label: "TOML"), side: 32), smallBare = render(DocumentIcon.draw(badge: red, label: ""), side: 32)
    try require((0..<32).allSatisfy { x in (0..<32).allSatisfy { small.colorAt(x: x, y: $0) == smallBare.colorAt(x: x, y: $0) } }, "Small icons leave the unreadable label off")
    // One cached icon serves the list and the grid, so a small draw must not stick at large sizes.
    let shared = DocumentIcon.draw(badge: red, label: "TOML")
    _ = render(shared, side: 32)
    let large = render(shared)
    try require((30..<98).contains { large.colorAt(x: $0, y: labelRow) != bare.colorAt(x: $0, y: labelRow) }, "A shared icon must regain its label when drawn large")
    print("PASS: Untyped files show their default app's document icon, or a page badged with it")
}
