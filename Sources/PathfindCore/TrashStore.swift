import Foundation

public final class TrashStore {
    public static let location = URL(string: "pathfind://trash")!
    public static let shared = TrashStore()
    private let defaults: UserDefaults
    private let roots: (() -> [URL])
    public var directories: [URL] { roots() }
    private let trashOperation: (URL) throws -> URL
    private let lock = NSLock()
    private struct Record: Codable { let original: URL; let inode: UInt64; let created: Date? }
    public init(defaults: UserDefaults = .standard, directories: @escaping () -> [URL] = TrashStore.systemDirectories,
                trashOperation: @escaping (URL) throws -> URL = TrashStore.systemTrash) {
        self.defaults = defaults; roots = directories; self.trashOperation = trashOperation
    }
    public static func systemDirectories() -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let volumes = fm.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        let external = volumes.filter { $0.path != "/" }.map { $0.appendingPathComponent(".Trashes/\(getuid())") }
        // Always attempt the home Trash: an access-denied stat must not look empty.
        return Array(Set([home] + external.filter { fm.fileExists(atPath: $0.path) })).sorted { $0.path < $1.path }
    }
    public static func systemTrash(_ source: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: source, resultingItemURL: &result)
        guard let result else { throw failure("macOS did not return the trashed item's location.") }
        return result as URL
    }
    private var records: [String: Record] {
        get { defaults.data(forKey: "trashOrigins").flatMap { try? JSONDecoder().decode([String: Record].self, from: $0) } ?? [:] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "trashOrigins") }
    }
    public func contents(showHidden: Bool) throws -> [FileEntry] {
        let directories = roots()
        let entries = try directories.flatMap { directory -> [FileEntry] in
            do { return try FileSystem.contents(of: directory, showHidden: true) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code) { return [] }
        }.filter { !Self.isMetadata($0.name) }
        let live = Set(entries.map { $0.url.standardizedFileURL.path })
        lock.lock()
        let saved = records
        let retained = saved.filter { path, _ in live.contains(path) || !directories.contains { path.hasPrefix($0.standardizedFileURL.path + "/") } }
        if retained.count != saved.count { records = retained }
        lock.unlock()
        return showHidden ? entries : entries.filter { !$0.isHidden }
    }
    public func isRoot(_ url: URL) -> Bool { roots().contains { $0.standardizedFileURL == url.standardizedFileURL } }
    public func contains(_ url: URL) -> Bool {
        url == Self.location || roots().contains { url.standardizedFileURL == $0.standardizedFileURL || url.standardizedFileURL.path.hasPrefix($0.standardizedFileURL.path + "/") }
    }
    @discardableResult public func trash(_ source: URL) throws -> URL {
        guard !contains(source) else { throw Self.failure("This item is already in the Trash.") }
        lock.lock(); defer { lock.unlock() }
        let originalAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let destination = try trashOperation(source)
        let attributes = (try? FileManager.default.attributesOfItem(atPath: destination.path)) ?? originalAttributes
        let record = Record(original: source.standardizedFileURL,
                            inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                            created: attributes[.creationDate] as? Date)
        var saved = records; saved[destination.standardizedFileURL.path] = record; records = saved
        return destination
    }
    public func originalURL(for item: URL) -> URL? {
        guard let root = roots().first(where: { item.standardizedFileURL.path.hasPrefix($0.standardizedFileURL.path + "/") }) else { return nil }
        let relative = String(item.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
        let parts = relative.split(separator: "/").map(String.init)
        guard let name = parts.first else { return nil }
        let top = root.appendingPathComponent(name)
        lock.lock(); let record = records[top.standardizedFileURL.path]; lock.unlock()
        var original: URL?
        if let record, let attributes = try? FileManager.default.attributesOfItem(atPath: top.path),
           (attributes[.systemFileNumber] as? NSNumber)?.uint64Value == record.inode,
           attributes[.creationDate] as? Date == record.created { original = record.original }
        if original == nil, let data = try? Data(contentsOf: root.appendingPathComponent(".DS_Store"), options: .mappedIfSafe),
           let metadata = try? TrashMetadata.read(data)[name], let parent = metadata.parent {
            let volume = (try? root.resourceValues(forKeys: [.volumeURLKey]))?.volume ?? URL(fileURLWithPath: "/")
            let directory = parent.hasPrefix("/") ? URL(fileURLWithPath: parent) : volume.appendingPathComponent(parent)
            let originalName = metadata.name ?? name
            guard !originalName.isEmpty, !originalName.contains("/"), originalName != ".", originalName != ".." else { return nil }
            original = directory.appendingPathComponent(originalName)
        }
        return parts.dropFirst().reduce(original) { $0?.appendingPathComponent($1) }
    }
    public func restore(_ item: URL, to destination: URL? = nil) throws {
        guard contains(item), item != Self.location, !isRoot(item) else { throw Self.failure("Select an item in the Trash to restore.") }
        guard let destination = destination ?? originalURL(for: item) else { throw Self.failure("The original location is unavailable. Choose a restore folder.") }
        guard !contains(destination) else { throw Self.failure("The restore destination cannot be inside the Trash.") }
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: item, to: destination)
        lock.lock(); var saved = records; saved.removeValue(forKey: item.standardizedFileURL.path); records = saved; lock.unlock()
    }
    public func clear() throws {
        let entries = try contents(showHidden: true)
        for entry in entries { try FileManager.default.removeItem(at: entry.url) }
        lock.lock(); var saved = records
        for entry in entries { saved.removeValue(forKey: entry.url.standardizedFileURL.path) }
        records = saved; lock.unlock()
    }
    private static func isMetadata(_ name: String) -> Bool { [".DS_Store", ".localized"].contains(name) }
    private static func failure(_ message: String) -> NSError { NSError(domain: "Pathfind", code: 3, userInfo: [NSLocalizedDescriptionKey: message]) }
}
