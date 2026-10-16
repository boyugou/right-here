import Foundation
import RightHereCore

extension StateStore {
    /// Loads state from `state.toml`, returning an empty store if the file does not exist or cannot be parsed.
    public static func load(paths: RHPaths) -> StateStore {
        guard let data = try? Data(contentsOf: paths.stateFile),
              data.count < 128 * 1024,
              let text = String(data: data, encoding: .utf8) else {
            return StateStore()
        }
        return parse(text)
    }

    /// Reads the state, changes it and writes it back as one step that nobody else takes part in, and says what `change` says. The write
    /// is atomic, but a read, a change and a write are three: two programs that did them at once each wrote the state they had read, and the
    /// one that came second lost the change of the first (20 `rh pin` started together kept 12). The file is written only when `change`
    /// changed something. `Busy` when another program holds the lock for longer than `timeout`, which is for one read and one write.
    @discardableResult
    public static func update<Value>(paths: RHPaths, timeout: Duration = .seconds(5), _ change: (inout StateStore) throws -> Value) throws -> Value {
        let lock = try FileLock.acquireNow(paths.stateLockFile, timeout: timeout)
        defer { lock.release() }
        var state = load(paths: paths)
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
