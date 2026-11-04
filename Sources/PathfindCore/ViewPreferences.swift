import Foundation

public enum FolderViewMode: String, Codable, Sendable {
    case details, icons
}

public struct FolderViewPreferences: Codable, Equatable, Sendable {
    public var mode: FolderViewMode = .icons
    public var iconSize: Double = 64
    public var sort: FileSort = .name
    public var ascending = true
    public var foldersFirst = true
    public var filter = ""
    public var columnWidths: [String: Double] = [:]
    public var columnOrder: [String] = ["name", "modified", "kind", "size"]
    public init() {}
}

/// Explicit folder overrides inherit the default only until the user customizes them.
public final class FolderViewStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private var overrides: [String: FolderViewPreferences] {
        guard let data = defaults.data(forKey: "folderViews"),
              let views = try? JSONDecoder().decode([String: FolderViewPreferences].self, from: data) else { return [:] }
        return views
    }
    public var defaultView: FolderViewPreferences {
        guard let data = defaults.data(forKey: "defaultFolderView"),
              let view = try? JSONDecoder().decode(FolderViewPreferences.self, from: data) else { return .init() }
        return view
    }
    public func view(for folder: URL) -> FolderViewPreferences { overrides[folder.folderPreferenceKey] ?? defaultView }
    public func hasOverride(for folder: URL) -> Bool { overrides[folder.folderPreferenceKey] != nil }
    public func save(_ view: FolderViewPreferences, for folder: URL) {
        var views = overrides
        views[folder.folderPreferenceKey] = view
        defaults.set(try? JSONEncoder().encode(views), forKey: "folderViews")
    }
    public func makeDefault(_ view: FolderViewPreferences) {
        defaults.set(try? JSONEncoder().encode(view), forKey: "defaultFolderView")
    }
    public func restoreDefault(for folder: URL) {
        var views = overrides
        views.removeValue(forKey: folder.folderPreferenceKey)
        defaults.set(try? JSONEncoder().encode(views), forKey: "folderViews")
    }
}

extension URL {
    var folderPreferenceKey: String { isFileURL ? standardizedFileURL.path : absoluteString }
}
