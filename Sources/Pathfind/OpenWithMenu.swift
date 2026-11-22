import AppKit
import UniformTypeIdentifiers

private struct InstalledApplication {
    let name: String
    let url: URL
    let icon: NSImage
}

/// The right-click "Open With…" submenu: a filterable grid of installed apps, with the current
/// default and every app ever chosen here in a Recent section above the rest.
final class OpenWithMenu: NSObject, NSSearchFieldDelegate, NSCollectionViewDataSource {
    /// Paths of apps chosen from Open With, most recent first.
    static let recentsKey = "openWithRecentApplications"
    private static let columns = 3
    private static let rowHeight: CGFloat = 30
    private static let columnGap: CGFloat = 8
    private static let sectionTitles = ["Recent", "Other Applications"]

    private let defaults: UserDefaults
    private let menu = NSMenu(title: "Open With…")
    private let searchField = NSSearchField(frame: .zero)
    private let setDefaultCheckbox = NSButton(checkboxWithTitle: "Set as default", target: nil, action: nil)
    private let collection = OpenWithCollectionView()
    private let layout = ColumnGridLayout(columns: OpenWithMenu.columns, rowHeight: OpenWithMenu.rowHeight, gap: OpenWithMenu.columnGap)
    private let emptyLabel = NSTextField(labelWithString: "No matching applications")
    private var applications: [InstalledApplication] = []
    /// The filtered apps: recent ones, then the rest.
    private var sections: [[InstalledApplication]] = [[], []]
    private var loadedApplications = false
    private var fileURL: URL?
    private var defaultApplication: URL?
    private var onChoose: ((URL, URL, Bool) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        menu.autoenablesItems = false
        searchField.placeholderString = "Filter applications"
        searchField.controlSize = .regular
        searchField.delegate = self
        setDefaultCheckbox.state = .off

        let filterRow = NSStackView(views: [searchField, setDefaultCheckbox])
        filterRow.orientation = .horizontal
        filterRow.alignment = .centerY
        filterRow.spacing = 12

        collection.autoresizingMask = [.width]
        collection.frame = NSRect(x: 0, y: 0, width: 504, height: 380)
        collection.collectionViewLayout = layout
        collection.dataSource = self
        collection.backgroundColors = [.clear]
        collection.register(OpenWithApplicationItem.self, forItemWithIdentifier: .init("application"))
        collection.register(OpenWithSectionHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, withIdentifier: .init("header"))

        // The app's thin overlay scrollbar, which floats over the grid instead of narrowing it.
        let scroll = BrowserScrollView(frame: NSRect(x: 0, y: 0, width: 504, height: 380))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.documentView = collection

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(emptyLabel)

        let content = NSStackView(views: [filterRow, scroll])
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 8
        content.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        content.frame = NSRect(x: 0, y: 0, width: 524, height: 426)
        searchField.heightAnchor.constraint(equalToConstant: 28).isActive = true
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        setDefaultCheckbox.setContentHuggingPriority(.required, for: .horizontal)
        setDefaultCheckbox.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalToConstant: 504),
            scroll.heightAnchor.constraint(equalToConstant: 380),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 40)
        ])

        let contentItem = NSMenuItem()
        contentItem.view = content
        menu.addItem(contentItem)
    }

    /// `onChoose` receives the file, the chosen app, and whether to make that app the default first.
    /// `defaultApplication` is the app the file opens with now, listed first.
    func makeMenuItem(for fileURL: URL, defaultApplication: URL?, onChoose: @escaping (URL, URL, Bool) -> Void) -> NSMenuItem {
        if !loadedApplications {
            applications = discoverApplications()
            loadedApplications = true
        }
        self.fileURL = fileURL
        self.onChoose = onChoose
        self.defaultApplication = defaultApplication?.standardizedFileURL
        searchField.stringValue = ""
        setDefaultCheckbox.state = .off
        configureDefaultCheckbox(for: fileURL)
        filterApplications()
        let item = NSMenuItem(title: "Open With…", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func configureDefaultCheckbox(for fileURL: URL) {
        let name = fileURL.lastPathComponent
        switch DefaultApplication.target(for: fileURL) {
        case .fileType:
            let ext = fileURL.pathExtension
            let type = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType
            let kind = ext.isEmpty ? (type?.localizedDescription ?? "these") : ".\(ext)"
            setDefaultCheckbox.title = "Set as default"
            setDefaultCheckbox.isEnabled = true
            setDefaultCheckbox.toolTip = "Always open \(kind) files with the app you choose"
        case .sameName:
            // A long name would widen the checkbox and squeeze the filter field.
            let note = name.count <= 12 ? "for all \(name) files" : "for all files so named"
            setDefaultCheckbox.attributedTitle = Self.checkboxTitle(note: note)
            setDefaultCheckbox.isEnabled = true
            setDefaultCheckbox.toolTip = "macOS has no default for files with no extension, so Explorer saves the app you choose on every \(name) in your home folder, and on new ones as it lists them. Finder follows it too."
        }
    }

    /// Two lines, the second small, so the checkbox stays as narrow as "Set as default".
    private static func checkboxTitle(note: String) -> NSAttributedString {
        let title = NSMutableAttributedString(string: "Set as default\n", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        title.append(NSAttributedString(string: note, attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]))
        return title
    }

    func controlTextDidChange(_ notification: Notification) {
        filterApplications()
    }

    /// Return in the filter opens the first match.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)), let first = sections.joined().first else { return false }
        choose(first)
        return true
    }

    private func filterApplications() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = applications.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        let byPath = Dictionary(matches.map { ($0.url.standardizedFileURL.path, $0) }, uniquingKeysWith: { first, _ in first })
        // The current default leads Recent, like Finder's Open With menu; then apps used here, newest first.
        var recentPaths = defaults.stringArray(forKey: Self.recentsKey) ?? []
        if let defaultPath = defaultApplication?.path {
            recentPaths.removeAll { $0 == defaultPath }
            recentPaths.insert(defaultPath, at: 0)
        }
        let recent = recentPaths.compactMap { byPath[$0] }
        let recentSet = Set(recent.map { $0.url.standardizedFileURL.path })
        sections = [recent, matches.filter { !recentSet.contains($0.url.standardizedFileURL.path) }]
        // With nothing recent there is only one list, so it needs no titles.
        layout.showsHeaders = !recent.isEmpty
        emptyLabel.isHidden = !matches.isEmpty
        collection.reloadData()
        collection.scroll(.zero)
        collection.hoveredItem = nil
    }

    private func recordRecent(_ application: URL) {
        let path = application.standardizedFileURL.path
        var paths = defaults.stringArray(forKey: Self.recentsKey) ?? []
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        defaults.set(paths, forKey: Self.recentsKey)
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].count
    }

    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSView {
        let header = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: .init("header"), for: indexPath) as! OpenWithSectionHeader
        header.title = Self.sectionTitles[indexPath.section]
        return header
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .init("application"), for: indexPath) as! OpenWithApplicationItem
        let application = sections[indexPath.section][indexPath.item]
        item.configure(application, isDefault: application.url.standardizedFileURL == defaultApplication) { [weak self] in
            self?.choose(application)
        }
        (item.view as? OpenWithApplicationRow)?.isHighlighted = indexPath == (collectionView as? OpenWithCollectionView)?.hoveredItem
        return item
    }

    private func choose(_ application: InstalledApplication) {
        guard let fileURL else { return }
        let makeDefault = setDefaultCheckbox.isEnabled && setDefaultCheckbox.state == .on
        recordRecent(application.url)
        menu.cancelTracking()
        onChoose?(fileURL, application.url, makeDefault)
    }

    private func discoverApplications() -> [InstalledApplication] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        var found: [String: InstalledApplication] = [:]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                let bundle = Bundle(url: url)
                let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 20, height: 20)
                found[url.standardizedFileURL.path] = InstalledApplication(name: name, url: url, icon: icon)
            }
        }

        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private final class OpenWithApplicationItem: NSCollectionViewItem {
    override func loadView() { view = OpenWithApplicationRow() }

    func configure(_ application: InstalledApplication, isDefault: Bool, onChoose: @escaping () -> Void) {
        (view as! OpenWithApplicationRow).configure(name: application.name, icon: application.icon, isDefault: isDefault, onChoose: onChoose)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        (view as! OpenWithApplicationRow).isHighlighted = false
    }
}

