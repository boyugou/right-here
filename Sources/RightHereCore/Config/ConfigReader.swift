import Foundation
import TOMLDecoder

struct ConfigReader {
    let table: TOMLTable
    let path: [String]
    let schema: [SchemaNode]
    let sink: ConfigSink

    func string(_ key: String) -> String? {
        guard table.contains(key: key) else { return nil }
        do { return try table.string(forKey: key) } catch {
            let found = found(key, after: error)
            let raw = found == Self.bareText ? sink.rawValue(of: path + [key]) : nil
            sink.error(path + [key], "expected a string, found \(found)",
                       suggestion: raw.map { Hint(text: "write it in quotes: \(TOMLEmitter.quote($0))", replacement: TOMLEmitter.quote($0)) })
            return nil
        }
    }

    func integer(_ key: String) -> Int64? {
        guard table.contains(key: key) else { return nil }
        do { return try table.integer(forKey: key) } catch {
            sink.error(path + [key], "expected an integer, found \(found(key, after: error))")
            return nil
        }
    }

    func boolean(_ key: String) -> Bool? {
        guard table.contains(key: key) else { return nil }
        do { return try table.bool(forKey: key) } catch {
            sink.error(path + [key], "expected a boolean, found \(found(key, after: error))")
            return nil
        }
    }

    func stringArray(_ key: String) -> [String]? {
        guard table.contains(key: key) else { return nil }
        guard let array = try? table.array(forKey: key) else {
            let found = Self.kind(of: key, in: table) ?? Self.bareText
            // A single string where a list was meant: the list of it is the likely fix.
            let raw = found == "a string" ? sink.rawValue(of: path + [key]) : nil
            sink.error(path + [key], "expected an array of strings, found \(found)",
                       suggestion: raw.map { Hint(text: "write it as a list: [\($0)]", replacement: "[\($0)]") })
            return nil
        }
        var items: [String] = []
        for index in 0..<array.count {
            do { items.append(try array.string(atIndex: index)) } catch {
                sink.error(path + [key], "expected an array of strings, found \(Self.kind(ofItem: index, in: array) ?? Self.bareText) as item \(index + 1)")
                return nil
            }
        }
        return items
    }

    private func children(of key: String) -> [SchemaNode] {
        schema.first(where: { $0.key == key })?.children ?? []
    }

    func subtable(_ key: String) -> ConfigReader? {
        guard table.contains(key: key) else { return nil }
        do {
            return ConfigReader(table: try table.table(forKey: key), path: path + [key], schema: children(of: key), sink: sink)
        } catch {
            sink.error(path + [key], "expected a table, found \(Self.kind(of: key, in: table) ?? Self.bareText)")
            return nil
        }
    }

    func tableArray(_ key: String) -> [ConfigReader] {
        guard table.contains(key: key) else { return [] }
        let written = "written [[\((path + [key]).joined(separator: "."))]]"
        guard let array = try? table.array(forKey: key) else {
            sink.error(path + [key], "expected an array of tables, \(written), found \(Self.kind(of: key, in: table) ?? Self.bareText)")
            return []
        }
        let childSchema = children(of: key)
        var readers: [ConfigReader] = []
        for index in 0..<array.count {
            guard let nested = try? array.table(atIndex: index) else {
                sink.error(path + [key], "expected an array of tables, \(written), found \(Self.kind(ofItem: index, in: array) ?? Self.bareText) as item \(index + 1)")
                return []
            }
            readers.append(ConfigReader(table: nested, path: path + [key, String(index + 1)], schema: childSchema, sink: sink))
        }
        return readers
    }

    /// Warn about keys the schema does not know, with the closest valid key as a suggestion, or, when the key is one of another
    /// table, where it belongs.
    func checkKnownKeys(extra: Set<String> = []) {
        let known = schema.map(\.key)
        for key in table.keys.sorted() where !known.contains(key) && !extra.contains(key) {
            let hint = Suggestion.didYouMean(key, in: known) ?? Self.belongs(key, notIn: known)
            sink.warning(path + [key], "unknown key", suggestion: hint)
        }
    }

    func checkAllowed(_ value: String?, key: String, allowed: [String]) -> String? {
        guard let value else { return nil }
        guard allowed.contains(value) else {
            sink.error(path + [key], "\"\(value)\" is not one of " + allowed.joined(separator: ", "),
                       suggestion: Suggestion.didYouMean(value, in: allowed))
            return nil
        }
        return value
    }

