import Foundation
import TOMLDecoder

/// Persistent state kept in `state.toml` next to the config (pins, recent folders).
public struct StateStore: Sendable, Equatable, Codable {
    public var pins: [String]
    public var recents: [String]

    public static let maxRecents = 20

    public init(pins: [String] = [], recents: [String] = []) {
        self.pins = pins
        self.recents = recents
    }

    public enum ParseError: Error, LocalizedError, Equatable {
        case tooDeep
        case unknownKey(String)
        case invalidDocument(String)

        public var errorDescription: String? {
            switch self {
            case .tooDeep: "Saved folders are nested too deeply."
            case .unknownKey(let key): "Unknown saved-folder field: \(key.withControlCharactersEscaped)."
            case .invalidDocument(let reason): reason
            }
        }
    }

    public static func parse(_ text: String) throws -> StateStore {
        guard !NestingDepth.tomlExceeds(text, limit: 8) else { throw ParseError.tooDeep }
        do {
            let table = try TOMLTable(source: text + "\n")
            if let unknown = table.keys.sorted().first(where: { !["pins", "recents"].contains($0) }) {
                throw ParseError.unknownKey(unknown)
            }
            return try StateStore(pins: folders(in: table, key: "pins"),
                                  recents: Array(folders(in: table, key: "recents").prefix(maxRecents)))
        } catch let error as TOMLError {
            // TOMLError describes the line and cause, but NSError bridging otherwise reduces it to "error 1".
            let explained = TOMLSyntax.explain(error.description, outline: TOMLOutline(text))
            throw ParseError.invalidDocument((explained.line.map { "Line \($0): " } ?? "") + explained.message + ".")
        }
    }

    /// A pin or a recent folder is an absolute path. A relative one (the file is meant to be written by `rh`, but it is plain text) would name a
    /// different folder for every program that reads it, whatever its working directory is, so it is dropped.
    private static func absolute(_ path: String) -> String? {
        path.hasPrefix("/") ? (path as NSString).standardizingPath : nil
    }

    private static func folders(in table: TOMLTable, key: String) throws -> [String] {
        guard table.contains(key: key) else { return [] }
        let array = try table.array(forKey: key)
        var folders: [String] = []
        for index in 0..<array.count {
            let text = try array.string(atIndex: index)
            if let path = absolute(text), !folders.contains(path) {
                folders.append(path)
            }
        }
        return folders
    }

    public func render() -> String {
        var text = "# Right Here local state (pins and recent folders)\n\n"
        text += "pins = [\n"
        for pin in pins {
            text += "  " + TOMLEmitter.quote(pin) + ",\n"
        }
        text += "]\n\n"
        text += "recents = [\n"
        for recent in recents {
            text += "  " + TOMLEmitter.quote(recent) + ",\n"
        }
        text += "]\n"
        return text
    }

    @discardableResult
    public mutating func pin(_ path: String) -> Bool {
        guard let clean = Self.absolute(path), !pins.contains(clean) else { return false }
        pins.append(clean)
        return true
    }

    @discardableResult
    public mutating func unpin(_ path: String) -> Bool {
        guard let clean = Self.absolute(path), let index = pins.firstIndex(of: clean) else { return false }
        pins.remove(at: index)
        return true
    }

    public mutating func recordRecent(_ path: String) {
        guard let clean = Self.absolute(path) else { return }
        recents.removeAll { $0 == clean }
        recents.insert(clean, at: 0)
        if recents.count > Self.maxRecents {
            recents = Array(recents.prefix(Self.maxRecents))
        }
    }

    public mutating func clearRecents() {
        recents.removeAll()
    }
}
