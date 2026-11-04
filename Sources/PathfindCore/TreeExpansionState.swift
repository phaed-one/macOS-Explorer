import Foundation

/// Stores each branch's own choice. Closing an ancestor never erases descendants.
public struct TreeExpansionState {
    public private(set) var paths: Set<String>
    public init(paths: [String] = []) { self.paths = Set(paths) }
    public func isExpanded(_ path: String) -> Bool { paths.contains(path) }
    public mutating func setExpanded(_ expanded: Bool, path: String) {
        if expanded { paths.insert(path) } else { paths.remove(path) }
    }
}
