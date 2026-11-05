import AppKit

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
