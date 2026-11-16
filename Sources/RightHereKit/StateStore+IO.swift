import Darwin
import Foundation
import RightHereCore

public enum StateStoreError: Error, LocalizedError, Sendable {
    case unreadable(file: String, detail: String)
    case tooLarge(file: String, limit: Int)

    public func message(home: String? = nil) -> LocalizedMessage {
        func display(_ file: String) -> String {
            let path = home.map { PathDisplay.abbreviatingHome(file, home: $0) } ?? file
            return path.withControlCharactersEscaped
        }
        switch self {
        case .unreadable(let file, let detail): return .appSavedFoldersReadFailed(display(file), detail.withControlCharactersEscaped)
        case .tooLarge(let file, let limit): return .appSavedFoldersTooLarge(display(file), String(limit))
        }
    }

    public var errorDescription: String? { message().english() }
}

extension StateStoreError: LocalizedFailure {
    public var sentences: [LocalizedMessage] { [message()] }
}

extension StateStore {
    public static let maximumFileBytes = 128 * 1024

    /// Only an absent file means no saved folders. A read failure must never become the starting point for an update.
    public static func load(paths: RHPaths) throws(StateStoreError) -> StateStore {
        let data: Data
        switch BoundedRead.read(paths.stateFile, limit: maximumFileBytes) {
        case .data(let read): data = read
        case .absent:
            var metadata = stat()
            // Reading a dangling symlink also reports ENOENT; lstat must confirm that the entry itself is absent.
            let failed = lstat(paths.stateFile.path, &metadata) != 0
            let code = failed ? errno : ENOENT
            if failed, code == ENOENT { return StateStore() }
            throw StateStoreError.unreadable(file: paths.stateFile.path, detail: String(cString: strerror(code)))
        case .unreadable(let reason):
            throw StateStoreError.unreadable(file: paths.stateFile.path, detail: reason)
        case .tooLarge:
            throw StateStoreError.tooLarge(file: paths.stateFile.path, limit: maximumFileBytes)
        }
        do {
            guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            return try parse(text)
        } catch {
            throw StateStoreError.unreadable(file: paths.stateFile.path, detail: error.localizedDescription)
        }
    }

    /// Reads the state, changes it and writes it back as one step that nobody else takes part in, and says what `change` says. The write
    /// is atomic, but a read, a change and a write are three: two programs that did them at once each wrote the state they had read, and the
    /// one that came second lost the change of the first (20 `rh pin` started together kept 12). The file is written only when `change`
    /// changed something. `Busy` when another program holds the lock for longer than `timeout`, which is for one read and one write.
    @discardableResult
    public static func update<Value>(paths: RHPaths, timeout: Duration = .seconds(5), _ change: (inout StateStore) throws -> Value) throws -> Value {
        let lock = try FileLock.acquireNow(paths.stateLockFile, timeout: timeout)
        defer { lock.release() }
        var state = try load(paths: paths)
        let before = state
        let result = try change(&state)
        if state != before { try state.save(paths: paths) }
        return result
    }

    /// Saves state to `state.toml` atomically.
    public func save(paths: RHPaths) throws {
        let data = Data(render().utf8)
        guard data.count <= Self.maximumFileBytes else {
            throw StateStoreError.tooLarge(file: paths.stateFile.path, limit: Self.maximumFileBytes)
        }
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        // Folders the person worked in: readable by them only, like the run log.
        try AtomicFile.write(data, to: paths.stateFile, mode: 0o600)
    }
}
