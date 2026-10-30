import Foundation

/// Where the config writes an entry of a list of tables (`[[preset]]`, `[[agent.claude.variant]]`): the file that holds it on this Mac and its place among the entries of that file, from 1. An
/// edit of one of its fields names the entry by that place, under the check that the entry at that place is still the one that was shown.
public struct EntryLocation: Sendable, Equatable {
    /// The file that decides it on this Mac: this Mac's own when it writes the entry, else the shared one.
    public var target: ConfigTarget
    /// The place of the entry among the entries of that table in that file, from 1.
    public var position: Int

    public init(target: ConfigTarget, position: Int) {
        self.target = target
        self.position = position
    }
}

/// The changes of one edit and the file they go to: an entry of a list of tables is in the file that holds it, and the same place in the other file is another entry, so a change names its
/// file instead of leaving the file to be decided by a key.
public struct FileChange: Sendable, Equatable {
    public var target: ConfigTarget
    public var operations: [ConfigOperation]

    public init(target: ConfigTarget, operations: [ConfigOperation]) {
        self.target = target
        self.operations = operations
    }
}