    // MARK: What a value is, when it is not what was asked for

    /// What a value is called when no kind of value matches it: it is not a string, a number, a list or a date, so it is
    /// text that was written without its quotes.
    static let bareText = "text without quotes"

    /// What the value of `key` is, in words; `nil` when it is none of the kinds a TOML file has.
    static func kind(of key: String, in table: TOMLTable) -> String? {
        if (try? table.table(forKey: key)) != nil { return "a table" }
        if (try? table.array(forKey: key)) != nil { return "an array" }
        if (try? table.string(forKey: key)) != nil { return "a string" }
        if (try? table.bool(forKey: key)) != nil { return "a boolean" }
        if (try? table.integer(forKey: key)) != nil { return "an integer" }
        if (try? table.float(forKey: key)) != nil { return "a number with a decimal point" }
        if (try? table.offsetDateTime(forKey: key)) != nil || (try? table.localDateTime(forKey: key)) != nil
            || (try? table.localDate(forKey: key)) != nil || (try? table.localTime(forKey: key)) != nil { return "a date or time" }
        return nil
    }

    static func kind(ofItem index: Int, in array: TOMLArray) -> String? {
        if (try? array.table(atIndex: index)) != nil { return "a table" }
        if (try? array.array(atIndex: index)) != nil { return "an array" }
        if (try? array.string(atIndex: index)) != nil { return "a string" }
        if (try? array.bool(atIndex: index)) != nil { return "a boolean" }
        if (try? array.integer(atIndex: index)) != nil { return "an integer" }
        if (try? array.float(atIndex: index)) != nil { return "a number with a decimal point" }
        if (try? array.offsetDateTime(atIndex: index)) != nil || (try? array.localDateTime(atIndex: index)) != nil
            || (try? array.localDate(atIndex: index)) != nil || (try? array.localTime(atIndex: index)) != nil { return "a date or time" }
        return nil
    }

    /// What the value of `key` was, after the library refused to read it as what was asked for. A value of another kind is
    /// named. One that is no kind at all is text without quotes, or, when it was written in quotes, a malformed string, which
    /// the library says how.
    private func found(_ key: String, after error: any Error) -> String {
        if let kind = Self.kind(of: key, in: table) { return kind }
        let said = String(describing: error)
        let written = sink.rawValue(of: path + [key])
        let quoted = written.map { $0.first == "\"" || $0.first == "'" } ?? !(said.contains("Type mismatch") || said.contains("not found in table"))
        guard quoted else { return Self.bareText }
        var reason = said.replacingOccurrences(of: #"^\(Line \d+\) "#, with: "", options: .regularExpression)
        if reason.hasSuffix(".") { reason.removeLast() }
        reason = reason.prefix(1).lowercased() + reason.dropFirst()
        let advice = said.contains("escape") ? "; write \\\\ for a backslash, or use 'single quotes', which have no escapes" : ""
        return "a value that is not valid (\(reason)\(advice))"
    }

    // MARK: Keys that belong elsewhere

    /// "Belongs in [general]" for a key that is not this table's but is a key of another table; the tables are named when
    /// there are two or three, and nothing is said when there are more (`id`), which would be no hint.
    static func belongs(_ key: String, notIn known: [String]) -> Hint? {
        var homes: [String] = []
        func walk(_ nodes: [SchemaNode], name: [String]) {
            for node in nodes {
                // A table of tables is written `[agent.<id>]`, and what is under it is that table's keys.
                let header = name + [node.key] + (node.kind == .tableMap ? ["<id>"] : [])
                if node.children.contains(where: { $0.key == key }), node.children.map(\.key) != known {
                    let text = header.joined(separator: ".")
                    homes.append(node.kind == .tableArray ? "[[\(text)]]" : "[\(text)]")
                }
                walk(node.children, name: header)
            }
        }
        walk(ConfigSchema.root, name: [])
        switch homes.count {
        case 1: return Hint(text: "\"\(key)\" belongs in \(homes[0])", replacement: nil)
        case 2, 3: return Hint(text: "\"\(key)\" is a key of \(homes.dropLast().joined(separator: ", ")) and \(homes[homes.count - 1])", replacement: nil)
        default: return nil
        }
    }
}
