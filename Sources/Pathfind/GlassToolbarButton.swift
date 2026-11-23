import AppKit

/// Draws only a hover surface, leaving icons and native button behavior intact.
final class GlassToolbarButton: NSButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
    private var hover = false
    private var drawsToggleSelection = false
    /// Draws a thin outline, so a labelled button reads as a button at rest.
    var drawsOutline = false { didSet { needsDisplay = true } }
    /// Shows an on state like a selected segment: a solid system-blue fill under a white icon.
    var showsOnState = false { didSet { needsDisplay = true } }
    override var state: NSControl.StateValue {
        didSet {
            guard showsOnState else { return }
            updateOnStateTint()
        }
    }
    /// The icon turns accent when on, and back to plain while the accent hover fill sits behind it.
    private func updateOnStateTint() {
        contentTintColor = state == .on && !hover ? .white : .labelColor
        needsDisplay = true
    }
    private var hoverArea: NSTrackingArea?
    override func setButtonType(_ type: NSButton.ButtonType) {
        super.setButtonType(type)
        drawsToggleSelection = [.toggle, .onOff, .pushOnPushOff, .switch, .radio].contains(type)
    }
    override func updateTrackingAreas() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true; if showsOnState { updateOnStateTint() } }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true; if showsOnState { updateOnStateTint() } }
    override func draw(_ dirtyRect: NSRect) {
        if #available(macOS 26, *), isEnabled && (isHighlighted || (drawsToggleSelection && state == .on)) {
            if bezelStyle != .glass { bezelStyle = .glass }
            if !isBordered { isBordered = true }
            if bezelColor != BrowserTheme.accentColor { bezelColor = BrowserTheme.accentColor }
            super.draw(dirtyRect)
            return
        }
        if isBordered { isBordered = false }
        // A labelled button gets a hover shape the size of the button; an icon gets a square.
        let side = min(bounds.width, bounds.height) - 2
        let square = bounds.width > bounds.height + 4 ? bounds.insetBy(dx: 1, dy: 1)
            : NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        if drawsOutline {
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
            NSColor.labelColor.withAlphaComponent(isEnabled ? 0.3 : 0.14).setStroke()
            outline.lineWidth = 1; outline.stroke()
        }
        if showsOnState && state == .on && isEnabled && !hover && !isHighlighted {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: square, xRadius: 7, yRadius: 7).fill()
        }
        if (hover || isHighlighted || (drawsToggleSelection && state == .on)) && isEnabled {
            let shape = NSBezierPath(roundedRect: square, xRadius: 7, yRadius: 7)
            let tint = BrowserTheme.accentColor
            let fill = isHighlighted ? tint.blended(withFraction: 0.18, of: .white) ?? tint : tint
            fill.setFill()
            shape.fill()
            (tint.blended(withFraction: isHighlighted ? 0.38 : 0.25, of: .white) ?? tint).setStroke()
            shape.lineWidth = 0.75; shape.stroke()
        }
        super.draw(dirtyRect)
    }
}
