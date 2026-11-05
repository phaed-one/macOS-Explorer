import AppKit

private final class ServerToolbarDelegate: NSObject, NSApplicationDelegate, ServerConnectionPresenting {
    var connections = 0
    func connectToServer() { connections += 1 }
}

func checkServerConnections() throws {
    let delegate = ServerToolbarDelegate()
    let previousDelegate = NSApp.delegate
    NSApp.delegate = delegate
    defer { NSApp.delegate = previousDelegate }
    let browser = BrowserController()
    defer { browser.close() }
    let root = browser.window!.contentView!
    guard let toolbarConnect = descendants(root).compactMap({ $0 as? NSButton }).first(where: { $0.accessibilityLabel() == "Connect to Server" }) else {
        throw NativeCheckError.failed("Connect to Server must be directly visible on the toolbar")
    }
    for width in [900.0, 1120.0, 1400.0] {
        browser.window!.setContentSize(NSSize(width: width, height: 740))
        root.layoutSubtreeIfNeeded()
        let frame = toolbarConnect.convert(toolbarConnect.bounds, to: root)
        try require(root.bounds.contains(frame) && frame.size == NSSize(width: 30, height: 30) && toolbarConnect.imagePosition == .imageOnly, "Server connection must use one standard square toolbar icon")
        let path = descendants(root).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Current folder path" }!
        let search = descendants(root).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Search this folder" }!
        var searchSurface: NSView = search
        if #available(macOS 26, *) {
            var ancestor = search.superview
            while let view = ancestor {
                if view is NSGlassEffectView { searchSurface = view; break }
                ancestor = view.superview
            }
        }
        let searchFrame = searchSurface.convert(searchSurface.bounds, to: root)
        try require(path.frame.width > 150 && abs(searchFrame.maxX - (root.bounds.maxX - 20)) < 1, "Search must retain its original right-aligned position")
        let favorite = descendants(root).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Add selected folder to Favorites" }!
        let favoriteFrame = favorite.convert(favorite.bounds, to: root)
        try require(abs(frame.midY - favoriteFrame.midY) < 1 && frame.minX - favoriteFrame.maxX >= 24, "Server icon must sit to the right of Favorites with a clear gap")
    }
    toolbarConnect.performClick(nil)
    try require(delegate.connections == 1, "The toolbar button must open the app's connection dialog")
    print("PASS: Server icon after Favorites with a clear gap at 900/1120/1400 widths, original Search position, and working action")

    for (input, expected) in [("server/share", "smb://server/share"), (" smb://server/Team Files ", "smb://server/Team%20Files"),
        ("afp://nas/share", "afp://nas/share"), ("nfs://nas/export", "nfs://nas/export"),
        ("https://nas/dav", "https://nas/dav"), ("http://[::1]:8080/", "http://[::1]:8080/")] {
        let actual = try ServerConnectionController.serverURL(input).absoluteString
        try require(actual == expected, "Network addresses must retain their host, path and protocol")
    }
    for input in ["", "   ", "file:///tmp", "ssh://server/share", "smb:///share", "smb://bad host/share", "smb://user:secret@host/share", "https://host/?password=secret"] {
        do { _ = try ServerConnectionController.serverURL(input); throw NativeCheckError.failed("Invalid server address accepted") }
        catch is NativeCheckError { throw NativeCheckError.failed("Invalid server address accepted: \(input)") }
        catch { }
    }
    var completion: ((Result<[URL], Error>) -> Void)?
    var started = 0, cancelled = 0
    var opened: [URL] = []
    let controller = ServerConnectionController(mount: { url, callback in
        try require(url.scheme == "smb", "A plain server address must use SMB")
        started += 1; completion = callback
        return { cancelled += 1 }
    }, onConnected: { opened = $0 })
    defer { controller.close() }
    controller.present(); controller.address.stringValue = "nas/share"; controller.connect(); controller.connect()
    let content = controller.window!.contentView!
    content.layoutSubtreeIfNeeded()
    for button in descendants(content).compactMap({ $0 as? NSButton }) {
        try require(content.bounds.contains(button.convert(button.bounds, to: content)), "Connection actions must fit inside the dialog")
    }
    try require(started == 1 && !controller.address.isEnabled, "Repeated Connect must not start overlapping mounts")
    controller.close()
    try require(cancelled == 1 && controller.address.isEnabled, "Closing the dialog must cancel the native mount")
    completion?(.success([URL(fileURLWithPath: "/tmp/stale")]))
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    try require(opened.isEmpty, "A queued completion from a cancelled connection must not navigate")
    controller.present(); controller.connect()
    completion?(.failure(NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNREFUSED))))
    try waitUntil { controller.address.isEnabled }
    let labels = descendants(controller.window!.contentView!).compactMap { ($0 as? NSTextField)?.stringValue }
    try require(labels.contains { $0.contains("Couldn’t connect") }, "Connection errors must leave the address editable and show recovery guidance")
    controller.connect()
    let shares = [URL(fileURLWithPath: "/Volumes/Team"), URL(fileURLWithPath: "/Volumes/Public")]
    completion?(.success(shares))
    try waitUntil { opened == shares && controller.window?.isVisible == false }
    try require(cancelled == 1, "Successful connections must not cancel an already completed native request")
    print("PASS: Network URL validation, SMB defaults, one active mount, cancellation, stale callbacks, retry, and opening connected shares")

    if let endpoint = ProcessInfo.processInfo.environment["PATHFIND_TEST_SERVER"] {
        var result: Result<[URL], Error>?
        let cancel = try ServerConnectionController.mount(ServerConnectionController.serverURL(endpoint)) { result = $0 }
        defer { if result == nil { cancel() } }
        let deadline = Date().addingTimeInterval(60)
        while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        try require(result != nil, "Network mount did not complete within 60 seconds")
        let urls = try result!.get()
        try require(!urls.isEmpty, "Native mounting must return a mounted folder")
        for url in urls {
            defer { try? NSWorkspace.shared.unmountAndEjectDevice(at: url) }
            let files = try FileManager.default.contentsOfDirectory(atPath: url.path)
            try require(files.contains("Explorer-Network-QA.txt"), "The mounted share must expose real server files")
        }
        print("PASS: Real NetFS connection, mounted share paths, directory listing, and test-share disconnect")
    }
}
