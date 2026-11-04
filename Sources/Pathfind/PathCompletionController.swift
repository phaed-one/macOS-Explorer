import AppKit
import PathfindCore

private final class PathCompletionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Keeps editing in the path field while a nonactivating folder list sits beneath it.
final class PathCompletionController: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private weak var field: NSTextField?
    private let baseURL: () -> URL
    private let queue = DispatchQueue(label: "explorer.path-completion", qos: .userInitiated)
    private let panel = PathCompletionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let table = NSTableView()
    private let scroll = BrowserScrollView()
    private var folders: [URL] = []
    private var prefix = ""
    private var generation = 0
    private var mouseMonitor: Any?

    init(field: NSTextField, baseURL: @escaping () -> URL) {
        self.field = field; self.baseURL = baseURL
        super.init()
        field.delegate = self
        panel.identifier = NSUserInterfaceItemIdentifier("pathCompletions")
        panel.setAccessibilityLabel("Path folder suggestions")
        panel.level = .popUpMenu; panel.hidesOnDeactivate = true
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        let background = NSVisualEffectView()
        background.material = .popover; background.state = .active
        background.wantsLayer = true; background.layer?.cornerRadius = 8; background.layer?.masksToBounds = true
        panel.contentView = background
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scroll.autoresizingMask = [.width, .height]
        background.addSubview(scroll)
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("folder")))
        table.headerView = nil; table.style = .plain
        table.usesAutomaticRowHeights = false
        table.rowHeight = 28; table.intercellSpacing = .zero
        table.backgroundColor = .clear; table.allowsEmptySelection = true
        table.dataSource = self; table.delegate = self
        table.target = self; table.action = #selector(chooseFolder)
        table.setAccessibilityLabel("Folder suggestions")
        scroll.documentView = table
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.window !== self.panel {
                let inField = self.field.map { event.window === $0.window && $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) } ?? false
                if !inField { self.dismiss() }
            }
            return event
        }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowChanged(_:)), name: name, object: nil)
        }
    }

    func controlTextDidChange(_ notification: Notification) { updateSuggestions() }
    func controlTextDidEndEditing(_ notification: Notification) { dismiss() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard panel.isVisible else { return false }
        switch NSStringFromSelector(command) {
        case "moveDown:", "moveUp:":
            let delta = command == #selector(NSResponder.moveDown(_:)) ? 1 : -1
            let row = table.selectedRow < 0 ? (delta > 0 ? 0 : folders.count - 1) : min(folders.count - 1, max(0, table.selectedRow + delta))
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
            return true
        case "insertNewline:", "insertTab:":
            guard table.selectedRow >= 0 else { dismiss(); return false }
            chooseFolder(); return true
        case "cancelOperation:": dismiss(); return true
        default: return false
        }
    }

    private func updateSuggestions() {
        dismiss()
        guard let field, let editor = field.currentEditor(),
              editor.selectedRange.location == (field.stringValue as NSString).length,
              editor.selectedRange.length == 0,
              let slash = field.stringValue.range(of: "/", options: .backwards) else { return }
        let text = field.stringValue
        let prefix = String(text[...slash.lowerBound])
        let partial = String(text[slash.upperBound...])
        let directory = FileSystem.resolve(prefix, relativeTo: baseURL())
        let version = generation
        queue.async { [weak self] in
            let fm = FileManager.default
            let children = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
            let folders = children.filter { url in
                guard partial.isEmpty || url.lastPathComponent.range(of: partial, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil else { return false }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isDirectory == true { return true }
                var isDirectory: ObjCBool = false
                return values?.isSymbolicLink == true && fm.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            DispatchQueue.main.async {
                guard let self, self.generation == version, self.field?.currentEditor() != nil else { return }
                guard !folders.isEmpty else { return }
                self.prefix = prefix; self.folders = folders
                self.table.reloadData(); self.table.deselectAll(nil)
                self.present()
            }
        }
    }

    @objc private func chooseFolder() {
        guard let field, folders.indices.contains(table.selectedRow) else { return }
        let value = prefix + folders[table.selectedRow].lastPathComponent + "/"
        field.stringValue = value
        if let editor = field.currentEditor() {
            editor.string = value
            editor.selectedRange = NSRange(location: (value as NSString).length, length: 0)
        }
        updateSuggestions()
    }

    private func present() {
        guard let field, let window = field.window else { return }
        let rect = window.convertToScreen(field.convert(field.bounds, to: nil))
        let available = rect.minY - (window.screen?.visibleFrame.minY ?? 0) - 4
        let height = min(CGFloat(min(10, folders.count)) * table.rowHeight + 16, max(44, available))
        panel.setFrame(NSRect(x: rect.minX, y: rect.minY - height - 4, width: rect.width, height: height), display: true)
        scroll.frame = panel.contentView!.bounds.insetBy(dx: 4, dy: 8)
        table.tableColumns.first?.width = max(0, scroll.contentSize.width)
        if panel.parent !== window { panel.parent?.removeChildWindow(panel); window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func dismiss() {
        generation += 1
        panel.orderOut(nil)
        panel.parent?.removeChildWindow(panel)
        folders = []
    }

    @objc private func windowChanged(_ notification: Notification) {
        guard notification.object as? NSWindow === field?.window else { return }
        if notification.name == NSWindow.didMoveNotification || notification.name == NSWindow.didResizeNotification {
            if panel.isVisible { present() }
        } else { dismiss() }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { folders.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: folders[row].lastPathComponent)
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingMiddle
        label.frame = NSRect(x: 10, y: 5, width: max(0, tableView.bounds.width - 20), height: 18)
        label.autoresizingMask = [.width]
        cell.addSubview(label); cell.textField = label
        return cell
    }

    deinit {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        NotificationCenter.default.removeObserver(self)
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }
}
