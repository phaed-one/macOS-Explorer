import AppKit

/// A conventional wheel follows the available axis; vertical wins when both overflow.
final class BrowserScrollView: NSScrollView {
    override func tile() {
        if let scroller = verticalScroller, !(scroller is HalfThicknessScroller) {
            verticalScroller = narrowScroller(replacing: scroller, horizontal: false)
        }
        if let scroller = horizontalScroller, !(scroller is HalfThicknessScroller) {
            horizontalScroller = narrowScroller(replacing: scroller, horizontal: true)
        }
        if verticalScroller?.controlSize != .small { verticalScroller?.controlSize = .small }
        if horizontalScroller?.controlSize != .small { horizontalScroller?.controlSize = .small }
        super.tile()
    }
    private func narrowScroller(replacing original: NSScroller, horizontal: Bool) -> NSScroller {
        let frame = horizontal ? NSRect(x: 0, y: 0, width: 100, height: 15) : NSRect(x: 0, y: 0, width: 15, height: 100)
        let scroller = HalfThicknessScroller(frame: frame)
        scroller.controlSize = .small; scroller.scrollerStyle = original.scrollerStyle
        scroller.knobStyle = original.knobStyle
        scroller.doubleValue = original.doubleValue; scroller.knobProportion = original.knobProportion
        scroller.target = original.target; scroller.action = original.action
        return scroller
    }
    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        guard clipView === contentView,
              let table = documentView as? NSTableView,
              let headerClip = table.headerView?.superview as? NSClipView else { return }
        let origin = NSPoint(x: contentView.bounds.minX, y: headerClip.bounds.minY)
        if headerClip.bounds.origin != origin { headerClip.scroll(to: origin) }
    }
    var routesWheelHorizontally: Bool {
        let document = contentView.documentRect
        let viewport = contentView.bounds
        return document.width > viewport.width + 0.5 && document.height <= viewport.height + 0.5
    }
    override func scrollWheel(with event: NSEvent) {
        guard routesWheelHorizontally, event.scrollingDeltaX == 0, event.scrollingDeltaY != 0 else {
            super.scrollWheel(with: event); return
        }
        let scale = event.hasPreciseScrollingDeltas ? 1 : horizontalLineScroll
        var origin = contentView.bounds.origin
        origin.x -= event.scrollingDeltaY * scale
        contentView.scroll(to: contentView.constrainBoundsRect(NSRect(origin: origin, size: contentView.bounds.size)).origin)
        reflectScrolledClipView(contentView)
    }
}

/// Narrow only the painted parts; AppKit retains tracking, fade, and scroll physics.
final class HalfThicknessScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override func drawKnob() {
        let knob = halfThicknessRect(rect(for: .knob))
        guard !knob.isEmpty else { return }
        thumbColor.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: knob, xRadius: min(knob.width, knob.height) / 2, yRadius: min(knob.width, knob.height) / 2).fill()
    }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        let knob = halfThicknessRect(rect(for: .knob))
        var track = slotRect
        if bounds.width > bounds.height { track.origin.y = knob.minY; track.size.height = knob.height }
        else { track.origin.x = knob.minX; track.size.width = knob.width }
        thumbColor.withAlphaComponent(flag ? 0.12 : 0.06).setFill()
        NSBezierPath(roundedRect: track, xRadius: min(track.width, track.height) / 2, yRadius: min(track.width, track.height) / 2).fill()
    }
    private func halfThicknessRect(_ rect: NSRect) -> NSRect {
        bounds.width > bounds.height ? rect.insetBy(dx: 0, dy: rect.height / 4) : rect.insetBy(dx: rect.width / 4, dy: 0)
    }
    private var thumbColor: NSColor {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return knobStyle == .light || (knobStyle == .default && dark) ? .white : .black
    }
}
