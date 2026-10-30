import Foundation
import TOMLDecoder

/// A TOML document as plain values, so two documents can be merged and written back as text. `TOMLTable` is read-only,
/// and the config builder reads a `TOMLTable`, so a merge goes through text: read both files into this tree, merge,
/// write it out (`TOMLEmitter`), and build once from the result. That keeps every schema check and cross-reference
/// check (an overlay entry naming an app only the base defines) working on the merged settings.
enum TOMLValue: Equatable {
    case string(String)
    case integer(Int64)
    case float(Double)
    case bool(Bool)
    /// A date or time, kept as its TOML text. No setting uses one; it is carried so that the builder's own
    /// "expected a string" message stays true.
    case datetime(String)
    case array([TOMLValue])
    case table([String: TOMLValue])
    /// A value this reader cannot type (text without quotes, a string with a bad escape), kept as it was written and written
    /// back the same, so that the builder reports it as it would have in the file alone, and the rest of the file applies.
    case untyped(String)

    var tableValue: [String: TOMLValue]? {
        if case .table(let table) = self { return table }
        return nil
    }

    var arrayValue: [TOMLValue]? {
        if case .array(let array) = self { return array }
        return nil
    }

    /// Every element is a table (and there is at least one): written `[[name]]`.
    var isTableArray: Bool {
        guard case .array(let items) = self, !items.isEmpty else { return false }
        return items.allSatisfy { $0.tableValue != nil }
    }

    /// Reads a whole table. A value of a kind this reader does not know is kept as it was written, when `written` can say
    /// how (it is given the path of the key); `nil` when it cannot.
    static func read(_ table: TOMLTable, path: [String] = [], written: ([String]) -> String? = { _ in nil }) -> [String: TOMLValue]? {
        var result: [String: TOMLValue] = [:]
        for key in table.keys {
            let here = path + [key]
            if let value = read(table, key: key, path: here, written: written) {
                result[key] = value
            } else if let raw = written(here) {
                result[key] = .untyped(raw)
            } else {
                return nil
            }
        }
        return result
    }

    private static func read(_ table: TOMLTable, key: String, path: [String], written: ([String]) -> String?) -> TOMLValue? {
        if let nested = try? table.table(forKey: key) { return read(nested, path: path, written: written).map(TOMLValue.table) }
        if let array = try? table.array(forKey: key) { return read(array, path: path, written: written).map(TOMLValue.array) }
        if let value = try? table.string(forKey: key) { return .string(value) }
        if let value = try? table.bool(forKey: key) { return .bool(value) }
        if let value = try? table.integer(forKey: key) { return .integer(value) }
        if let value = try? table.float(forKey: key) { return .float(value) }
        if let value = try? table.offsetDateTime(forKey: key) { return .datetime(value.description) }
        if let value = try? table.localDateTime(forKey: key) { return .datetime(value.description) }
        if let value = try? table.localDate(forKey: key) { return .datetime(value.description) }
        if let value = try? table.localTime(forKey: key) { return .datetime(value.description) }
        return nil
    }

    private static func read(_ array: TOMLArray, path: [String], written: ([String]) -> String?) -> [TOMLValue]? {
        var items: [TOMLValue] = []
        for index in 0..<array.count {
            let item: TOMLValue?
            if let nested = try? array.table(atIndex: index) { item = read(nested, path: path + [String(index + 1)], written: written).map(TOMLValue.table) }
            else if let nested = try? array.array(atIndex: index) { item = read(nested, path: path + [String(index + 1)], written: written).map(TOMLValue.array) }
            else if let value = try? array.string(atIndex: index) { item = .string(value) }
            else if let value = try? array.bool(atIndex: index) { item = .bool(value) }
            else if let value = try? array.integer(atIndex: index) { item = .integer(value) }
            else if let value = try? array.float(atIndex: index) { item = .float(value) }
            else if let value = try? array.offsetDateTime(atIndex: index) { item = .datetime(value.description) }
            else if let value = try? array.localDateTime(atIndex: index) { item = .datetime(value.description) }
            else if let value = try? array.localDate(atIndex: index) { item = .datetime(value.description) }
            else if let value = try? array.localTime(atIndex: index) { item = .datetime(value.description) }
            else { item = nil }
            guard let item else { return nil }
            items.append(item)
        }
        return items
    }
}

/// Writes a `TOMLValue` table as TOML text. Keys are always quoted and sorted, so the output does not depend on
/// the order the tree was built in; arrays of tables keep their order, which the builder's indices rely on.
public enum TOMLEmitter {
    static func emit(_ root: [String: TOMLValue]) -> String {
        var out = ""
        emit(table: root, path: [], into: &out)
        return out
    }

    private static func emit(table: [String: TOMLValue], path: [String], into out: inout String) {
        let keys = table.keys.sorted()
        for key in keys {
            guard let value = table[key], value.tableValue == nil, !value.isTableArray else { continue }
            out += quote(key) + " = " + inline(value) + "\n"
        }
        for key in keys {
            guard let value = table[key] else { continue }
            let child = path + [key]
            if let nested = value.tableValue {
                out += "\n[" + header(child) + "]\n"
                emit(table: nested, path: child, into: &out)
            } else if value.isTableArray, let items = value.arrayValue {
                for item in items {
                    guard let nested = item.tableValue else { continue }
                    out += "\n[[" + header(child) + "]]\n"
                    emit(table: nested, path: child, into: &out)
                }
            }
        }
    }

    private static func header(_ path: [String]) -> String {
        path.map(quote).joined(separator: ".")
    }

    private static func inline(_ value: TOMLValue) -> String {
        switch value {
        case .string(let text): return quote(text)
        case .integer(let number): return String(number)
        case .bool(let flag): return flag ? "true" : "false"
        case .datetime(let text), .untyped(let text): return text
        case .float(let number):
            if number.isNaN { return "nan" }
            if number.isInfinite { return number < 0 ? "-inf" : "inf" }
            return String(number)
        case .array(let items): return "[" + items.map(inline).joined(separator: ", ") + "]"
        case .table(let table):
            return "{ " + table.keys.sorted().compactMap { key in table[key].map { quote(key) + " = " + inline($0) } }.joined(separator: ", ") + " }"
        }
    }

    public static func quote(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    let hex = String(scalar.value, radix: 16, uppercase: true)
                    result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}
