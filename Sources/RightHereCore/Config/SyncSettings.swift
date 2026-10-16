import Foundation
import TOMLDecoder

/// What `rh config sync` remembers between runs, kept in `sync.toml` next to the config: the folder, and the hash of
/// the content both sides had at the last successful sync. It is state, not a setting, so the config file never holds it.
public struct SyncSettings: Sendable, Equatable {
    public var folder: String
    /// SHA-256 (hex) of the config content at the last sync.
    public var lastSynced: String?

    public init(folder: String, lastSynced: String? = nil) {
        self.folder = folder
        self.lastSynced = lastSynced
    }

    /// `nil` when the text is not a `sync.toml` this build wrote (no folder, wrong types, a syntax error).
    public static func parse(_ text: String) -> SyncSettings? {
        guard !NestingDepth.tomlExceeds(text, limit: 8), let table = try? TOMLTable(source: text + "\n"),
              let folder = try? table.string(forKey: "folder"), !folder.isEmpty else { return nil }
        var last: String?
        if table.contains(key: "last_synced_sha256") {
            guard let value = try? table.string(forKey: "last_synced_sha256"), isHash(value) else { return nil }
            last = value
        }
        return SyncSettings(folder: folder, lastSynced: last)
    }

    public func render() -> String {
        var text = "# Written by `rh config sync`; `rh config sync disable` forgets it. The config itself never holds this.\n"
        text += "folder = " + TOMLEmitter.quote(folder) + "\n"
        if let lastSynced { text += "last_synced_sha256 = " + TOMLEmitter.quote(lastSynced) + "\n" }
        return text
    }

    static func isHash(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
    }
}
