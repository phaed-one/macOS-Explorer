import AppKit
import PathfindCore

final class FolderNode {
    let title: String
    let url: URL?
    var children: [FolderNode]?
    var loading = false
    var wantsExpanded = false
    var error: String?
    let group: Bool
    init(_ title: String, url: URL? = nil, children: [FolderNode]? = nil, group: Bool = false) {
        self.title = title; self.url = url; self.children = children; self.group = group
    }
}

final class FolderDisclosureButton: NSButton {
    var onToggle: (() -> Void)?
    private let folderName: String
    init(title: String, expanded: Bool) {
        folderName = title
        super.init(frame: .zero)
        self.title = ""; isBordered = false
        target = self; action = #selector(toggle)
        update(expanded: expanded)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(expanded: Bool) {
        image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        contentTintColor = .secondaryLabelColor
        setAccessibilityLabel("\(expanded ? "Collapse" : "Expand") \(folderName)")
    }
    @objc private func toggle() { onToggle?() }
}

final class FolderOutlineView: NSOutlineView {
    override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }
    var onToggle: ((FolderNode, Bool) -> Void)?
    private(set) var userActionItem: FolderNode?
    override func mouseDown(with event: NSEvent) {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        userActionItem = item(atRow: row) as? FolderNode
        defer { userActionItem = nil }
        super.mouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if let node = item(atRow: selectedRow) as? FolderNode {
            if event.keyCode == 124 && !isItemExpanded(node) { onToggle?(node, true); return }
            if event.keyCode == 123 && isItemExpanded(node) { onToggle?(node, false); return }
        }
        super.keyDown(with: event)
    }
}

