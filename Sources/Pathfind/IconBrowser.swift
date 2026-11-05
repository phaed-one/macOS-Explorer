import AppKit
import PathfindCore

final class IconCollectionView: NSCollectionView {
    var onRightDrag: ((NSEvent) -> Void)?
    var onDoubleClick: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
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
    var entries: [FileEntry] = []
    var onOpen: (() -> Void)?
    var onSelection: (() -> Void)?
    var onDrop: (([URL], URL, Bool) -> Void)?
    var currentFolder = FileManager.default.homeDirectoryForCurrentUser
    var iconSize: CGFloat = 64 {
        didSet {
            updateLayout()
            collection.reloadData()
        }
    }
    var iconSpacing: CGFloat = 10 { didSet { updateLayout() } }
    private func updateLayout() {
        let gap = min(40, max(0, iconSpacing))
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
        collection.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        collection.autoresizingMask = [.width]
        collection.isSelectable = true; collection.allowsMultipleSelection = true
        collection.backgroundColors = [.controlBackgroundColor]
        collection.delegate = self; collection.dataSource = self
        collection.register(FileIconItem.self, forItemWithIdentifier: .init("file"))
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
        collection.selectionIndexPaths = []
        collection.reloadData()
    }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { entries.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .init("file"), for: indexPath) as! FileIconItem
        item.configure(entries[indexPath.item], size: iconSize)
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

private final class FileIconItem: NSCollectionViewItem {
    private var iconWidth: NSLayoutConstraint!
    private var iconHeight: NSLayoutConstraint!
    override func loadView() {
        view = NSView(); view.wantsLayer = true; view.layer?.cornerRadius = 7
        let image = NSImageView()
        image.imageScaling = .scaleProportionallyUpOrDown
        let label = NSTextField(wrappingLabelWithString: "")
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
    func configure(_ entry: FileEntry, size: CGFloat) {
        imageView?.image = NSWorkspace.shared.icon(forFile: entry.url.path)
        imageView?.alphaValue = entry.isHidden ? 0.5 : 1
        textField?.stringValue = entry.name
        textField?.textColor = entry.isHidden ? .secondaryLabelColor : .labelColor
        view.toolTip = entry.url.path
        view.setAccessibilityLabel(entry.name)
        iconWidth.constant = size; iconHeight.constant = size
        updateSelection()
    }
    override var isSelected: Bool { didSet { updateSelection() } }
    private func updateSelection() {
        view.layer?.backgroundColor = (isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.45) : .clear).cgColor
    }
}
