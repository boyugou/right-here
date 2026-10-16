import Foundation
import RightHereCore

extension JSONValue {
    /// The same JSON with every string under one of `keys` fenced as a name (`Fence.wrap`), at any depth. The text of a tool
    /// result is made of it; the structured data next to it stays as it is.
    func fencing(_ keys: Set<String>) -> JSONValue {
        switch self {
        case .object(let object):
            var fenced: [String: JSONValue] = [:]
            for (key, value) in object {
                if keys.contains(key), case .string(let text) = value {
                    fenced[key] = .string(Fence.wrap(text))
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
