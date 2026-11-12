import Foundation
import RightHereCore

/// `state.toml` is there and was not read, so it was not written over: whoever pins a folder or records a recent one must not replace what it holds (the person's pinned
/// folders) with an empty list.
public struct StateFileNotRead: Error, LocalizedError, Equatable {
    public var file: String
    public var reason: String

    public var errorDescription: String? { text(in: .english) }
}

extension StateFileNotRead: LocalizedFailure {
    public var sentences: [LocalizedMessage] { [.configCannotBeUsed(file, reason + ", so it was left as it is")] }
}

extension StateStore {
    /// What the state file holds: nothing yet, the state, or a file that is there and cannot be read (and why, in English).
    public enum Reading: Sendable, Equatable {
        case absent
        case read(StateStore)
        case unreadable(String)
    }

    public static func read(paths: RHPaths) -> Reading {
        var info = stat()
        guard lstat(paths.stateFile.path, &info) == 0 else {
            return errno == ENOENT ? .absent : .unreadable("it cannot be looked at (\(String(cString: strerror(errno))))")
        }
        // Its size is asked before it is read: every `rh run` reads it, and any program of the person's can write it.
        let data: Data
        switch BoundedRead.read(paths.stateFile, limit: 128 * 1024 - 1) {
        case .data(let read): data = read
        case .tooLarge: return .unreadable("it is larger than 128 KB")
        case .absent, .unreadable: return .unreadable("it cannot be read")
        }
        guard let text = String(data: data, encoding: .utf8) else { return .unreadable("it is not UTF-8 text") }
        guard let state = parseStrictly(text) else { return .unreadable("it is not valid TOML") }
        return .read(state)
    }

    /// Loads state from `state.toml`, returning an empty store if the file does not exist or cannot be read (`read` says which).
    public static func load(paths: RHPaths) -> StateStore {
        if case .read(let state) = read(paths: paths) { return state }
        return StateStore()
    }

    /// Reads the state, changes it and writes it back as one step that nobody else takes part in, and says what `change` says. The write
    /// is atomic, but a read, a change and a write are three: two programs that did them at once each wrote the state they had read, and the
    /// one that came second lost the change of the first (20 `rh pin` started together kept 12). The file is written only when `change`
    /// changed something. `Busy` when another program holds the lock for longer than `timeout`, which is for one read and one write.
    @discardableResult
    public static func update<Value>(paths: RHPaths, timeout: Duration = .seconds(5), _ change: (inout StateStore) throws -> Value) throws -> Value {
        let lock = try FileLock.acquireNow(paths.stateLockFile, timeout: timeout)
        defer { lock.release() }
        var state = StateStore()
        switch read(paths: paths) {
        case .absent: break
        case .read(let found): state = found
        case .unreadable(let reason): throw StateFileNotRead(file: paths.stateFile.path, reason: reason)
        }
        let before = state
        let result = try change(&state)
        if state != before { try state.save(paths: paths) }
        return result
    }

    /// Saves state to `state.toml` atomically.
    public func save(paths: RHPaths) throws {
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        let text = render()
        // Folders the person worked in: readable by them only, like the run log.
        try AtomicFile.write(Data(text.utf8), to: paths.stateFile, mode: 0o600)
    }
}
