import AppKit

/// A toolbar group divider bright enough to read on the dark chrome.
final class ToolbarDivider: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 1, height: 42) }
    /// A translucent wash of the text color: about #383838 over the black chrome.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.22).setFill()
        bounds.fill()
    }
}

/// The dark grey rounded track behind the sort chips and the view switcher, so unselected options read as buttons.
final class ChipTrack: NSStackView {
    /// How much of the text color tints the track; lower it behind a control that draws its own track.
    var fillAlpha: CGFloat = 0.12 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(fillAlpha).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }
}

/// One sort chip: a blue fill with white text when selected, a light wash on hover.
final class SortChipButton: NSButton {
    private var hover = false
    private var hoverArea: NSTrackingArea?
    static let font = NSFont.systemFont(ofSize: 12.5, weight: .medium)

    convenience init(title: String, image: NSImage? = nil, target: AnyObject?, action: Selector) {
        self.init(frame: .zero)
        self.title = title; self.image = image
        self.target = target; self.action = action
        isBordered = false
        setButtonType(.momentaryChange)
        let width = image == nil ? ceil((title as NSString).size(withAttributes: [.font: Self.font]).width) + 18 : 26
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }
    var isSelected = false { didSet { needsDisplay = true; setAccessibilityValue(isSelected ? "selected" : nil) } }
    override func updateTrackingAreas() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        if isSelected {
            NSColor.controlAccentColor.setFill(); shape.fill()
        } else if isHighlighted || hover {
            NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.16 : 0.1).setFill(); shape.fill()
        }
        if let image {
            let tinted = image.withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) ?? image
            let size = tinted.size
            let rect = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
            NSGraphicsContext.saveGraphicsState()
            tinted.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        let text = NSAttributedString(string: title, attributes: [.font: Self.font, .foregroundColor: isSelected ? NSColor.white : NSColor.labelColor])
        let size = text.size()
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}

/// Holds a stock slider and paints a grey strip behind its track. The slider itself is left
/// untouched, so it keeps the native white knob that turns to liquid glass while held.
final class SliderWell: NSView {
    let slider: NSSlider
    private let fillAlpha: CGFloat
    init(_ slider: NSSlider, fillAlpha: CGFloat) {
        self.slider = slider; self.fillAlpha = fillAlpha
        super.init(frame: .zero)
        slider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(slider)
        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: leadingAnchor), slider.trailingAnchor.constraint(equalTo: trailingAnchor),
            slider.topAnchor.constraint(equalTo: topAnchor), slider.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        guard let cell = slider.cell as? NSSliderCell else { return }
        let bar = convert(cell.barRect(flipped: slider.isFlipped), from: slider)
        NSColor.labelColor.withAlphaComponent(fillAlpha).setFill()
        NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
    }
}
