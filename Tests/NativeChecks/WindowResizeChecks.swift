import AppKit
import PathfindCore

func checkWindowResizeInput() throws {
    let policy = NSApp.activationPolicy()
    NSApp.setActivationPolicy(.regular)
    NSApp.finishLaunching()
    defer { NSApp.setActivationPolicy(policy) }
    let screen = NSScreen.screens[0].frame
    let frame = NSRect(x: screen.midX - 250, y: screen.midY - 175, width: 500, height: 350)
    let behind = NSWindow(contentRect: frame.insetBy(dx: -20, dy: -20), styleMask: [.borderless], backing: .buffered, defer: false)
    behind.animationBehavior = .none
    behind.backgroundColor = .red; behind.orderFrontRegardless()
    let window = BrowserWindow(contentRect: frame, styleMask: [.borderless, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
    window.animationBehavior = .none
    content.wantsLayer = true; content.layer?.cornerRadius = 20; content.layer?.masksToBounds = true
    content.layer?.actions = ["backgroundColor": NSNull()]
    window.contentView = content
    defer { window.orderOut(nil); behind.orderOut(nil) }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil); window.orderFrontRegardless()
    let points = [NSPoint(x: frame.minX + 0.5, y: frame.minY + 0.5), NSPoint(x: frame.maxX - 0.5, y: frame.minY + 0.5),
        NSPoint(x: frame.minX + 0.5, y: frame.maxY - 0.5), NSPoint(x: frame.maxX - 0.5, y: frame.maxY - 0.5),
        NSPoint(x: frame.minX + 0.5, y: frame.midY), NSPoint(x: frame.maxX - 0.5, y: frame.midY),
        NSPoint(x: frame.midX, y: frame.minY + 0.5), NSPoint(x: frame.midX, y: frame.maxY - 0.5)]
    for opacity in [0.01, 0.5, 1.0] {
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(opacity).cgColor
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        for point in points {
            let target = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
            try require(target == window.windowNumber,
                "Resize point \(point) at opacity \(opacity) hit \(target) instead of \(window.windowNumber); window active: \(NSApp.isActive)")
        }
    }
    print("PASS: WindowServer mouse targeting at all four resize edges and transparent corners across 1%, 50%, and opaque content")
}

func checkBrowserEdgeResizing() throws {
    let browser = BrowserController(tabs: BrowserTabs(url: URL(fileURLWithPath: NSHomeDirectory())))
    browser.showWindow(nil); defer { browser.window?.close() }
    let window = browser.window!
    let screen = (window.screen ?? NSScreen.screens[0]).visibleFrame
    let start = NSRect(x: screen.midX - 500, y: screen.midY - 300, width: 1000, height: 600)
    window.setFrame(start, display: true)
    let root = window.contentView!
    root.layoutSubtreeIfNeeded()
    let resizers = descendants(root).compactMap { $0 as? WindowResizeView }
    try require(resizers.count == 1, "The browser window must own exactly one resize frame")
    let resizer = resizers[0]
    try require(resizer.superview?.subviews.last === resizer, "The resize frame must sit above every other browser view")
    let size = resizer.bounds.size
    let edges: [(WindowResizeView.Edge, NSPoint)] = [
        (.bottomLeft, NSPoint(x: 2, y: 2)), (.bottomRight, NSPoint(x: size.width - 2, y: 2)),
        (.topLeft, NSPoint(x: 2, y: size.height - 2)), (.topRight, NSPoint(x: size.width - 2, y: size.height - 2)),
        (.left, NSPoint(x: 1, y: size.height / 2)), (.right, NSPoint(x: size.width - 1, y: size.height / 2)),
        (.top, NSPoint(x: size.width / 2, y: size.height - 1)), (.bottom, NSPoint(x: size.width / 2, y: 1))]
    for (edge, point) in edges {
        try require(resizer.edge(at: point) == edge, "\(point) must resize from \(edge)")
        let hit = root.hitTest(resizer.convert(point, to: root.superview))
        try require(hit === resizer, "Clicks at the \(edge) edge must reach the resize frame, not \(String(describing: hit))")
    }
    let middle = resizer.convert(NSPoint(x: size.width / 2, y: size.height / 2), to: root.superview)
    try require(root.hitTest(middle) !== resizer, "Clicks inside the window must pass through to its content")
    if #available(macOS 15, *) {
        try require(WindowResizeView.Edge.bottomRight.cursor == .frameResize(position: .bottomRight, directions: .all), "Corners must show the system diagonal resize cursor")
    }

    func drag(_ edge: WindowResizeView.Edge, from point: NSPoint, by moves: [NSPoint]) {
        let screenStart = window.convertPoint(toScreen: resizer.convert(point, to: nil))
        var pending = moves.map { NSPoint(x: screenStart.x + $0.x, y: screenStart.y + $0.y) }
        resizer.pointerLocation = { pending.isEmpty ? screenStart : pending.removeFirst() }
        for _ in moves {
            NSApp.postEvent(NSEvent.mouseEvent(with: .leftMouseDragged, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!, atStart: false)
        }
        NSApp.postEvent(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!, atStart: false)
        resizer.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: resizer.convert(point, to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
    }
    drag(.bottomRight, from: edges[1].1, by: [NSPoint(x: 40, y: -20), NSPoint(x: 120, y: -60)])
    try require(window.frame.width == start.width + 120 && window.frame.height == start.height + 60
        && window.frame.minX == start.minX && window.frame.maxY == start.maxY,
        "Dragging the bottom-right corner must grow the window while the top-left stays put: \(window.frame)")
    window.setFrame(start, display: true)
    drag(.left, from: edges[4].1, by: [NSPoint(x: -80, y: 0)])
    try require(window.frame.width == start.width + 80 && window.frame.maxX == start.maxX,
        "Dragging the left edge must widen the window while its right edge stays put: \(window.frame)")
    window.setFrame(start, display: true)
    drag(.topLeft, from: edges[2].1, by: [NSPoint(x: 900, y: -900)])
    try require(window.frame.size == window.minSize && window.frame.maxX == start.maxX && window.frame.minY == start.minY,
        "Shrinking must stop at the minimum size and keep the opposite corner fixed: \(window.frame)")
    print("PASS: The browser window resizes from every edge and corner, shows resize cursors, passes interior clicks through, and respects its minimum size")

    // The first responder up the chain that handles mouseDown decides what a click does.
    func mouseDownHandler(at point: NSPoint) -> NSResponder? {
        let selector = #selector(NSResponder.mouseDown(with:))
        let base = class_getMethodImplementation(NSView.self, selector)
        var responder: NSResponder? = root.hitTest(resizer.convert(point, to: root.superview))
        while let current = responder {
            if class_getMethodImplementation(type(of: current), selector) != base { return current }
            responder = current.nextResponder
        }
        return nil
    }
    window.setFrame(start, display: true)
    root.layoutSubtreeIfNeeded()
    let blankTabStrip = NSPoint(x: size.width - 120, y: size.height - 20)
    let blankHit = root.hitTest(resizer.convert(blankTabStrip, to: root.superview))
    try require(mouseDownHandler(at: blankTabStrip) is ChromeView, "Blank tab-strip clicks must reach the window-dragging chrome; hit \(String(describing: blankHit)) in \(String(describing: blankHit?.superview)), handler \(String(describing: mouseDownHandler(at: blankTabStrip)))")
    let tabs = descendants(root).compactMap { $0 as? NSButton }.filter { $0.accessibilityLabel()?.hasPrefix("Tab:") == true }
    if let tab = tabs.first?.superview {
        let onTab = resizer.convert(NSPoint(x: tab.bounds.midX, y: tab.bounds.midY), from: tab)
        try require(!(mouseDownHandler(at: onTab) is ChromeView), "Clicks on a tab must still select or drag the tab")
    }
    print("PASS: Blank tab-strip clicks drag the window while tabs keep their own clicks")
}
