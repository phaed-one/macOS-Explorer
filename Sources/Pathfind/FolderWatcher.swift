import Foundation
import CoreServices

/// Watches directory entries and immediate-child metadata without polling.
final class FolderWatcher {
    var onChange: (() -> Void)?
    private var stream: FSEventStreamRef?
    private var directories: Set<String> = []
    private var pending: DispatchWorkItem?

    func watch(_ urls: [URL]) {
        let roots = Set(urls.map { url -> String in
            guard let resolved = realpath(url.path, nil) else { return url.path }
            defer { free(resolved) }
            return String(cString: resolved)
        })
        guard roots != directories else { return }
        stop()
        directories = roots
        guard !roots.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer)
        stream = FSEventStreamCreate(nil, { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let names = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as! [String]
            let rescanFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)
            let changed = (0..<count).contains { index in
                // Keep FSEvents' physical path, including for an item that was deleted.
                let url = URL(fileURLWithPath: names[index])
                return flags[index] & rescanFlags != 0 || watcher.directories.contains(url.path) || watcher.directories.contains(url.deletingLastPathComponent().path)
            }
            if changed { watcher.scheduleChange() }
        }, &context, Array(roots) as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2, flags)
        guard let stream else { directories = []; return }
        FSEventStreamSetDispatchQueue(stream, .main)
        if !FSEventStreamStart(stream) { stop() }
    }

    func stop() {
        pending?.cancel(); pending = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        directories = []
    }

    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange?() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    deinit { stop() }
}
