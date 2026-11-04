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

    init(urls: [URL]) throws {
        let modes = try urls.map { try FileSystem.permissions(for: $0) }
        original = modes[0]; mode = original
        isDirectory = (try? urls[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 510), styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Permissions"
        let heading = NSTextField(labelWithString: urls.count == 1 ? urls[0].lastPathComponent : "Permissions for \(urls.count) selected items")
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        let description = NSTextField(wrappingLabelWithString: modes.allSatisfy { $0 == original } ? "Changes apply only to the selected items." : "Selected items have different modes. The first item is shown; Apply sets all selected items to the mode below.")
        description.textColor = .secondaryLabelColor
        var rows: [[NSView]] = [[NSTextField(labelWithString: ""), NSTextField(labelWithString: "Read"), NSTextField(labelWithString: "Write"), NSTextField(labelWithString: "Execute")]]
        for (label, shift) in [("Owner", UInt16(6)), ("Group", 3), ("Everyone", 0)] {
            var row: [NSView] = [NSTextField(labelWithString: label)]
            for bit: UInt16 in [4, 2, 1] {
                let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkboxChanged))
                box.setAccessibilityLabel("\(label) \(bit == 4 ? "read" : bit == 2 ? "write" : "execute")")
                boxes.append((box, bit << shift)); row.append(box)
            }
            rows.append(row)
        }
        let grid = NSGridView(views: rows); grid.columnSpacing = 28; grid.rowSpacing = 10
        for index in 0..<grid.numberOfRows { grid.row(at: index).height = 22 }
        grid.setContentHuggingPriority(.required, for: .vertical)
        let special = NSStackView()
        for (title, bit) in [("Set UID", UInt16(0o4000)), ("Set GID", 0o2000), ("Sticky", 0o1000)] {
            let box = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkboxChanged))
            boxes.append((box, bit)); special.addArrangedSubview(box)
        }
        input.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        input.placeholderString = "755 or u+rwx,g-w"
        input.setAccessibilityLabel("chmod mode")
        input.delegate = self
        validation.font = .systemFont(ofSize: 11); validation.textColor = .systemRed
        let hint = NSTextField(wrappingLabelWithString: "Optional ‘chmod’ prefix accepted. Omitted class means all. POSIX bits only; existing ACLs and macOS protections still apply.")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        applyButton.target = self; applyButton.action = #selector(apply); applyButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, applyButton])
        let stack = NSStackView(views: [heading, description, grid, special, NSTextField(labelWithString: "Mode"), input, validation, hint, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22), stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24), stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -22), input.widthAnchor.constraint(equalTo: stack.widthAnchor), description.widthAnchor.constraint(equalTo: stack.widthAnchor), hint.widthAnchor.constraint(equalTo: stack.widthAnchor), validation.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        window.contentView?.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 490, height: stack.fittingSize.height + 44))
        updateCheckboxes(); input.stringValue = String(format: "%04o", mode)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present(on parent: NSWindow) { parent.beginSheet(window!) }
    private func updateCheckboxes() { for (box, bit) in boxes { box.state = mode & bit != 0 ? .on : .off } }
    @objc private func checkboxChanged() {
        mode = boxes.reduce(0) { $0 | ($1.0.state == .on ? $1.1 : 0) }
        input.stringValue = String(format: "%04o", mode)
        validation.stringValue = ""; applyButton.isEnabled = true
    }
    func controlTextDidChange(_ obj: Notification) {
        do {
            mode = try PermissionMode.parse(input.stringValue, original: original, isDirectory: isDirectory)
            updateCheckboxes(); validation.stringValue = ""; applyButton.isEnabled = true
        } catch { validation.stringValue = error.localizedDescription; applyButton.isEnabled = false }
    }
    @objc private func apply() { window?.sheetParent?.endSheet(window!); onApply?(mode) }
    @objc private func cancel() { window?.sheetParent?.endSheet(window!) }
}
