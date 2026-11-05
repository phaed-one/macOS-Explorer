import AppKit

/// The custom borderless frame owns its resize hit areas, cursors, and drag geometry.
final class WindowResizeView: NSView {
    enum Edge: CaseIterable {
        case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight
        var left: Bool { [.left, .topLeft, .bottomLeft].contains(self) }
        var right: Bool { [.right, .topRight, .bottomRight].contains(self) }
        var top: Bool { [.top, .topLeft, .topRight].contains(self) }
        var bottom: Bool { [.bottom, .bottomLeft, .bottomRight].contains(self) }
        var cursor: NSCursor {
            if #available(macOS 15, *) {
                let position: NSCursor.FrameResizePosition
                switch self {
                case .left: position = .left
                case .right: position = .right
                case .top: position = .top
                case .bottom: position = .bottom
                case .topLeft: position = .topLeft
                case .topRight: position = .topRight
                case .bottomLeft: position = .bottomLeft
                case .bottomRight: position = .bottomRight
                }
                return .frameResize(position: position, directions: .all)
            }
            if (left || right) && !(top || bottom) { return .resizeLeftRight }
            if (top || bottom) && !(left || right) { return .resizeUpDown }
            return Self.diagonalCursor(rising: self == .topRight || self == .bottomLeft)
        }
        private static func diagonalCursor(rising: Bool) -> NSCursor {
            let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
                func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: rising ? y : 20 - y) }
                let path = NSBezierPath()
                path.move(to: point(4, 4)); path.line(to: point(16, 16))
                path.move(to: point(4, 10)); path.line(to: point(4, 4)); path.line(to: point(10, 4))
                path.move(to: point(10, 16)); path.line(to: point(16, 16)); path.line(to: point(16, 10))
                path.lineCapStyle = .round; path.lineJoinStyle = .round
                NSColor.white.setStroke(); path.lineWidth = 4; path.stroke()
                NSColor.black.setStroke(); path.lineWidth = 2; path.stroke()
                return true
            }
            return NSCursor(image: image, hotSpot: NSPoint(x: 10, y: 10))
        }
        func frame(from start: NSRect, delta: NSPoint, minimum: NSSize, maximum: NSSize) -> NSRect {
            let requestedWidth = start.width + (right ? delta.x : left ? -delta.x : 0)
            let requestedHeight = start.height + (top ? delta.y : bottom ? -delta.y : 0)
            let width = min(maximum.width, max(minimum.width, requestedWidth))
            let height = min(maximum.height, max(minimum.height, requestedHeight))
            return NSRect(x: left ? start.maxX - width : start.minX,
                          y: bottom ? start.maxY - height : start.minY, width: width, height: height)
        }
    }

    private var areas: [NSTrackingArea] = []
    /// Screen position of the pointer while dragging; checks replace it to script a drag.
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }
    private var canResize: Bool { window?.styleMask.contains(.resizable) == true && window?.styleMask.contains(.fullScreen) != true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var regions: [(Edge, NSRect)] {
        let w = bounds.width, h = bounds.height
        let c = min(16, min(w, h) / 2), band: CGFloat = 4
        return [(.bottomLeft, NSRect(x: 0, y: 0, width: c, height: c)),
                (.bottomRight, NSRect(x: w - c, y: 0, width: c, height: c)),
                (.topLeft, NSRect(x: 0, y: h - c, width: c, height: c)),
                (.topRight, NSRect(x: w - c, y: h - c, width: c, height: c)),
                (.left, NSRect(x: 0, y: c, width: band, height: max(0, h - 2 * c))),
                (.right, NSRect(x: w - band, y: c, width: band, height: max(0, h - 2 * c))),
                (.bottom, NSRect(x: c, y: 0, width: max(0, w - 2 * c), height: band)),
                (.top, NSRect(x: c, y: h - band, width: max(0, w - 2 * c), height: band))]
    }
    func edge(at point: NSPoint) -> Edge? { regions.first { $0.1.contains(point) }?.0 }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard canResize, edge(at: convert(point, from: superview)) != nil else { return nil }
        return self
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        guard canResize else { return }
        for (edge, rect) in regions where !rect.isEmpty { addCursorRect(rect, cursor: edge.cursor) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        areas.forEach(removeTrackingArea); areas.removeAll()
        guard canResize else { return }
        for (_, rect) in regions where !rect.isEmpty {
            let area = NSTrackingArea(rect: rect, options: [.cursorUpdate, .activeInActiveApp], owner: self)
            addTrackingArea(area); areas.append(area)
        }
    }
    override func cursorUpdate(with event: NSEvent) {
        if canResize, let edge = edge(at: convert(event.locationInWindow, from: nil)) { edge.cursor.set() }
        else { super.cursorUpdate(with: event) }
    }
    override func mouseDown(with event: NSEvent) {
        guard canResize, let window, let edge = edge(at: convert(event.locationInWindow, from: nil)) else { return }
        let start = window.frame
        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        window.makeKeyAndOrderFront(nil)
        edge.cursor.push()
        defer { NSCursor.pop() }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown]) {
            if next.type == .leftMouseUp { break }
            if next.type == .keyDown {
                if next.keyCode == 53 { window.setFrame(start, display: true); break }
                continue
            }
            let current = pointerLocation()
            let frame = edge.frame(from: start, delta: NSPoint(x: current.x - mouse.x, y: current.y - mouse.y),
                                   minimum: window.minSize, maximum: window.maxSize)
            window.setFrame(frame, display: true)
        }
    }
}
