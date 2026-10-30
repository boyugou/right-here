import Foundation

/// Checks tool arguments against the small subset of JSON Schema the tools declare (object, properties,
/// required, additionalProperties: false, string / integer / boolean / array of string, enum, minimum, maxLength, maxItems). The model is told
/// the schema, but nothing makes it follow it: without this a `dry_run` given as the string "true" is
/// not `true`, and the action would really run.
enum ArgumentValidator {
    /// The first problem found, worded for the model so it can correct the call; `nil` when the arguments fit.
    static func problem(in arguments: JSONValue, schema: JSONValue) -> String? {
        guard case .object(let given) = arguments else { return "The arguments must be a JSON object." }
        let properties: [String: JSONValue]
        if case .object(let declared)? = schema["properties"] { properties = declared } else { properties = [:] }

        for key in given.keys.sorted() where properties[key] == nil {
            let known = properties.keys.sorted().joined(separator: ", ")
            return "Unknown argument \"\(key)\"." + (known.isEmpty ? " This tool takes no arguments." : " Known arguments: \(known).")
        }
        if case .array(let required)? = schema["required"] {
            for name in required.compactMap(\.stringValue) where given[name] == nil {
                return "The argument \"\(name)\" is required."
            }
        }
        for (key, value) in given.sorted(by: { $0.key < $1.key }) {
            if let problem = self.problem(for: value, named: key, schema: properties[key] ?? .null) { return problem }
        }
        return nil
    }

    private static func problem(for value: JSONValue, named name: String, schema: JSONValue) -> String? {
        switch schema["type"]?.stringValue {
        case "string":
            guard case .string(let text) = value else { return "\"\(name)\" must be a string, not \(describe(value))." }
            if case .array(let allowed)? = schema["enum"], !allowed.contains(.string(text)) {
                return "\"\(name)\" must be one of: " + allowed.compactMap(\.stringValue).joined(separator: ", ") + "."
            }
            if let longest = schema["maxLength"]?.intValue, text.unicodeScalars.count > longest {
                return "\"\(name)\" is too long (at most \(longest) characters)."
            }
        case "integer":
            guard case .number(let number) = value, number == number.rounded(), abs(number) < 1e15 else { return "\"\(name)\" must be a whole number, not \(describe(value))." }
            if let least = schema["minimum"]?.intValue, Int(number) < least { return "\"\(name)\" must be at least \(least)." }
        case "boolean":
            guard case .bool = value else { return "\"\(name)\" must be true or false (a JSON boolean), not \(describe(value))." }
        case "array":
            guard case .array(let items) = value else { return "\"\(name)\" must be an array, not \(describe(value))." }
            if let most = schema["maxItems"]?.intValue, items.count > most {
                return "\"\(name)\" has \(items.count) entries; at most \(most) are accepted. Split the work into several calls."
            }
            if schema["items"]?["type"]?.stringValue == "string" {
                if items.contains(where: { $0.stringValue == nil }) { return "Every entry of \"\(name)\" must be a string." }
                if let longest = schema["items"]?["maxLength"]?.intValue,
                   items.contains(where: { ($0.stringValue ?? "").unicodeScalars.count > longest }) {
                    return "An entry of \"\(name)\" is too long (at most \(longest) characters)."
                }
            }
        default:
            break
        }
        return nil
    }

    private static func describe(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let flag): return "the boolean \(flag)"
        case .number(let number): return "the number \(number)"
        case .string(let text): return "the string \"\(text.prefix(40))\""
        case .array: return "an array"
        case .object: return "an object"
        }
    }
}
