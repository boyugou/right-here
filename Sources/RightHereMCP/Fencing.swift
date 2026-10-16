import Foundation
import RightHereCore

extension JSONValue {
    /// The same JSON with every string under one of `keys` fenced as a name (`Fence.wrap`), at any depth. The text of a tool
    /// result is made of it; the structured data next to it stays as it is. An object whose `kind` is one of `kindsNamedByTheConfig`
    /// has its `value` fenced as well: the icon of a kind of file is named by the extension a template gave, which is free text.
    func fencing(_ keys: Set<String>, kindsNamedByTheConfig: Set<String> = []) -> JSONValue {
        switch self {
        case .object(let object):
            let valueIsNamed = object["kind"]?.stringValue.map(kindsNamedByTheConfig.contains) ?? false
            var fenced: [String: JSONValue] = [:]
            for (key, value) in object {
                if keys.contains(key) || (valueIsNamed && key == "value"), case .string(let text) = value {
                    fenced[key] = .string(Fence.wrap(text))
                } else {
                    fenced[key] = value.fencing(keys, kindsNamedByTheConfig: kindsNamedByTheConfig)
                }
            }
            return .object(fenced)
        case .array(let items):
            return .array(items.map { $0.fencing(keys, kindsNamedByTheConfig: kindsNamedByTheConfig) })
        default:
            return self
        }
    }
}
