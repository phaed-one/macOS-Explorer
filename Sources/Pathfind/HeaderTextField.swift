import AppKit

private final class HeaderTextCell: NSTextFieldCell {
    var leading: CGFloat = 10
    var hidesPlaceholderWhileEditing = false
    private var editingPlaceholder: String?
    private func hideEditingPlaceholder() {
        guard hidesPlaceholderWhileEditing, editingPlaceholder == nil else { return }
        editingPlaceholder = placeholderString
        placeholderString = nil
    }
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let font = self.font ?? .systemFont(ofSize: 14)
        let height = min(rect.height, ceil(font.ascender - font.descender + font.leading))
        return NSRect(x: rect.minX + leading, y: rect.midY - height / 2, width: max(0, rect.width - leading - 10), height: height)
    }
    override func select(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        hideEditingPlaceholder()
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: editor, delegate: delegate, start: selStart, length: selLength)
    }
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        hideEditingPlaceholder()
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: editor, delegate: delegate, event: event)
    }
    override func endEditing(_ textObj: NSText) {
        super.endEditing(textObj)
        if let placeholder = editingPlaceholder {
            placeholderString = placeholder; editingPlaceholder = nil
        }
        controlView?.needsDisplay = true
    }
}

/// One field style for both the editable path and the folder filter.
final class HeaderTextField: NSTextField {
    private var symbol: NSImageView?
    var hidesPlaceholderWhileEditing: Bool {
        get { (cell as? HeaderTextCell)?.hidesPlaceholderWhileEditing ?? false }
        set { (cell as? HeaderTextCell)?.hidesPlaceholderWhileEditing = newValue }
    }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
    init(symbol: String? = nil) {
        super.init(frame: .zero)
        let textCell = HeaderTextCell(textCell: "")
        textCell.isEditable = true; textCell.isSelectable = true
        textCell.isBezeled = true; textCell.bezelStyle = .roundedBezel
        textCell.drawsBackground = true; textCell.usesSingleLineMode = true
        textCell.focusRingType = .none
        cell = textCell
        focusRingType = .none
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let icon = NSImageView(image: image)
            icon.contentTintColor = .secondaryLabelColor
            addSubview(icon); self.symbol = icon; textCell.leading = 32
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled && isEditable { addCursorRect(bounds, cursor: .iBeam) }
    }
    override func layout() {
        super.layout()
        symbol?.frame = NSRect(x: 10, y: bounds.midY - 8, width: 16, height: 16)
    }
}
