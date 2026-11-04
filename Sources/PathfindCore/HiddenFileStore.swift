import Foundation

/// A shared default with explicit per-folder choices, independent of folder views.
public final class HiddenFileStore {
    public static let changed = Notification.Name("ExplorerHiddenFilesChanged")
    private let defaults: UserDefaults
    private struct Legacy: Decodable { let showHidden: Bool }
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let baseline = defaults.data(forKey: "defaultFolderView").flatMap { try? JSONDecoder().decode(Legacy.self, from: $0) }?.showHidden ?? false
        if defaults.object(forKey: "defaultShowHiddenFiles") == nil { defaults.set(baseline, forKey: "defaultShowHiddenFiles") }
        if defaults.data(forKey: "folderHiddenFiles") == nil {
            let legacy = defaults.data(forKey: "folderViews").flatMap { try? JSONDecoder().decode([String: Legacy].self, from: $0) } ?? [:]
            overrides = legacy.filter { $0.value.showHidden != baseline }.mapValues(\.showHidden)
        }
        // Seed the filesystem once; later user choices must survive restarts.
        if !defaults.bool(forKey: "filesystemShowHiddenDefaultApplied") {
            var saved = overrides; saved["/"] = true; overrides = saved
            defaults.set(true, forKey: "filesystemShowHiddenDefaultApplied")
        }
    }
    private var overrides: [String: Bool] {
        get { defaults.data(forKey: "folderHiddenFiles").flatMap { try? JSONDecoder().decode([String: Bool].self, from: $0) } ?? [:] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "folderHiddenFiles") }
    }
    public var defaultShowsHidden: Bool {
        get { defaults.bool(forKey: "defaultShowHiddenFiles") }
        set {
            defaults.set(newValue, forKey: "defaultShowHiddenFiles")
            NotificationCenter.default.post(name: Self.changed, object: self)
        }
    }
    public func showsHidden(in folder: URL) -> Bool { overrides[folder.folderPreferenceKey] ?? defaultShowsHidden }
    public func hasOverride(for folder: URL) -> Bool { overrides[folder.folderPreferenceKey] != nil }
    public func set(_ value: Bool, for folder: URL) {
        var saved = overrides; saved[folder.folderPreferenceKey] = value; overrides = saved
        notify(folder)
    }
    public func useDefault(for folder: URL) {
        var saved = overrides; saved.removeValue(forKey: folder.folderPreferenceKey); overrides = saved
        notify(folder)
    }
    private func notify(_ folder: URL) { NotificationCenter.default.post(name: Self.changed, object: self, userInfo: ["folder": folder]) }
}
