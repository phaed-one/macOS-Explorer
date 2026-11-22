import AppKit
import UniformTypeIdentifiers

/// Icons for files macOS has no type for (`.toml`, `.gitignore`, `Makefile`), taken from the app
/// that opens them.
///
/// macOS takes these icons from some installed app that lists the extension in its Info.plist. That
/// is the default app only when the default lists it too, and macOS's icon cache can show the old app
/// long after the default changes. Explorer asks for the default itself: its own document icon for
/// the extension when it ships one, otherwise a blank page badged with the app's icon.
enum DocumentIcon {
    private static let cache = NSCache<NSString, NSImage>()

    /// The file's icon: from its default app when macOS has no type for it, otherwise macOS's own.
    static func icon(forFile url: URL) -> NSImage {
        defaultAppIcon(forFile: url) ?? NSWorkspace.shared.icon(forFile: url.path)
    }

    /// The file's icon from its default app, or nil when macOS has a type (and so an icon) for the
    /// file or nothing opens it. The default is looked up every time, so a change made anywhere,
    /// Finder included, shows at the next redraw.
    static func defaultAppIcon(forFile url: URL) -> NSImage? {
        guard isUntyped(url), let app = DefaultApplication.application(for: url) else { return nil }
        let label = extensionLabel(url)
        let key = "\(label)|\(app.path)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = documentIcon(in: app, forExtension: label.lowercased())
            ?? draw(badge: NSWorkspace.shared.icon(forFile: app.path), label: label)
        cache.setObject(image, forKey: key)
        return image
    }

    /// The document icon `app` ships for files with this extension (or dotfile name), if it ships one.
    static func documentIcon(in app: URL, forExtension ext: String) -> NSImage? {
        guard !ext.isEmpty, let bundle = Bundle(url: app),
              let types = bundle.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] else { return nil }
        for type in types {
            guard let extensions = type["CFBundleTypeExtensions"] as? [String],
                  extensions.contains(where: { $0.lowercased() == ext }),
                  let iconName = type["CFBundleTypeIconFile"] as? String,
                  let image = bundle.image(forResource: iconName) else { continue }
            return image
        }
        return nil
    }

    /// Files whose type macOS made up from the extension, or the catch-all type files with no
    /// extension share. No app defines these types, so none supplies an icon for them.
    static func isUntyped(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey]),
              values.isDirectory != true, let type = values.contentType else { return false }
        return type.isDynamic || type == .data
    }

    /// The text under the badge, as macOS writes it: the extension, or a dotfile's name.
    private static func extensionLabel(_ url: URL) -> String {
        let name = url.lastPathComponent
        let ext = url.pathExtension
        if !ext.isEmpty { return ext.uppercased() }
        return name.hasPrefix(".") ? String(name.dropFirst()).uppercased() : ""
    }

    /// A blank page with `badge` in the middle and `label` near the foot, drawn fresh at every size.
    static func draw(badge: NSImage, label: String) -> NSImage {
        let page = NSWorkspace.shared.icon(for: .data)
        return NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
            page.draw(in: rect)
            let side = (rect.width * 0.4).rounded()
            badge.draw(in: NSRect(x: rect.midX - side / 2, y: rect.minY + rect.height * 0.5 - side / 2, width: side, height: side))
            // `rect` is always the image's own size; the context's scale says how big it really lands.
            // Text under 8 device pixels can't be read, so small icons leave it off, as macOS does.
            let pixels = NSGraphicsContext.current.map { rect.height * abs($0.cgContext.userSpaceToDeviceSpaceTransform.d) } ?? rect.height
            var size = rect.height * 0.085
            guard !label.isEmpty, size * pixels / rect.height >= 8 else { return true }
            let maxWidth = rect.width * 0.56
            func text() -> NSAttributedString {
                NSAttributedString(string: label, attributes: [
                    .font: NSFont.systemFont(ofSize: size),
                    .foregroundColor: NSColor(white: 0.62, alpha: 1)
                ])
            }
            var string = text()
            while string.size().width > maxWidth, size > rect.height * 0.05 { size -= 0.5; string = text() }
            let bounds = string.size()
            let width = min(bounds.width, maxWidth)
            string.draw(with: NSRect(x: rect.midX - width / 2, y: rect.minY + rect.height * 0.17 - bounds.height / 2, width: width, height: bounds.height),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            return true
        }
    }
}
