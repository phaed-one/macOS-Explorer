import AppKit
import PathfindCore

final class PermissionsController: NSWindowController, NSTextFieldDelegate {
    var onApply: ((UInt16) -> Void)?
    private let original: UInt16
    private let isDirectory: Bool
    private var mode: UInt16
    private var boxes: [(NSButton, UInt16)] = []
    private let input = NSTextField()
    private let validation = NSTextField(wrappingLabelWithString: "")
    private let applyButton = NSButton(title: "Apply", target: nil, action: nil)

    private let symbolic = NSTextField(labelWithString: "")
    private let summary = NSTextField(labelWithString: "")
    private static let cardWidth: CGFloat = 330

    init(urls: [URL]) throws {
        let modes = try urls.map { try FileSystem.permissions(for: $0) }
        original = modes[0]; mode = original
        isDirectory = (try? urls[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 724, height: 360), styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Permissions"
        let inner = Self.cardWidth - 2 * SettingsCard.padding
        let attributes = try? FileManager.default.attributesOfItem(atPath: urls[0].path)
        let owner = attributes?[.ownerAccountName] as? String, group = attributes?[.groupOwnerAccountName] as? String

        // Header: which item, and its mode now.
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: urls[0].path))
        icon.widthAnchor.constraint(equalToConstant: 44).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let heading = NSTextField(labelWithString: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) selected items")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        heading.lineBreakMode = .byTruncatingMiddle
        summary.textColor = .secondaryLabelColor
        if !modes.allSatisfy({ $0 == original }) {
            summary.toolTip = "Selected items have different modes. The first item is shown; Apply sets them all to the mode below."
        }
        let titles = NSStackView(views: [heading, summary])
        titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 3
        let header = NSStackView(views: [icon, titles])
        header.alignment = .centerY; header.spacing = 14

        // Access card: who can do what.
        func columnTitle(_ text: String) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11, weight: .semibold); label.textColor = .secondaryLabelColor
            return label
        }
        var rows: [[NSView]] = [[NSGridCell.emptyContentView, columnTitle("READ"), columnTitle("WRITE"), columnTitle("EXECUTE")]]
        for (label, name, shift) in [("Owner", owner, UInt16(6)), ("Group", group, 3), ("Everyone", nil, 0)] {
            let title = NSTextField(labelWithString: label)
            let who = NSStackView(views: [title] + (name.map { name -> NSTextField in
                let detail = NSTextField(labelWithString: name)
                detail.font = .systemFont(ofSize: 11); detail.textColor = .secondaryLabelColor
                return detail
            }.map { [$0] } ?? []))
            who.orientation = .vertical; who.alignment = .leading; who.spacing = 0
            var row: [NSView] = [who]
            for bit: UInt16 in [4, 2, 1] {
                let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkboxChanged))
                box.setAccessibilityLabel("\(label) \(bit == 4 ? "read" : bit == 2 ? "write" : "execute")")
                boxes.append((box, bit << shift)); row.append(box)
            }
            rows.append(row)
        }
        let grid = NSGridView(views: rows)
        grid.columnSpacing = 18; grid.rowSpacing = 10
        grid.column(at: 0).width = 96
        for index in 1...3 { grid.column(at: index).xPlacement = .center; grid.column(at: index).width = 58 }
        for index in 0..<grid.numberOfRows { grid.row(at: index).yPlacement = .center }
        let special = NSStackView()
        special.spacing = 14
        for (title, bit) in [("Set UID", UInt16(0o4000)), ("Set GID", 0o2000), ("Sticky", 0o1000)] {
            let box = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkboxChanged))
            boxes.append((box, bit)); special.addArrangedSubview(box)
        }
        let separator = NSBox(); separator.boxType = .separator
        separator.widthAnchor.constraint(equalToConstant: inner).isActive = true
        let access = SettingsCard(title: "Access", width: Self.cardWidth, content: [grid, separator, special])

        // Mode card: the same thing as a chmod expression.
        input.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        input.placeholderString = "755 or u+rwx,g-w"
        input.setAccessibilityLabel("chmod mode")
        input.delegate = self
        input.widthAnchor.constraint(equalToConstant: inner).isActive = true
        symbolic.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        validation.font = .systemFont(ofSize: 11); validation.textColor = .systemRed
        validation.preferredMaxLayoutWidth = inner
        let hint = NSTextField(wrappingLabelWithString: "Octal like 644, or symbolic like u+x, go-w or a=r. A leading “chmod” is fine; no class means everyone. Only POSIX bits change; ACLs and macOS protections still apply.")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = inner
        let modeCard = SettingsCard(title: "Mode", width: Self.cardWidth, fillsHeight: true, content: [input, symbolic, validation, hint])
        let cards = NSStackView(views: [access, modeCard])
        cards.alignment = .top; cards.spacing = 16
        modeCard.heightAnchor.constraint(equalTo: access.heightAnchor).isActive = true

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        applyButton.target = self; applyButton.action = #selector(apply); applyButton.keyEquivalent = "\r"
        applyButton.bezelColor = .controlAccentColor
        if #available(macOS 26, *) { applyButton.tintProminence = .primary }
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancel, applyButton])
        buttons.widthAnchor.constraint(equalToConstant: 2 * Self.cardWidth + 16).isActive = true

        let stack = NSStackView(views: [header, cards, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24)])
        content.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 2 * Self.cardWidth + 16 + 48, height: stack.fittingSize.height + 34))
        updateCheckboxes(); input.stringValue = String(format: "%04o", mode); showMode()
        DialogAppearance.install(on: window)
    }
    /// `ls -l` style letters for a mode, including set-ID and sticky bits.
    static func symbolic(_ mode: UInt16) -> String {
        var letters = Array("rwxrwxrwx")
        for index in 0..<9 where mode & (UInt16(0o400) >> UInt16(index)) == 0 { letters[index] = "-" }
        for (bit, index, set) in [(UInt16(0o4000), 2, Character("s")), (0o2000, 5, "s"), (0o1000, 8, "t")] where mode & bit != 0 {
            letters[index] = letters[index] == "-" ? Character(set.uppercased()) : set
        }
        return String(letters)
    }
    private func showMode() {
        symbolic.stringValue = Self.symbolic(mode)
        let mixed = summary.toolTip != nil ? " · items differ" : ""
        summary.stringValue = "Now \(String(format: "%04o", original)) · \(Self.symbolic(original))\(mixed)"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present(on parent: NSWindow) { parent.beginSheet(window!) }
    private func updateCheckboxes() { for (box, bit) in boxes { box.state = mode & bit != 0 ? .on : .off } }
    @objc private func checkboxChanged() {
        mode = boxes.reduce(0) { $0 | ($1.0.state == .on ? $1.1 : 0) }
        input.stringValue = String(format: "%04o", mode)
        validation.stringValue = ""; applyButton.isEnabled = true; showMode()
    }
    func controlTextDidChange(_ obj: Notification) {
        do {
            mode = try PermissionMode.parse(input.stringValue, original: original, isDirectory: isDirectory)
            updateCheckboxes(); validation.stringValue = ""; applyButton.isEnabled = true; showMode()
        } catch { validation.stringValue = error.localizedDescription; applyButton.isEnabled = false }
    }
    @objc private func apply() { window?.sheetParent?.endSheet(window!); onApply?(mode) }
    @objc private func cancel() { window?.sheetParent?.endSheet(window!) }
}
