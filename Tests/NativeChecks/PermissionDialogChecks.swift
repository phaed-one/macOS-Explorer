import AppKit

func checkPermissionDialog() throws {
    for (mode, letters) in [(UInt16(0o755), "rwxr-xr-x"), (0o644, "rw-r--r--"), (0o4755, "rwsr-xr-x"), (0o4644, "rwSr--r--"),
                            (0o2750, "rwxr-s---"), (0o1777, "rwxrwxrwt"), (0o1776, "rwxrwxrwT"), (0, "---------")] {
        try require(PermissionsController.symbolic(mode) == letters, "\(String(mode, radix: 8)) must read \(letters), not \(PermissionsController.symbolic(mode))")
    }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-Permissions-\(UUID()).sh")
    try Data("echo".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    chmod(file.path, 0o754)
    let dialog = try PermissionsController(urls: [file])
    defer { dialog.close() }
    let views = descendants(dialog.window!.contentView!)
    let labels = views.compactMap { ($0 as? NSTextField)?.stringValue }
    try require(labels.contains("Now 0754 · rwxr-xr--") && labels.contains(file.lastPathComponent), "The header must name the item and its current mode: \(labels)")
    let field = views.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "chmod mode" }!
    let groupWrite = views.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Group write" }!
    groupWrite.performClick(nil)
    try require(field.stringValue == "0774" && labels.count > 0 && descendants(dialog.window!.contentView!).compactMap { ($0 as? NSTextField)?.stringValue }.contains("rwxrwxr--"),
        "Ticking a box must update the mode field and the letter preview together")
    let frame = dialog.window!.frame.size
    try require(frame.width > frame.height, "The permissions dialog must be wider than tall: \(frame)")
    print("PASS: Permissions dialog shows the current mode, previews ls-style letters including set-ID and sticky bits, and stays wide")
}
