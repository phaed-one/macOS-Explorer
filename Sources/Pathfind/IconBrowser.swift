import AppKit
import PathfindCore

/// A file's name in any view. Files are selected, not their text, so it keeps the arrow cursor.
final class FileNameLabel: NSTextField {
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}

final class IconCollectionView: NSCollectionView {
    var onRightDrag: ((NSEvent) -> Void)?
    var onDoubleClick: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    /// List's columns run sideways past the viewport, so size the grid to them for horizontal scrolling.
    override func layout() {
        super.layout()
        guard let list = collectionViewLayout as? ListColumnLayout, let clip = enclosingScrollView?.contentView else { return }
        let size = NSSize(width: max(clip.bounds.width, list.collectionViewContentSize.width), height: clip.bounds.height)
        if frame.size != size { setFrameSize(size) }
    }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
        if event.clickCount == 2 { onDoubleClick?() }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if let index = indexPathForItem(at: point) {
            if !selectionIndexPaths.contains(index) { selectionIndexPaths = [index] }
        } else { deselectAll(nil) }
        return super.menu(for: event)
    }
    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        _ = menu(for: event)
        FileTransfer.trackRightMouse(in: self, event: event) { [weak self] drag in self?.onRightDrag?(drag) }
    }
}

final class IconBrowser: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    let collection = IconCollectionView()
    let scroll = BrowserScrollView()
    private let layout = NSCollectionViewFlowLayout()
    private let listLayout = ListColumnLayout()
    /// List item widths for `entries`, measured once per reload rather than on every relayout.
    private var listWidths: [CGFloat]?
    var entries: [FileEntry] = []
    var onOpen: (() -> Void)?
    var onSelection: (() -> Void)?
    var onDrop: (([URL], URL, Bool) -> Void)?
    var currentFolder = FileManager.default.homeDirectoryForCurrentUser
    var isListView = false {
        didSet {
            guard isListView != oldValue else { return }
            // List scrolls sideways through its columns; Icons scrolls down through its rows.
            scroll.hasHorizontalScroller = isListView
            scroll.hasVerticalScroller = !isListView
            // Icons track the viewport's width and grow downward; List tracks its height and grows sideways.
            collection.autoresizingMask = isListView ? [.height] : [.width]
            collection.collectionViewLayout = isListView ? listLayout : layout
            updateLayout(); refreshItems()
        }
    }
    var iconSize: CGFloat = 64 {
        didSet {
            updateLayout()
            collection.reloadData()
        }
    }
    var iconSpacing: CGFloat = 10 { didSet { updateLayout() } }
    private func updateLayout() {
        let gap = min(40, max(0, iconSpacing))
        if isListView {
            listLayout.columnGap = gap
            return
        }
        layout.itemSize = NSSize(width: max(72 + 2.8 * gap, iconSize + 16 + 2.2 * gap), height: iconSize + 42 + 1.2 * gap)
        layout.minimumInteritemSpacing = max(0, gap - 4)
        layout.minimumLineSpacing = gap
        layout.invalidateLayout()
    }
    override init() {
        super.init()
        updateLayout()
        layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        collection.collectionViewLayout = layout
        listLayout.itemWidth = { [weak self] index in self?.listWidth(at: index) ?? 0 }
        collection.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        collection.autoresizingMask = [.width]
        collection.isSelectable = true; collection.allowsMultipleSelection = true
        collection.backgroundColors = [.controlBackgroundColor]
        collection.delegate = self; collection.dataSource = self
        collection.register(FileIconItem.self, forItemWithIdentifier: .init("file"))
        collection.register(FileListItem.self, forItemWithIdentifier: .init("list-file"))
        collection.registerForDraggedTypes([.fileURL])
        collection.setDraggingSourceOperationMask(.copy, forLocal: true)
        collection.setDraggingSourceOperationMask(.copy, forLocal: false)
        collection.onDoubleClick = { [weak self] in self?.onOpen?() }
        scroll.documentView = collection; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.drawsBackground = true; scroll.backgroundColor = .controlBackgroundColor
    }
    func reload(_ entries: [FileEntry]) {
        self.entries = entries
        listWidths = nil
        collection.selectionIndexPaths = []
        collection.reloadData()
    }
    private func listWidth(at index: Int) -> CGFloat {
        if listWidths == nil {
            let font = NSFont.systemFont(ofSize: 13)
            listWidths = entries.map { FileListItem.width(for: $0.name, font: font) }
        }
        return listWidths!.indices.contains(index) ? listWidths![index] : 0
    }
    /// Scrolls an item into view along whichever axis the current view scrolls.
    func scrollToItem(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        collection.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: isListView ? .nearestVerticalEdge : .nearestHorizontalEdge)
    }
    /// Redraws every item for the same entries, keeping the selection.
    func refreshItems() {
        let selected = collection.selectionIndexPaths
        collection.reloadData()
        collection.selectionIndexPaths = selected
    }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { entries.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        if isListView {
            let item = collectionView.makeItem(withIdentifier: .init("list-file"), for: indexPath) as! FileListItem
            item.configure(entries[indexPath.item], scale: collectionView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
            return item
        }
        let item = collectionView.makeItem(withIdentifier: .init("file"), for: indexPath) as! FileIconItem
        item.configure(entries[indexPath.item], size: iconSize, scale: collectionView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { onSelection?() }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { onSelection?() }
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        entries[indexPath.item].url as NSURL
    }
    private func dropFolder(at indexPath: IndexPath, operation: NSCollectionView.DropOperation) -> URL {
        if operation == .on, entries.indices.contains(indexPath.item), entries[indexPath.item].isDirectory { return entries[indexPath.item].url }
        return currentFolder
    }
    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        let index = proposedDropIndexPath.pointee as IndexPath
        if entries.indices.contains(index.item), entries[index.item].isDirectory { proposedDropOperation.pointee = .on }
        else { proposedDropOperation.pointee = .before }
        return FileTransfer.dragOperation(draggingInfo)
    }
    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        FileTransfer.accept(draggingInfo, destination: dropFolder(at: indexPath, operation: dropOperation), perform: onDrop)
    }
}

