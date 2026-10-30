import CryptoKit
import Foundation
import RightHereCore

/// Who made an edit through `ConfigService`.
public enum ConfigActor: String, Sendable, Codable, Equatable {
    case window, cli, mcp
}

/// The text a config file had before each edit made through `ConfigService`, so that an edit can be undone and the window can say who changed what. One small file
/// for each edit, in `.history` next to the config; the newest fifty of each file are kept, and no more than `maxBytes` of text before them (the newest edit always is).
struct ConfigHistory: Sendable {
    struct Entry: Sendable, Equatable, Codable {
        var time: Date
        var actor: ConfigActor
        var target: ConfigTarget
        var summary: String
        /// The text before the edit.
        var before: String
        /// The SHA-256 of the text the edit wrote: the file is still as the edit left it when this is what it has now.
        var afterDigest: String
        /// The file the edit was made to. Two configs can share a folder (`RH_CONFIG` names a file anywhere), and an undo of one must not write its text into the other.
        var file: String
        /// Whether the file was there before the edit: the first edit of `config.local.toml` makes it, and taking that edit back removes it again.
        var existed: Bool
        /// The name of the entry's file, which sorts by time; set when it is read or written.
        var name: String = ""

        private enum CodingKeys: String, CodingKey { case time, actor, target, summary, before, afterDigest, file, existed }
    }

    static let keep = 50
    /// The text an entry holds is the whole file before the edit, which may be as large as a config may be (a megabyte); fifty of those would be a lot to leave in a folder
    /// that an edit loop of a script or an assistant fills. The entries beyond this many bytes of text are forgotten, oldest first.
    static let maxBytes = 8 * 1024 * 1024
    /// The characters of an entry's name that are its time: `20261016-143005-123`.
    static let stampLength = 19

    var directory: URL

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The entries of a file, newest first. A file that cannot be read as an entry is left alone and not listed.
    func entries(of target: ConfigTarget, file: String) -> [Entry] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".json") && $0.contains("-\(target.rawValue)-") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var found: [Entry] = []
        for name in names.sorted(by: >) {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)), var entry = try? decoder.decode(Entry.self, from: data), entry.target == target, entry.file == file else { continue }
            entry.name = name
            found.append(entry)
        }
        return found
    }

    private var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }

    /// Keeps the entry. The name of the stored entry is returned; the oldest entries are forgotten by `prune`, once the edit that the entry is for has been written.
    ///
    /// The names sort by time, and an entry that is made in the same millisecond as the one before (two changes of the window, or of a script), or when the clock is behind the
    /// newest entry's, still has to sort after it, or undo would take back the wrong one: its time is the millisecond after the newest entry's. The caller holds the lock of the
    /// config, so no other entry is made meanwhile.
    @discardableResult
    func record(_ entry: Entry) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = self.formatter
        let newest = entries(of: entry.target, file: entry.file).first.map { String($0.name.prefix(Self.stampLength)) }
        var time = entry.time
        if let newest, formatter.string(from: time) <= newest, let after = formatter.date(from: newest) { time = after.addingTimeInterval(0.001) }
        let name = "\(formatter.string(from: time))-\(entry.target.rawValue)-\(UUID().uuidString.prefix(8).lowercased()).json"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try AtomicFile.write(try encoder.encode(entry), to: directory.appendingPathComponent(name), mode: 0o600)
        return name
    }

    /// Forgets the entries beyond the newest fifty of a file, and those past `maxBytes` of text (the newest entry always stays). After the write, not before: an edit that failed
    /// must not cost the oldest entry.
    func prune(of target: ConfigTarget, file: String) {
        var kept = 0
        for (index, old) in entries(of: target, file: file).enumerated() {
            kept += old.before.utf8.count
            if index >= Self.keep || (index > 0 && kept > Self.maxBytes) { remove(old) }
        }
    }

    func remove(_ entry: Entry) {
        remove(named: entry.name)
    }

    func remove(named name: String) {
        guard !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}
