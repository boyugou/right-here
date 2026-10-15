import Foundation
import RightHereCore

extension Fence {
    /// A title or a name the config gave, as it goes in the text of a tool result: with control characters and the controls
    /// that reorder text shown as escapes, and marked as data. The config can come through the sync folder, so what it calls
    /// an app, an agent or a menu entry is whatever somebody wrote, and the agent reading this must be able to tell it from
    /// the tool's own words.
    static func name(_ text: String) -> String {
        text.isEmpty ? text : wrap(text.withControlCharactersEscaped)
    }
}

extension JSONValue {
    /// The same JSON with every string under one of `keys` fenced as a name (`Fence.name`), at any depth. The text of a tool
    /// result is made of it; the structured data next to it stays as it is.
    func fencing(_ keys: Set<String>) -> JSONValue {
        switch self {
        case .object(let object):
            var fenced: [String: JSONValue] = [:]
            for (key, value) in object {
                if keys.contains(key), case .string(let text) = value {
                    fenced[key] = .string(Fence.name(text))
                } else {
                    fenced[key] = value.fencing(keys)
                }
            }
            return .object(fenced)
        case .array(let items):
            return .array(items.map { $0.fencing(keys) })
        default:
            return self
        }
    }
}