private final class FileListItem: NSCollectionViewItem {
    private let preview = FilePreviewImageView()
    /// 7pt insets, a 20pt icon and an 8pt gap around the name; very long names truncate.
    static func width(for name: String, font: NSFont) -> CGFloat {
        let text = ceil((name as NSString).size(withAttributes: [.font: font]).width)
        return min(420, max(80, text + 7 + 20 + 8 + 7 + 2))
    }

    override func loadView() {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.wantsLayer = true
        row.layer?.cornerRadius = 5
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = FileNameLabel(labelWithString: "")
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 13)
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.widthAnchor.constraint(equalToConstant: 20).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 20).isActive = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(preview)
        row.addArrangedSubview(label)
        let container = NSView()
        container.wantsLayer = true
        container.addSubview(row)
        view = container
        textField = label
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 7),
            row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -7),
            row.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            row.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -2)
        ])
    }

    func configure(_ entry: FileEntry, scale: CGFloat) {
        preview.configure(for: entry, size: 20, scale: scale)
        textField?.stringValue = entry.name
        textField?.textColor = entry.isHidden ? .secondaryLabelColor : .labelColor
        view.toolTip = entry.url.path
        view.setAccessibilityLabel(entry.name)
        updateSelection()
    }

    override var isSelected: Bool { didSet { updateSelection() } }

    private func updateSelection() {
        view.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.45).cgColor : .clear
    }
}

