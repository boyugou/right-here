import Foundation
import Synchronization

/// An advisory lock on a file of its own, so that the programs of one person take turns at what must not be done twice at once: the setup
/// window and `rh setup` in a terminal (or an AI agent's), the commands that change the pinned folders. `flock` belongs to the open file
/// description and not to the process, so two locks in one process contend as two processes do, and the system lets go of it when the
/// descriptor is closed or the process ends, even when it is killed: there is no stale lock to clean up, and the file is never removed
/// (a waiter that had opened the old file and a newcomer that made a new one would both hold "the" lock). Measured on APFS, see ADR 0021.
///
/// A lock that cannot be made at all (the folder is not writable, the name is a link or not a file, the file system has no locks) is not
/// held and is not an error: the work goes on as it did before there was a lock, and what the lock protects is also safe without it, or
/// was no safer before. Only a lock that somebody else holds for longer than the caller waits is an error (`Busy`).
public final class FileLock: Sendable {
    /// The lock is held by somebody else, and was not let go in the time that was given.
    public struct Busy: Error, LocalizedError, Equatable {
        public var file: URL
        public var errorDescription: String? {
            "Another Right Here process holds the lock \(file.path) and did not let go of it in time. Try again in a moment."
        }
    }

    private let descriptor: Mutex<Int32>

    private init(descriptor: Int32) {
        self.descriptor = Mutex(descriptor)
    }

    /// Whether this holds the lock: `false` for the lock that could not be made.
    public var isHeld: Bool { descriptor.withLock { $0 >= 0 } }

    /// Lets go. The lock is let go when the object is gone too.
    public func release() {
        descriptor.withLock { descriptor in
            guard descriptor >= 0 else { return }
            flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }
    }

    deinit {
        descriptor.withLock { descriptor in
            if descriptor >= 0 { close(descriptor) }
        }
    }

    // MARK: Taking it

    private enum Attempt {
        case held
        case busy
        /// The file system or the file does not take a lock.
        case unavailable
    }

    /// The file, opened as a lock file: made when it is not there (with its folder), never through a link, and only if it is a file.
    private static func open(_ file: URL) -> Int32? {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // O_CLOEXEC: what `rh` starts (the login shell, `pluginkit`) must not keep the lock after `rh` has let go of it.
        let descriptor = Darwin.open(file.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { return nil }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    private static func attempt(_ descriptor: Int32) -> Attempt {
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            if errno == EINTR { continue }
            return errno == EWOULDBLOCK ? .busy : .unavailable
        }
        return .held
    }

    /// Takes the lock, waiting for whoever holds it as long as `timeout`. For code that is `async`: the wait does not hold a thread.
    public static func acquire(_ file: URL, timeout: Duration, poll: Duration = .milliseconds(100)) async throws -> FileLock {
        guard let descriptor = open(file) else { return FileLock(descriptor: -1) }
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            switch attempt(descriptor) {
            case .held: return FileLock(descriptor: descriptor)
            case .unavailable:
                close(descriptor)
                return FileLock(descriptor: -1)
            case .busy:
                guard clock.now < deadline else {
                    close(descriptor)
                    throw Busy(file: file)
                }
                do { try await Task.sleep(for: poll) } catch {
                    close(descriptor)
                    throw error
                }
            }
        }
    }

    /// The same for a short critical section in code that is not `async`: it waits by sleeping the thread, so `timeout` is short.
    public static func acquireNow(_ file: URL, timeout: Duration, poll: Duration = .milliseconds(5)) throws -> FileLock {
        guard let descriptor = open(file) else { return FileLock(descriptor: -1) }
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            switch attempt(descriptor) {
            case .held: return FileLock(descriptor: descriptor)
            case .unavailable:
                close(descriptor)
                return FileLock(descriptor: -1)
            case .busy:
                guard clock.now < deadline else {
                    close(descriptor)
                    throw Busy(file: file)
                }
                let parts = poll.components
                usleep(UInt32(parts.seconds * 1_000_000 + parts.attoseconds / 1_000_000_000_000))
            }
        }
    }
}
