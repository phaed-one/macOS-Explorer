import Foundation
import Darwin

public enum PermissionMode {
    public static func parse(_ text: String, original: UInt16, isDirectory: Bool) throws -> UInt16 {
        var input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.hasPrefix("chmod ") { input = String(input.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        if (3...4).contains(input.count), input.allSatisfy({ ("0"..."7").contains(String($0)) }), let value = UInt16(input, radix: 8) { return value }
        guard !input.isEmpty else { throw invalid() }
        return try input.split(separator: ",", omittingEmptySubsequences: false).reduce(original) { mode, clause in
            try apply(String(clause), to: mode, isDirectory: isDirectory)
        }
    }
    private static func invalid() -> NSError {
        NSError(domain: "Pathfind", code: 3, userInfo: [NSLocalizedDescriptionKey: "Use an octal mode (755, 0644) or symbolic mode (u+rwx,g-w,o=rx). No file arguments or shell commands."])
    }
    private static func apply(_ clause: String, to mode: UInt16, isDirectory: Bool) throws -> UInt16 {
        guard let operation = clause.firstIndex(where: { "+-=".contains($0) }) else { throw invalid() }
        let who = String(clause[..<operation])
        guard who.allSatisfy({ "ugoa".contains($0) }) else { throw invalid() }
        let classes = who.isEmpty || who.contains("a") ? "ugo" : who
        let flags = clause[clause.index(after: operation)...]
        guard flags.allSatisfy({ "rwxXstugo".contains($0) }) else { throw invalid() }
        var bits: UInt16 = 0, mask: UInt16 = 0
        for group in Set(classes) {
            let shift: UInt16 = group == "u" ? 6 : group == "g" ? 3 : 0
            mask |= [Character("u"): UInt16(0o4700), "g": 0o2070, "o": 0o1007][group]!
            bits |= triad(flags, mode: mode, isDirectory: isDirectory) << shift
            bits |= specialBits(flags, group: group)
        }
        switch clause[operation] {
        case "+": return mode | bits
        case "-": return mode & ~bits
        default: return (mode & ~mask) | bits
        }
    }
    private static func triad(_ flags: Substring, mode: UInt16, isDirectory: Bool) -> UInt16 {
        let simple: [Character: UInt16] = ["r": 4, "w": 2, "x": 1]
        let sourceShifts: [Character: UInt16] = ["u": 6, "g": 3, "o": 0]
        var bits: UInt16 = 0
        for flag in flags {
            if let value = simple[flag] { bits |= value }
            if let shift = sourceShifts[flag] { bits |= (mode >> shift) & 7 }
        }
        if flags.contains("X"), isDirectory || mode & 0o111 != 0 { bits |= 1 }
        return bits
    }
    private static func specialBits(_ flags: Substring, group: Character) -> UInt16 {
        var bits: UInt16 = 0
        if flags.contains("s") { bits |= [Character("u"): UInt16(0o4000), "g": 0o2000][group] ?? 0 }
        if flags.contains("t"), group == "o" { bits |= 0o1000 }
        return bits
    }
}

extension FileSystem {
    public static func permissions(for url: URL) throws -> UInt16 {
        try rejectSymlink(url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let value = attributes[.posixPermissions] as? NSNumber else {
            throw NSError(domain: "Pathfind", code: 4, userInfo: [NSLocalizedDescriptionKey: "This filesystem does not expose POSIX permissions."])
        }
        return value.uint16Value & 0o7777
    }
    private static func rejectSymlink(_ url: URL) throws {
        if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw NSError(domain: "Pathfind", code: 5, userInfo: [NSLocalizedDescriptionKey: "Open the link’s target to change its permissions. Link targets are not changed implicitly."])
        }
    }
    public static func setPermissions(_ mode: UInt16, for url: URL) throws {
        try rejectSymlink(url)
        if chmod(url.path, mode_t(mode & 0o7777)) != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
