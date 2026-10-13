import Foundation
import RightHereCore
import Synchronization

/// The request `rh doctor` leaves for the Finder extension: a file named `.probe` in the config folder whose
/// text names the probe. It is a request for the next minute or two, not a standing order. If the doctor is
/// interrupted (Ctrl-C), the file would otherwise sit there until some later Finder start, and the extension
/// would open a terminal window at a moment nobody asked for, so a request older than `lifetime` is ignored.
public enum ProbeMarker {
    public static let name = ".probe"

    /// Longer than the slowest probe waits (75 seconds), short enough that a forgotten one is never honoured.
    public static let lifetime: TimeInterval = 120

    public static func url(in paths: RHPaths) -> URL {
        paths.configDirectory.appendingPathComponent(name)
    }

    /// Leaves a request. `false` when the file cannot be written.
    @discardableResult
    public static func write(_ text: String, in paths: RHPaths) -> Bool {
        try? FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        return (try? Data(text.utf8).write(to: url(in: paths))) != nil
    }

    /// The text of the pending request, or `nil` when there is none or it is too old to honour.
    public static func pending(in paths: RHPaths, now: Date = Date()) -> String? {
        let file = url(in: paths)
        guard let modified = modificationDate(of: file.path), isFresh(modified, now: now),
              let data = FileManager.default.contents(atPath: file.path) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Takes the request. Several processes can see it (Finder and every Open panel start an extension), and
    /// only one of them may act on it, and only while it is fresh. A stale file is taken and removed all the
    /// same, so it cannot trigger anything later.
    ///
    /// The file is claimed by renaming it to a name of the caller's own, because that is atomic: exactly one
    /// caller's `rename` finds the file. Racing `unlink` calls are not a claim: measured on APFS, several of
    /// eight concurrent `unlink`s of one path all return success.
    public static func claim(in paths: RHPaths, now: Date = Date()) -> Bool {
        let marker = url(in: paths).path
        let mine = "\(marker).claimed-\(getpid())-\(UInt32.random(in: 0...UInt32.max))"
        guard rename(marker, mine) == 0 else { return false }
        defer { unlink(mine) }
        guard let modified = modificationDate(of: mine) else { return false }
        return isFresh(modified, now: now)
    }

    /// A file dated well into the future is as untrustworthy as an old one (a clock that was set back).
    static func isFresh(_ modified: Date, now: Date) -> Bool {
        abs(now.timeIntervalSince(modified)) < lifetime
    }

    /// `lstat`, so a link left in place of the marker is judged by itself (`rename` and `unlink` move and remove the link).
    private static func modificationDate(of path: String) -> Date? {
        var status = stat()
        guard lstat(path, &status) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec) + TimeInterval(status.st_mtimespec.tv_nsec) / 1e9)
    }
}

extension ProbeMarker {
    /// What an interrupted probe does before it exits: withdraw the request first, then switch the extension back
    /// on. In the other order the extension would start with the request still there and open a terminal nobody asked for.
    public static func cleanUpAfterInterrupt(in paths: RHPaths, reenableExtension: () -> Void) {
        _ = claim(in: paths)
        reenableExtension()
    }
}

/// Runs the interrupt cleanup when the process gets one of `signals`. The signals are ignored by default and read
/// through dispatch sources, so the handler runs on a normal thread and may start a process; `finish` is what ends
/// the process (`exit(130)` in `rh`, a recorder in tests).
public final class InterruptGuard: Sendable {
    private let sources: Mutex<[DispatchSourceSignal]>

    public init(signals: [Int32] = [SIGINT, SIGTERM, SIGHUP], paths: RHPaths, reenableExtension: @escaping @Sendable () -> Void, finish: @escaping @Sendable () -> Void) {
        for number in signals { signal(number, SIG_IGN) }
        let made: [DispatchSourceSignal] = signals.map { number in
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                ProbeMarker.cleanUpAfterInterrupt(in: paths, reenableExtension: reenableExtension)
                finish()
            }
            source.resume()
            return source
        }
        sources = Mutex(made)
    }

    public func cancel() {
        let taken = sources.withLock { current in
            defer { current = [] }
            return current
        }
        taken.forEach { $0.cancel() }
    }
}

