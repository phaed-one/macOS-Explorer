import AppKit
import PathfindCore

func checkIconSpacing() throws {
    let defaults = UserDefaults.standard
    let saved = defaults.object(forKey: "folderViews")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-Spacing-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for index in 0..<30 { try Data().write(to: folder.appendingPathComponent("file-\(index).txt")) }
    defer {
        try? FileManager.default.removeItem(at: folder)
        if let saved { defaults.set(saved, forKey: "folderViews") } else { defaults.removeObject(forKey: "folderViews") }
    }
    let browser = BrowserController(tabs: BrowserTabs(url: folder))
    defer { browser.close() }
    browser.showWindow(nil)
    try waitUntil { browser.window?.representedURL == folder }
    let root = browser.window!.contentView!
    let controls = descendants(root)
    let mode = controls.compactMap { $0 as? NSSegmentedControl }.first!
    mode.selectedSegment = 0; mode.sendAction(mode.action, to: mode.target)
    let size = controls.compactMap { $0 as? LiveSlider }.first { $0.accessibilityLabel() == "Icon size" }!
    let spacing = controls.compactMap { $0 as? LiveSlider }.first { $0.accessibilityLabel() == "Icon spacing" }!
    let collection = controls.compactMap { $0 as? IconCollectionView }.first!
    let layout = collection.collectionViewLayout as! NSCollectionViewFlowLayout
    size.setAccessibilityValue(64)
    collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
    spacing.setAccessibilityValue(0)
    let tight = layout.itemSize
    spacing.setAccessibilityValue(40)
    try require(layout.itemSize.width > tight.width && layout.itemSize.height > tight.height && layout.minimumLineSpacing == 40, "Spacing must change grid density in both directions")
    try require(size.doubleValue == 64 && collection.selectionIndexPaths == [IndexPath(item: 0, section: 0)], "Changing gaps must retain icon size and file selection")
    let stored = FolderViewStore().view(for: folder)
    try require(stored.iconSpacing == 40 && stored.iconSize == 64, "Spacing must be saved independently in this folder's view settings")
    for width in [900.0, 1120.0, 1400.0] {
        browser.window!.setContentSize(NSSize(width: width, height: 740)); root.layoutSubtreeIfNeeded()
        let a = size.convert(size.bounds, to: root), b = spacing.convert(spacing.bounds, to: root)
        try require(b.width < a.width && b.minX > a.maxX && abs(b.midY - a.midY) < 1, "The smaller spacing slider must sit beside icon size")
        for control in controls.compactMap({ $0 as? NSControl }) where !control.isHiddenOrHasHiddenAncestor {
            if control is LiveSlider || control is GlassToolbarButton {
                try require(root.bounds.contains(control.convert(control.bounds, to: root)), "Both sliders and toolbar icons must fit at the minimum window width")
            }
        }
    }
    mode.selectedSegment = 1; mode.sendAction(mode.action, to: mode.target)
    try require(spacing.isHidden && size.isHidden, "Both icon controls must hide in Details view")
    mode.selectedSegment = 0; mode.sendAction(mode.action, to: mode.target)
    try require(!spacing.isHidden && spacing.doubleValue == 40, "Switching back to Icons must restore spacing")
    print("PASS: Smaller spacing slider, tight/wide grid density, unchanged icon size and selection, saved spacing, and toolbar layout")
}
