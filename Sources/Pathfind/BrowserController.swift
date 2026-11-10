import AppKit
import PathfindCore

final class BrowserController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate, NSSplitViewDelegate {
    private let sidebar: Sidebar
    private let table = FileTableView()
    private let icons = IconBrowser()
    private let split = SidebarSplitView()
    private let files = BrowserScrollView()
    private let tabStrip = TabStrip()
    private let backdrop = WindowBackdrop()
    private let sidebarPane = BrowserViewport()
    private let contentPane = BrowserViewport()
    private let topChrome = NSView()
    private let titlebarChrome = NSView()
    private let windowOutline = WindowOutlineView()
    private let infoPresenter = FileInfoPresenter()
    private let trashStore: TrashStore
    private let trashActions: TrashActions
    private var creationButtons: [NSButton] = []
    private var favoriteButton: NSButton?
    private var settingsButton: NSButton?
    private let updateBadge = UpdateBadgeView()
    private let ancestorPathBar = AncestorPathBar()
    private let folderWatcher = FolderWatcher()
    private let indexedSearch: IndexedFolderSearch
    private var searchEntries: [FileEntry] = []
    private var searchState = IndexedFolderSearch.State.live
    private var isSearching: Bool { !search.stringValue.isEmpty }
    private var isTrashBrowsing: Bool { trashStore.contains(current) }
    private var tabs: BrowserTabs
    let windowID: UUID
    private let statePrefix: String
    var onSessionChanged: (() -> Void)?
    var onTabDrop: ((TabTransfer, UUID?) -> Bool)?
    var onDetachTab: ((UUID, NSPoint) -> Void)?
    /// The tabs as they look right now, including the active tab's selection and scroll position.
    var sessionTabs: BrowserTabs {
        var saved = tabs
        saved.current.selection = selection.map(\.url)
        saved.current.scrollOffset = Double(activeScroll.contentView.bounds.origin.y)
        return saved
    }
    /// Saved selection and scroll waiting for a folder (or its search results) to finish loading.
    private var pendingRestore: (folder: URL, selection: Set<URL>, scroll: Double?)?
    private var activeScroll: NSScrollView { isSearching || folderView.mode != .icons ? files : icons.scroll }
    private func rememberActiveTabState() {
        guard pendingRestore == nil else { return }
        tabs.current.selection = selection.map(\.url)
        tabs.current.scrollOffset = Double(activeScroll.contentView.bounds.origin.y)
    }
    private func restoreTabState() {
        pendingRestore = (current.standardizedFileURL, Set((tabs.current.selection ?? []).map(\.standardizedFileURL)), tabs.current.scrollOffset)
    }
    private func applyPendingRestore() {
        guard let restore = pendingRestore else { return }
        pendingRestore = nil
        guard restore.folder == current.standardizedFileURL else { return }
        let indexes = visible.indices.filter { restore.selection.contains(visible[$0].url.standardizedFileURL) }
        table.selectRowIndexes(IndexSet(indexes), byExtendingSelection: false)
        if !isSearching { icons.collection.selectionIndexPaths = Set(indexes.map { IndexPath(item: $0, section: 0) }) }
        let scroll = activeScroll
        scroll.layoutSubtreeIfNeeded()
        if let offset = restore.scroll, let document = scroll.documentView {
            let maxY = max(0, document.frame.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(maxY, max(0, offset))))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        updateStatus()
    }
    var canTransferTabs: Bool { !busy }
    private let iconSlider = LiveSlider(value: 64, minValue: 32, maxValue: 160, target: nil, action: nil)
    private let spacingSlider = LiveSlider(value: 10, minValue: 0, maxValue: 40, target: nil, action: nil)
    private let viewMenu = NSMenu(), sortMenu = NSMenu()
    private let viewToggle = NSSegmentedControl()
    private let viewStore = FolderViewStore()
    private let hiddenFiles = HiddenFileStore()
    private var folderView = FolderViewPreferences()
    private var restoringView = true
    private var restoringLayout = true
    private let dragSource = FileDragSource()
    private var permissionsPanel: PermissionsController?
    private let path = HeaderTextField()
    private var pathCompletion: PathCompletionController?
    private let search = HeaderTextField(symbol: "magnifyingglass")
    private var fieldSurfaces: [NSView] = []
    private let status = NSTextField(labelWithString: "")
    private let hidden = GlassToolbarButton()
    private let folderHidden = GlassToolbarButton()
    private var current: URL { get { tabs.current.url } set { tabs.current.url = newValue } }
    private var entries: [FileEntry] = []
    private var visible: [FileEntry] = []
    private var history: NavigationHistory { get { tabs.current.history } set { tabs.current.history = newValue } }
    private let queue = DispatchQueue(label: "pathfind.files", qos: .userInitiated)
    private var request = 0
    private var busy = false
    private var monitor: Any?
    private var sortKey: FileSort { get { folderView.sort } set { folderView.sort = newValue } }
    private var ascending: Bool { get { folderView.ascending } set { folderView.ascending = newValue } }
    private var showHidden: Bool { hiddenFiles.showsHidden(in: current) }
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short; return formatter
    }()

    init(tabs initialTabs: BrowserTabs? = nil, windowID: UUID? = nil, trashStore: TrashStore = .shared, indexedSearch: IndexedFolderSearch = IndexedFolderSearch()) {
        self.indexedSearch = indexedSearch
        self.trashStore = trashStore; trashActions = TrashActions(store: trashStore)
        self.windowID = windowID ?? UUID()
        statePrefix = windowID.map { $0.uuidString + "." } ?? ""
        sidebar = Sidebar(stateID: windowID?.uuidString)
        tabs = initialTabs ?? BrowserTabs.restore(fallback: FileManager.default.homeDirectoryForCurrentUser)
        BrowserTheme.initializeAccent()
        let window = BrowserWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
                              styleMask: [.borderless, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.hasShadow = true
        super.init(window: window)
        window.title = "Explorer"
        window.minSize = NSSize(width: 900, height: 440)
        window.center()
        if windowID == nil { window.setFrameAutosaveName("PathfindBrowser") }
        buildUI(window)
        window.initialFirstResponder = icons.collection
        tabStrip.onSelect = { [weak self] id in self?.selectTab(id) }
        tabStrip.onClose = { [weak self] id in self?.closeTab(id) }
        tabStrip.onNew = { [weak self] in self?.newTab() }
        tabStrip.windowID = self.windowID
        tabStrip.onTabDrop = { [weak self] payload, before in self?.onTabDrop?(payload, before) ?? false }
        tabStrip.onDetach = { [weak self] id, point in self?.onDetachTab?(id, point) }
        tabStrip.onDrop = { [weak self] urls, destination, move in self?.transfer(urls, into: destination, move: move) }
        tabStrip.update(tabs)
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: BrowserTheme.changed, object: nil)
        appearanceChanged()
        restoringView = false
        window.contentView?.layoutSubtreeIfNeeded()
        let savedWidth = (UserDefaults.standard.object(forKey: statePrefix + "sidebarWidth") as? Double) ?? UserDefaults.standard.double(forKey: "sidebarWidth")
        split.setPosition(savedWidth > 0 ? savedWidth : 230, ofDividerAt: 0)
        restoringLayout = false
        sidebar.reload()
        sidebar.onNavigate = { [weak self] url in self?.navigate(url) }
        sidebar.onUnmount = { [weak self] url in self?.unmount(url) }
        sidebar.onGetInfo = { [weak self] url in self?.showInfo(for: [url]) }
        sidebar.onClearTrash = { [weak self] in self?.clearTrash() }
        sidebar.onFavoritesChanged = { [weak self] in self?.updateFavoriteButton() }
        let transfer: ([URL], URL, Bool) -> Void = { [weak self] urls, destination, move in self?.transfer(urls, into: destination, move: move) }
        sidebar.onDrop = transfer; icons.onDrop = transfer
        icons.onOpen = { [weak self] in self?.openSelection() }
        icons.onSelection = { [weak self] in self?.updateStatus() }
        table.onRightDrag = { [weak self] event in
            guard let self else { return }
            self.dragSource.begin(urls: self.selection.map(\.url), in: self.table, event: event)
        }
        icons.collection.onRightDrag = { [weak self] event in
            guard let self else { return }
            self.dragSource.begin(urls: self.selection.map(\.url), in: self.icons.collection, event: event)
        }
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(volumesChanged(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(otherWindowChangedFiles(_:)), name: .pathfindFilesChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(hiddenFilesChanged(_:)), name: HiddenFileStore.changed, object: nil)
        folderWatcher.onChange = { [weak self] in self?.reloadObservedFolder() }
        NotificationCenter.default.addObserver(self, selector: #selector(reloadObservedFolder), name: NSApplication.didBecomeActiveNotification, object: nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window == self.window else { return event }
            if event.type == .keyDown { return self.handleKey(event) ? nil : event }
            self.releaseInputFocusForHeaderClick(event)
            return event
        }
        restoreTabState()
        navigate(current, record: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    private func button(_ symbol: String, _ title: String, _ action: Selector, size: CGFloat = 30) -> NSButton {
        let button = GlassToolbarButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = false; button.contentTintColor = .labelColor
        button.setAccessibilityLabel(title)
        ToolbarHelp.install(on: button, text: title)
        button.widthAnchor.constraint(equalToConstant: size).isActive = true
        button.heightAnchor.constraint(equalToConstant: size).isActive = true
        button.image = button.image?.withSymbolConfiguration(.init(pointSize: size >= 36 ? 18 : 15, weight: .regular))
        return button
    }
    private func buildUI(_ window: NSWindow) {
        let root = ChromeView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.onAppearanceChange = { [weak self] in self?.appearanceChanged() }
        window.contentView = backdrop
        backdrop.install(root)
        for background in [titlebarChrome, topChrome] {
            background.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(background)
        }
        hidden.title = "Hidden files"
        hidden.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        folderHidden.image = ToolbarImages.folderEye
        for control in [hidden, folderHidden] {
            control.setButtonType(.toggle); control.bezelStyle = .texturedRounded
            control.isBordered = false; control.imagePosition = .imageOnly
            control.contentTintColor = .labelColor
            control.widthAnchor.constraint(equalToConstant: 30).isActive = true
            control.heightAnchor.constraint(equalToConstant: 30).isActive = true
            control.target = self
        }
        hidden.action = #selector(toggleHidden)
        hidden.setAccessibilityLabel("Show hidden files by default")
        ToolbarHelp.install(on: hidden, text: "Show hidden files by default (⌘⇧.). Folders can override this.")
        folderHidden.action = #selector(toggleFolderHidden)
        folderHidden.setAccessibilityLabel("Show hidden files in this folder")
        ToolbarHelp.install(on: folderHidden, text: "Show hidden files in this folder — saved for this folder only")
        let hiddenMenu = NSMenu()
        hiddenMenu.addItem(withTitle: "Use default hidden-file setting for this folder", action: #selector(useDefaultHiddenFiles), keyEquivalent: "").target = self
        folderHidden.menu = hiddenMenu
        updateHiddenControls()
        search.placeholderString = "Search this folder and subfolders"
        search.hidesPlaceholderWhileEditing = true
        search.setAccessibilityLabel("Search this folder")
        search.delegate = self
        search.controlSize = .large
        search.font = .systemFont(ofSize: 14)
        search.heightAnchor.constraint(equalToConstant: 36).isActive = true
        search.widthAnchor.constraint(equalToConstant: 280).isActive = true
        let viewControl = NSPopUpButton(frame: .zero, pullsDown: true)
        viewControl.isBordered = false
        if #available(macOS 26, *) { viewControl.widthAnchor.constraint(equalToConstant: 40).isActive = true }
        ToolbarHelp.install(on: viewControl, text: "Folder view options")
        viewControl.setAccessibilityLabel("View options")
        viewMenu.delegate = self; viewControl.menu = viewMenu
        rebuildViewMenu()
        viewToggle.segmentCount = 2
        viewToggle.setImage(NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Icons view"), forSegment: 0)
        viewToggle.setImage(NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Details view"), forSegment: 1)
        viewToggle.setWidth(32, forSegment: 0); viewToggle.setWidth(32, forSegment: 1)
        viewToggle.trackingMode = .selectOne
        viewToggle.target = self; viewToggle.action = #selector(changeViewSegment(_:))
        viewToggle.setAccessibilityLabel("Folder view")
        ToolbarHelp.install(on: viewToggle, text: "Icons / Details view", textAtPoint: { [weak viewToggle] point in
            point.x < (viewToggle?.bounds.midX ?? 32) ? "Icons view" : "Details view"
        })
        let sortControl = NSPopUpButton(frame: .zero, pullsDown: true)
        sortMenu.delegate = self; sortControl.menu = sortMenu
        rebuildSortMenu()
        ToolbarHelp.install(on: sortControl, text: "Sort files and folders")
        iconSlider.target = self; iconSlider.action = #selector(iconSizeChanged)
        iconSlider.isContinuous = true
        iconSlider.widthAnchor.constraint(equalToConstant: 110).isActive = true
        iconSlider.setAccessibilityLabel("Icon size")
        ToolbarHelp.install(on: iconSlider, text: "Icon size")
        spacingSlider.target = self; spacingSlider.action = #selector(iconSpacingChanged)
        spacingSlider.isContinuous = true; spacingSlider.controlSize = .small
        spacingSlider.widthAnchor.constraint(equalToConstant: 56).isActive = true
        spacingSlider.setAccessibilityLabel("Icon spacing")
        ToolbarHelp.install(on: spacingSlider, text: "Icon spacing — tight to wide")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true
        path.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        path.controlSize = .large
        path.heightAnchor.constraint(equalToConstant: 36).isActive = true
        path.placeholderString = "Enter a path, then press Return"
        path.bezelStyle = .roundedBezel
        path.target = self; path.action = #selector(pathEntered)
        path.setAccessibilityLabel("Current folder path")
        pathCompletion = PathCompletionController(field: path, baseURL: { [weak self] in
            guard let self, self.current.isFileURL else { return FileManager.default.homeDirectoryForCurrentUser }
            return self.current
        })
        path.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let connect = button("server.rack", "Connect to Server (⌘K)", #selector(connectToServer))
        connect.setAccessibilityLabel("Connect to Server")
        let pathSurface = GlassControls.fieldSurface(for: path)
        let searchSurface = GlassControls.fieldSurface(for: search)
        if searchSurface !== search { searchSurface.widthAnchor.constraint(equalToConstant: 280).isActive = true }
        pathSurface.setContentHuggingPriority(.defaultLow, for: .horizontal)
        fieldSurfaces = [pathSurface, searchSurface]
        let navigation = NSStackView(views: fieldSurfaces)
        searchSurface.trailingAnchor.constraint(equalTo: navigation.trailingAnchor).isActive = true
        navigation.spacing = 6
        navigation.heightAnchor.constraint(equalToConstant: 52).isActive = true
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        creationButtons = [button("folder.badge.plus", "New folder (⌘⇧N)", #selector(newFolder)), button("doc.badge.plus", "New file", #selector(newFile))]
        let favorite = button("star", "Add selected folder to Favorites", #selector(toggleSelectedFavorite))
        favorite.setButtonType(.toggle)
        favorite.isEnabled = false
        favoriteButton = favorite
        let settings = button("gearshape", "Settings (⌘,)", #selector(showSettings))
        settingsButton = settings
        updateBadge.translatesAutoresizingMaskIntoConstraints = false
        settings.addSubview(updateBadge)
        NSLayoutConstraint.activate([updateBadge.widthAnchor.constraint(equalToConstant: 8), updateBadge.heightAnchor.constraint(equalToConstant: 8), updateBadge.trailingAnchor.constraint(equalTo: settings.trailingAnchor), updateBadge.topAnchor.constraint(equalTo: settings.topAnchor)])
        NotificationCenter.default.addObserver(self, selector: #selector(updateIndicatorChanged), name: AppUpdater.changed, object: nil)
        updateIndicatorChanged()
        let commands = NSStackView(views: [
            creationButtons[0], creationButtons[1],
            divider(), button("scissors", "Cut (⌘X)", #selector(cutFiles)),
            button("rectangle.portrait.on.rectangle.portrait", "Copy (⌘C)", #selector(copyFiles)),
            button("clipboard", "Paste (⌘V)", #selector(pasteFiles)),
            button("pencil", "Rename (F2)", #selector(rename)),
            button("trash", "Move to Trash (⌘Delete)", #selector(trash)),
            divider(), sortControl, viewToggle, viewControl, iconSlider, spacingSlider, divider(), hidden, folderHidden,
            favorite, connect, spacer,
            settings
        ])
        commands.spacing = 6; commands.heightAnchor.constraint(equalToConstant: 36).isActive = true
        commands.setCustomSpacing(28, after: favorite)
        commands.setCustomSpacing(4, after: iconSlider)
        let top = NSStackView(views: [navigation, commands])
        top.orientation = .vertical; top.alignment = .leading; top.spacing = 10
        top.heightAnchor.constraint(equalToConstant: 98).isActive = true
        for row in [navigation, commands] { row.widthAnchor.constraint(equalTo: top.widthAnchor).isActive = true }
        split.isVertical = true; split.dividerStyle = .thin; split.delegate = self
        sidebarPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        split.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        files.documentView = table; files.hasVerticalScroller = true; files.hasHorizontalScroller = true
        files.automaticallyAdjustsContentInsets = false
        files.autohidesScrollers = true
        files.scrollerStyle = .overlay
        table.style = .fullWidth; table.rowHeight = 29
        table.backgroundColor = .clear
        files.drawsBackground = false
        table.usesAlternatingRowBackgroundColors = false
        table.allowsMultipleSelection = true
        table.delegate = self; table.dataSource = self
        table.target = self; table.doubleAction = #selector(openSelection)
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        configureTableColumns()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        table.menu = menu
        icons.collection.menu = menu
        for view in [files, icons.scroll] {
            contentPane.install(view)
        }
        installAncestorPathBar()
        sidebarPane.install(sidebar.scroll)
        split.addArrangedSubview(sidebarPane); split.addArrangedSubview(contentPane)
        // The sidebar keeps its width when the window resizes, so a restored window looks the same.
        split.setHoldingPriority(.init(260), forSubviewAt: 0)
        split.setHoldingPriority(.init(250), forSubviewAt: 1)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        for view in [tabStrip, top, split, status] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            titlebarChrome.topAnchor.constraint(equalTo: root.topAnchor), titlebarChrome.leadingAnchor.constraint(equalTo: root.leadingAnchor), titlebarChrome.trailingAnchor.constraint(equalTo: root.trailingAnchor), titlebarChrome.bottomAnchor.constraint(equalTo: topChrome.topAnchor),
            topChrome.topAnchor.constraint(equalTo: tabStrip.bottomAnchor), topChrome.leadingAnchor.constraint(equalTo: root.leadingAnchor), topChrome.trailingAnchor.constraint(equalTo: root.trailingAnchor), topChrome.bottomAnchor.constraint(equalTo: split.topAnchor),
            tabStrip.topAnchor.constraint(equalTo: root.topAnchor), tabStrip.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 94), tabStrip.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12), tabStrip.heightAnchor.constraint(equalToConstant: 46),
            top.topAnchor.constraint(equalTo: tabStrip.bottomAnchor, constant: 10), top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20), top.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            split.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 14), split.leadingAnchor.constraint(equalTo: root.leadingAnchor), split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            status.topAnchor.constraint(equalTo: split.bottomAnchor, constant: 7), status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -7), status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16)
        ])
        installWindowControls(in: root, window: window)
        windowOutline.frame = root.bounds
        windowOutline.autoresizingMask = [.width, .height]
        root.addSubview(windowOutline)
        let resize = WindowResizeView(frame: root.bounds)
        resize.autoresizingMask = [.width, .height]
        root.addSubview(resize)
    }
    private func installWindowControls(in root: NSView, window: NSWindow) {
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = true
        }
        let controls: [(NSWindow.ButtonType, Selector)] = [(.closeButton, #selector(NSWindow.performClose(_:))), (.miniaturizeButton, #selector(NSWindow.performMiniaturize(_:))), (.zoomButton, #selector(NSWindow.performZoom(_:)))]
        for (index, definition) in controls.enumerated() {
            guard let control = NSWindow.standardWindowButton(definition.0, for: [.titled, .closable, .miniaturizable, .resizable]) else { continue }
            control.target = window; control.action = definition.1
            control.translatesAutoresizingMaskIntoConstraints = false
            control.isHidden = false; control.alphaValue = 1
            ToolbarHelp.install(on: control, text: ["Close window", "Minimize window", "Maximize / restore window"][index])
            root.addSubview(control)
            NSLayoutConstraint.activate([control.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16 + CGFloat(index * 20)), control.topAnchor.constraint(equalTo: root.topAnchor, constant: 14), control.widthAnchor.constraint(equalToConstant: 14), control.heightAnchor.constraint(equalToConstant: 14)])
        }
    }
    private func divider() -> NSView {
        let separator = NSBox(); separator.boxType = .separator
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return separator
    }
    private func installAncestorPathBar() {
        ancestorPathBar.onNavigate = { [weak self] in self?.navigate($0) }
        contentPane.installHeader(ancestorPathBar)
    }
    private var parentLocation: URL? {
        guard current != TrashStore.location, current.path != "/" else { return nil }
        let parent = current.deletingLastPathComponent()
        return isTrashBrowsing && trashStore.isRoot(parent) ? TrashStore.location : parent
    }
    private func updateAncestorPathBar() {
        var ancestors: [URL] = []
        var parent = parentLocation
        while let location = parent {
            ancestors.insert(location, at: 0)
            if location == TrashStore.location || location.path == "/" { break }
            let next = location.deletingLastPathComponent()
            parent = isTrashBrowsing && trashStore.isRoot(next) ? TrashStore.location : next
        }
        ancestorPathBar.update(ancestors)
        contentPane.headerHeight = 40
    }

    func navigate(_ destination: URL, record: Bool = true, historyOnSuccess: NavigationHistory? = nil, selecting urls: [URL] = []) {
        guard !busy else { return }
        pathCompletion?.dismiss()
        indexedSearch.cancel()
        let url = destination.isFileURL && trashStore.isRoot(destination) ? TrashStore.location : destination
        if !hiddenFiles.showsHidden(in: url), urls.contains(where: {
            $0.lastPathComponent.hasPrefix(".") || (try? $0.resourceValues(forKeys: [.isHiddenKey]).isHidden) == true
        }) {
            hiddenFiles.set(true, for: url)
        }
        request += 1
        var preferences = viewStore.view(for: url)
        if !urls.isEmpty { preferences.filter = "" }
        let version = request, showHidden = hiddenFiles.showsHidden(in: url)
        status.stringValue = "Loading \(url.path)…"
        queue.async {
            let result = Result { try url == TrashStore.location ? self.trashStore.contents(showHidden: showHidden) : FileSystem.contents(of: url, showHidden: showHidden) }
            DispatchQueue.main.async {
                guard self.request == version else { return }
                switch result {
                case .success(let entries):
                    self.current = url; self.entries = entries
                    self.folderWatcher.watch(url == TrashStore.location ? self.trashStore.directories : [url])
                    if let historyOnSuccess { self.history = historyOnSuccess }
                    else if record { self.history.visit(url) }
                    self.onSessionChanged?(); self.tabStrip.update(self.tabs)
                    self.path.stringValue = BrowserLocation.path(url)
                    self.window?.title = "\(BrowserLocation.title(url)) — Explorer"
                    self.window?.representedURL = url
                    self.applyView(preferences)
                    self.creationButtons.forEach { $0.isEnabled = !self.isTrashBrowsing }
                    self.table.deselectAll(nil)
                    self.applyFilter()
                    if !self.isSearching { self.applyPendingRestore() }
                    if !urls.isEmpty {
                        let selected = Set(urls.map(\.standardizedFileURL))
                        let indexes = self.visible.indices.filter { selected.contains(self.visible[$0].url.standardizedFileURL) }
                        self.table.selectRowIndexes(IndexSet(indexes), byExtendingSelection: false)
                        self.icons.collection.selectionIndexPaths = Set(indexes.map { IndexPath(item: $0, section: 0) })
                        if let first = indexes.first {
                            self.table.scrollRowToVisible(first)
                            self.icons.collection.scrollToItems(at: [IndexPath(item: first, section: 0)], scrollPosition: .nearestHorizontalEdge)
                        }
                        self.updateStatus()
                    }
                case .failure(let error):
                    self.pendingRestore = nil
                    self.path.stringValue = BrowserLocation.path(self.current)
                    self.updateStatus()
                    self.show(error)
                }
            }
        }
    }
    @objc private func reloadObservedFolder() {
        guard !busy else { return }
        let url = current, version = request, showHidden = showHidden
        queue.async {
            let result = Result { try url == TrashStore.location ? self.trashStore.contents(showHidden: showHidden) : FileSystem.contents(of: url, showHidden: showHidden) }
            DispatchQueue.main.async {
                guard self.request == version, self.current == url, !self.busy else { return }
                guard case .success(let entries) = result else { return }
                let selected = Set(self.selection.map(\.url))
                self.entries = entries
                if self.isSearching { self.sidebar.reload(); return }
                self.applyFilter()
                let indexes = self.visible.indices.filter { selected.contains(self.visible[$0].url) }
                self.table.selectRowIndexes(IndexSet(indexes), byExtendingSelection: false)
                self.icons.collection.selectionIndexPaths = Set(indexes.map { IndexPath(item: $0, section: 0) })
                self.updateStatus()
                self.sidebar.reload()
            }
        }
    }
    private func applyFilter() {
        updateFilePanePresentation()
        if isSearching {
            let roots = current == TrashStore.location ? trashStore.directories : [current]
            indexedSearch.start(text: search.stringValue, roots: roots, showHidden: showHidden) { [weak self] matches, state in
                guard let self, self.isSearching else { return }
                self.searchEntries = matches; self.searchState = state
                self.renderSearchResults()
            }
            return
        }
        indexedSearch.cancel(); searchEntries = []
        visible = FileSystem.sorted(entries, by: sortKey, ascending: ascending, foldersFirst: folderView.foldersFirst)
        table.reloadData(); icons.reload(visible); updateStatus()
    }
    private func renderSearchResults() {
        let selected = Set(selection.map(\.url))
        let sort = table.sortDescriptors.first
        if sort?.key == "path" {
            visible = searchEntries.sorted {
                let order = $0.url.path.localizedStandardCompare($1.url.path)
                return sort?.ascending == false ? order == .orderedDescending : order == .orderedAscending
            }
        } else {
            visible = FileSystem.sorted(searchEntries, by: FileSort(rawValue: sort?.key ?? "") ?? sortKey, ascending: sort?.ascending ?? ascending, foldersFirst: folderView.foldersFirst)
        }
        table.reloadData()
        table.selectRowIndexes(IndexSet(visible.indices.filter { selected.contains(visible[$0].url) }), byExtendingSelection: false)
        updateStatus()
        if searchState != .gathering { applyPendingRestore() }
    }
    private func updateStatus() {
        let count = visible.count, selected = selection.count
        if isSearching {
            let progress = searchState == .gathering ? "Searching Spotlight…" : searchState == .unavailable ? "Spotlight search is unavailable" : "Spotlight"
            status.stringValue = "\(count) results" + (selected > 0 ? " · \(selected) selected" : "") + " · \(progress) · Folder and subfolders · Excluded locations are not searched"
            updateFavoriteButton()
            return
        }
        status.stringValue = "\(count) items" + (selected > 0 ? " · \(selected) selected" : "") + "    ·    \(BrowserLocation.path(current))" + (showHidden ? "    ·    Hidden files visible" : "")
        updateFavoriteButton()
    }
    func controlTextDidChange(_ obj: Notification) {
        folderView.filter = search.stringValue; saveView(); applyView(folderView); applyFilter()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        FileRowView(alternate: row % 2 == 1)
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateStatus() }
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !restoringView else { return }
        if isSearching { renderSearchResults(); return }
        guard let sort = tableView.sortDescriptors.first, let key = sort.key, let value = FileSort(rawValue: key) else { return }
        sortKey = value; ascending = sort.ascending; saveView(); applyFilter()
    }
    func tableViewColumnDidResize(_ notification: Notification) { saveColumnLayout() }
    func tableViewColumnDidMove(_ notification: Notification) { saveColumnLayout() }
    private func saveColumnLayout() {
        guard !restoringView, !isSearching else { return }
        folderView.columnWidths = Dictionary(uniqueKeysWithValues: table.tableColumns.map { ($0.identifier.rawValue, Double($0.width)) })
        folderView.columnOrder = table.tableColumns.map { $0.identifier.rawValue }
        saveView()
    }
    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !restoringLayout, sidebar.scroll.frame.width >= 170 else { return }
        UserDefaults.standard.set(sidebar.scroll.frame.width, forKey: statePrefix + "sidebarWidth")
    }
    private func applyView(_ view: FolderViewPreferences) {
        restoringView = true
        defer { restoringView = false }
        folderView = view
        viewToggle.selectedSegment = view.mode == .icons ? 0 : 1
        if search.stringValue != view.filter { search.stringValue = view.filter }
        updateHiddenControls()
        configureTableColumns()
        table.sortDescriptors = [NSSortDescriptor(key: view.sort.rawValue, ascending: view.ascending)]
        for (target, id) in (isSearching ? [] : view.columnOrder).enumerated() {
            let index = table.column(withIdentifier: .init(id))
            if index >= 0 && index != target && target < table.tableColumns.count { table.moveColumn(index, toColumn: target) }
        }
        for column in table.tableColumns where !isSearching {
            column.width = max(70, view.columnWidths[column.identifier.rawValue] ?? defaultColumnWidth(column.identifier.rawValue))
        }
        icons.iconSize = min(160, max(32, view.iconSize))
        icons.iconSpacing = min(40, max(0, view.iconSpacing ?? 10))
        icons.currentFolder = current
        iconSlider.doubleValue = Double(icons.iconSize)
        spacingSlider.doubleValue = Double(icons.iconSpacing)
        updateFilePanePresentation()
        updateAncestorPathBar()
    }
    private func configureTableColumns() {
        let definitions: [(String, String, Double)] = isSearching
            ? [("name", "Name", 300), ("path", "Full Path", 600)]
            : [("name", "Name", 350), ("modified", "Date modified", 170), ("kind", "Kind", 140), ("size", "Size", 85)]
        guard Set(table.tableColumns.map { $0.identifier.rawValue }) != Set(definitions.map { $0.0 }) else { return }
        let wasRestoring = restoringView; restoringView = true
        defer { restoringView = wasRestoring }
        table.tableColumns.forEach { table.removeTableColumn($0) }
        for (key, title, width) in definitions {
            let column = NSTableColumn(identifier: .init(key)); column.title = title; column.width = width; column.minWidth = 70
            column.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: true)
            table.addTableColumn(column)
        }
        table.sortDescriptors = [NSSortDescriptor(key: sortKey.rawValue, ascending: ascending)]
        table.setAccessibilityLabel(isSearching ? "Search results" : "Folder contents")
    }
    private func updateFilePanePresentation() {
        configureTableColumns()
        files.isHidden = !isSearching && folderView.mode != .details
        icons.scroll.isHidden = isSearching || folderView.mode != .icons
        viewToggle.isEnabled = !isSearching
        viewToggle.selectedSegment = isSearching || folderView.mode == .details ? 1 : 0
        updateSizeSliderVisibility()
    }
    private func defaultColumnWidth(_ key: String) -> Double {
        ["name": 350, "modified": 170, "kind": 140, "size": 85][key] ?? 100
    }
    private func updateSizeSliderVisibility() {
        iconSlider.isHidden = isSearching || folderView.mode != .icons
        spacingSlider.isHidden = iconSlider.isHidden
    }
    private func saveView() { if !restoringView { viewStore.save(folderView, for: current) } }
    private func rebuildViewMenu() {
        viewMenu.removeAllItems()
        viewMenu.addItem(withTitle: "⋯", action: nil, keyEquivalent: "")
        viewMenu.addItem(withTitle: "Make Current View the Default", action: #selector(makeViewDefault), keyEquivalent: "").target = self
        viewMenu.addItem(withTitle: "Restore Default for This Folder", action: #selector(restoreViewDefault), keyEquivalent: "").target = self
    }
    private func rebuildSortMenu() {
        sortMenu.removeAllItems()
        sortMenu.addItem(withTitle: "Sort", action: nil, keyEquivalent: "")
        for (key, label) in [(FileSort.name, "Name (Alphabetical)"), (.modified, "Date Modified"), (.kind, "Kind"), (.size, "Size")] {
            let item = sortMenu.addItem(withTitle: label, action: #selector(changeSort(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = key.rawValue; item.state = sortKey == key ? .on : .off
        }
        sortMenu.addItem(.separator())
        for (label, value) in [("Ascending", true), ("Descending", false)] {
            let item = sortMenu.addItem(withTitle: label, action: #selector(changeSortDirection(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = value; item.state = ascending == value ? .on : .off
        }
        sortMenu.addItem(.separator())
        let first = sortMenu.addItem(withTitle: "Folders First", action: #selector(toggleFoldersFirst), keyEquivalent: "")
        first.target = self; first.state = folderView.foldersFirst ? .on : .off
    }
    @objc private func changeViewSegment(_ sender: NSSegmentedControl) {
        let mode: FolderViewMode = sender.selectedSegment == 0 ? .icons : .details
        folderView.mode = mode; saveView(); applyView(folderView)
        window?.makeFirstResponder(mode == .icons ? icons.collection : table)
    }
    @objc private func iconSizeChanged() {
        folderView.iconSize = iconSlider.doubleValue
        icons.iconSize = iconSlider.doubleValue; saveView()
    }
    @objc private func iconSpacingChanged() {
        folderView.iconSpacing = spacingSlider.doubleValue
        icons.iconSpacing = spacingSlider.doubleValue; saveView()
    }
    @objc private func makeViewDefault() {
        var defaults = folderView; defaults.filter = ""
        viewStore.makeDefault(defaults)
        status.stringValue = "Current view is now the default for folders without a saved view."
    }
    @objc private func restoreViewDefault() {
        viewStore.restoreDefault(for: current); navigate(current)
    }
    @objc private func changeSort(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let sort = FileSort(rawValue: value) else { return }
        sortKey = sort; saveView(); applyView(folderView); applyFilter()
    }
    @objc private func changeSortDirection(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Bool else { return }
        ascending = value; saveView(); applyView(folderView); applyFilter()
    }
    @objc private func toggleFoldersFirst() { folderView.foldersFirst.toggle(); saveView(); applyFilter() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = visible[row]
        let key = tableColumn!.identifier.rawValue
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        label.textColor = entry.isHidden ? .secondaryLabelColor : .labelColor
        switch key {
        case "name": label.stringValue = entry.name
        case "modified": label.stringValue = dateFormatter.string(from: entry.modified)
        case "kind": label.stringValue = entry.kind
        case "path": label.stringValue = entry.url.path; label.toolTip = entry.url.path
        default:
            label.stringValue = entry.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
            label.alignment = .right
        }
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label); cell.textField = label
        var inset: CGFloat = 8
        if key == "name" {
            let icon = FilePreviewImageView()
            let iconSize: CGFloat = 19
            icon.configure(for: entry, size: iconSize, scale: tableView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
            icon.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(icon)
            NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: iconSize), icon.heightAnchor.constraint(equalToConstant: iconSize)])
            inset = 35
        }
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: inset), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        return cell
    }
    private var selection: [FileEntry] {
        let indexes = !isSearching && folderView.mode == .icons ? icons.collection.selectionIndexPaths.map(\.item).sorted() : Array(table.selectedRowIndexes)
        return indexes.compactMap { visible.indices.contains($0) ? visible[$0] : nil }
    }
    @objc private func updateIndicatorChanged() {
        let available = AppUpdater.shared.state.hasUpdate
        updateBadge.isHidden = !available
        settingsButton?.setAccessibilityLabel(available ? "Settings — update available" : "Settings")
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === viewMenu { rebuildViewMenu(); return }
        if menu === sortMenu { rebuildSortMenu(); return }
        menu.removeAllItems()
        let actions: [(String, Selector)]
        if isTrashBrowsing {
            actions = selection.isEmpty ? [("Clear Trash…", #selector(clearTrash)), ("Refresh", #selector(refresh))] : [("Open", #selector(openSelection)), ("Get Info", #selector(getInfo)), ("Restore", #selector(restoreTrashSelection)), ("Copy", #selector(copyFiles)), ("Copy Path", #selector(copyPath)), ("Reveal in Finder", #selector(reveal))]
        } else if selection.isEmpty {
            actions = [("New Folder…", #selector(newFolder)), ("New File…", #selector(newFile)), ("Paste", #selector(pasteFiles)), ("Refresh", #selector(refresh))]
        } else {
            actions = [("Open", #selector(openSelection)), ("Get Info", #selector(getInfo)), ("Duplicate", #selector(duplicate)), ("Copy", #selector(copyFiles)), ("Cut", #selector(cutFiles)), ("Rename…", #selector(rename)), ("Move to Trash…", #selector(trash)), ("Copy Path", #selector(copyPath)), ("Permissions…", #selector(editPermissions)), ("Reveal in Finder", #selector(reveal))]
        }
        for (title, action) in actions {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self; item.isEnabled = !busy
            if action == #selector(rename) { item.isEnabled = !busy && selection.count == 1 }
            if action == #selector(pasteFiles) {
                item.isEnabled = !busy && NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            }
        }
        if !isTrashBrowsing, selection.isEmpty {
            TerminalLauncher.shared.appendItem(to: menu, folder: current)
        }
        if !isTrashBrowsing, selection.count == 1, let entry = selection.first, entry.isDirectory {
            menu.addItem(.separator())
            sidebar.appendContextItems(to: menu, for: entry.url)
        }
    }
    @objc private func pathEntered() {
        if ["trash", TrashStore.location.absoluteString].contains(path.stringValue.lowercased()) { navigate(TrashStore.location) }
        else { navigate(FileSystem.resolve(path.stringValue, relativeTo: current.isFileURL ? current : FileManager.default.homeDirectoryForCurrentUser)) }
    }
    @objc private func goBack() {
        var next = history
        if let url = next.back() { navigate(url, record: false, historyOnSuccess: next) }
    }
    @objc private func goForward() {
        var next = history
        if let url = next.forward() { navigate(url, record: false, historyOnSuccess: next) }
    }
    @objc private func goUp() {
        if let parent = parentLocation { navigate(parent) }
    }
    @objc private func refresh() { sidebar.reload(); navigate(current) }
    @objc private func toggleHidden() {
        hiddenFiles.defaultShowsHidden.toggle()
    }
    @objc private func toggleFolderHidden() { hiddenFiles.set(!showHidden, for: current) }
    @objc private func useDefaultHiddenFiles() { hiddenFiles.useDefault(for: current) }
    private func updateHiddenControls() {
        hidden.state = hiddenFiles.defaultShowsHidden ? .on : .off
        folderHidden.state = showHidden ? .on : .off
    }
    @objc private func hiddenFilesChanged(_ notification: Notification) {
        if let folder = notification.userInfo?["folder"] as? URL {
            let same = folder.isFileURL && current.isFileURL ? folder.standardizedFileURL.path == current.standardizedFileURL.path : folder == current
            if !same { return }
        }
        updateHiddenControls(); navigate(current, record: false)
    }
    private var selectedFavoriteFolder: URL? {
        guard !isTrashBrowsing, selection.count == 1, let entry = selection.first, entry.isDirectory else { return nil }
        return entry.url
    }
    private func updateFavoriteButton() {
        guard let button = favoriteButton else { return }
        let folder = selectedFavoriteFolder
        let saved = folder.map { sidebar.isFavorite($0) } ?? false
        button.isEnabled = folder != nil
        button.state = saved ? .on : .off
        let description = saved ? "Remove selected folder from Favorites" : "Add selected folder to Favorites"
        button.setAccessibilityLabel(description)
        ToolbarHelp.update(on: button, text: description)
    }
    @objc private func toggleSelectedFavorite() {
        if let folder = selectedFavoriteFolder { sidebar.toggleFavorite(folder) }
    }
    @objc private func volumesChanged(_ notification: Notification) {
        sidebar.reload()
        if let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL,
           notification.name == NSWorkspace.didUnmountNotification, isInside(url) {
            navigate(FileManager.default.homeDirectoryForCurrentUser)
        } else { navigate(current) }
    }
    private func isInside(_ volume: URL) -> Bool {
        current.path == volume.path || current.path.hasPrefix(volume.path + "/")
    }
    private func unmount(_ url: URL) {
        guard !busy else { return }
        busy = true; request += 1
        status.stringValue = "Unmounting \(url.lastPathComponent)…"
        queue.async {
            let result = Result { try NSWorkspace.shared.unmountAndEjectDevice(at: url) }
            DispatchQueue.main.async {
                self.busy = false
                self.sidebar.reload()
                if case .failure(let error) = result { self.updateStatus(); self.show(error); return }
                self.navigate(self.isInside(url) ? FileManager.default.homeDirectoryForCurrentUser : self.current)
            }
        }
    }
    @objc private func openSelection() {
        let selected = selection
        for entry in selected {
            if entry.isBrowsableFolder {
                if selected.count == 1 { navigate(entry.url) }
            } else {
                NSWorkspace.shared.open(entry.url)
            }
        }
    }
    @objc private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selection.isEmpty ? current.path : selection.map { $0.url.path }.joined(separator: "\n"), forType: .string)
    }
    private func showInfo(for urls: [URL]) {
        for url in urls { infoPresenter.show(url, relativeTo: window) }
    }
    @objc private func getInfo() {
        if window?.firstResponder === sidebar.outline,
           let node = sidebar.outline.item(atRow: sidebar.outline.selectedRow) as? FolderNode, let url = node.url {
            if url != TrashStore.location { showInfo(for: [url]) }
        } else { showInfo(for: selection.map(\.url)) }
    }
    @objc private func duplicate() {
        guard !isTrashBrowsing else { return }
        let urls = selection.map(\.url)
        guard !urls.isEmpty else { return }
        performFileOperation { for url in urls { try FileSystem.duplicate(url) } }
    }
    @objc private func reveal() { NSWorkspace.shared.activateFileViewerSelecting(selection.isEmpty ? [current] : selection.map(\.url)) }
    @objc private func copyFiles() {
        let urls = selection.map { $0.url as NSURL }
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(urls)
    }
    @objc private func cutFiles() {
        guard !selection.isEmpty else { return }
        copyFiles()
        NSPasteboard.general.setString("true", forType: FileTransfer.moveType)
        status.stringValue = "\(selection.count) items ready to move. Paste in the destination folder."
    }
    @objc private func pasteFiles() {
        guard let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return }
        let destination = current, clipboardVersion = NSPasteboard.general.changeCount
        let moving = NSPasteboard.general.string(forType: FileTransfer.moveType) == "true"
        guard !busy else { return }
        resolveNameConflicts(urls, into: destination) { plan in
            var remaining = plan.map(\.source)
            self.performFileOperation(onCompletion: { _ in
                guard moving, NSPasteboard.general.changeCount == clipboardVersion else { return }
                NSPasteboard.general.clearContents()
                if !remaining.isEmpty {
                    NSPasteboard.general.writeObjects(remaining.map { $0 as NSURL })
                    NSPasteboard.general.setString("true", forType: FileTransfer.moveType)
                }
            }) {
                for (source, conflict) in plan {
                    try self.transferOne(source, into: destination, move: moving, conflict: conflict)
                    remaining.removeFirst()
                }
            }
        }
    }
    private func transfer(_ urls: [URL], into destination: URL, move: Bool) {
        guard !busy else { return }
        resolveNameConflicts(urls, into: destination) { plan in
            self.performFileOperation {
                for (url, conflict) in plan { try self.transferOne(url, into: destination, move: move, conflict: conflict) }
            }
        }
    }
    private func transferOne(_ url: URL, into destination: URL, move: Bool, conflict: NameConflict) throws {
        if destination == TrashStore.location { try trashActions.moveToTrash(url); return }
        try FileSystem.transfer(url, into: destination, move: move, conflict: conflict) { _ = try self.trashStore.trash($0) }
    }
    /// Asks, like Finder, what to do with each name already in the destination. Skipped items are left out
    /// of the plan, and Stop cancels the whole operation.
    func resolveNameConflicts(_ urls: [URL], into destination: URL, then proceed: @escaping ([(source: URL, conflict: NameConflict)]) -> Void) {
        let clashes = destination == TrashStore.location ? [] : urls.filter { url in
            let target = destination.appendingPathComponent(url.lastPathComponent)
            return FileSystem.itemExists(target) && target.resolvingSymlinksInPath().path != url.resolvingSymlinksInPath().path
        }
        guard !clashes.isEmpty, let window else { proceed(urls.map { ($0, .fail) }); return }
        var choices: [URL: NameConflict?] = [:]
        func ask(_ index: Int) {
            guard index < clashes.count else {
                proceed(urls.compactMap { url in
                    guard let choice = choices[url] else { return (url, .fail) }
                    return choice.map { (url, $0) }
                })
                return
            }
            let url = clashes[index]
            let alert = NSAlert()
            alert.messageText = "An item named “\(url.lastPathComponent)” already exists in “\(destination.lastPathComponent)”."
            alert.informativeText = "Replacing it moves the existing item to the Trash."
            for title in ["Replace", "Keep Both"] + (clashes.count > 1 ? ["Skip"] : []) + ["Stop"] { alert.addButton(withTitle: title) }
            if index < clashes.count - 1 {
                alert.showsSuppressionButton = true
                alert.suppressionButton?.title = "Apply to All"
            }
            alert.beginGlassSheetModal(for: window) { response in
                let button = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                let choice: NameConflict?
                switch alert.buttons.indices.contains(button) ? alert.buttons[button].title : "Stop" {
                case "Replace": choice = .replace
                case "Keep Both": choice = .keepBoth
                case "Skip": choice = nil
                default: return
                }
                let applyToAll = alert.suppressionButton?.state == .on
                for clash in clashes[index...(applyToAll ? clashes.count - 1 : index)] { choices[clash] = .some(choice) }
                ask(applyToAll ? clashes.count : index + 1)
            }
        }
        ask(0)
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? { visible[row].url as NSURL }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        let target = visible.indices.contains(row) && visible[row].isDirectory ? row : -1
        tableView.setDropRow(target, dropOperation: .on)
        return busy ? [] : FileTransfer.dragOperation(info)
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let destination = visible.indices.contains(row) && visible[row].isDirectory ? visible[row].url : current
        return FileTransfer.accept(info, destination: destination) { [weak self] urls, destination, move in self?.transfer(urls, into: destination, move: move) }
    }
    @objc private func newFolder() {
        guard !isTrashBrowsing else { return }
        prompt("New Folder", value: "New Folder") { name in
            let destination = self.current.appendingPathComponent(name)
            self.performFileOperation { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false) }
        }
    }
    @objc private func newFile() {
        guard !isTrashBrowsing else { return }
        prompt("New File", value: "New File.txt") { name in
            let destination = self.current.appendingPathComponent(name)
            self.performFileOperation { try Data().write(to: destination, options: .withoutOverwriting) }
        }
    }
    @objc private func editPermissions() {
        let urls = selection.map(\.url)
        guard !urls.isEmpty, let window else { return }
        do {
            let panel = try PermissionsController(urls: urls)
            permissionsPanel = panel
            panel.onApply = { [weak self] mode in
                self?.performFileOperation { for url in urls { try FileSystem.setPermissions(mode, for: url) } }
            }
            panel.present(on: window)
        } catch { show(error) }
    }
    @objc private func rename() {
        guard !isTrashBrowsing else { return }
        guard selection.count == 1, let entry = selection.first else { return }
        prompt("Rename", value: entry.name) { name in
            let destination = entry.url.deletingLastPathComponent().appendingPathComponent(name)
            guard destination != entry.url else { return }
            self.performFileOperation { try FileManager.default.moveItem(at: entry.url, to: destination) }
        }
    }
    @objc private func trash() {
        if isTrashBrowsing { restoreTrashSelection(); return }
        let urls = selection.map(\.url)
        guard !urls.isEmpty, let window else { return }
        let moveToTrash = { self.performFileOperation { for url in urls { try self.trashActions.moveToTrash(url) } } }
        guard ConfirmationPreference.moveToTrash.isEnabled else { moveToTrash(); return }
        let alert = NSAlert()
        alert.messageText = "Move \(urls.count) item\(urls.count == 1 ? "" : "s") to the Trash?"
        alert.informativeText = "You can restore these items from the Trash."
        alert.addButton(withTitle: "Move to Trash"); alert.addButton(withTitle: "Cancel")
        alert.beginGlassSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            moveToTrash()
        }
    }
    private func prompt(_ title: String, value: String, completion: @escaping (String) -> Void) {
        guard let window, !busy else { return }
        let alert = NSAlert(); alert.messageText = title
        let input = NSTextField(string: value); input.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = input; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = input
        alert.beginGlassSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let name = input.stringValue
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
                self.show(NSError(domain: "Pathfind", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter a filename without a slash. ‘.’ and ‘..’ are reserved."])); return
            }
            completion(name)
        }
    }
    private func performFileOperation(onCompletion: ((Error?) -> Void)? = nil, _ operation: @escaping () throws -> Void) {
        guard !busy else { return }
        busy = true; request += 1; status.stringValue = "Working…"
        queue.async {
            let result = Result { try operation() }
            DispatchQueue.main.async {
                self.busy = false
                let error: Error?
                switch result { case .failure(let failure): error = failure; case .success: error = nil }
                onCompletion?(error)
                self.refresh()
                NotificationCenter.default.post(name: .pathfindFilesChanged, object: self)
                if case .failure(let error) = result { self.show(error) }
            }
        }
    }
    private func show(_ error: Error) {
        guard let window else { return }
        let alert = NSAlert(error: error)
        let detail = error as NSError
        if detail.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(detail.code) {
            alert.informativeText += "\n\nFor protected folders, macOS may require Explorer to have Full Disk Access in System Settings → Privacy & Security."
        }
        alert.beginGlassSheetModal(for: window)
    }
    func releaseInputFocusForHeaderClick(_ event: NSEvent) {
        guard let window, let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else { return }
        let inHeader = [topChrome, titlebarChrome].contains { $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) }
        guard inHeader else { return }
        var hit = window.contentView?.hitTest(event.locationInWindow)
        while let view = hit {
            if view is NSControl || view is NSTextView { return }
            hit = view.superview
        }
        pathCompletion?.dismiss()
        window.makeFirstResponder(nil)
    }
    private func handleKey(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return handleCommand(event) }
        // ⌘Tab belongs to the system app switcher, so tabs cycle with ⌃Tab.
        if event.keyCode == 48, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control { nextTab(); return true }
        guard filePaneHasFocus else { return false }
        switch event.keyCode {
        case 36: openSelection()
        case 120: rename()
        default: return false
        }
        return true
    }
    private func handleCommand(_ event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let actions: [String: Selector] = ["l": #selector(focusPath), "[": #selector(goBack), "]": #selector(goForward), "r": #selector(refresh), "t": #selector(newTab), "w": #selector(closeActiveTab), "i": #selector(getInfo), "k": #selector(connectToServer), ",": #selector(showSettings)]
        let shifted: [String: Selector] = ["n": #selector(newFolder), ".": #selector(toggleHidden), ">": #selector(toggleHidden)]
        let action = event.modifierFlags.contains(.shift) ? shifted[key] ?? actions[key] : actions[key]
        if let action { perform(action); return true }
        if event.keyCode == 126 { goUp(); return true }
        guard filePaneHasFocus else { return false }
        return handleFileCommand(key: key, code: event.keyCode)
    }
    private func handleFileCommand(key: String, code: UInt16) -> Bool {
        switch key {
        case "c": copyFiles()
        case "x": cutFiles()
        case "v": pasteFiles()
        case "d": duplicate()
        default:
            guard code == 51 else { return false }
            trash()
        }
        return true
    }
    @objc private func focusPath() {
        window?.makeFirstResponder(path)
        path.selectText(nil)
    }
    @objc private func showSettings() {
        (NSApplication.shared.delegate as? SettingsPresenting)?.showSettings()
    }
    @objc private func connectToServer() {
        (NSApplication.shared.delegate as? ServerConnectionPresenting)?.connectToServer()
    }
    @objc private func appearanceChanged() {
        guard let window, let root = window.contentView else { return }
        root.effectiveAppearance.performAsCurrentDrawingAppearance {
            BrowserTheme.paint(root, color: .clear)
            BrowserTheme.paint(topChrome, color: BrowserTheme.chrome)
            BrowserTheme.paint(titlebarChrome, color: BrowserTheme.titlebarTint.withAlphaComponent(BrowserTheme.titlebarOpacity))
            titlebarChrome.isHidden = !BrowserTheme.titlebarTintEnabled
            windowOutline.isHidden = !BrowserTheme.outlineEnabled
            windowOutline.needsDisplay = true
            let fieldColor = BrowserTheme.fieldTintEnabled ? BrowserTheme.fieldTint : BrowserTheme.shade(dark: 0.105, light: 0.955)
            path.backgroundColor = fieldColor
            search.backgroundColor = fieldColor
            fieldSurfaces.forEach(GlassControls.tintFieldSurface)
            GlassControls.apply(to: root, excluding: [tabStrip, ancestorPathBar])
            sidebar.outline.backgroundColor = .clear
            table.backgroundColor = .clear
            icons.collection.backgroundColors = [.clear]
            icons.scroll.drawsBackground = false
            table.needsDisplay = true; sidebar.outline.needsDisplay = true
            table.enumerateAvailableRowViews { row, _ in row.needsDisplay = true }
            sidebar.outline.enumerateAvailableRowViews { row, _ in row.needsDisplay = true }
        }
    }
    @objc private func newTab() {
        guard !busy else { return }
        rememberActiveTabState()
        tabs.open(current); activateTab()
    }
    private func selectTab(_ id: UUID) {
        guard !busy, id != tabs.activeID else { return }
        rememberActiveTabState()
        tabs.select(id); activateTab()
    }
    private func closeTab(_ id: UUID) {
        guard !busy else { return }
        rememberActiveTabState()
        if !tabs.close(id) { window?.performClose(nil); return }
        activateTab()
    }
    private func activateTab() {
        request += 1
        entries = []; visible = []; table.reloadData(); icons.reload([])
        onSessionChanged?(); tabStrip.update(tabs)
        restoreTabState()
        navigate(current, record: false)
    }
    @objc private func closeActiveTab() { closeTab(tabs.activeID) }
    @objc private func nextTab() {
        let next = (tabs.activeIndex + 1) % tabs.items.count
        selectTab(tabs.items[next].id)
    }
    private var filePaneHasFocus: Bool { window?.firstResponder === table || window?.firstResponder === icons.collection }
    @objc private func restoreTrashSelection() {
        guard let window, !busy else { return }
        trashActions.restore(selection.map(\.url), on: window) { [weak self] operation in self?.performFileOperation(operation) }
    }
    @objc private func clearTrash() {
        guard let window, !busy else { return }
        trashActions.clear(on: window) { [weak self] operation in self?.performFileOperation(operation) }
    }
    func tab(_ id: UUID) -> BrowserTab? { tabs.items.first { $0.id == id } }
    func receiveTab(_ tab: BrowserTab, before id: UUID?) {
        tabs.insert(tab, before: id); activateTab()
    }
    func reorderTab(_ id: UUID, before otherID: UUID?) {
        tabs.move(id, before: otherID); onSessionChanged?(); tabStrip.update(tabs)
    }
    func removeTransferredTab(_ id: UUID) {
        if tabs.close(id) { activateTab() } else { window?.close() }
    }
    @objc private func otherWindowChangedFiles(_ notification: Notification) {
        guard notification.object as? BrowserController !== self, !busy else { return }
        refresh()
    }
}

private final class FileRowView: AccentRowView {
    private let alternate: Bool
    init(alternate: Bool) { self.alternate = alternate; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func drawBackground(in dirtyRect: NSRect) {
        let opacity = BrowserTheme.frosted ? BrowserTheme.opacity : 1
        let color = alternate ? NSColor.black.withAlphaComponent(0.025 * opacity) : .clear
        color.setFill()
        dirtyRect.fill()
    }
}
