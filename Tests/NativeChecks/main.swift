import AppKit
import PathfindCore

enum NativeCheckError: Error { case failed(String) }
func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NativeCheckError.failed(message) }
}
func waitUntil(_ condition: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(10)
    while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    try require(condition(), "Timed out waiting for folder load")
}
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let defaults = UserDefaults.standard
let savedKeys = ["explicitExpandedTreePaths", "collapsedTreeGroups", "hiddenVolumes", "frostedPanes", "paneOpacity", "glassTint", "browserTabs", "titlebarTint", "titlebarOpacity", "titlebarTintEnabled", "accentColor", "windowOutlineEnabled", "windowOutlineColor", "glassFrosting", "glassFrosted", "glassStyle", "glassTintEnabled", "defaultShowHiddenFiles", "folderHiddenFiles", "filesystemShowHiddenDefaultApplied", "favorites"]
// Also save each theme's own appearance values, without repeating keys already listed.
let allSavedKeys = savedKeys + BrowserTheme.appearancePreferenceKeys.filter { !savedKeys.contains($0) }
let saved = Dictionary(uniqueKeysWithValues: allSavedKeys.map { ($0, defaults.object(forKey: $0)) })
// Old shared appearance values would stand in for per-theme ones; start every run without them.
BrowserTheme.themedKeys.forEach(defaults.removeObject(forKey:))
defer {
    for key in allSavedKeys {
        if let value = saved[key] ?? nil { defaults.set(value, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
}
do {
    BrowserTheme.setThemed(true, forKey: "frostedPanes")
    BrowserTheme.setThemed(true, forKey: "glassTintEnabled")
    BrowserTheme.setThemed(nil, forKey: "glassTint")
    defaults.removeObject(forKey: "browserTabs")
    for appearanceName in [NSAppearance.Name.darkAqua, .aqua] {
        let appearance = NSAppearance(named: appearanceName)!
        let pane = WindowBackdrop(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        pane.appearance = appearance
        for opacity in [0.01, 0.25, 0.5, 0.75, 1.0] {
            BrowserTheme.setThemed(opacity, forKey: "paneOpacity")
            appearance.performAsCurrentDrawingAppearance { pane.refresh() }
            let tint = pane.tint
            let color = NSColor(cgColor: tint.layer!.backgroundColor!)!.usingColorSpace(.deviceRGB)!
            try require(abs(color.alphaComponent - opacity) < 0.001, "Opacity must use the entire 0–100% range")
            let expected: CGFloat = appearanceName == .darkAqua ? 0 : 1
            try require(abs(color.redComponent - expected) < 0.001 && abs(color.greenComponent - expected) < 0.001 && abs(color.blueComponent - expected) < 0.001, "Tint must stay black/white without a gray overlay")
            try require(pane.contentView.alphaValue == 1, "Pane contents must remain opaque")
            if opacity == 1 {
                try require(!pane.isUsingGlass, "Endpoints must bypass all material effects")
            }
        }
    }
    BrowserTheme.setThemed(0, forKey: "paneOpacity")
    try require(BrowserTheme.opacity == 0.01, "Saved zero opacity must be clamped to the 1% minimum")
    print("PASS: Native pane opacity at 1%, 25%, 50%, 75%, 100% in dark and light appearances")
    BrowserTheme.setThemed([0.15, 0.35, 0.55], forKey: "glassTint")
    let custom = BrowserTheme.pane.usingColorSpace(.sRGB)!
    try require(abs(custom.redComponent - 0.15) < 0.001 && abs(custom.blueComponent - 0.55) < 0.001, "Custom glass tint must persist its RGB color")
    BrowserTheme.setThemed(nil, forKey: "glassTint")
    print("PASS: Custom glass tint")
    let glassTintBefore = BrowserTheme.pane.usingColorSpace(.sRGB)
    BrowserTheme.setThemed(nil, forKey: "accentColor")
    BrowserTheme.setThemed([0.2, 0.3, 0.5], forKey: "titlebarTint")
    BrowserTheme.setThemed(0.4, forKey: "titlebarOpacity")
    try require(abs(BrowserTheme.titlebarTint.usingColorSpace(.sRGB)!.blueComponent - 0.5) < 0.001 && BrowserTheme.titlebarOpacity == 0.4, "Titlebar tint and opacity must persist")
    BrowserTheme.initializeAccent()
    let seededAccent = BrowserTheme.accentColor.usingColorSpace(.sRGB)
    try require(seededAccent == BrowserTheme.titlebarTint.usingColorSpace(.sRGB), "Accent must start with the current titlebar tint")
    BrowserTheme.setThemed([0.7, 0.2, 0.1], forKey: "titlebarTint")
    BrowserTheme.initializeAccent()
    try require(BrowserTheme.accentColor.usingColorSpace(.sRGB) == seededAccent, "Changing titlebar tint or restarting must preserve independent Accent")
    try require(BrowserTheme.pane.usingColorSpace(.sRGB) == glassTintBefore, "Titlebar tint must not change glass tint")
    let browser = BrowserController()
    let window = browser.window!
    window.orderFront(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    for size in [NSSize(width: 1120, height: 740), NSSize(width: 900, height: 440), NSSize(width: 1500, height: 1000)] {
        window.setContentSize(size)
        for opacity in [0.01, 0.5, 1.0, 0.25, 0.01] {
            BrowserTheme.setThemed(opacity, forKey: "paneOpacity")
            NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
            window.contentView!.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            let split = descendants(window.contentView!).compactMap { $0 as? NSSplitView }.first!
            let root = descendants(window.contentView!).compactMap { $0 as? ChromeView }.first!
            try require(abs(root.frame.width - size.width) < 1 && abs(root.frame.height - size.height) < 1, "Glass content must stay within the actual window: root \(root.frame), window \(size)")
            let tabs = descendants(root).compactMap { $0 as? TabStrip }.first!
            try require(window.contentView!.bounds.contains(tabs.convert(tabs.bounds, to: window.contentView!)), "Tabs must remain visible inside the window")
            try require(descendants(window.contentView!).filter { $0 is WindowBackdrop }.count == 1, "The whole window must share exactly one glass surface")
            try require(split.frame.height >= 200, "File panes collapsed below usable height")
            for pane in split.subviews.compactMap({ $0 as? BrowserViewport }) {
                pane.layoutSubtreeIfNeeded()
                try require(pane.frame.height >= 200, "Pane container lost its height")
                for scroll in pane.subviews.compactMap({ $0 as? NSScrollView }) {
                    try require(scroll.frame.height >= 200, "Scroll viewport collapsed at opacity \(opacity), size \(size); pane \(pane.frame), scroll \(scroll.frame)")
                }
            }
        }
    }
    print("PASS: Full browser layout at three window sizes while crossing transparent, glass, and opaque modes")
    let scrolling = BrowserScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    let scrollingDocument = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
    scrolling.documentView = scrollingDocument
    try require(scrolling.routesWheelHorizontally, "Horizontal-only overflow must route the wheel sideways")
    let wheelEvent = NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -3, wheel2: 0, wheel3: 0)!)!
    scrolling.scrollWheel(with: wheelEvent)
    try require(scrolling.contentView.bounds.minX > 0, "A vertical wheel event must actually move a horizontal-only pane")
    scrollingDocument.setFrameSize(NSSize(width: 600, height: 400))
    try require(!scrolling.routesWheelHorizontally, "Vertical must win when both axes overflow")
    scrollingDocument.setFrameSize(NSSize(width: 100, height: 400))
    try require(!scrolling.routesWheelHorizontally, "Vertical-only overflow must preserve native scrolling")
    print("PASS: Wheel chooses horizontal-only overflow and prioritizes vertical when both overflow")
    let headerScroll = BrowserScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    let headerTable = NSTableView(frame: NSRect(x: 0, y: 0, width: 800, height: 100))
    headerTable.columnAutoresizingStyle = .noColumnAutoresizing
    for name in ["Name", "Size"] { let column = NSTableColumn(identifier: .init(name)); column.width = 400; headerTable.addTableColumn(column) }
    headerScroll.documentView = headerTable; headerScroll.hasHorizontalScroller = true
    headerScroll.tile()
    headerScroll.scrollWheel(with: wheelEvent)
    let headerClip = headerTable.headerView!.superview as! NSClipView
    try require(headerScroll.contentView.bounds.minX > 0 && abs(headerClip.bounds.minX - headerScroll.contentView.bounds.minX) < 0.5, "Details column headers and contents must scroll together")
    print("PASS: Details headers stay aligned with content during horizontal wheel scrolling")
    let controlWindow = BrowserWindow(contentRect: NSRect(x: 200, y: 200, width: 500, height: 350), styleMask: [.borderless, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    controlWindow.isReleasedWhenClosed = false
    controlWindow.orderFront(nil)
    let normalFrame = controlWindow.frame
    controlWindow.performZoom(nil)
    try require(controlWindow.frame != normalFrame, "Custom maximize must resize the window instead of beeping")
    controlWindow.performZoom(nil)
    try require(controlWindow.frame == normalFrame, "Maximize must restore the previous frame")
    app.setActivationPolicy(.regular)
    controlWindow.performMiniaturize(nil)
    try waitUntil { controlWindow.isMiniaturized }
    controlWindow.deminiaturize(nil)
    controlWindow.performClose(nil)
    app.setActivationPolicy(.prohibited)
    try require(!controlWindow.isVisible, "Custom close must close the window instead of beeping")
    print("PASS: Custom window buttons close, minimize, maximize, and restore")
    for button in descendants(window.contentView!).compactMap({ $0 as? GlassToolbarButton }) {
        try require(abs(button.frame.width - button.frame.height) < 0.5, "Toolbar buttons must have square frames, including native alignment insets")
    }
    let headerFields = descendants(window.contentView!).compactMap { $0 as? HeaderTextField }
    try require(headerFields.count == 2 && abs(headerFields[0].frame.height - headerFields[1].frame.height) < 0.5, "Path and search must use matching heights")
    for field in headerFields {
        try require(field.focusRingType == .none && field.cell!.focusRingType == .none, "Path and search must not draw focus rings")
        let textRect = field.cell!.drawingRect(forBounds: field.bounds)
        try require(abs(textRect.midY - field.bounds.midY) < 0.5, "Header text must be vertically centered")
    }
    print("PASS: Square toolbar buttons, matching rectangular fields, centered text, and independent titlebar tint")
    BrowserTheme.setThemed(0.5, forKey: "paneOpacity")
    NotificationCenter.default.post(name: BrowserTheme.changed, object: nil)
    window.contentView!.layoutSubtreeIfNeeded()
    let tabButton = descendants(window.contentView!).compactMap { $0 as? NSButton }.first { $0.accessibilityHelp()?.hasPrefix("/") == true }!
    let surface = window.contentView!
    let point = tabButton.convert(NSPoint(x: tabButton.bounds.midX, y: tabButton.bounds.midY), to: surface.superview)
    let hit = surface.hitTest(point)
    try require(hit === tabButton || hit?.isDescendant(of: tabButton) == true, "Glass must not intercept clicks on tab buttons; hit \(String(describing: hit)), point \(point), button \(tabButton.frame)")
    for y in [CGFloat(1), tabButton.bounds.height - 1] {
        let edge = tabButton.convert(NSPoint(x: tabButton.bounds.midX, y: y), to: surface.superview)
        let edgeHit = surface.hitTest(edge)
        try require(edgeHit === tabButton || edgeHit?.isDescendant(of: tabButton) == true, "The top and bottom of a tab must both be clickable")
    }
    let originalFolder = FileManager.default.homeDirectoryForCurrentUser
    let plus = descendants(surface).compactMap { $0 as? NSButton }.first { $0.accessibilityHelp() == "New tab (⌘T)" }!
    plus.performClick(nil)
    browser.navigate(URL(fileURLWithPath: "/tmp"))
    try waitUntil { window.representedURL?.path == "/tmp" }
    let originalTab = descendants(surface).compactMap { $0 as? NSButton }.first { $0.accessibilityHelp() == originalFolder.path }!
    try require(originalTab.superview?.layer?.backgroundColor?.alpha == 0, "Inactive tabs must have transparent backgrounds")
    try require(!plus.isBordered && !originalTab.isBordered, "Tabs and the new-tab button must retain their original flat appearance")
    let closeTabButtons = descendants(surface).compactMap { $0 as? NSButton }.filter { $0.accessibilityHelp() == "Close tab (⌘W)" }
    try require(!closeTabButtons.isEmpty && closeTabButtons.allSatisfy { !$0.isBordered }, "Tab close buttons must remain plain icons")
    originalTab.performClick(nil)
    try waitUntil { window.representedURL?.path == originalFolder.path }
    print("PASS: Glass forwards tab clicks and native tab buttons switch folders")
    let menuFixture = FileManager.default.temporaryDirectory.appendingPathComponent("PathfindNativeMenu-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: menuFixture, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: menuFixture) }
    let infoFile = menuFixture.appendingPathComponent("sample.txt")
    try Data(repeating: 65, count: 128).write(to: infoFile)
    try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: infoFile.path)
    browser.navigate(menuFixture)
    try waitUntil { window.representedURL?.path == menuFixture.path }
    let modeControl = descendants(window.contentView!).compactMap { $0 as? NSSegmentedControl }.first!
    modeControl.selectedSegment = 0
    modeControl.sendAction(modeControl.action, to: modeControl.target)
    let menuCollection = descendants(window.contentView!).compactMap { $0 as? IconCollectionView }.first!
    let contextMenu = menuCollection.menu!
    menuCollection.deselectAll(nil)
    browser.menuNeedsUpdate(contextMenu)
    try require(contextMenu.items.prefix(4).map(\.title) == ["New Folder…", "New File…", "Paste", "Refresh"] && contextMenu.items.count == 5 && contextMenu.items.last?.identifier?.rawValue == "openTerminalHere", "Background menu must contain folder-background commands and a terminal action")
    menuCollection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
    browser.menuNeedsUpdate(contextMenu)
    try require(contextMenu.items.contains { $0.title == "Get Info" } && contextMenu.items.contains { $0.title == "Duplicate" } && !contextMenu.items.contains { $0.title.hasPrefix("New ") }, "Item menus must offer Get Info and Duplicate without creation commands")
    let infoItem = contextMenu.items.first { $0.title == "Get Info" }!
    app.sendAction(infoItem.action!, to: infoItem.target, from: infoItem)
    let infoWindow = app.windows.first { $0.title == "sample.txt Info" }
    try require(infoWindow?.isVisible == true, "Get Info context action must open the selected item's information window")
    let infoText = descendants(infoWindow!.contentView!).compactMap { ($0 as? NSTextField)?.stringValue }
    try require(infoText.contains(infoFile.path) && infoText.contains("0640") && infoText.contains { $0.contains("128 bytes") }, "Get Info must show the real path, size, and permissions")
    infoWindow!.performClose(nil)
    browser.navigate(originalFolder)
    try waitUntil { window.representedURL?.path == originalFolder.path }
    print("PASS: Background/item context menus are distinct and Get Info opens real item metadata")
    let settings = SettingsController()
    let accentWell = descendants(settings.window!.contentView!).compactMap { $0 as? NSColorWell }.first { $0.action == NSSelectorFromString("accentChanged") }!
    accentWell.color = NSColor(srgbRed: 0.1, green: 0.35, blue: 0.6, alpha: 1)
    accentWell.sendAction(accentWell.action, to: accentWell.target)
    try require(abs(BrowserTheme.accentColor.usingColorSpace(.sRGB)!.blueComponent - 0.6) < 0.001 && abs(BrowserTheme.titlebarTint.usingColorSpace(.sRGB)!.redComponent - 0.7) < 0.001, "Accent picker must not change titlebar tint")
    print("PASS: Independent Accent settings initialize from titlebar tint and persist separately")
    let savedAccent = BrowserTheme.themed("accentColor")
    BrowserTheme.setThemed([0.1, 0.15, 0.2], forKey: "accentColor")
    let darkField = NSAppearance(named: .darkAqua)!
    var lowAccentField: NSColor!
    darkField.performAsCurrentDrawingAppearance { lowAccentField = BrowserTheme.field.usingColorSpace(.sRGB) }
    BrowserTheme.setThemed([0.5, 0.75, 1.0], forKey: "accentColor")
    darkField.performAsCurrentDrawingAppearance {
        let highAccentField = BrowserTheme.field.usingColorSpace(.sRGB)!
        try! require(abs(lowAccentField.redComponent - highAccentField.redComponent) < 0.001 && abs(lowAccentField.blueComponent - highAccentField.blueComponent) < 0.001 && highAccentField.blueComponent > highAccentField.redComponent, "Field tint must use Accent hue without inheriting its brightness")
    }
    for (name, brightness) in [(NSAppearance.Name.darkAqua, CGFloat(0.105)), (.aqua, CGFloat(0.955))] {
        var field: NSColor!
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance { field = BrowserTheme.field.usingColorSpace(.genericRGB) }
        try require(abs(field.saturationComponent - 0.5) < 0.001 && abs(field.brightnessComponent - brightness) < 0.001, "Path/search must inherit full Accent saturation while preserving dark/light brightness")
    }
    if let savedAccent { BrowserTheme.setThemed(savedAccent, forKey: "accentColor") } else { BrowserTheme.setThemed(nil, forKey: "accentColor") }
    print("PASS: Path/search fields use Accent hue and saturation at their existing dark/light brightness")
    let glassStyle = descendants(settings.window!.contentView!).compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Glass style" }!
    try require(glassStyle.itemTitles == GlassStyle.allCases.map(\.title), "Settings must offer every glass style: \(glassStyle.itemTitles)")
    let opacityBeforeStyle = BrowserTheme.opacity
    let backdrop = descendants(window.contentView!).compactMap { $0 as? WindowBackdrop }.first!
    for (index, style) in GlassStyle.allCases.enumerated() {
        glassStyle.selectItem(at: index)
        glassStyle.sendAction(glassStyle.action, to: glassStyle.target)
        try require(BrowserTheme.glassStyle == style && BrowserTheme.opacity == opacityBeforeStyle, "Glass style must switch independently of opacity")
        // Only the window's own material; the path and search fields keep their own clear glass.
        let shown = backdrop.subviews.filter { !$0.isHidden && ($0 is NSVisualEffectView || String(describing: type(of: $0)).contains("Glass")) }
        try require(shown.count == 1, "Exactly one window material must show for \(style): \(shown.map { type(of: $0) })")
        if style.usesLiquidGlass, #available(macOS 26, *) {
            try require((shown[0] as? NSGlassEffectView)?.style == (style == .dark ? .regular : .clear), "\(style.title) must be Liquid Glass in the matching style")
        } else {
            let blur = shown[0] as? NSVisualEffectView
            try require(blur?.material == style.material && blur?.blendingMode == .behindWindow && blur?.state == .active && blur?.alphaValue == 1,
                "\(style.title) must be a full, always-active blur of what's behind the window")
        }
    }
    print("PASS: Each glass style shows exactly one matching window material, independently of opacity")
    let inactiveRow = AccentRowView(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
    inactiveRow.isSelected = true; inactiveRow.isEmphasized = false
    inactiveRow.selectionHighlightStyle = .regular
    let selectionImage = NSImage(size: inactiveRow.bounds.size, flipped: false) { rect in inactiveRow.drawSelection(in: rect); return true }
    let selectionColor = NSBitmapImageRep(data: selectionImage.tiffRepresentation!)!.colorAt(x: 20, y: 12)!.usingColorSpace(.sRGB)!
    let referenceImage = NSImage(size: inactiveRow.bounds.size, flipped: false) { rect in BrowserTheme.accentColor.setFill(); rect.fill(); return true }
    let referenceColor = NSBitmapImageRep(data: referenceImage.tiffRepresentation!)!.colorAt(x: 20, y: 12)!.usingColorSpace(.sRGB)!
    try require(abs(selectionColor.redComponent - referenceColor.redComponent) < 0.01 && abs(selectionColor.blueComponent - referenceColor.blueComponent) < 0.01, "Inactive selected rows must draw Accent instead of gray")
    let pressed = GlassToolbarButton(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
    pressed.isBordered = false; pressed.title = ""; pressed.isHighlighted = true
    let pressedImage = NSImage(size: pressed.bounds.size, flipped: false) { rect in pressed.draw(rect); return true }
    let pressedColor = NSBitmapImageRep(data: pressedImage.tiffRepresentation!)!.colorAt(x: 15, y: 15)!.usingColorSpace(.sRGB)!
    if #available(macOS 26, *) {
        try require(pressed.bezelStyle == .glass && pressed.isBordered, "Pressed toolbar buttons must use the native glass bezel")
    } else {
        try require(pressedColor.redComponent > referenceColor.redComponent && pressedColor.blueComponent > referenceColor.blueComponent, "Pressed buttons must draw a lighter Accent fill")
    }
    print("PASS: Inactive selection uses Accent; pressed buttons use native glass on macOS 26 with the earlier macOS fallback")
    try require(!window.styleMask.contains(.titled) && window.styleMask.contains(.resizable) && window.canBecomeKey && window.canBecomeMain, "Custom outline must retain key-window eligibility and the resize style")
    try checkWindowResizeInput()
    let outlineToggle = descendants(settings.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "Show window outline" }!
    outlineToggle.state = .on; outlineToggle.performClick(nil)
    try require(!BrowserTheme.outlineEnabled && descendants(window.contentView!).compactMap { $0 as? WindowOutlineView }.allSatisfy(\.isHidden), "Disabling the outline must hide the only window stroke")
    outlineToggle.performClick(nil)
    try require(BrowserTheme.outlineEnabled, "Outline can be re-enabled")
    print("PASS: App-owned window outline can be disabled with native control and resize behavior retained")
    let titlebarToggle = descendants(settings.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "Tint the titlebar" }!
    let tintBeforeToggle = BrowserTheme.titlebarTint.usingColorSpace(.sRGB)
    let opacityBeforeToggle = BrowserTheme.titlebarOpacity
    titlebarToggle.state = .on
    titlebarToggle.performClick(nil)
    try require(!BrowserTheme.titlebarTintEnabled, "Checkbox must disable titlebar tint")
    try require(BrowserTheme.titlebarTint.usingColorSpace(.sRGB) == tintBeforeToggle && BrowserTheme.titlebarOpacity == opacityBeforeToggle, "Disabling tint must preserve the saved color and opacity")
    titlebarToggle.performClick(nil)
    try require(BrowserTheme.titlebarTintEnabled, "Checkbox must re-enable titlebar tint")
    print("PASS: Titlebar tint can be disabled and re-enabled without losing its color or opacity")
    try require(settings.window is NSPanel && settings.window?.canBecomeMain == false, "Settings must preserve the browser's main-window appearance")
    print("PASS: Settings uses an auxiliary panel instead of replacing the browser's main-window appearance")
    defaults.set([], forKey: "collapsedTreeGroups")
    let sections = Sidebar()
    let favoritesGroup = sections.outline.item(atRow: 0) as! FolderNode
    let sectionCell = sections.outlineView(sections.outline, viewFor: sections.outline.tableColumns[0], item: favoritesGroup)!
    let sectionChevron = descendants(sectionCell).compactMap { $0 as? FolderDisclosureButton }.first!
    sectionChevron.performClick(nil)
    try require(!sections.outline.isItemExpanded(favoritesGroup), "Visible section chevron must collapse its section")
    sectionChevron.performClick(nil)
    try require(sections.outline.isItemExpanded(favoritesGroup), "Visible section chevron must expand its section")
    sections.outline.collapseItem(favoritesGroup, collapseChildren: false)
    try require(sections.outline.isItemExpanded(favoritesGroup) && (defaults.stringArray(forKey: "collapsedTreeGroups") ?? []).isEmpty, "Programmatic collapse must not close or persist an open section")
    sections.outline.onToggle?(favoritesGroup, false)
    let macGroup = sections.outline.item(atRow: 1) as! FolderNode
    sections.outline.onToggle?(macGroup, false)
    sections.reload()
    try require(!sections.outline.isItemExpanded(sections.outline.item(atRow: 0)) && !sections.outline.isItemExpanded(sections.outline.item(atRow: 1)), "Both collapsed section headers must survive reload")
    let reopenedSections = Sidebar()
    try require(!reopenedSections.outline.isItemExpanded(reopenedSections.outline.item(atRow: 0)) && !reopenedSections.outline.isItemExpanded(reopenedSections.outline.item(atRow: 1)), "Both collapsed section headers must survive restart")
    reopenedSections.outline.onToggle?(reopenedSections.outline.item(atRow: 0) as! FolderNode, true)
    let mixedSections = Sidebar()
    try require(mixedSections.outline.isItemExpanded(mixedSections.outline.item(atRow: 0)), "Expanded Favorites must survive restart")
    let mixedMac = (0..<mixedSections.outline.numberOfRows).compactMap { mixedSections.outline.item(atRow: $0) as? FolderNode }.first { $0.title == "THIS MAC" }!
    try require(!mixedSections.outline.isItemExpanded(mixedMac), "Expanding Favorites must not reopen This Mac")
    mixedSections.outline.onToggle?(mixedMac, true)
    let bothOpenSections = Sidebar()
    bothOpenSections.scroll.frame = NSRect(x: 0, y: 0, width: 230, height: 600)
    bothOpenSections.outline.frame.size = NSSize(width: 230, height: 600)
    let favoriteRow = bothOpenSections.outline.rowView(atRow: 1, makeIfNecessary: true)
    try require(favoriteRow is AccentRowView, "Actual sidebar rows must use the Accent selection renderer")
    let volumeNodes = (0..<bothOpenSections.outline.numberOfRows).compactMap { bothOpenSections.outline.item(atRow: $0) as? FolderNode }
    let visibleVolumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
    let hiddenVolumes = defaults.stringArray(forKey: "hiddenVolumes") ?? []
    for volume in visibleVolumes where !hiddenVolumes.contains(volume.standardizedFileURL.path) {
        try require(volumeNodes.contains { $0.url?.standardizedFileURL.path == volume.standardizedFileURL.path }, "Mounted local or network volume missing from This Mac: \(volume.path)")
    }
    print("PASS: Actual sidebar rows use Accent and all visible mounted volumes appear under This Mac")
    let bothGroups = (0..<bothOpenSections.outline.numberOfRows).compactMap { bothOpenSections.outline.item(atRow: $0) as? FolderNode }.filter(\.group)
    try require(bothGroups.count == 2 && bothGroups.allSatisfy { bothOpenSections.outline.isItemExpanded($0) }, "Native expansion of both section headers must survive restart")
    print("PASS: Favorites and This Mac persist independent collapsed/expanded states")
    let doubleClickTree = Sidebar()
    let filesystemRow = (0..<doubleClickTree.outline.numberOfRows).first { (doubleClickTree.outline.item(atRow: $0) as? FolderNode)?.url?.path == "/" }!
    let filesystemNode = doubleClickTree.outline.item(atRow: filesystemRow) as! FolderNode
    doubleClickTree.outline.expandItem(filesystemNode, expandChildren: true)
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    try require(!doubleClickTree.outline.isItemExpanded(filesystemNode) && filesystemNode.children == nil, "Unrequested recursive expansion must neither open nor load tree branches")
    let folderCell = doubleClickTree.outlineView(doubleClickTree.outline, viewFor: doubleClickTree.outline.tableColumns[0], item: filesystemNode)!
    let folderChevron = descendants(folderCell).compactMap { $0 as? FolderDisclosureButton }.first!
    folderChevron.performClick(nil)
    try waitUntil { doubleClickTree.outline.isItemExpanded(filesystemNode) }
    folderChevron.performClick(nil)
    try require(!doubleClickTree.outline.isItemExpanded(filesystemNode), "Visible folder chevron must toggle both ways")
    doubleClickTree.outline.selectRowIndexes(IndexSet(integer: filesystemRow), byExtendingSelection: false)
    doubleClickTree.outline.sendAction(doubleClickTree.outline.doubleAction, to: doubleClickTree.outline.target)
    try waitUntil { doubleClickTree.outline.isItemExpanded(filesystemNode) }
    try require((defaults.stringArray(forKey: "explicitExpandedTreePaths") ?? []).contains("/"), "Double-click expansion must be saved")
    doubleClickTree.outline.sendAction(doubleClickTree.outline.doubleAction, to: doubleClickTree.outline.target)
    try require(!doubleClickTree.outline.isItemExpanded(filesystemNode), "Second double-click must collapse the folder")
    try require(!(defaults.stringArray(forKey: "explicitExpandedTreePaths") ?? []).contains("/"), "Double-click collapse must be saved")
    print("PASS: Native double-click action expands/collapses tree folders and saves the choice")
    try checkWindowTransfers()
    try checkFileViewerRequests()
    try checkTrashInterface()
    try checkFavoriteAndVisibilityControls()
    try checkFavoriteReordering()
    try checkInitialFavoriteOrder()
    try checkTerminalIntegration()
    try MainActor.assumeIsolated { try checkUpdateInterface() }
    try checkDiskAccessOnboarding()
    try checkServerConnections()
    try checkIconSpacing()
    try checkFolderDropsAddFavorites()
    try checkTreeHidingAndFavoriteDrops()
    try checkNameConflictPrompts()
    try checkPermissionDialog()
    try checkLiveFolderUpdates()
    try checkPathCompletion()
    try checkSearchAndHeaderFocus()
    try checkMomentaryButtonHighlight()
    try checkHalfThicknessScrollbars()
    try checkSettingsReset()
    try checkThemeMode()
    try checkDialogAppearance()
    try checkBrowserEdgeResizing()
    let volume = URL(fileURLWithPath: "/Volumes/Pathfind-QA")
    if FileManager.default.fileExists(atPath: volume.appendingPathComponent("FOLDER1").path) {
        defaults.set([], forKey: "explicitExpandedTreePaths")
        defaults.set([], forKey: "collapsedTreeGroups")
        defaults.set([], forKey: "hiddenVolumes")
        let sidebar = Sidebar()
        guard let node = (0..<sidebar.outline.numberOfRows).compactMap({ sidebar.outline.item(atRow: $0) as? FolderNode }).first(where: { $0.url?.path == volume.path }) else { throw NativeCheckError.failed("Mount Pathfind-QA without -nobrowse for the outline scenario") }
        sidebar.outline.expandItem(node, expandChildren: true)
        try require(node.children == nil, "Unrequested expansion must not load the volume")
        sidebar.outline.onToggle?(node, true)
        try waitUntil { node.children != nil }
        let folder = node.children!.first { $0.title == "FOLDER1" }!
        sidebar.outline.onToggle?(folder, true)
        try waitUntil { folder.children != nil }
        try require(folder.children!.allSatisfy { !sidebar.outline.isItemExpanded($0) }, "Opening a folder must not open all children")
        let c = folder.children!.first { $0.title == "C" }!
        sidebar.outline.onToggle?(c, true)
        try waitUntil { c.children != nil }
        sidebar.outline.onToggle?(folder, false)
        sidebar.outline.onToggle?(folder, true)
        try waitUntil { sidebar.outline.isItemExpanded(c) }
        try require(sidebar.outline.isItemExpanded(c), "C must reopen after closing and reopening FOLDER1")
        try require(folder.children!.filter { $0.title != "C" }.allSatisfy { !sidebar.outline.isItemExpanded($0) }, "A, B, D must remain collapsed")
        let restarted = Sidebar()
        try waitUntil {
            (0..<restarted.outline.numberOfRows).compactMap { restarted.outline.item(atRow: $0) as? FolderNode }.contains { $0.title == "C1" }
        }
        let restoredNodes = (0..<restarted.outline.numberOfRows).compactMap { restarted.outline.item(atRow: $0) as? FolderNode }
        try require(restoredNodes.filter { ["A", "B", "D"].contains($0.title) }.allSatisfy { !restarted.outline.isItemExpanded($0) }, "Restart must restore only explicitly expanded branches")
        let beforeRestore = defaults.stringArray(forKey: "explicitExpandedTreePaths")
        restarted.reload()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        try require(defaults.stringArray(forKey: "explicitExpandedTreePaths") == beforeRestore, "Restoration must not change saved expansion choices")
        print("PASS: Actual outline loading, independent child expansion, collapse/reopen, and restart restoration")
    } else { print("SKIP: Mount the Pathfind-QA fixture to run the native outline scenario") }
} catch {
    print("FAIL: \(error)")
    exit(1)
}
