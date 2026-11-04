import AppKit
import NetFS

protocol ServerConnectionPresenting: AnyObject { func connectToServer() }

/// Owns the connection dialog and its single cancellable macOS mount request.
final class ServerConnectionController: NSWindowController, NSWindowDelegate {
    typealias Mount = (URL, @escaping (Result<[URL], Error>) -> Void) throws -> (() -> Void)
    let address = NSTextField(string: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let connectButton = NSButton(title: "Connect", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private let mount: Mount
    private let onConnected: ([URL]) -> Void
    private var cancelMount: (() -> Void)?
    private var request: UUID?

    init(mount: @escaping Mount = ServerConnectionController.mount, onConnected: @escaping ([URL]) -> Void) {
        self.mount = mount; self.onConnected = onConnected
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 210),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        super.init(window: panel)
        panel.title = "Connect to Server"; panel.delegate = self
        address.placeholderString = "smb://server/share"
        address.target = self; address.action = #selector(connect)
        connectButton.target = self; connectButton.action = #selector(connect); connectButton.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel)); cancel.keyEquivalent = "\u{1b}"
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        message.textColor = .secondaryLabelColor; message.heightAnchor.constraint(equalToConstant: 42).isActive = true
        let buttons = NSStackView(views: [progress, cancel, connectButton])
        let stack = NSStackView(views: [NSTextField(labelWithString: "Server address"), address,
            NSTextField(labelWithString: "SMB, AFP, NFS, or WebDAV (http/https)"), message, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = panel.contentView!; content.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            address.widthAnchor.constraint(equalTo: stack.widthAnchor), message.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        content.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: 500, height: stack.fittingSize.height + 48)); panel.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { cancelMount?() }

    func present() {
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
        if request == nil { window?.makeFirstResponder(address) }
    }
    static func serverURL(_ text: String) throws -> URL {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = input.contains("://") ? input : "smb://" + input
        guard !input.isEmpty, let parts = URLComponents(string: candidate),
              let scheme = parts.scheme?.lowercased(), ["smb", "afp", "nfs", "http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty, !host.contains(where: { $0.isWhitespace }),
              parts.password == nil, parts.query == nil, parts.fragment == nil, let url = parts.url else {
            throw NSError(domain: "ExplorerServer", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Enter a server address such as smb://server/share. Enter your password in the sign-in window when asked."])
        }
        return url
    }
    @objc func connect() {
        guard request == nil else { return }
        do {
            let url = try Self.serverURL(address.stringValue)
            let id = UUID(); request = id
            address.isEnabled = false; connectButton.isEnabled = false; progress.startAnimation(nil)
            message.stringValue = "Connecting… Sign in if asked."
            do {
                cancelMount = try mount(url) { [weak self] result in
                    DispatchQueue.main.async { self?.finish(result, request: id) }
                }
            } catch { finish(.failure(error), request: id) }
        } catch { message.stringValue = error.localizedDescription }
    }
    private func finish(_ result: Result<[URL], Error>, request id: UUID) {
        guard request == id else { return }
        request = nil; cancelMount = nil
        address.isEnabled = true; connectButton.isEnabled = true; progress.stopAnimation(nil)
        switch result {
        case .success(let urls) where !urls.isEmpty:
            message.stringValue = ""; close(); onConnected(urls)
        case .success:
            message.stringValue = "No shared folders were opened. Try including a share name in the address."
        case .failure(let error):
            if (error as NSError).code == Int(userCanceledErr) { message.stringValue = "Connection cancelled." }
            else { message.stringValue = "Couldn’t connect. Check the server address and your network, then try again." }
        }
    }
    @objc private func cancel() { close() }
    func windowWillClose(_ notification: Notification) {
        request = nil; cancelMount?(); cancelMount = nil
        address.isEnabled = true; connectButton.isEnabled = true; progress.stopAnimation(nil)
        message.stringValue = ""
    }
    static func mount(_ url: URL, completion: @escaping (Result<[URL], Error>) -> Void) throws -> (() -> Void) {
        var id: AsyncRequestID?
        let options = NSMutableDictionary(dictionary: [kNetFSAllowLoopbackKey: true])
        let status = NetFSMountURLAsync(url as CFURL, nil, nil, nil, options, nil, &id, .main) { status, _, paths in
            if status == 0 {
                let folders = (paths as? [String] ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
                completion(.success(folders))
            } else {
                completion(.failure(NSError(domain: status > 0 ? NSPOSIXErrorDomain : NSOSStatusErrorDomain, code: Int(status))))
            }
        }
        guard status == 0 else { throw NSError(domain: status > 0 ? NSPOSIXErrorDomain : NSOSStatusErrorDomain, code: Int(status)) }
        return { if let id { NetFSMountURLCancel(id) } }
    }
}
