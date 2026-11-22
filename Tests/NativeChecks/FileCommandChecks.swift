import Foundation
import PathfindCore

/// Compress archives one item as "<name>.zip" and several as "Archive.zip" holding each at the top,
/// numbering names that are taken; Make Alias numbers its aliases the same way.
func checkCompressAndAlias() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-Compress-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let a = folder.appendingPathComponent("a.txt"), b = folder.appendingPathComponent("b.txt")
    try Data("a".utf8).write(to: a); try Data("b".utf8).write(to: b)

    func entries(_ archive: URL) throws -> [String] {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", archive.path]; process.standardOutput = output
        try process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return text.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("__MACOSX") }.sorted()
    }
    let single = try FileSystem.compress([a], into: folder), singleEntries = try entries(single)
    try require(single.lastPathComponent == "a.txt.zip" && singleEntries == ["a.txt"], "One item compresses to <name>.zip holding it: \(singleEntries)")
    let again = try FileSystem.compress([a], into: folder)
    try require(again.lastPathComponent == "a.txt 2.zip", "A taken archive name is numbered")
    let several = try FileSystem.compress([a, b], into: folder), severalEntries = try entries(several)
    try require(several.lastPathComponent == "Archive.zip" && severalEntries == ["a.txt", "b.txt"], "Several items compress to Archive.zip, each at the top: \(severalEntries)")

    let project = folder.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
    try Data("c".utf8).write(to: project.appendingPathComponent("c.txt"))
    let zippedFolder = try FileSystem.compress([project], into: folder), folderEntries = try entries(zippedFolder)
    try require(zippedFolder.lastPathComponent == "project.zip" && folderEntries == ["project/", "project/c.txt"], "A folder compresses with its own name at the top: \(folderEntries)")

    let alias = try FileSystem.makeAlias(a)
    try require(alias.lastPathComponent == "a.txt alias" && (try? alias.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == true, "Make Alias creates \"<name> alias\"")
    let secondAlias = try FileSystem.makeAlias(a)
    try require(secondAlias.lastPathComponent == "a.txt alias 2", "A taken alias name is numbered")
    print("PASS: Compress and Make Alias name their results as Finder does")
}
