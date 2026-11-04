import AppKit
import PathfindCore

func checkTerminalIntegration() throws {
    try require(TerminalApp.allCases.count == 14 && Set(TerminalApp.allCases.map(\.rawValue)).count == 14, "The complete terminal catalog must have unique application identifiers")
    let tricky = URL(fileURLWithPath: "/tmp/Space + ünicode & #?%' \" $(touch nope)\nFolder", isDirectory: true)
    for terminal in [TerminalApp.warp, .warpPreview] {
        let destination = terminal.destination(for: tricky)
        let components = URLComponents(url: destination, resolvingAgainstBaseURL: false)!
        try require(components.queryItems == [URLQueryItem(name: "path", value: tricky.path)], "Warp must receive the entire path as one query argument")
        try require(destination.absoluteString.contains("%2B") && !destination.absoluteString.contains(" "), "Plus signs and spaces must be URL-encoded")
        try require(destination.scheme == (terminal == .warp ? "warp" : "warppreview"), "Warp channels must use their own URL scheme")
    }
    try require(TerminalApp.terminal.destination(for: tricky) == tricky && TerminalApp.iterm.destination(for: tricky) == tricky, "Terminal and iTerm2 must receive directory URLs directly")
    for terminal in TerminalApp.allCases {
        if let arguments = terminal.arguments(for: tricky) {
            try require(arguments.last == tricky.path, "CLI terminal launches must pass the folder as one literal argument")
        }
    }
    func request(_ item: NSMenuItem?) -> TerminalLauncher.Request? {
        (item?.submenu?.items.first ?? item)?.representedObject as? TerminalLauncher.Request
    }
    func terminalItem(_ menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.identifier?.rawValue == "openTerminalHere" }
    }
    for applications: [TerminalApp] in [[.terminal], [.terminal, .warp], [.terminal, .warp, .iterm], []] {
        let menu = NSMenu()
        TerminalLauncher.shared.appendItem(to: menu, folder: tricky, applications: applications)
        let item = terminalItem(menu)!
        if applications.count > 2 {
            try require(item.title == "Open in Terminal", "Multiple choices must use a native submenu chevron with no literal arrow or ellipsis")
            try require(item.submenu?.items.map(\.title) == applications.map(\.title), "Submenu must list every installed terminal, including Terminal")
            for (child, terminal) in zip(item.submenu!.items, applications) {
                let target = request(child)
                try require(target?.terminal == terminal && target?.folder == tricky, "Each terminal choice must preserve its app and the exact folder")
            }
        } else {
            try require(item.submenu == nil, "Zero or one alternative must not introduce a submenu")
            try require(request(item)?.terminal == (applications.last ?? .terminal), "A single alternative must open directly; otherwise use Terminal")
            try require(item.title == "Open in \((applications.last ?? .terminal).title)", "Direct actions must name the terminal they open")
            try require(item.isEnabled == !applications.isEmpty, "No available terminals must disable the action")
        }
    }

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer Terminal \(UUID())")
    let child = root.appendingPathComponent("A Folder", isDirectory: true)
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
    try Data().write(to: root.appendingPathComponent("B File.txt"))
    defer { try? FileManager.default.removeItem(at: root) }
    let browser = BrowserController(tabs: BrowserTabs(url: root))
    defer { browser.close() }
    try waitUntil { browser.window?.representedURL == root }
    let views = descendants(browser.window!.contentView!)
    let table = views.compactMap { $0 as? FileTableView }.first!
    let collection = views.compactMap { $0 as? IconCollectionView }.first!
    let mode = views.compactMap { $0 as? NSSegmentedControl }.first!
    let menu = NSMenu()
    for segment in [0, 1] {
        mode.selectedSegment = segment; mode.sendAction(mode.action, to: mode.target)
        func select(_ index: Int?) {
            table.selectRowIndexes(index.map { IndexSet(integer: $0) } ?? [], byExtendingSelection: false)
            collection.selectionIndexPaths = index.map { [IndexPath(item: $0, section: 0)] } ?? []
            browser.menuNeedsUpdate(menu)
        }
        select(nil)
        try require(request(terminalItem(menu))?.folder.standardizedFileURL.path == root.standardizedFileURL.path, "Empty space must target the current folder in both views")
        select(0)
        try require(request(terminalItem(menu))?.folder.standardizedFileURL.path == child.standardizedFileURL.path, "A folder menu must target that folder in both views")
        select(1)
        try require(terminalItem(menu) == nil, "File menus must not contain a terminal action")
        table.selectRowIndexes([0, 1], byExtendingSelection: false)
        collection.selectionIndexPaths = [IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0)]
        browser.menuNeedsUpdate(menu)
        try require(terminalItem(menu) == nil, "Mixed selections must not be treated as empty space")
    }
    let sidebarMenu = NSMenu()
    Sidebar().appendContextItems(to: sidebarMenu, for: child)
    try require(request(terminalItem(sidebarMenu))?.folder.standardizedFileURL.path == child.standardizedFileURL.path, "Tree folders must use the same terminal action")
    print("PASS: 14-terminal catalog, zero/one/multiple alternatives, exact app/folder targets, safe path arguments, both views, tree folders, and no file menu")
}
