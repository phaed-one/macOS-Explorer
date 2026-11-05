import AppKit
import PathfindCore

final class TabStrip: NSView {
    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onNew: (() -> Void)?
    var onDrop: (([URL], URL, Bool) -> Void)?
    var onTabDrop: ((TabTransfer, UUID?) -> Bool)?
    var onDetach: ((UUID, NSPoint) -> Void)?
    var windowID = UUID()
    private let scroll = BrowserScrollView()
    private let content = NSView()
    private let plus = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New tab")!, target: nil, action: nil)
    private var buttons: [BrowserTabView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scroll.horizontalScrollElasticity = .allowed
        scroll.documentView = content
        addSubview(scroll)
        plus.target = self; plus.action = #selector(newTab)
        plus.isBordered = false
        ToolbarHelp.install(on: plus, text: "New tab (⌘T)")
        content.addSubview(plus)
        registerForDraggedTypes([TabTransfer.pasteboardType])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(_ tabs: BrowserTabs) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = tabs.items.map { tab in
            let button = BrowserTabView(tab: tab, selected: tabs.activeID == tab.id)
            button.onSelect = { [weak self] in self?.onSelect?(tab.id) }
            button.onClose = { [weak self] in self?.onClose?(tab.id) }
            button.onDrop = { [weak self] urls, move in self?.onDrop?(urls, tab.url, move) }
            button.transfer = TabTransfer(windowID: windowID, tabID: tab.id)
            button.onTabDrop = { [weak self] payload in self?.onTabDrop?(payload, tab.id) ?? false }
            button.onDetach = { [weak self] point in self?.onDetach?(tab.id, point) }
            content.addSubview(button)
            return button
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        if let active = tabs.items.firstIndex(where: { $0.id == tabs.activeID }), buttons.indices.contains(active) {
            content.scrollToVisible(buttons[active].frame)
        }
    }
    override func layout() {
        super.layout()
        scroll.frame = bounds
        let width = min(220, max(145, (bounds.width - 42) / CGFloat(max(buttons.count, 1))))
        content.frame = NSRect(x: 0, y: 0, width: max(bounds.width, CGFloat(buttons.count) * (width + 5) + 42), height: bounds.height)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: CGFloat(index) * (width + 5), y: 0, width: width, height: max(0, bounds.height - 8))
        }
        plus.frame = NSRect(x: CGFloat(buttons.count) * (width + 5), y: 0, width: 32, height: max(0, bounds.height - 8))
    }
    @objc private func newTab() { onNew?() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { TabTransfer.read(sender) == nil ? [] : .move }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { TabTransfer.read(sender) != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let payload = TabTransfer.read(sender) else { return false }
        return onTabDrop?(payload, nil) ?? false
    }
}

private final class BrowserTabView: NSView, NSDraggingSource {
    override var mouseDownCanMoveWindow: Bool { false }
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onDrop: (([URL], Bool) -> Void)?
    var onTabDrop: ((TabTransfer) -> Bool)?
    var onDetach: ((NSPoint) -> Void)?
    var transfer: TabTransfer?
    private var originalWindowFrame: NSRect?
    private let selected: Bool
    private var dropHighlight = false
    init(tab: BrowserTab, selected: Bool) {
        self.selected = selected
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 8
        layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        let title = BrowserLocation.title(tab.url)
        let icon = BrowserLocation.icon(tab.url).copy() as! NSImage
        icon.size = NSSize(width: 16, height: 16)
        let select = TabSelectButton(title: title, image: icon, target: self, action: #selector(selectTab))
        select.onPointerDown = { [weak self] event in self?.mouseDown(with: event) }
        select.isBordered = false; select.imagePosition = .imageLeading
        select.imageScaling = .scaleProportionallyDown
        select.alignment = .left
        select.cell?.lineBreakMode = .byTruncatingMiddle
        select.font = .systemFont(ofSize: 12, weight: selected ? .semibold : .regular)
        select.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: select.font!,
            .foregroundColor: selected ? BrowserTheme.shade(dark: 1, light: 0) : NSColor.secondaryLabelColor
        ])
        ToolbarHelp.install(on: select, text: BrowserLocation.path(tab.url))
        select.setAccessibilityLabel("Tab: \(title)")
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab \(title)")!, target: self, action: #selector(closeTab))
        close.isBordered = false
        ToolbarHelp.install(on: close, text: "Close tab (⌘W)")
        for child in [select, close] { child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child) }
        NSLayoutConstraint.activate([select.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), select.topAnchor.constraint(equalTo: topAnchor), select.bottomAnchor.constraint(equalTo: bottomAnchor), select.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -6), close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), close.centerYAnchor.constraint(equalTo: centerYAnchor), close.widthAnchor.constraint(equalToConstant: 22)])
        registerForDraggedTypes([.fileURL, TabTransfer.pasteboardType]); refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: BrowserTheme.changed, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func refresh() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            BrowserTheme.paint(self, color: dropHighlight ? .selectedContentBackgroundColor : selected ? BrowserTheme.chrome : .clear)
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { onSelect?(); return }
            if hypot(next.locationInWindow.x - event.locationInWindow.x, next.locationInWindow.y - event.locationInWindow.y) >= 5 {
                beginTabDrag(event); return
            }
        }
    }
    private func beginTabDrag(_ event: NSEvent) {
        guard let transfer, let data = try? JSONEncoder().encode(transfer) else { return }
        let pasteboard = NSPasteboardItem(); pasteboard.setData(data, forType: TabTransfer.pasteboardType)
        let item = NSDraggingItem(pasteboardWriter: pasteboard)
        let preview = NSImage(size: bounds.size)
        if let bitmap = bitmapImageRepForCachingDisplay(in: bounds) { cacheDisplay(in: bounds, to: bitmap); preview.addRepresentation(bitmap) }
        item.setDraggingFrame(bounds, contents: preview)
        originalWindowFrame = window?.frame
        beginDraggingSession(with: [item], event: event, source: self).animatesToStartingPositionsOnCancelOrFail = false
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt point: NSPoint, operation: NSDragOperation) {
        let event = NSApp.currentEvent
        let cancelled = event?.type == .keyDown && event?.keyCode == 53
        if operation.isEmpty, !cancelled, NSEvent.pressedMouseButtons == 0, originalWindowFrame?.contains(point) == false { onDetach?(point) }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh() }
    @objc private func selectTab() { onSelect?() }
    @objc private func closeTab() { onClose?() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if TabTransfer.read(sender) != nil { return .move }
        let operation = FileTransfer.dragOperation(sender)
        dropHighlight = !operation.isEmpty; refresh(); return operation
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropHighlight = false; refresh() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { TabTransfer.read(sender) != nil || !FileTransfer.dragOperation(sender).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHighlight = false; refresh()
        if let payload = TabTransfer.read(sender) { return onTabDrop?(payload) ?? false }
        let operation = FileTransfer.dragOperation(sender)
        guard !operation.isEmpty, let onDrop else { return false }
        onDrop(FileTransfer.urls(sender), operation == .move); return true
    }
}
