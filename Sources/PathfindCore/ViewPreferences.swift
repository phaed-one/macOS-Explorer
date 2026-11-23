import Foundation

public enum FolderViewMode: String, Codable, Sendable {
    case details, icons, list
}

public struct FolderViewPreferences: Codable, Equatable, Sendable {
    public var mode: FolderViewMode = .icons
    public var iconSize: Double = 64
    // Optional so existing saved views decode without losing their icon spacing.
    public var iconSpacing: Double? = nil
    public var listSpacing: Double? = nil
    public var sort: FileSort = .name
    public var ascending = true
    public var foldersFirst = true
    public var filter = ""
    public var columnWidths: [String: Double] = [:]
    public var columnOrder: [String] = ["name", "modified", "kind", "size"]
    /// Built-in spacing for views that never saved their own.
    public static let defaultIconSpacing = 6.25, defaultListSpacing = 10.8
    public init() {}
}

/// Explicit folder overrides inherit the default only until the user customizes them.
public final class FolderViewStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Once, so the Trash starts from its own default rather than a view saved before it had one.
        if !defaults.bool(forKey: "trashViewDefaultApplied") {
            restoreDefault(for: TrashStore.location)
            defaults.set(true, forKey: "trashViewDefaultApplied")
        }
    }
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
    public func view(for folder: URL) -> FolderViewPreferences {
        if let saved = overrides[folder.folderPreferenceKey] { return saved }
        return folder == TrashStore.location ? Self.trashView(from: defaultView) : defaultView
    }
    /// The Trash, like Finder's: details with a Date Deleted column, most recently deleted first,
    /// folders mixed in by date. Icon sizes and spacing follow the default view.
    public static func trashView(from base: FolderViewPreferences) -> FolderViewPreferences {
        var view = base
        view.mode = .details
        view.sort = .deleted; view.ascending = false
        view.foldersFirst = false
        view.filter = ""
        view.columnOrder = ["name", "deleted", "modified", "kind", "size"]
        return view
    }
    public func hasOverride(for folder: URL) -> Bool { overrides[folder.folderPreferenceKey] != nil }
    public func save(_ view: FolderViewPreferences, for folder: URL) {
        var views = overrides
        views[folder.folderPreferenceKey] = view
        defaults.set(try? JSONEncoder().encode(views), forKey: "folderViews")
    }
    public func makeDefault(_ view: FolderViewPreferences) {
        var view = view
        // Only the Trash has a Date Deleted column, so other folders sort by date modified instead.
        if view.sort == .deleted { view.sort = .modified }
        view.columnOrder.removeAll { $0 == "deleted" }
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