private final class FileIconItem: NSCollectionViewItem {
    private let preview = FilePreviewImageView()
    private var iconWidth: NSLayoutConstraint!
    private var iconHeight: NSLayoutConstraint!
    override func loadView() {
        view = NSView(); view.wantsLayer = true; view.layer?.cornerRadius = 7
        let image = preview
        let label = FileNameLabel(wrappingLabelWithString: "")
        label.isSelectable = false
        label.alignment = .center; label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 12)
        for child in [image, label] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        imageView = image; textField = label
        iconWidth = image.widthAnchor.constraint(equalToConstant: 64)
        iconHeight = image.heightAnchor.constraint(equalToConstant: 64)
        NSLayoutConstraint.activate([
            image.topAnchor.constraint(equalTo: view.topAnchor, constant: 7), image.centerXAnchor.constraint(equalTo: view.centerXAnchor), iconWidth, iconHeight,
            label.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 6), label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5), label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5), label.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -5)
        ])
    }
    func configure(_ entry: FileEntry, size: CGFloat, scale: CGFloat) {
        preview.configure(for: entry, size: size, scale: scale)
        textField?.stringValue = entry.name
        textField?.textColor = entry.isHidden ? .secondaryLabelColor : .labelColor
        view.toolTip = entry.url.path
        view.setAccessibilityLabel(entry.name)
        iconWidth.constant = size; iconHeight.constant = size
        updateSelection()
    }
    override var isSelected: Bool { didSet { updateSelection() } }
    override var highlightState: NSCollectionViewItem.HighlightState { didSet { updateSelection() } }
    private func updateSelection() {
        let highlighted = highlightState == .forSelection || (isSelected && highlightState != .forDeselection)
        view.layer?.backgroundColor = (highlighted ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.45) : .clear).cgColor
    }
}

/// Windows-style List: names fill each column top to bottom, columns run left to right, and each
/// column is only as wide as its own widest name. The spacing setting is the gap between columns.
final class ListColumnLayout: NSCollectionViewLayout {
    var itemWidth: (Int) -> CGFloat = { _ in 200 }
    var columnGap: CGFloat = 10 { didSet { if columnGap != oldValue { invalidateLayout() } } }
    let rowHeight: CGFloat = 34, rowGap: CGFloat = 4, inset: CGFloat = 16
    private var frames: [NSRect] = []
    private var contentSize = NSSize.zero
    private var preparedHeight: CGFloat = -1

    private var viewportHeight: CGFloat {
        collectionView?.enclosingScrollView?.contentSize.height ?? collectionView?.bounds.height ?? 0
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let count = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
        let height = viewportHeight
        preparedHeight = height
        let rows = max(1, Int((height - 2 * inset + rowGap) / (rowHeight + rowGap)))
        var frames: [NSRect] = []
        frames.reserveCapacity(count)
        var x = inset
        for start in stride(from: 0, to: count, by: rows) {
            let range = start..<min(count, start + rows)
            let widths = range.map(itemWidth)
            for (row, width) in widths.enumerated() {
                frames.append(NSRect(x: x, y: inset + CGFloat(row) * (rowHeight + rowGap), width: width, height: rowHeight))
            }
            x += (widths.max() ?? 0) + columnGap
        }
        self.frames = frames
        contentSize = NSSize(width: count == 0 ? 0 : x - columnGap + inset, height: height)
    }

    override var collectionViewContentSize: NSSize { contentSize }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        frames.indices.filter { frames[$0].intersects(rect) }.map(attributes)
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        frames.indices.contains(indexPath.item) ? attributes(indexPath.item) : nil
    }

    /// Dropping on a name targets that item; anywhere else targets the folder itself.
    override func layoutAttributesForDropTarget(at point: NSPoint) -> NSCollectionViewLayoutAttributes? {
        if let index = frames.firstIndex(where: { $0.contains(point) }) { return attributes(index) }
        let gap = NSCollectionViewLayoutAttributes(forInterItemGapBefore: IndexPath(item: frames.count, section: 0))
        gap.frame = NSRect(x: max(0, contentSize.width - inset), y: inset, width: 1, height: rowHeight)
        return gap
    }

    override func layoutAttributesForInterItemGap(before indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        let gap = NSCollectionViewLayoutAttributes(forInterItemGapBefore: indexPath)
        let frame = frames.indices.contains(indexPath.item) ? frames[indexPath.item] : frames.last ?? .zero
        gap.frame = NSRect(x: frame.minX, y: frame.minY, width: 1, height: rowHeight)
        return gap
    }

    // A taller or shorter window changes how many rows fit in each column.
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool { viewportHeight != preparedHeight }

    private func attributes(_ index: Int) -> NSCollectionViewLayoutAttributes {
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
        attributes.frame = frames[index]
        return attributes
    }
}
