import Foundation

public struct FileEntry: Sendable {
    public let url: URL
    public let isDirectory: Bool
    public let isHidden: Bool
    public let size: Int64
    public let modified: Date
    public let kind: String
    public init(url: URL, isDirectory: Bool, isHidden: Bool, size: Int64, modified: Date, kind: String) {
        self.url = url; self.isDirectory = isDirectory; self.isHidden = isHidden
        self.size = size; self.modified = modified; self.kind = kind
    }
    public var name: String { url.lastPathComponent }
}

public enum FileSort: String, CaseIterable, Sendable, Codable {
    case name, modified, kind, size
}

public enum FileSystem {
    @discardableResult
    public static func duplicate(_ source: URL) throws -> URL {
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        let hasExtension = values.isDirectory != true || values.isPackage == true
        let suffix = hasExtension && !source.pathExtension.isEmpty ? "." + source.pathExtension : ""
        let name = suffix.isEmpty ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        let parent = source.deletingLastPathComponent()
        var number = 1
        while true {
            let destination = parent.appendingPathComponent(name + (number == 1 ? " copy" : " copy \(number)") + suffix)
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                return destination
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                number += 1
            }
        }
    }
    public static func transfer(_ source: URL, into directory: URL, move: Bool) throws {
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        let originalPath = source.resolvingSymlinksInPath().path
        let targetPath = destination.resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory)
        if targetPath == originalPath || (isDirectory.boolValue && targetPath.hasPrefix(originalPath + "/")) {
            throw NSError(domain: "Pathfind", code: 2, userInfo: [NSLocalizedDescriptionKey: "A folder cannot be transferred into itself, and an item cannot replace itself."])
        }
        if move { try FileManager.default.moveItem(at: source, to: destination) }
        else { try FileManager.default.copyItem(at: source, to: destination) }
    }
    public static func resolve(_ path: String, relativeTo current: URL) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded).standardizedFileURL }
        return current.appendingPathComponent(expanded).standardizedFileURL
    }

    public static func contents(of directory: URL, showHidden: Bool) throws -> [FileEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .fileSizeKey,
                                       .contentModificationDateKey, .localizedTypeDescriptionKey, .isSymbolicLinkKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys),
            options: showHidden ? [] : [.skipsHiddenFiles])
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            var directory = ObjCBool(values.isDirectory ?? false)
            if values.isSymbolicLink == true {
                _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            }
            return FileEntry(url: url, isDirectory: directory.boolValue,
                             isHidden: values.isHidden == true || url.lastPathComponent.hasPrefix("."),
                             size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast,
                             kind: directory.boolValue ? "Folder" : values.localizedTypeDescription ?? "File")
        }
    }

    public static func sorted(_ entries: [FileEntry], by key: FileSort, ascending: Bool, foldersFirst: Bool = true) -> [FileEntry] {
        entries.sorted { a, b in
            if foldersFirst && a.isDirectory != b.isDirectory { return a.isDirectory }
            let result: ComparisonResult
            switch key {
            case .name: result = a.name.localizedStandardCompare(b.name)
            case .kind: result = a.kind.localizedStandardCompare(b.kind)
            case .size: result = a.size == b.size ? .orderedSame : (a.size < b.size ? .orderedAscending : .orderedDescending)
            case .modified: result = a.modified.compare(b.modified)
            }
            let order = result == .orderedSame ? a.name.localizedStandardCompare(b.name) : result
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }
}

public struct NavigationHistory: Codable {
    public private(set) var locations: [URL] = []
    public private(set) var index = -1
    public init() {}
    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index + 1 < locations.count }
    public mutating func visit(_ url: URL) {
        if index >= 0 && locations[index] == url { return }
        locations = Array(locations.prefix(index + 1))
        locations.append(url)
        index = locations.count - 1
    }
    public mutating func back() -> URL? {
        guard canGoBack else { return nil }
        index -= 1
        return locations[index]
    }
    public mutating func forward() -> URL? {
        guard canGoForward else { return nil }
        index += 1
        return locations[index]
    }
}