final class Sidebar: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    let outline = FolderOutlineView()
    let scroll = BrowserScrollView()
    var onNavigate: ((URL) -> Void)?
    var onUnmount: ((URL) -> Void)?
    var onGetInfo: ((URL) -> Void)?
    var onClearTrash: (() -> Void)?
    var onDrop: (([URL], URL, Bool) -> Void)?
    var onFavoritesChanged: (() -> Void)?
    private let hiddenFiles = HiddenFileStore()
    private var roots: [FolderNode] = []
    private let queue = DispatchQueue(label: "pathfind.tree", qos: .userInitiated)
    private var generation = 0
    private var expansion: TreeExpansionState
    private var collapsedGroups: Set<String>
    private let statePrefix: String
    private static let sharedChanged = Notification.Name("PathfindSidebarSharedChanged")
    private static let favoriteDragType = NSPasteboard.PasteboardType("com.pathfind.favorite")
    private var rebuilding = false
    private var restoringSelection = false
    private var needsSelectionRestore = true

    override convenience init() { self.init(stateID: nil) }
    init(stateID: String?) {
        statePrefix = stateID.map { $0 + "." } ?? ""
        expansion = TreeExpansionState(paths: UserDefaults.standard.stringArray(forKey: statePrefix + "explicitExpandedTreePaths") ?? [])
        collapsedGroups = Set(UserDefaults.standard.stringArray(forKey: statePrefix + "collapsedTreeGroups") ?? [])
        super.init()
        let column = NSTableColumn(identifier: .init("folders"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 27
        outline.indentationPerLevel = 15
        outline.style = .plain
        outline.delegate = self; outline.dataSource = self
        outline.target = self; outline.action = #selector(selected)
        outline.doubleAction = #selector(toggleClickedFolder)
        outline.onToggle = { [weak self] node, expanded in self?.setExpansion(node, expanded: expanded) }
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.registerForDraggedTypes([.fileURL, Self.favoriteDragType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.setDraggingSourceOperationMask([], forLocal: false)
        scroll.documentView = outline
        scroll.automaticallyAdjustsContentInsets = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu
        NotificationCenter.default.addObserver(self, selector: #selector(sharedStateChanged), name: Self.sharedChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sharedStateChanged), name: HiddenFileStore.changed, object: nil)
        reload()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func sharedStateChanged() { reload(); onFavoritesChanged?() }
    private func publishSharedChange() { NotificationCenter.default.post(name: Self.sharedChanged, object: nil) }

    var favorites: [URL] {
        if let paths = UserDefaults.standard.stringArray(forKey: "favorites") {
            return paths.map { URL(fileURLWithPath: $0) }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home, URL(fileURLWithPath: "/Applications")] + ["Desktop", "Documents", "Downloads"].map { home.appendingPathComponent($0) }
    }
    private var hiddenVolumePaths: [String] {
        UserDefaults.standard.stringArray(forKey: "hiddenVolumes") ?? []
    }

    func saveFavorite(_ url: URL) {
        var paths = favorites.map(\.path)
        if !isFavorite(url) { paths.append(url.path) }
        UserDefaults.standard.set(paths, forKey: "favorites")
        publishSharedChange()
    }
    func isFavorite(_ url: URL) -> Bool {
        favorites.contains { $0.standardizedFileURL.path == url.standardizedFileURL.path }
    }
    func toggleFavorite(_ url: URL) {
        if isFavorite(url) {
            UserDefaults.standard.set(favorites.filter { $0.standardizedFileURL.path != url.standardizedFileURL.path }.map(\.path), forKey: "favorites")
            publishSharedChange()
        } else { saveFavorite(url) }
    }

    func reload() {
        generation += 1
        needsSelectionRestore = true
        rebuilding = true
        defer { rebuilding = false }
        let favoriteNodes = favorites.map { FolderNode($0.lastPathComponent, url: $0, children: []) }
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        var drives = [FolderNode("Filesystem  /", url: URL(fileURLWithPath: "/"))]
        drives += volumes.filter { $0.path != "/" }.map { FolderNode($0.lastPathComponent, url: $0) }
        drives.removeAll { node in node.url.map { hiddenVolumePaths.contains($0.standardizedFileURL.path) } ?? false }
        drives.append(FolderNode("Trash", url: TrashStore.location, children: []))
        roots = [FolderNode("FAVORITES", children: favoriteNodes, group: true),
                 FolderNode("THIS MAC", children: drives, group: true)]
        outline.reloadData()
        for root in roots where !collapsedGroups.contains(root.title) {
            applyExpansion(root, expanded: true)
        }
        restoreSelection()
    }
    private func restoreChildren(of node: FolderNode) {
        for child in node.children ?? [] where child.url.map({ expansion.isExpanded($0.path) }) == true {
            applyExpansion(child, expanded: true)
        }
    }
    private func applyExpansion(_ node: FolderNode, expanded: Bool) {
        node.wantsExpanded = expanded
        if expanded {
            outline.expandItem(node, expandChildren: false)
            if node.children != nil { restoreChildren(of: node) }
        } else { outline.collapseItem(node, collapseChildren: false) }
        let row = outline.row(forItem: node)
        if row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) {
            cell.subviews.compactMap { $0 as? FolderDisclosureButton }.first?.update(expanded: expanded)
        }
    }
    private func setExpansion(_ node: FolderNode, expanded: Bool) {
        rememberExpansion(node, expanded: expanded)
        applyExpansion(node, expanded: expanded)
    }
    private func rememberExpansion(_ node: FolderNode, expanded: Bool) {
        guard !rebuilding else { return }
        if let url = node.url { expansion.setExpanded(expanded, path: url.path) }
        else if expanded { collapsedGroups.remove(node.title) }
        else { collapsedGroups.insert(node.title) }
        saveTreeState()
    }
    private func selectionID(_ node: FolderNode) -> String? {
        guard let url = node.url else { return nil }
        let favorite = (outline.parent(forItem: node) as? FolderNode) === roots.first
        return (favorite ? "favorite:" : "tree:") + (url.isFileURL ? url.path : url.absoluteString)
    }
    private func restoreSelection() {
        guard needsSelectionRestore, let saved = UserDefaults.standard.string(forKey: statePrefix + "selectedTreeItem") else { return }
        for row in 0..<outline.numberOfRows {
            if let node = outline.item(atRow: row) as? FolderNode, selectionID(node) == saved {
                restoringSelection = true
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                restoringSelection = false
                outline.scrollRowToVisible(row)
                needsSelectionRestore = false
                return
            }
        }
    }
    private func saveTreeState() {
        UserDefaults.standard.set(Array(expansion.paths).sorted(), forKey: statePrefix + "explicitExpandedTreePaths")
        UserDefaults.standard.set(Array(collapsedGroups).sorted(), forKey: statePrefix + "collapsedTreeGroups")
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !rebuilding, !restoringSelection, let node = outline.item(atRow: outline.selectedRow) as? FolderNode else { return }
        UserDefaults.standard.set(selectionID(node), forKey: statePrefix + "selectedTreeItem")
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? FolderNode)?.children?.count ?? (item == nil ? roots.count : 0)
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? FolderNode { return node.children![index] }
        return roots[index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        let node = item as! FolderNode
        return node.children == nil || !(node.children?.isEmpty ?? true)
    }
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool { (item as! FolderNode).group }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { AccentRowView() }
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { (item as! FolderNode).url != nil }
    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        let node = item as! FolderNode
        // AppKit may probe expansion while rebuilding or exposing accessibility rows.
        // Only explicit input or a requested restore may change the visible tree.
        guard node.wantsExpanded || outline.userActionItem === node else { return false }
        if !node.wantsExpanded {
            node.wantsExpanded = true
            if outline.userActionItem === node { rememberExpansion(node, expanded: true) }
        }
        guard node.children == nil else {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.outline.isItemExpanded(node) else { return }
                self.restoreChildren(of: node)
            }
            return true
        }
        guard !node.loading, let url = node.url else { return false }
        node.loading = true
        let hidden = hiddenFiles.showsHidden(in: url), version = generation
        queue.async {
            let result = Result { try FileSystem.contents(of: url, showHidden: hidden).filter(\.isDirectory) }
            DispatchQueue.main.async {
                guard self.generation == version else { return }
                node.loading = false
                switch result {
                case .success(let entries):
                    node.children = FileSystem.sorted(entries, by: .name, ascending: true).map { FolderNode($0.name, url: $0.url) }
                    self.outline.reloadItem(node, reloadChildren: true)
                    if node.wantsExpanded && self.outline.row(forItem: node) >= 0 {
                        self.applyExpansion(node, expanded: true)
                    }
                    self.restoreSelection()
                case .failure(let error):
                    node.error = error.localizedDescription
                    node.children = [FolderNode("Unavailable", children: [])]
                    node.children?.first?.error = error.localizedDescription
                    self.outline.reloadItem(node, reloadChildren: true)
                    if node.wantsExpanded && self.outline.row(forItem: node) >= 0 {
                        self.outline.expandItem(node, expandChildren: false)
                    }
                }
            }
        }
        return false
    }
    func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
        let node = item as! FolderNode
        guard rebuilding || !node.wantsExpanded || outline.userActionItem === node else { return false }
        node.wantsExpanded = false
        if outline.userActionItem === node { rememberExpansion(node, expanded: false) }
        return true
    }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let node = item as! FolderNode
        let cell = NSTableCellView()
        cell.toolTip = node.error ?? node.url?.path
        let label = NSTextField(labelWithString: node.title)
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: node.group ? 10 : 12, weight: node.group ? .semibold : .regular)
        label.textColor = node.group ? .secondaryLabelColor : .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label); cell.textField = label
        let disclosure = FolderDisclosureButton(title: node.title, expanded: node.wantsExpanded)
        disclosure.isHidden = !self.outlineView(outline, isItemExpandable: node)
        disclosure.onToggle = { [weak self] in self?.toggle(node) }
        disclosure.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(disclosure)
        NSLayoutConstraint.activate([disclosure.leadingAnchor.constraint(equalTo: cell.leadingAnchor), disclosure.centerYAnchor.constraint(equalTo: cell.centerYAnchor), disclosure.widthAnchor.constraint(equalToConstant: 16), disclosure.heightAnchor.constraint(equalToConstant: 22)])
        var leading = disclosure.trailingAnchor
        if let url = node.url {
            let image = NSImageView(image: BrowserLocation.icon(url))
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            NSLayoutConstraint.activate([image.leadingAnchor.constraint(equalTo: leading, constant: 6), image.centerYAnchor.constraint(equalTo: cell.centerYAnchor), image.widthAnchor.constraint(equalToConstant: 18), image.heightAnchor.constraint(equalToConstant: 18)])
            leading = image.trailingAnchor
        }
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: leading, constant: 6), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        return cell
    }
    @objc private func selected() {
        if let node = outline.item(atRow: outline.selectedRow) as? FolderNode, let url = node.url {
            UserDefaults.standard.set(selectionID(node), forKey: statePrefix + "selectedTreeItem")
            onNavigate?(url)
        }
    }
    @objc private func toggleClickedFolder() {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        guard let node = outline.item(atRow: row) as? FolderNode else { return }
        toggle(node)
    }
    private func toggle(_ node: FolderNode) {
        guard self.outlineView(outline, isItemExpandable: node) else { return }
        let expanded = node.loading ? !node.wantsExpanded : !outline.isItemExpanded(node)
        setExpansion(node, expanded: expanded)
    }
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? FolderNode, let url = node.url,
              (outlineView.parent(forItem: node) as? FolderNode) === roots.first else { return nil }
        let writer = NSPasteboardItem()
        writer.setString(url.path, forType: Self.favoriteDragType)
        return writer
    }
    private func favoriteDropIndex(item: Any?, childIndex: Int) -> Int? {
        guard let group = roots.first, let children = group.children,
              let node = item as? FolderNode else { return nil }
        if node === group {
            return childIndex == NSOutlineViewDropOnItemIndex ? children.count : ((0...children.count).contains(childIndex) ? childIndex : nil)
        }
        // Dropping on a favorite means inserting before it, never into its folder.
        return children.firstIndex { $0 === node }
    }
    private func moveFavorite(path: String, to insertionIndex: Int) -> Bool {
        var paths = favorites.map(\.path)
        guard (0...paths.count).contains(insertionIndex), let sourceIndex = paths.firstIndex(of: path) else { return false }
        let destinationIndex = insertionIndex > sourceIndex ? insertionIndex - 1 : insertionIndex
        guard destinationIndex != sourceIndex else { return true }
        paths.insert(paths.remove(at: sourceIndex), at: destinationIndex)
        UserDefaults.standard.set(paths, forKey: "favorites")
        publishSharedChange()
        return true
    }
    /// Folders dropped on the FAVORITES header or between favorites become favorites; dropped on a favorite, they copy into it.
    private func newFavoriteDrop(_ info: NSDraggingInfo, item: Any?, childIndex: Int) -> (index: Int, folders: [URL])? {
        guard let group = roots.first, (item as? FolderNode) === group, let children = group.children else { return nil }
        let urls = FileTransfer.urls(info)
        let folders = urls.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            return values?.isDirectory == true && values?.isPackage != true
        }
        guard !folders.isEmpty, folders.count == urls.count, folders.contains(where: { !isFavorite($0) }) else { return nil }
        let index = childIndex == NSOutlineViewDropOnItemIndex ? children.count : childIndex
        return (0...children.count).contains(index) ? (index, folders) : nil
    }
    private func addFavorites(_ urls: [URL], at index: Int) {
        var paths = favorites.map(\.path)
        var added: [String] = []
        for url in urls where !isFavorite(url) && !added.contains(url.standardizedFileURL.path) {
            added.append(url.standardizedFileURL.path)
        }
        paths.insert(contentsOf: added, at: min(index, paths.count))
        UserDefaults.standard.set(paths, forKey: "favorites")
        publishSharedChange()
    }
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        if let path = info.draggingPasteboard.string(forType: Self.favoriteDragType) {
            guard info.draggingSource is FolderOutlineView, favorites.contains(where: { $0.path == path }),
                  let insertionIndex = favoriteDropIndex(item: item, childIndex: index) else { return [] }
            outlineView.setDropItem(roots.first, dropChildIndex: insertionIndex)
            return .move
        }
        if let drop = newFavoriteDrop(info, item: item, childIndex: index) {
            outlineView.setDropItem(roots.first, dropChildIndex: drop.index)
            return [.link, .copy, .generic, .move].first { info.draggingSourceOperationMask.contains($0) } ?? []
        }
        guard let node = item as? FolderNode, node.url != nil else { return [] }
        outlineView.setDropItem(node, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return FileTransfer.dragOperation(info)
    }
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        if let path = info.draggingPasteboard.string(forType: Self.favoriteDragType) {
            guard info.draggingSource is FolderOutlineView,
                  let insertionIndex = favoriteDropIndex(item: item, childIndex: index) else { return false }
            return moveFavorite(path: path, to: insertionIndex)
        }
        if let drop = newFavoriteDrop(info, item: item, childIndex: index) {
            addFavorites(drop.folders, at: drop.index)
            return true
        }
        guard let node = item as? FolderNode, let destination = node.url else { return false }
        return FileTransfer.accept(info, destination: destination, perform: onDrop)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let node = outline.item(atRow: outline.clickedRow) as? FolderNode else { return }
        if node === roots.last {
            menu.addItem(withTitle: "Show All Filesystems", action: #selector(showAllVolumes), keyEquivalent: "").target = self
            return
        }
        guard let url = node.url else { return }
        if url == TrashStore.location {
            menu.addItem(withTitle: "Clear Trash…", action: #selector(clearTrash), keyEquivalent: "").target = self
            return
        }
        let info = menu.addItem(withTitle: "Get Info", action: #selector(getInfo(_:)), keyEquivalent: "")
        info.target = self; info.representedObject = url
        menu.addItem(.separator())
        appendContextItems(to: menu, for: url)
    }
    @objc private func getInfo(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { onGetInfo?(url) }
    }
    @objc private func clearTrash() { onClearTrash?() }
    // Both folder panes use the persisted favorites and current mount list at menu-open time.
    func appendContextItems(to menu: NSMenu, for url: URL) {
        let saved = isFavorite(url)
        let favorite = menu.addItem(withTitle: saved ? "Remove from Favorites" : "Add to Favorites", action: #selector(toggleFavoriteFromMenu(_:)), keyEquivalent: "")
        favorite.target = self; favorite.representedObject = url
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? []
        let mounted = url.path == "/" || volumes.contains(where: { $0.standardizedFileURL.path == url.standardizedFileURL.path })
        if mounted {
            menu.addItem(.separator())
            let hide = menu.addItem(withTitle: "Hide from Tree", action: #selector(hideVolume(_:)), keyEquivalent: "")
            hide.target = self; hide.representedObject = url
        }
        if mounted && url.path != "/" {
            let unmount = menu.addItem(withTitle: "Unmount \(url.lastPathComponent)", action: #selector(unmountVolume(_:)), keyEquivalent: "")
            unmount.target = self; unmount.representedObject = url
        }
    }
    @objc private func toggleFavoriteFromMenu(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        toggleFavorite(url)
    }
    @objc private func unmountVolume(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { onUnmount?(url) }
    }
    @objc private func hideVolume(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let paths = Set(hiddenVolumePaths + [url.standardizedFileURL.path])
        UserDefaults.standard.set(Array(paths).sorted(), forKey: "hiddenVolumes")
        publishSharedChange()
    }
    @objc private func showAllVolumes() {
        UserDefaults.standard.removeObject(forKey: "hiddenVolumes")
        publishSharedChange()
    }
}