/// One app in the grid: icon, an 8pt gap, then the name, matching the List view's rows.
private final class OpenWithApplicationRow: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var name = ""
    private var isDefault = false
    private var onChoose: (() -> Void)?
    var isHighlighted = false { didSet { updateAppearance() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 5
        iconView.imageScaling = .scaleProportionallyUpOrDown
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.wraps = false
        label.font = .systemFont(ofSize: 13)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [iconView, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(name: String, icon: NSImage, isDefault: Bool, onChoose: @escaping () -> Void) {
        self.name = name
        self.isDefault = isDefault
        self.onChoose = onChoose
        iconView.image = icon
        toolTip = isDefault ? "\(name) (current default)" : name
        setAccessibilityLabel(toolTip)
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = isHighlighted ? NSColor.selectedContentBackgroundColor.cgColor : NSColor.clear.cgColor
        let primary: NSColor = isHighlighted ? .alternateSelectedControlTextColor : .labelColor
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString(string: name, attributes: [.foregroundColor: primary, .font: NSFont.systemFont(ofSize: 13), .paragraphStyle: paragraph])
        if isDefault {
            let secondary: NSColor = isHighlighted ? .alternateSelectedControlTextColor : .secondaryLabelColor
            text.append(NSAttributedString(string: " (default)", attributes: [.foregroundColor: secondary, .font: NSFont.systemFont(ofSize: 11)]))
        }
        label.attributedStringValue = text
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onChoose?()
    }
    override func accessibilityPerformPress() -> Bool { onChoose?(); return true }
}

/// Tracks hover for the whole grid, so exactly one row is highlighted: the one under the pointer.
/// Rows tracking themselves miss exits when scrolling moves them out from under a still pointer.
private final class OpenWithCollectionView: NSCollectionView {
    // Column widths come from the grid's width, so any width change (a scroller appearing) re-lays it out.
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { collectionViewLayout?.invalidateLayout() }
    }
    // Custom layouts don't size the grid; grow it to every row so the whole list scrolls.
    override func layout() {
        super.layout()
        guard let content = collectionViewLayout?.collectionViewContentSize, let clip = enclosingScrollView?.contentView else { return }
        let height = max(clip.bounds.height, content.height)
        if frame.height != height { setFrameSize(NSSize(width: frame.width, height: height)) }
    }

    var hoveredItem: IndexPath? {
        didSet {
            guard hoveredItem != oldValue else { return }
            for indexPath in [oldValue, hoveredItem].compactMap({ $0 }) {
                (item(at: indexPath)?.view as? OpenWithApplicationRow)?.isHighlighted = indexPath == hoveredItem
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let clip = superview as? NSClipView else { return }
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: clip)
    }

    @objc private func scrolled() { updateHover() }
    override func mouseMoved(with event: NSEvent) { updateHover() }
    override func mouseEntered(with event: NSEvent) { updateHover() }
    override func mouseExited(with event: NSEvent) { hoveredItem = nil }

    private func updateHover() {
        guard let window else { hoveredItem = nil; return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard visibleRect.contains(point), let indexPath = indexPathForItem(at: point) else { hoveredItem = nil; return }
        hoveredItem = indexPath
    }
}

/// A section title in the grid, styled like a menu's section header.
private final class OpenWithSectionHeader: NSView, NSCollectionViewElement {
    private let label = NSTextField(labelWithString: "")
    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue; setAccessibilityLabel(newValue) }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Exactly `columns` columns `gap` apart, filling the grid's width, section after section, each under
/// an optional title. Positions are computed directly, so an item width that is briefly off can never
/// reflow the grid into fewer columns.
private final class ColumnGridLayout: NSCollectionViewLayout {
    private let columns: Int, rowHeight: CGFloat, gap: CGFloat, lineGap: CGFloat = 2
    private let headerHeight: CGFloat = 22, sectionGap: CGFloat = 8
    /// Whether each non-empty section gets a title above it.
    var showsHeaders = false
    private var width: CGFloat = 0, height: CGFloat = 0
    private var itemFrames: [[NSRect]] = [], headerFrames: [Int: NSRect] = [:]

    init(columns: Int, rowHeight: CGFloat, gap: CGFloat) {
        self.columns = columns; self.rowHeight = rowHeight; self.gap = gap
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var pitch: CGFloat { rowHeight + lineGap }

    override func prepare() {
        super.prepare()
        itemFrames = []; headerFrames = [:]; height = 0
        guard let collectionView else { return }
        width = collectionView.bounds.width
        let itemWidth = max(0, floor((width - CGFloat(columns - 1) * gap) / CGFloat(columns)))
        var y: CGFloat = 0
        for section in 0..<collectionView.numberOfSections {
            let count = collectionView.numberOfItems(inSection: section)
            guard count > 0 else { itemFrames.append([]); continue }
            if y > 0 { y += sectionGap }
            if showsHeaders {
                headerFrames[section] = NSRect(x: 0, y: y, width: width, height: headerHeight)
                y += headerHeight
            }
            let top = y
            itemFrames.append((0..<count).map {
                NSRect(x: CGFloat($0 % columns) * (itemWidth + gap), y: top + CGFloat($0 / columns) * pitch, width: itemWidth, height: rowHeight)
            })
            y += CGFloat((count + columns - 1) / columns) * pitch
        }
        height = y
    }

    override var collectionViewContentSize: NSSize { NSSize(width: width, height: height) }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        let headers = headerFrames.filter { $0.value.intersects(rect) }.map { header($0.key) }
        let items = itemFrames.enumerated().flatMap { section, frames in
            frames.indices.filter { frames[$0].intersects(rect) }.map { item(IndexPath(item: $0, section: section)) }
        }
        return headers + items
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        indexPath.section < itemFrames.count && indexPath.item < itemFrames[indexPath.section].count ? item(indexPath) : nil
    }

    override func layoutAttributesForSupplementaryView(ofKind elementKind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        elementKind == NSCollectionView.elementKindSectionHeader && headerFrames[indexPath.section] != nil ? header(indexPath.section) : nil
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool { newBounds.width != width }

    private func item(_ indexPath: IndexPath) -> NSCollectionViewLayoutAttributes {
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        attributes.frame = itemFrames[indexPath.section][indexPath.item]
        return attributes
    }

    private func header(_ section: Int) -> NSCollectionViewLayoutAttributes {
        let attributes = NSCollectionViewLayoutAttributes(forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, with: IndexPath(item: 0, section: section))
        attributes.frame = headerFrames[section]!
        return attributes
    }
}
