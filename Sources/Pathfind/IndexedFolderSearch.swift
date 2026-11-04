import Foundation
import PathfindCore

/// Uses Spotlight's recursive scope and live updates rather than enumerating trees.
final class IndexedFolderSearch {
    enum State: Equatable { case gathering, live, unavailable }
    private let makeQuery: () -> NSMetadataQuery
    private let processing = OperationQueue()
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?

    init(makeQuery: @escaping () -> NSMetadataQuery = { NSMetadataQuery() }) {
        self.makeQuery = makeQuery
        processing.maxConcurrentOperationCount = 1
        processing.qualityOfService = .userInitiated
    }

    func start(text: String, roots: [URL], showHidden: Bool, update: @escaping ([FileEntry], State) -> Void) {
        cancel()
        guard !text.isEmpty, !roots.isEmpty else { return }
        let query = makeQuery()
        self.query = query
        query.searchScopes = roots.map(\.path)
        query.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, text)
        query.notificationBatchingInterval = 0.2
        query.operationQueue = processing
        for name in [NSNotification.Name.NSMetadataQueryGatheringProgress, .NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: nil) { [weak self, weak query] _ in
                guard let query, !query.isStopped else { return }
                let entries = Self.snapshot(query, roots: roots, showHidden: showHidden)
                let state: State = query.isGathering ? .gathering : .live
                DispatchQueue.main.async {
                    guard let self, self.query === query else { return }
                    update(entries, state)
                }
            })
        }
        update([], .gathering)
        let work = DispatchWorkItem { [weak self, weak query] in
            guard let self, let query, self.query === query else { return }
            if !query.start() { update([], .unavailable) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private static func snapshot(_ query: NSMetadataQuery, roots: [URL], showHidden: Bool) -> [FileEntry] {
        query.disableUpdates()
        defer { query.enableUpdates() }
        var entries: [FileEntry] = []
        query.enumerateResults { object, _, _ in
            guard let item = object as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return }
            let url = URL(fileURLWithPath: path)
            // Enforce containment even if an index supplies an unexpected result.
            guard let root = roots.first(where: { path.hasPrefix($0.path == "/" ? "/" : $0.path + "/") }) else { return }
            let relative = String(path.dropFirst(root.path == "/" ? 1 : root.path.count + 1))
            let hidden = relative.split(separator: "/").contains { $0.hasPrefix(".") } || (item.value(forAttribute: "kMDItemFSInvisible") as? NSNumber)?.boolValue == true
            guard showHidden || !hidden else { return }
            let types = item.value(forAttribute: NSMetadataItemContentTypeTreeKey) as? [String] ?? []
            let directory = types.contains("public.directory") || types.contains("public.folder")
            entries.append(FileEntry(url: url, isDirectory: directory, isHidden: hidden,
                                     size: (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value ?? 0,
                                     modified: item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date ?? .distantPast,
                                     kind: item.value(forAttribute: NSMetadataItemKindKey) as? String ?? (directory ? "Folder" : "File")))
        }
        return entries
    }

    func cancel() {
        pending?.cancel(); pending = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
        query?.stop(); query = nil
    }
    deinit { cancel() }
}
