import AppKit
import PathfindCore

/// The sole owner of open windows, tab transfers, and their persisted session.
final class BrowserWorkspace: NSObject, NSWindowDelegate {
    private struct SavedWindow: Codable { let id: UUID; let tabs: BrowserTabs; let frame: String }
    private struct Session: Codable { var windows: [SavedWindow]; var lastClosed: SavedWindow? }
    private(set) var browsers: [UUID: BrowserController] = [:]
    private var order: [UUID] = []
    private var lastClosed: SavedWindow?
    private var restoring = false
    private var terminating = false
    private var transferDepth = 0
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var activeBrowser: BrowserController? {
        browsers.values.first { $0.window === NSApp.mainWindow } ?? order.last.flatMap { browsers[$0] }
    }
    func restore() {
        restoring = true
        let saved = defaults.data(forKey: "browserWorkspace").flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
        lastClosed = saved?.lastClosed
        for record in saved?.windows ?? [] where !record.tabs.items.isEmpty {
            let browser = create(tabs: record.tabs, id: record.id)
            let frame = NSRectFromString(record.frame)
            if frame.width >= 900, frame.height >= 440, let window = browser.window { place(window, frame: frame) }
        }
        if browsers.isEmpty {
            if let lastClosed {
                let browser = create(tabs: lastClosed.tabs, id: lastClosed.id)
                if let window = browser.window { place(window, frame: NSRectFromString(lastClosed.frame)) }
            } else {
                let id = UUID()
                for key in Self.treeKeys {
                    if let value = defaults.object(forKey: key) { defaults.set(value, forKey: id.uuidString + "." + key) }
                }
                let browser = create(tabs: BrowserTabs.restore(from: defaults, fallback: FileManager.default.homeDirectoryForCurrentUser), id: id)
                _ = browser.window?.setFrameUsingName("PathfindBrowser")
            }
        }
        restoring = false; save()
    }
    /// Clicking the Dock icon with no windows brings back the last closed one exactly as it was.
    @discardableResult func reopenLastClosed() -> BrowserController {
        guard let saved = lastClosed, !saved.tabs.items.isEmpty else { return newWindow() }
        lastClosed = nil
        let browser = create(tabs: saved.tabs, id: saved.id)
        if let window = browser.window { place(window, frame: NSRectFromString(saved.frame)) }
        save()
        return browser
    }
    @discardableResult func newWindow(at url: URL? = nil) -> BrowserController {
        create(tabs: BrowserTabs(url: url ?? FileManager.default.homeDirectoryForCurrentUser))
    }
    @discardableResult private func create(tabs: BrowserTabs, id: UUID = UUID()) -> BrowserController {
        let browser = BrowserController(tabs: tabs, windowID: id)
        browsers[id] = browser; order.append(id)
        browser.window?.delegate = self
        browser.onSessionChanged = { [weak self] in self?.save() }
        browser.onTabDrop = { [weak self] payload, before in self?.moveTab(payload, to: id, before: before) ?? false }
        browser.onDetachTab = { [weak self] tab, point in self?.detachTab(TabTransfer(windowID: id, tabID: tab), at: point) }
        if let previous = activeBrowser?.window, previous !== browser.window, let window = browser.window {
            window.setFrameOrigin(NSPoint(x: previous.frame.minX + 28, y: previous.frame.minY - 28))
        }
        if let window = browser.window { place(window, frame: window.frame) }
        browser.showWindow(nil); save()
        return browser
    }
    @discardableResult func moveTab(_ payload: TabTransfer, to targetID: UUID, before id: UUID?) -> Bool {
        guard let source = browsers[payload.windowID], let target = browsers[targetID],
              source.canTransferTabs, target.canTransferTabs, let tab = source.tab(payload.tabID) else { return false }
        transferDepth += 1
        defer { transferDepth -= 1; save() }
        if source === target { source.reorderTab(tab.id, before: id) }
        else {
            target.receiveTab(tab, before: id)
            source.removeTransferredTab(tab.id)
            target.window?.makeKeyAndOrderFront(nil)
        }
        return true
    }
    func detachTab(_ payload: TabTransfer, at point: NSPoint) {
        guard let source = browsers[payload.windowID], source.canTransferTabs, let tab = source.tab(payload.tabID) else { return }
        transferDepth += 1
        defer { transferDepth -= 1; save() }
        let browser = create(tabs: BrowserTabs(tab: tab))
        if let window = browser.window {
            let screen = NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame ?? NSScreen.main!.visibleFrame
            window.setFrameOrigin(NSPoint(x: max(screen.minX, min(point.x - 150, screen.maxX - window.frame.width)), y: max(screen.minY, min(point.y - window.frame.height + 25, screen.maxY - window.frame.height))))
        }
        source.removeTransferredTab(tab.id)
    }
    func windowWillClose(_ notification: Notification) {
        guard !terminating, let window = notification.object as? NSWindow,
              let id = browsers.first(where: { $0.value.window === window })?.key else { return }
        if let old = lastClosed, old.id != id, browsers[old.id] == nil {
            for key in Self.treeKeys { defaults.removeObject(forKey: old.id.uuidString + "." + key) }
        }
        if let browser = browsers[id] { lastClosed = SavedWindow(id: id, tabs: browser.sessionTabs, frame: NSStringFromRect(window.frame)) }
        browsers.removeValue(forKey: id); order.removeAll { $0 == id }; save()
    }
    func windowDidMove(_ notification: Notification) { save() }
    func windowDidResize(_ notification: Notification) { save() }
    func windowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = browsers.first(where: { $0.value.window === window })?.key else { return }
        order.removeAll { $0 == id }; order.append(id); save()
    }
    private func place(_ window: NSWindow, frame: NSRect) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = min(visible.width, max(900, frame.width)), height = min(visible.height, max(440, frame.height))
        window.setFrame(NSRect(x: max(visible.minX, min(frame.minX, visible.maxX - width)), y: max(visible.minY, min(frame.minY, visible.maxY - height)), width: width, height: height), display: true)
    }
    func prepareToTerminate() { save(); terminating = true }
    private static let treeKeys = ["explicitExpandedTreePaths", "collapsedTreeGroups", "selectedTreeItem", "sidebarWidth"]
    private func save() {
        guard !restoring, !terminating, transferDepth == 0 else { return }
        let windows = order.compactMap { id -> SavedWindow? in
            guard let browser = browsers[id], let window = browser.window else { return nil }
            return SavedWindow(id: id, tabs: browser.sessionTabs, frame: NSStringFromRect(window.frame))
        }
        defaults.set(try? JSONEncoder().encode(Session(windows: windows, lastClosed: lastClosed)), forKey: "browserWorkspace")
    }
}
