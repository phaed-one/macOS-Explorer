import Foundation

public struct BrowserTab: Codable {
    public let id: UUID
    public var url: URL
    public var history: NavigationHistory
    public init(url: URL) {
        id = UUID(); self.url = url; history = NavigationHistory(); history.visit(url)
    }
}

public struct BrowserTabs: Codable {
    public private(set) var items: [BrowserTab]
    public private(set) var activeID: UUID
    public init(url: URL) {
        let tab = BrowserTab(url: url); items = [tab]; activeID = tab.id
    }
    public init(tab: BrowserTab) { items = [tab]; activeID = tab.id }
    public mutating func insert(_ tab: BrowserTab, before otherID: UUID? = nil) {
        if items.contains(where: { $0.id == tab.id }) { move(tab.id, before: otherID); return }
        let index = otherID.flatMap { id in items.firstIndex { $0.id == id } } ?? items.count
        items.insert(tab, at: index); activeID = tab.id
    }
    public mutating func move(_ id: UUID, before otherID: UUID?) {
        guard id != otherID, let index = items.firstIndex(where: { $0.id == id }) else { return }
        let tab = items.remove(at: index)
        let destination = otherID.flatMap { id in items.firstIndex { $0.id == id } } ?? items.count
        items.insert(tab, at: destination)
    }
    public var activeIndex: Int { items.firstIndex { $0.id == activeID } ?? 0 }
    public var current: BrowserTab {
        get { items[activeIndex] }
        set { items[activeIndex] = newValue }
    }
    public mutating func open(_ url: URL) {
        let tab = BrowserTab(url: url); items.append(tab); activeID = tab.id
    }
    public mutating func select(_ id: UUID) {
        if items.contains(where: { $0.id == id }) { activeID = id }
    }
    @discardableResult public mutating func close(_ id: UUID) -> Bool {
        guard items.count > 1, let index = items.firstIndex(where: { $0.id == id }) else { return false }
        items.remove(at: index)
        if activeID == id { activeID = items[min(index, items.count - 1)].id }
        return true
    }
    public static func restore(from defaults: UserDefaults = .standard, fallback: URL) -> BrowserTabs {
        guard let data = defaults.data(forKey: "browserTabs"),
              let saved = try? JSONDecoder().decode(BrowserTabs.self, from: data), !saved.items.isEmpty,
              saved.items.contains(where: { $0.id == saved.activeID }) else { return BrowserTabs(url: fallback) }
        return saved
    }
    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: "browserTabs")
    }
}
