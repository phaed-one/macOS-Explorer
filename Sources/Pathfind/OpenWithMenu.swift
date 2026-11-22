import AppKit

private struct InstalledApplication {
    let name: String
    let url: URL
    let icon: NSImage
}

final class OpenWithMenu: NSObject, NSSearchFieldDelegate {
    private let menu = NSMenu(title: "Open With…")
    private let searchField = NSSearchField(frame: .zero)
    private let setDefaultButton = NSButton(title: "Set as default", target: nil, action: nil)
    private let grid = NSGridView()
    private var applications: [InstalledApplication] = []
    private var loadedApplications = false
    private var fileURL: URL?
    private var onOpen: ((URL, URL) -> Void)?
    private var onSetDefault: ((URL, URL) -> Void)?

    override init() {
        super.init()
        menu.autoenablesItems = false
        searchField.placeholderString = "Filter applications"
        searchField.controlSize = .regular
        searchField.delegate = self
        setDefaultButton.target = self
        setDefaultButton.action = #selector(setDefaultApplication)
        setDefaultButton.bezelStyle = .rounded
        setDefaultButton.controlSize = .small
        setDefaultButton.isHidden = true

        let filterRow = NSStackView(views: [searchField, setDefaultButton])
        filterRow.orientation = .horizontal
        filterRow.alignment = .centerY
        filterRow.spacing = 8

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 488, height: 380))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = grid

        let content = NSStackView(views: [filterRow, scroll])
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 8
        content.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        content.frame = NSRect(x: 0, y: 0, width: 508, height: 426)
        searchField.widthAnchor.constraint(equalToConstant: 398).isActive = true
        searchField.heightAnchor.constraint(equalToConstant: 28).isActive = true
        setDefaultButton.widthAnchor.constraint(equalToConstant: 82).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 488).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 380).isActive = true

        let contentItem = NSMenuItem()
        contentItem.view = content
        menu.addItem(contentItem)
    }

    func makeMenuItem(
        for fileURL: URL,
        onOpen: @escaping (URL, URL) -> Void,
        onSetDefault: @escaping (URL, URL) -> Void
    ) -> NSMenuItem {
        if !loadedApplications {
            applications = discoverApplications()
            loadedApplications = true
        }
        self.fileURL = fileURL
        self.onOpen = onOpen
        self.onSetDefault = onSetDefault
        searchField.stringValue = ""
        rebuildGrid()
        let item = NSMenuItem(title: "Open With…", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    func controlTextDidChange(_ notification: Notification) {
        rebuildGrid()
    }

    private func rebuildGrid() {
        while grid.numberOfRows > 0 { grid.removeRow(at: 0) }

        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = applications.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        setDefaultButton.isHidden = query.isEmpty || matches.count != 1
        setDefaultButton.identifier = matches.count == 1
            ? NSUserInterfaceItemIdentifier(matches[0].url.path)
            : nil
        let columns = 4
        for start in stride(from: 0, to: matches.count, by: columns) {
            let apps = Array(matches[start..<min(start + columns, matches.count)])
            var buttons: [NSView] = apps.map { application in
                let button = NSButton(title: application.name, target: self, action: #selector(openApplication(_:)))
                button.image = application.icon
                button.imagePosition = .imageAbove
                button.imageScaling = .scaleProportionallyDown
                button.setButtonType(.momentaryPushIn)
                button.bezelStyle = .rounded
                button.cell?.lineBreakMode = .byTruncatingTail
                button.font = .systemFont(ofSize: 11)
                button.toolTip = application.name
                button.identifier = NSUserInterfaceItemIdentifier(application.url.path)
                button.widthAnchor.constraint(equalToConstant: 116).isActive = true
                button.heightAnchor.constraint(equalToConstant: 74).isActive = true
                return button
            }
            while buttons.count < columns { buttons.append(NSView()) }
            grid.addRow(with: buttons)
        }
        for column in 0..<columns {
            grid.column(at: column).width = 116
        }
        grid.rowSpacing = 4
        grid.columnSpacing = 4
        grid.frame = NSRect(x: 0, y: 0, width: 488, height: CGFloat(grid.numberOfRows) * 78)
    }

    @objc private func openApplication(_ sender: NSButton) {
        guard let fileURL, let path = sender.identifier?.rawValue else { return }
        onOpen?(fileURL, URL(fileURLWithPath: path))
        menu.cancelTracking()
    }

    @objc private func setDefaultApplication() {
        guard let fileURL, let path = setDefaultButton.identifier?.rawValue else { return }
        onSetDefault?(fileURL, URL(fileURLWithPath: path))
        menu.cancelTracking()
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
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                enumerator.skipDescendants()
                let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                found[url.standardizedFileURL.path] = InstalledApplication(
                    name: name,
                    url: url,
                    icon: NSWorkspace.shared.icon(forFile: url.path)
                )
            }
        }

        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
