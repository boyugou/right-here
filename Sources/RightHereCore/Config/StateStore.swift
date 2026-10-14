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

    public static func parse(_ text: String) -> StateStore {
        guard !NestingDepth.tomlExceeds(text, limit: 8),
              let table = try? TOMLTable(source: text + "\n") else {
            return StateStore()
        }
        var pins: [String] = []
        if let array = try? table.array(forKey: "pins") {
            for i in 0..<array.count {
                if let str = try? array.string(atIndex: i), !str.isEmpty, !pins.contains(str) {
                    pins.append(str)
                }
            }
        }
        var recents: [String] = []
        if let array = try? table.array(forKey: "recents") {
            for i in 0..<array.count {
                if let str = try? array.string(atIndex: i), !str.isEmpty, !recents.contains(str) {
                    recents.append(str)
                }
            }
        }
        return StateStore(pins: pins, recents: recents)
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
        let clean = (path as NSString).standardizingPath
        guard !pins.contains(clean) else { return false }
        pins.append(clean)
        return true
    }

    @discardableResult
    public mutating func unpin(_ path: String) -> Bool {
        let clean = (path as NSString).standardizingPath
        if let idx = pins.firstIndex(of: clean) {
            pins.remove(at: idx)
            return true
        }
        return false
    }

    public mutating func recordRecent(_ path: String) {
        let clean = (path as NSString).standardizingPath
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
