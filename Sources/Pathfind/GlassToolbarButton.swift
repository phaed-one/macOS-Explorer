import AppKit

/// Draws only a hover surface, leaving icons and native button behavior intact.
final class GlassToolbarButton: NSButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
    private var hover = false
    private var drawsToggleSelection = false
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
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if (hover || isHighlighted || (drawsToggleSelection && state == .on)) && isEnabled {
            let side = min(bounds.width, bounds.height) - 2
            let square = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
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
