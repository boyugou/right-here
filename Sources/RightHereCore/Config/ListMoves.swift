import Foundation

/// How a drag in a list of the window becomes changes of the config.
enum ListMoves {
    /// The changes that do what SwiftUI's `onMove` says of a list of `count` items: the items at `source` (counting from 0) go before the item at `destination` (from 0, in the
    /// list as it is), and the others keep their order. Each change moves one item, `entries` for a list of tables and else for a list of text, so that what an item carries (a comment
    /// above it) goes with it. Nothing for a drag that leaves every item where it was, or that does not fit the list.
    static func operations(moving source: IndexSet, to destination: Int, count: Int, key: String, entries: Bool = false) -> [ConfigOperation] {
        guard !source.isEmpty, source.allSatisfy({ $0 >= 0 && $0 < count }), destination >= 0, destination <= count else { return [] }
        let moving = source.sorted()
        var wanted = Array(0..<count).filter { !source.contains($0) }
        wanted.insert(contentsOf: moving, at: destination - source.filter { $0 < destination }.count)
        var current = Array(0..<count)
        var operations: [ConfigOperation] = []
        for place in 0..<count where current[place] != wanted[place] {
            let from = current.firstIndex(of: wanted[place]) ?? place
            operations.append(entries ? .moveEntry(from: from + 1, to: place + 1, in: key) : .move(from: from + 1, to: place + 1, in: key))
            current.insert(current.remove(at: from), at: place)
        }
        return operations
    }
}
