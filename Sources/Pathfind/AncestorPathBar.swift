import AppKit
import PathfindCore

final class AncestorPathBar: NSView {
    var onNavigate: ((URL) -> Void)?
    private let scroll = BrowserScrollView()
    private let content = NSView()
    private var locations: [URL] = []
    private var buttons: [NSButton] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = content
        addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ ancestors: [URL]) {
        locations = ancestors
        buttons.forEach { $0.removeFromSuperview() }
        buttons = ancestors.enumerated().map { index, location in
            let title = location == TrashStore.location ? "Trash" : location.path == "/" ? "/" : location.lastPathComponent
            let button = NSButton(title: title, target: self, action: #selector(openAncestor))
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.tag = index
            button.setAccessibilityLabel("Go to ancestor folder: \(location.path)")
            ToolbarHelp.install(on: button, text: "Open \(location == TrashStore.location ? "Trash" : location.path)")
            content.addSubview(button)
            return button
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        content.scrollToVisible(NSRect(x: max(0, content.bounds.width - 1), y: 0, width: 1, height: bounds.height))
    }

    override func layout() {
        super.layout()
        scroll.frame = NSRect(x: 12, y: 0, width: max(0, bounds.width - 24), height: bounds.height)
        var x: CGFloat = 0
        for button in buttons {
            button.sizeToFit()
            let width = max(28, button.frame.width)
            button.frame = NSRect(x: x, y: (bounds.height - 26) / 2, width: width, height: 26)
            x += width + 5
        }
        content.frame = NSRect(x: 0, y: 0, width: max(scroll.contentSize.width, x - 5), height: bounds.height)
    }

    @objc private func openAncestor(_ sender: NSButton) {
        guard locations.indices.contains(sender.tag) else { return }
        onNavigate?(locations[sender.tag])
    }
}
