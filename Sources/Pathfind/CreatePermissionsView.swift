import AppKit
import PathfindCore

final class CreatePermissionsView: NSView, NSTextFieldDelegate {
    private(set) var mode: UInt16
    var onValidityChange: ((Bool) -> Void)?

    private let isDirectory: Bool
    private var referenceMode: UInt16
    private var boxes: [(NSButton, UInt16)] = []
    private let input = NSTextField()
    private let symbolic = NSTextField(labelWithString: "")
    private let validation = NSTextField(wrappingLabelWithString: "")

    init(initialMode: UInt16, isDirectory: Bool) {
        mode = initialMode
        referenceMode = initialMode
        self.isDirectory = isDirectory
        super.init(frame: .zero)

        let width: CGFloat = 620
        let accessWidth: CGFloat = 290
        let modeWidth: CGFloat = width - accessWidth - 16
        let innerAccess = accessWidth - 2 * SettingsCard.padding
        let innerMode = modeWidth - 2 * SettingsCard.padding

        func columnTitle(_ text: String) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 10, weight: .semibold)
            label.textColor = .secondaryLabelColor
            return label
        }

        var rows: [[NSView]] = [[NSGridCell.emptyContentView, columnTitle("READ"), columnTitle("WRITE"), columnTitle("EXECUTE")]]
        for (label, shift) in [("Owner", UInt16(6)), ("Group", 3), ("Everyone", 0)] {
            var row: [NSView] = [NSTextField(labelWithString: label)]
            for bit: UInt16 in [4, 2, 1] {
                let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkboxChanged))
                box.setAccessibilityLabel("\(label) \(bit == 4 ? "read" : bit == 2 ? "write" : "execute")")
                boxes.append((box, bit << shift))
                row.append(box)
            }
            rows.append(row)
        }
        let grid = NSGridView(views: rows)
        grid.columnSpacing = 10; grid.rowSpacing = 8
        grid.column(at: 0).width = 76
        for index in 1...3 { grid.column(at: index).xPlacement = .center; grid.column(at: index).width = 50 }
        for index in 0..<grid.numberOfRows { grid.row(at: index).yPlacement = .center }

        let special = NSStackView()
        special.spacing = 8
        for (title, bit) in [("Set UID", UInt16(0o4000)), ("Set GID", 0o2000), ("Sticky", 0o1000)] {
            let box = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkboxChanged))
            box.font = .systemFont(ofSize: 10)
            boxes.append((box, bit)); special.addArrangedSubview(box)
        }
        let separator = NSBox(); separator.boxType = .separator
        separator.widthAnchor.constraint(equalToConstant: innerAccess).isActive = true
        let access = SettingsCard(title: "Access", width: accessWidth, content: [grid, separator, special])

        input.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        input.placeholderString = "755 or u+rwx,g-w"
        input.setAccessibilityLabel("chmod mode")
        input.delegate = self
        input.widthAnchor.constraint(equalToConstant: innerMode).isActive = true
        symbolic.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        validation.font = .systemFont(ofSize: 10); validation.textColor = .systemRed
        validation.preferredMaxLayoutWidth = innerMode
        let hint = NSTextField(wrappingLabelWithString: "Octal like 644, or symbolic like u+x, go-w or a=r. Only POSIX bits change; ACLs and macOS protections still apply.")
        hint.font = .systemFont(ofSize: 10); hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = innerMode
        let modeCard = SettingsCard(title: "Mode", width: modeWidth, content: [input, symbolic, validation, hint])

        let cards = NSStackView(views: [access, modeCard])
        cards.alignment = .top; cards.spacing = 16
        cards.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cards)
        NSLayoutConstraint.activate([
            cards.topAnchor.constraint(equalTo: topAnchor),
            cards.leadingAnchor.constraint(equalTo: leadingAnchor),
            cards.trailingAnchor.constraint(equalTo: trailingAnchor),
            cards.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: width)
        ])
        input.stringValue = String(format: "%04o", mode)
        updateCheckboxes(); showMode()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func showMode() {
        symbolic.stringValue = PermissionsController.symbolic(mode)
    }

    private func updateCheckboxes() {
        for (box, bit) in boxes { box.state = mode & bit != 0 ? .on : .off }
    }

    @objc private func checkboxChanged() {
        mode = boxes.reduce(0) { $0 | ($1.0.state == .on ? $1.1 : 0) }
        referenceMode = mode
        input.stringValue = String(format: "%04o", mode)
        validation.stringValue = ""
        showMode()
        onValidityChange?(true)
    }

    func controlTextDidChange(_ obj: Notification) {
        do {
            mode = try PermissionMode.parse(input.stringValue, original: referenceMode, isDirectory: isDirectory)
            updateCheckboxes(); showMode(); validation.stringValue = ""
            onValidityChange?(true)
        } catch {
            validation.stringValue = error.localizedDescription
            onValidityChange?(false)
        }
    }
}
