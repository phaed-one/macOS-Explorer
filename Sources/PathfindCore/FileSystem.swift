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

/// What a transfer does when the destination folder already has an item with the same name.
public enum NameConflict: Sendable {
    case fail, replace, keepBoth
}

public enum FileSystem {
    /// Splits a name so numbering goes before the extension; plain folders keep dots in their name.
    private static func nameParts(_ source: URL) -> (name: String, suffix: String) {
        let values = try? source.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        let hasExtension = values?.isDirectory != true || values?.isPackage == true
        let suffix = hasExtension && !source.pathExtension.isEmpty ? "." + source.pathExtension : ""
        return (suffix.isEmpty ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent, suffix)
    }
    public static func itemExists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
    /// The first unused "name 2.ext", "name 3.ext", … in a directory, as Finder's Keep Both names them.
    public static func availableDestination(for source: URL, in directory: URL) -> URL {
        let (name, suffix) = nameParts(source)
        var number = 2
        while true {
            let candidate = directory.appendingPathComponent("\(name) \(number)\(suffix)")
            if !itemExists(candidate) { return candidate }
            number += 1
        }
    }
    @discardableResult
    public static func duplicate(_ source: URL) throws -> URL {
        let (name, suffix) = nameParts(source)
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
    /// `trash` disposes of an item being replaced, so a replaced item stays recoverable.
    public static func transfer(_ source: URL, into directory: URL, move: Bool, conflict: NameConflict = .fail,
                                trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        var destination = directory.appendingPathComponent(source.lastPathComponent)
        let originalPath = source.resolvingSymlinksInPath().path
        let targetPath = destination.resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory)
        if targetPath == originalPath || (isDirectory.boolValue && targetPath.hasPrefix(originalPath + "/")) {
            throw NSError(domain: "Pathfind", code: 2, userInfo: [NSLocalizedDescriptionKey: "A folder cannot be transferred into itself, and an item cannot replace itself."])
        }
        if itemExists(destination) {
            switch conflict {
            case .fail: break
            case .keepBoth: destination = availableDestination(for: source, in: directory)
            case .replace:
                guard !originalPath.hasPrefix(targetPath + "/") else {
                    throw NSError(domain: "Pathfind", code: 2, userInfo: [NSLocalizedDescriptionKey: "“\(destination.lastPathComponent)” can’t be replaced because it contains the item being \(move ? "moved" : "copied")."])
                }
                try replace(destination, with: source, move: move, trash: trash)
                return
            }
        }
        if move { try FileManager.default.moveItem(at: source, to: destination) }
        else { try FileManager.default.copyItem(at: source, to: destination) }
    }
    /// Stages the new item beside the target first, so a failed copy never costs the existing item.
    private static func replace(_ target: URL, with source: URL, move: Bool, trash: (URL) throws -> Void) throws {
        let fm = FileManager.default
        let staged = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).explorer-\(UUID().uuidString)")
        if move { try fm.moveItem(at: source, to: staged) } else { try fm.copyItem(at: source, to: staged) }
        do {
            try trash(target)
            try fm.moveItem(at: staged, to: target)
        } catch {
            if move { try? fm.moveItem(at: staged, to: source) } else { try? fm.removeItem(at: staged) }
            throw error
        }
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
