import AppKit
import UniformTypeIdentifiers

/// The app macOS really opens a file with, and where a new default for it goes.
///
/// A file with no extension (`.env`, `Makefile`) has the catch-all data type. macOS refuses a
/// default for that type, even from Finder, and its lookup answers with the catch-all default. Opening
/// the file goes by more than that: an app saved on the file itself wins, then an empty or
/// plain-ASCII file opens with the plain-text default. Explorer follows the open, so the "(default)"
/// label and the icon match what a double-click does.
enum DefaultApplication {
    /// Where a new default for the file goes.
    enum Target: Equatable {
        /// The file's own type, such as every `.toml` file.
        case fileType
        /// Every file with this name, such as every `.env` file: see `SameNameDefaults`.
        case sameName
    }

    /// Types so broad that macOS won't take a default for them.
    private static let genericTypes: Set<UTType> = [.data, .item, .content, .compositeContent]
    /// How much of a file to look at when deciding whether it is plain text.
    private static let sniffLength = 4_096
    /// Where macOS keeps an app chosen for one file, as Finder's "Open with" does.
    static let fileChoiceAttribute = "com.apple.LaunchServices.OpenWith"

    static func application(for url: URL, names: SameNameDefaults = .shared) -> URL? {
        if hasFileChoice(url) { return NSWorkspace.shared.urlForApplication(toOpen: url) }
        if target(for: url) == .sameName, let app = names.application(forName: url.lastPathComponent) { return app }
        if opensAsPlainText(url), let app = NSWorkspace.shared.urlForApplication(toOpen: .plainText) { return app }
        return NSWorkspace.shared.urlForApplication(toOpen: url)
    }

    static func target(for url: URL) -> Target {
        guard let type = contentType(url) else { return .fileType }
        return genericTypes.contains(type) ? .sameName : .fileType
    }

    /// Whether an app has been saved on this one file.
    static func hasFileChoice(_ url: URL) -> Bool {
        getxattr(url.path, fileChoiceAttribute, nil, 0, 0, 0) >= 0
    }

    /// A file with no type of its own that macOS opens as plain text: empty, or ASCII text.
    static func opensAsPlainText(_ url: URL) -> Bool {
        guard contentType(url) == .data, let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: sniffLength) else { return true }
        return isPlainASCII(data)
    }

    /// Printable ASCII plus tab, line feed, form feed and carriage return. macOS treats a file with
    /// an accented letter as data, not text, so UTF-8 beyond ASCII doesn't count.
    static func isPlainASCII(_ data: Data) -> Bool {
        data.allSatisfy { (0x20...0x7E).contains($0) || [0x09, 0x0A, 0x0C, 0x0D].contains($0) }
    }

    private static func contentType(_ url: URL) -> UTType? {
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey]), values.isDirectory != true else { return nil }
        return values.contentType
    }
}

/// Default apps for files with no extension, by name: every `.env` opens in Code.
///
/// macOS has no default by name, so Explorer remembers the choice and saves it on each file with that
/// name: once on every one in the home folder, then on new ones as Explorer lists them. Finder reads
/// the saved choice too, so it opens those files the same way.
final class SameNameDefaults {
    static let shared = SameNameDefaults()
    static let key = "sameNameDefaultApplications"
    /// Folders the home sweep never enters: app data, dependencies, and hidden folders such as `.git`.
    private static let skippedFolders: Set<String> = ["Library", "node_modules"]

    typealias SaveChoice = (_ app: URL, _ file: URL, _ done: @escaping (Error?) -> Void) -> Void
    private let defaults: UserDefaults
    private let home: URL
    private let saveChoice: SaveChoice
    private let sweeping = DispatchQueue(label: "Explorer.SameNameDefaults", qos: .utility)

    init(defaults: UserDefaults = .standard, home: URL = FileManager.default.homeDirectoryForCurrentUser,
         saveChoice: @escaping SaveChoice = { app, file, done in
             NSWorkspace.shared.setDefaultApplication(at: app, toOpenFileAt: file) { done($0) }
         }) {
        self.defaults = defaults; self.home = home; self.saveChoice = saveChoice
    }

    func application(forName name: String) -> URL? {
        guard let path = rules[name], FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private var rules: [String: String] { defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:] }

    /// Makes `app` the default for every file named like `file`. `saved` reports the chosen file once
    /// its choice is saved; `swept` reports how many other files with that name were updated.
    func set(_ app: URL, for file: URL, saved: @escaping (Error?) -> Void, swept: @escaping (Int) -> Void = { _ in }) {
        let name = file.lastPathComponent
        var rules = self.rules
        rules[name] = app.path
        defaults.set(rules, forKey: Self.key)
        saveChoice(app, file) { [weak self] error in
            DispatchQueue.main.async { saved(error) }
            guard let self else { return }
            self.sweeping.async {
                let others = Self.files(named: name, under: self.home).filter { $0.standardizedFileURL != file.standardizedFileURL }
                for other in others { self.saveChoice(app, other) { _ in } }
                DispatchQueue.main.async { swept(others.count) }
            }
        }
    }

    /// Saves the remembered app on listed files that have a remembered name and no app of their own yet.
    func adopt(_ urls: [URL]) {
        let rules = self.rules
        guard !rules.isEmpty else { return }
        for url in urls {
            guard let path = rules[url.lastPathComponent], DefaultApplication.target(for: url) == .sameName,
                  !DefaultApplication.hasFileChoice(url), FileManager.default.fileExists(atPath: path) else { continue }
            saveChoice(URL(fileURLWithPath: path), url) { _ in }
        }
    }

    /// Files called `name` under `root`, outside skipped folders. Symbolic links are not followed.
    static func files(named name: String, under root: URL) -> [URL] {
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                                                        options: [.skipsPackageDescendants]) else { return [] }
        var found: [URL] = []
        for case let url as URL in walk {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            let entry = url.lastPathComponent
            if values?.isDirectory == true {
                if entry.hasPrefix(".") || skippedFolders.contains(entry) { walk.skipDescendants() }
            } else if entry == name, values?.isRegularFile == true {
                found.append(url)
            }
        }
        return found
    }
}
