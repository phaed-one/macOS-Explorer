import AppKit
import CryptoKit
import Foundation

let manager = FileManager.default
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("dist/Explorer.app")
let destination = URL(fileURLWithPath: "/Applications/Explorer.app")
let staging = URL(fileURLWithPath: "/Applications/.Explorer-install-\(UUID()).app")
let backup = URL(fileURLWithPath: "/Applications/.Explorer-backup-\(UUID()).app")

func command(_ arguments: [String]) throws -> String {
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    process.arguments = arguments; process.standardOutput = output; process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else { throw NSError(domain: "ExplorerInstall", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    return text
}
func requirement(_ url: URL) throws -> String {
    try command(["-d", "-r-", url.path]).split(separator: "\n").first { $0.hasPrefix("designated => ") }.map(String.init) ?? ""
}
func info(_ url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
    return try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
}
do {
    let expected = try info(source), identity = try requirement(source)
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("dist/release.json"))) as! [String: String]
    guard expected["CFBundleIdentifier"] as? String == "local.pathfind.app", identity.contains("certificate leaf"),
          expected["CFBundleShortVersionString"] as? String == manifest["version"],
          expected["CFBundleVersion"] as? String == manifest["build"] else {
        throw NSError(domain: "ExplorerInstall", code: 2, userInfo: [NSLocalizedDescriptionKey: "The app does not match the packaged release"])
    }
    _ = try command(["--verify", "--deep", "--strict", source.path])
    try manager.copyItem(at: source, to: staging)
    defer { try? manager.removeItem(at: staging) }
    _ = try command(["--verify", "--deep", "--strict", staging.path])
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: "local.pathfind.app")
    running.forEach { _ = $0.terminate() }
    let deadline = Date().addingTimeInterval(8)
    while running.contains(where: { !$0.isTerminated }), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    running.filter { !$0.isTerminated }.forEach { _ = $0.forceTerminate() }
    let forcedDeadline = Date().addingTimeInterval(3)
    while running.contains(where: { !$0.isTerminated }), Date() < forcedDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    guard running.allSatisfy(\.isTerminated) else { throw NSError(domain: "ExplorerInstall", code: 3, userInfo: [NSLocalizedDescriptionKey: "Explorer could not be stopped"]) }
    let hadPrevious = manager.fileExists(atPath: destination.path)
    if hadPrevious { try manager.moveItem(at: destination, to: backup) }
    do {
        try manager.moveItem(at: staging, to: destination)
        _ = try command(["--verify", "--deep", "--strict", destination.path])
        let installed = try info(destination)
        guard installed["CFBundleShortVersionString"] as? String == manifest["version"],
              installed["CFBundleVersion"] as? String == manifest["build"],
              try requirement(destination) == identity else { throw NSError(domain: "ExplorerInstall", code: 4) }
        let binary = "Contents/MacOS/Explorer"
        guard SHA256.hash(data: try Data(contentsOf: source.appendingPathComponent(binary))) == SHA256.hash(data: try Data(contentsOf: destination.appendingPathComponent(binary))) else { throw NSError(domain: "ExplorerInstall", code: 5) }
    } catch {
        try? manager.removeItem(at: destination)
        if hadPrevious { try? manager.moveItem(at: backup, to: destination) }
        throw error
    }
    if hadPrevious { try manager.removeItem(at: backup) }
    print("Installed /Applications/Explorer.app, version \(manifest["version"]!), build \(manifest["build"]!). Signature and binary match the published build. Stopped \(running.count) running instance(s).")
} catch { fputs("Install failed: \(error.localizedDescription)\n", stderr); exit(1) }
