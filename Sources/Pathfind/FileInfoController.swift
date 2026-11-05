import AppKit

/// Retains one independent information window per item until it is closed.
final class FileInfoPresenter {
    private var windows: [URL: FileInfoController] = [:]
    func show(_ url: URL, relativeTo parent: NSWindow?) {
        let url = url.standardizedFileURL
        if let existing = windows[url] { existing.window?.makeKeyAndOrderFront(nil); return }
        do {
            let controller = try FileInfoController(url: url)
            controller.onClose = { [weak self] in self?.windows.removeValue(forKey: url) }
            windows[url] = controller
            controller.showWindow(nil)
        } catch {
            let alert = NSAlert(error: error)
            if let parent { alert.beginGlassSheetModal(for: parent) } else { alert.runGlassModal() }
        }
    }
}

final class FileInfoController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let sizeLabel = NSTextField(wrappingLabelWithString: "")
    private let calculation = Progress(totalUnitCount: 0)
    private var contentStack: NSStackView?

    init(url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let values = try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey, .isHiddenKey])
        let type = attributes[.type] as? FileAttributeType
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 450), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "\(url.lastPathComponent) Info"; window.delegate = self
        window.isReleasedWhenClosed = false
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: url.path))
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let name = NSTextField(wrappingLabelWithString: url.lastPathComponent)
        name.font = .systemFont(ofSize: 17, weight: .semibold); name.isSelectable = true
        let heading = NSStackView(views: [icon, name]); heading.spacing = 14
        sizeLabel.isSelectable = true
        sizeLabel.stringValue = type == .typeDirectory ? "Calculating…" : Self.formatSize((attributes[.size] as? NSNumber)?.int64Value ?? 0)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        var rows: [(String, NSView)] = [
            ("Kind", Self.value(type == .typeSymbolicLink ? "Symbolic link" : values?.localizedTypeDescription ?? "File")),
            ("Size", sizeLabel),
            ("Where", Self.value(url.deletingLastPathComponent().path)),
            ("Full path", Self.value(url.path)),
            ("Created", Self.value(Self.date(attributes[.creationDate]))),
            ("Modified", Self.value(Self.date(attributes[.modificationDate]))),
            ("Hidden", Self.value(values?.isHidden == true || url.lastPathComponent.hasPrefix(".") ? "Yes" : "No")),
            ("Owner", Self.value(attributes[.ownerAccountName] as? String ?? "—")),
            ("Group", Self.value(attributes[.groupOwnerAccountName] as? String ?? "—")),
            ("Permissions", Self.value(String(format: "%04o", mode)))
        ]
        if type == .typeSymbolicLink {
            rows.append(("Link target", Self.value(try FileManager.default.destinationOfSymbolicLink(atPath: url.path))))
        }
        let grid = NSGridView(views: rows.map { [NSTextField(labelWithString: $0.0), $0.1] })
        grid.columnSpacing = 16; grid.rowSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 350
        grid.yPlacement = .top
        let stack = NSStackView(views: [heading, grid])
        contentStack = stack
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            name.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])
        window.contentView!.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 500, height: stack.fittingSize.height + 48))
        window.center()
        DialogAppearance.install(on: window)
        if type == .typeDirectory { calculateFolderSize(url) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { calculation.cancel(); onClose?() }
    private static func value(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.isSelectable = true; return label
    }
    private static func date(_ value: Any?) -> String {
        guard let date = value as? Date else { return "—" }
        return DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .medium)
    }
    private static func formatSize(_ bytes: Int64) -> String {
        "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) (\(bytes.formatted()) bytes)"
    }
    private func calculateFolderSize(_ url: URL) {
        let progress = calculation
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var bytes: Int64 = 0, count = 0, partial = false
            let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
            let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in partial = true; return !progress.isCancelled })
            if iterator == nil { partial = true }
            while !progress.isCancelled, let item = iterator?.nextObject() as? URL {
                count += 1
                do {
                    let values = try item.resourceValues(forKeys: Set(keys))
                    if values.isDirectory != true { bytes += Int64(values.fileSize ?? 0) }
                } catch { partial = true }
            }
            guard !progress.isCancelled else { return }
            let summary = (partial ? "At least " : "") + Self.formatSize(bytes) + " · \(count.formatted()) items" + (partial ? " (some items inaccessible)" : "")
            DispatchQueue.main.async {
                guard let self, let window = self.window,
                      let stack = self.contentStack else { return }
                self.sizeLabel.stringValue = summary
                window.contentView?.layoutSubtreeIfNeeded()
                window.setContentSize(NSSize(width: 500, height: stack.fittingSize.height + 48))
            }
        }
    }
}
