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

    public static func record(_ message: String, paths: RHPaths = .current(), now: Date = Date()) {
        try? FileManager.default.createDirectory(at: paths.logDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        rotateIfNeeded(paths.logFile)
        let line = Array("\(ISO8601DateFormatter().string(from: now)) \(message.withControlCharactersEscaped)\n".utf8)
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
    }
}
