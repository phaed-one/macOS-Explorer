import Foundation
import PathfindCore

func checkHiddenFiles() throws {
    let suite = "ExplorerHiddenChecks." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let a = URL(fileURLWithPath: "/A"), b = URL(fileURLWithPath: "/B")
    defaults.set(try JSONSerialization.data(withJSONObject: ["showHidden": false]), forKey: "defaultFolderView")
    defaults.set(try JSONSerialization.data(withJSONObject: [a.path: ["showHidden": true], b.path: ["showHidden": false]]), forKey: "folderViews")
    let store = HiddenFileStore(defaults: defaults)
    let filesystem = URL(fileURLWithPath: "/")
    try expect(store.showsHidden(in: filesystem) && store.hasOverride(for: filesystem) && !store.defaultShowsHidden, "Filesystem starts with a local show-hidden choice without changing the global default")
    store.set(false, for: filesystem)
    try expect(!HiddenFileStore(defaults: defaults).showsHidden(in: filesystem), "A later explicit filesystem hide choice must survive restart")
    store.set(true, for: filesystem)
    try expect(store.showsHidden(in: a) && !store.showsHidden(in: b), "Existing folder visibility choices migrate")
    try expect(store.hasOverride(for: a) && !store.hasOverride(for: b), "Only legacy choices that differed from the old default become overrides")
    store.defaultShowsHidden = true
    try expect(store.showsHidden(in: b), "Folders without a choice inherit the default")
    store.set(false, for: a)
    try expect(!store.showsHidden(in: a) && store.showsHidden(in: b), "An explicit hide choice affects only its folder")
    let reopened = HiddenFileStore(defaults: defaults)
    try expect(!reopened.showsHidden(in: a) && reopened.defaultShowsHidden, "Default and explicit false both survive restart")
    try expect(!reopened.showsHidden(in: URL(fileURLWithPath: "/A/child/..")), "Equivalent folder paths share the same choice")
    reopened.useDefault(for: a)
    try expect(reopened.showsHidden(in: a) && !reopened.hasOverride(for: a), "A folder can return to inheriting the default")
    reopened.set(false, for: TrashStore.location)
    try expect(!reopened.showsHidden(in: TrashStore.location) && reopened.showsHidden(in: URL(fileURLWithPath: "/")), "Virtual Trash and filesystem root have distinct preferences")
    let views = FolderViewStore(defaults: defaults)
    var view = FolderViewPreferences(); view.mode = .details
    views.makeDefault(view)
    try expect(HiddenFileStore(defaults: defaults).defaultShowsHidden, "Changing the default folder view does not change visibility")
}
