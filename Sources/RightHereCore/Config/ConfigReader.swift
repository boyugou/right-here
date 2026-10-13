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
            sink.error(path + [key], "expected a string")
            return nil
        }
    }

    func integer(_ key: String) -> Int64? {
        guard table.contains(key: key) else { return nil }
        do { return try table.integer(forKey: key) } catch {
            sink.error(path + [key], "expected an integer")
            return nil
        }
    }

    func stringArray(_ key: String) -> [String]? {
        guard table.contains(key: key) else { return nil }
        do {
            let array = try table.array(forKey: key)
            return try (0..<array.count).map { try array.string(atIndex: $0) }
        } catch {
            sink.error(path + [key], "expected an array of strings")
            return nil
        }
    }

    private func children(of key: String) -> [SchemaNode] {
        schema.first(where: { $0.key == key })?.children ?? []
    }

    func subtable(_ key: String) -> ConfigReader? {
        guard table.contains(key: key) else { return nil }
        do {
            return ConfigReader(table: try table.table(forKey: key), path: path + [key], schema: children(of: key), sink: sink)
        } catch {
            sink.error(path + [key], "expected a table")
            return nil
        }
    }

    func tableArray(_ key: String) -> [ConfigReader] {
        guard table.contains(key: key) else { return [] }
        do {
            let array = try table.array(forKey: key)
            let childSchema = children(of: key)
            return try (0..<array.count).map { index in
                ConfigReader(table: try array.table(atIndex: index), path: path + [key, String(index + 1)], schema: childSchema, sink: sink)
            }
        } catch {
            sink.error(path + [key], "expected an array of tables, written [[\((path + [key]).joined(separator: "."))]]")
            return []
        }
    }

    /// Warn about keys the schema does not know, with the closest valid key as a suggestion.
    func checkKnownKeys(extra: Set<String> = []) {
        let known = schema.map(\.key)
        for key in table.keys.sorted() where !known.contains(key) && !extra.contains(key) {
            sink.warning(path + [key], "unknown key", suggestion: Suggestion.didYouMean(key, in: known))
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
}
