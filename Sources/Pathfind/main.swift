import AppKit
import CoreServices

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate, SettingsPresenting, ServerConnectionPresenting {
    private let workspace = BrowserWorkspace()
    private var settings: SettingsController?
    private lazy var serverConnection = ServerConnectionController(onConnected: { [weak self] urls in
        guard let self else { return }
        for (index, url) in urls.enumerated() {
            if index == 0, let browser = self.workspace.activeBrowser {
                browser.navigate(url); browser.window?.makeKeyAndOrderFront(nil)
            } else { self.workspace.newWindow(at: url) }
        }
    })
    private lazy var diskAccess = DiskAccessController(onAccessGranted: { [weak self] in
        for browser in self?.workspace.browsers.values ?? [:].values {
            browser.navigate(browser.sessionTabs.current.url, record: false)
        }
    })
    private var launched = false
    private var pendingRequests: [([URL], Bool)] = []
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(revealFiles(_:withReply:)),
            forEventClass: AEEventClass(kAEMiscStandards), andEventID: AEEventID(kAEMakeObjectsVisible))
    }
    func application(_ sender: NSApplication, open urls: [URL]) { openFiles(urls, revealing: false) }
    @objc private func revealFiles(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        let urls = FileViewerRequest.urls(in: event)
        guard !urls.isEmpty else {
            reply.setParam(NSAppleEventDescriptor(int32: Int32(errAEParamMissed)), forKeyword: AEKeyword(keyErrorNumber))
            return
        }
        openFiles(urls, revealing: true)
    }
    private func openFiles(_ urls: [URL], revealing: Bool) {
        guard launched else { pendingRequests.append((urls, revealing)); return }
        let groups = Dictionary(grouping: urls.filter(\.isFileURL)) { url in
            !revealing && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                ? url.standardizedFileURL : url.deletingLastPathComponent().standardizedFileURL
        }
        for folder in groups.keys.sorted(by: { $0.path < $1.path }) {
            let browser = workspace.newWindow(at: folder)
            browser.navigate(folder, selecting: (groups[folder] ?? []).filter { revealing || $0.standardizedFileURL != folder })
        }
        app.activate(ignoringOtherApps: true)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Explorer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Explorer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let fileItem = NSMenuItem(); menu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Window", action: #selector(newWindow), keyEquivalent: "n").target = self
        fileItem.submenu = fileMenu
        let editItem = NSMenuItem()
        menu.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        for (name, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: name, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = edit
        app.mainMenu = menu
        workspace.restore()
        launched = true
        for (urls, revealing) in pendingRequests { openFiles(urls, revealing: revealing) }
        pendingRequests.removeAll()
        app.activate(ignoringOtherApps: true)
        AppUpdater.shared.start()
        diskAccess.start()
    }
    @objc func showSettings() {
        if settings == nil { settings = SettingsController() }
        if let parent = workspace.activeBrowser?.window, let panel = settings?.window, panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        settings?.window?.orderFront(nil)
    }
    @objc private func newWindow() { workspace.newWindow() }
    @objc func connectToServer() { serverConnection.present() }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Window", action: #selector(newWindow), keyEquivalent: "").target = self
        return menu
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if workspace.browsers.isEmpty { workspace.newWindow() }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        workspace.prepareToTerminate(); return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
