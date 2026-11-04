import Foundation

/// Reads only live Finder put-back records. Never edits Finder's .DS_Store.
/// Format reference: https://github.com/dmgbuild/ds_store
public enum TrashMetadata {
    public struct Location { public var parent: String?; public var name: String? }
    public static func read(_ data: Data) throws -> [String: Location] {
        var header = Cursor(data)
        guard try header.integer() == 1, try header.text(4) == "Bud1" else { throw InvalidData() }
        let offset = try header.integer(), size = try header.integer()
        guard try header.integer() == offset else { throw InvalidData() }
        var allocator = try Cursor(data, offset: offset + 4, count: size)
        let count = try allocator.integer()
        guard count <= data.count / 4 else { throw InvalidData() }
        try allocator.skip(4)
        let addresses = try (0..<count).map { _ in try allocator.integer() }
        try allocator.skip((((count + 255) / 256) * 256 - count) * 4)
        let names = try allocator.integer()
        guard names <= allocator.data.count / 5 else { throw InvalidData() }
        var database: Int?
        for _ in 0..<names {
            let length = try allocator.byte()
            let name = try allocator.text(length), block = try allocator.integer()
            if name == "DSDB" { database = block }
        }
        func block(_ index: Int) throws -> Cursor {
            guard addresses.indices.contains(index), addresses[index] != 0 else { throw InvalidData() }
            let address = addresses[index]
            return try Cursor(data, offset: (address & ~31) + 4, count: 1 << (address & 31))
        }
        guard let database else { throw InvalidData() }
        var tree = try block(database)
        var pending = [try tree.integer()], visited = Set<Int>()
        var result: [String: Location] = [:]
        while let index = pending.popLast() {
            guard visited.insert(index).inserted else { throw InvalidData() }
            var node = try block(index)
            let next = try node.integer(), records = try node.integer()
            guard records <= node.data.count / 12 else { throw InvalidData() }
            if next != 0 { pending.append(next) }
            for _ in 0..<records {
                if next != 0 { pending.append(try node.integer()) }
                let name = try node.unicode(), code = try node.text(4)
                let value = try node.value()
                if code == "ptbL" { result[name, default: Location()].parent = value }
                if code == "ptbN" { result[name, default: Location()].name = value }
            }
        }
        return result
    }
    private struct InvalidData: Error {}
    private struct Cursor {
        let data: Data
        var position = 0
        init(_ data: Data) { self.data = data }
        init(_ data: Data, offset: Int, count: Int) throws {
            guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else { throw InvalidData() }
            self.data = data.subdata(in: offset..<(offset + count))
        }
        mutating func take(_ count: Int) throws -> Data {
            guard count >= 0, count <= data.count - position else { throw InvalidData() }
            defer { position += count }
            return data.subdata(in: position..<(position + count))
        }
        mutating func skip(_ count: Int) throws { _ = try take(count) }
        mutating func integer() throws -> Int { try take(4).reduce(0) { ($0 << 8) | Int($1) } }
        mutating func byte() throws -> Int { Int(try take(1).first!) }
        mutating func text(_ count: Int) throws -> String { String(decoding: try take(count), as: UTF8.self) }
        mutating func unicode() throws -> String {
            let length = try integer()
            guard length <= (data.count - position) / 2,
                  let value = String(data: try take(length * 2), encoding: .utf16BigEndian) else { throw InvalidData() }
            return value
        }
        mutating func value() throws -> String? {
            switch try text(4) {
            case "ustr": return try unicode()
            case "bool": try skip(1)
            case "long", "shor", "type": try skip(4)
            case "comp", "dutc": try skip(8)
            case "blob": let length = try integer(); try skip(length)
            default: throw InvalidData()
            }
            return nil
        }
    }
}
