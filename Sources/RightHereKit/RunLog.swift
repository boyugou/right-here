import Foundation
import RightHereCore

/// A small append-only log so a failed action started from Finder leaves a trace. Lines are written
/// with O_APPEND, so several `rh` processes started at once do not overwrite each other.
///
/// Whatever goes in is made safe first: a path with a line break must not forge a line (the doctor reads
/// the probe lines back), and the file is private to the person and capped, so it does not grow without end.
public enum RunLog {
    /// Past this size the log is moved to `rh.log.1` (replacing the previous one) and a new one starts.
    static let maxBytes: Int64 = 1_000_000

    /// One finished action, as `rh run` records it and `rh doctor` reads it back. The on-disk line is
    /// `2026-10-12T05:00:00Z ok agent.claude [items, 2 items]`; lines written by earlier versions have the same shape.
    public struct Entry: Sendable, Equatable {
        public enum Outcome: String, Sendable, Equatable {
            case ok
        }

        public var date: Date
        public var outcome: Outcome
        public var actionID: String
        public var origin: HereContext.Origin
        public var itemCount: Int

        public init(date: Date = Date(), outcome: Outcome = .ok, actionID: String, origin: HereContext.Origin, itemCount: Int) {
            self.date = date
            self.outcome = outcome
            self.actionID = actionID
            self.origin = origin
            self.itemCount = itemCount
        }

        /// The line as written to the log, without the line break.
        public func format() -> String {
            "\(ISO8601DateFormatter().string(from: date)) \(outcome.rawValue) \(actionID) [\(origin.rawValue), \(itemCount) items]"
        }

        /// Reads a line `format()` wrote. Lines of any other kind (failures, probes) are not entries.
        public init?(parsing line: some StringProtocol) {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let outcome = Outcome(rawValue: String(parts[1])),
                  let date = ISO8601DateFormatter().date(from: String(parts[0])) else { return nil }
            let detail = parts[3].split(separator: "]").first.flatMap { $0.split(separator: "[").last }?.split(separator: ",")
            guard let first = detail?.first, let origin = HereContext.Origin(rawValue: String(first)) else { return nil }
            self.date = date
            self.outcome = outcome
            self.actionID = String(parts[2])
            self.origin = origin
            self.itemCount = detail?.dropFirst().first.flatMap { Int($0.split(separator: " ").first ?? "") } ?? 0
        }
    }

    public static func record(_ entry: Entry, paths: RHPaths = .current()) {
        record(entry.format(), paths: paths, timestamped: false)
    }

    public static func record(_ message: String, paths: RHPaths = .current(), now: Date = Date()) {
        record(message, paths: paths, timestamped: true, now: now)
    }

    private static func record(_ message: String, paths: RHPaths, timestamped: Bool, now: Date = Date()) {
        try? FileManager.default.createDirectory(at: paths.logDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        rotateIfNeeded(paths.logFile)
        let stamp = timestamped ? "\(ISO8601DateFormatter().string(from: now)) " : ""
        let line = Array("\(stamp)\(message.withControlCharactersEscaped)\n".utf8)
        let descriptor = open(paths.logFile.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        // A log an earlier version created is world-readable; the mode above only applies to a new file.
        fchmod(descriptor, 0o600)
        _ = line.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    }

    static func rotateIfNeeded(_ file: URL) {
        var status = stat()
        guard stat(file.path, &status) == 0, status.st_size > maxBytes else { return }
        let older = file.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: older)
        try? FileManager.default.moveItem(at: file, to: older)
        // The old log keeps whatever mode an earlier version gave it (world-readable), and it is the one left behind.
        chmod(older.path, 0o600)
    }
}
