import Foundation

/// A light reading of a TOML text's structure, for what the TOML library cannot say: on which line each table and key is,
/// what a key's value looks like as written, and which array or inline table was never closed. The library reports only
/// where it gave up, which for an array that was not closed is the end of the file or the next statement.
///
/// It reads no values and decides nothing about what a config means: it is asked about a text the library has already
/// read (to find a line or a value) or refused (to explain why). Where it cannot follow the text it stops, and what it
/// has found up to there stays. Paths are spelled as `ConfigDiagnostic` spells them: segments with control characters
/// escaped, joined by dots, and the position of an entry of `[[a]]` (counted from 1) as a segment of its own: `a.2.id`.
struct TOMLOutline {
    /// A mistake in the structure: an array, inline table or table header that is not closed, or two items without a comma.
    struct Problem: Equatable {
        var line: Int
        var message: String
    }

    private(set) var lines: [String: Int] = [:]
    /// The text of each key's value as it was written (a range of the text's UTF-8 bytes).
    private(set) var valueRanges: [String: Range<Int>] = [:]
    private(set) var problem: Problem?
    /// How many lines the text has: a final line break ends the last line, it does not start another.
    let lineCount: Int

    private let bytes: [UInt8]
    private let lineStarts: [Int]
    /// How many `[[a.b]]` entries have been seen, by path (segments joined with a character no key holds).
    private var entryCounts: [String: Int] = [:]
    private static let separator = "\u{1F}"

    init(_ text: String) {
        bytes = Array(text.utf8)
        var starts = [0]
        for (offset, byte) in bytes.enumerated() where byte == UInt8(ascii: "\n") { starts.append(offset + 1) }
        lineStarts = starts
        lineCount = bytes.isEmpty ? 1 : (bytes.last == UInt8(ascii: "\n") ? starts.count - 1 : starts.count)
        scan()
    }

    /// The line of this path, or of the nearest table or key above it that has one.
    func line(of path: String) -> Int? {
        var segments = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        while !segments.isEmpty {
            if let found = lines[segments.joined(separator: ".")] { return found }
            segments.removeLast()
        }
        return nil
    }

    /// The value of the key at this path as written, or `nil` when the key is not found or its value could not be followed.
    func rawValue(of path: String) -> String? {
        valueRanges[path].map { String(decoding: bytes[$0], as: UTF8.self) }
    }

    /// The same line, kept inside the text: the library counts the line break that is added after the last line.
    func clamped(_ line: Int) -> Int { min(max(line, 1), lineCount) }

    // MARK: Reading

    private func line(at offset: Int) -> Int {
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lineStarts[middle] <= offset { low = middle } else { high = middle - 1 }
        }
        return low + 1
    }

    /// A key's path. A dot that is inside a quoted key (`"general.terminal" = ...`) is not a separator, and the key is not `general.terminal`: it is written so that no path of the
    /// schema is spelled by it.
    private static func dotted(_ segments: [String]) -> String {
        segments.map { $0.withControlCharactersEscaped.replacingOccurrences(of: ".", with: "%2E") }.joined(separator: ".")
    }

    private mutating func record(_ segments: [String], at offset: Int, value: Range<Int>? = nil) {
        let path = Self.dotted(segments)
        if lines[path] == nil { lines[path] = line(at: offset) }
        if let value, valueRanges[path] == nil { valueRanges[path] = value }
    }

    private mutating func fail(line: Int, _ message: String) {
        if problem == nil { problem = Problem(line: line, message: message) }
    }

    private func isBareKeyByte(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
            || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-")
    }

    private func isValueEnd(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: ","), UInt8(ascii: "]"), UInt8(ascii: "}"), UInt8(ascii: "#"), UInt8(ascii: "\n"), UInt8(ascii: "\r"): return true
        default: return false
        }
    }

    private func isLineEnd(_ index: Int) -> Bool {
        index >= bytes.count || bytes[index] == UInt8(ascii: "\n") || bytes[index] == UInt8(ascii: "\r") || bytes[index] == UInt8(ascii: "#")
    }

    private func skipSpaces(_ start: Int) -> Int {
        var index = start
        while index < bytes.count, bytes[index] == UInt8(ascii: " ") || bytes[index] == UInt8(ascii: "\t") { index += 1 }
        return index
    }

    /// Spaces, line breaks and comments.
    private func skipTrivia(_ start: Int) -> Int {
        var index = start
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\r"), UInt8(ascii: "\n"): index += 1
            case UInt8(ascii: "#"):
                while index < bytes.count, bytes[index] != UInt8(ascii: "\n") { index += 1 }
            default: return index
            }
        }
        return index
    }

    private mutating func scan() {
        var table: [String] = []
        var index = 0
        while true {
            index = skipTrivia(index)
            guard index < bytes.count else { return }
            if bytes[index] == UInt8(ascii: "[") {
                let isArray = index + 1 < bytes.count && bytes[index + 1] == UInt8(ascii: "[")
                let opener = index
                guard let key = readKey(at: index + (isArray ? 2 : 1)) else { return }
                let closer = isArray ? "]]" : "]"
                var next = skipSpaces(key.end)
                guard next < bytes.count, bytes[next] == UInt8(ascii: "]") else {
                    if isLineEnd(next) { fail(line: line(at: opener), "table header not closed: missing `\(closer)`") }
                    return
                }
                next += 1
                if isArray {
                    guard next < bytes.count, bytes[next] == UInt8(ascii: "]") else { return }
                    next += 1
                    let counted = key.segments.joined(separator: Self.separator)
                    entryCounts[counted, default: 0] += 1
                    // A new entry starts its own arrays of tables afresh.
                    for known in entryCounts.keys where known.hasPrefix(counted + Self.separator) { entryCounts[known] = nil }
                }
                table = resolved(key.segments, includingLast: isArray)
                // A problem with the array as a whole (`[[agent]]` where a table was expected) is at its first entry.
                if isArray { record(Array(table.dropLast()), at: opener) }
                record(table, at: opener)
                index = skipSpaces(next)
                guard isLineEnd(index) else { return }
            } else {
                let start = index
                guard let key = readKey(at: index) else { return }
                var next = skipSpaces(key.end)
                guard next < bytes.count, bytes[next] == UInt8(ascii: "=") else { return }
                next = skipSpaces(next + 1)
                guard let end = scanValue(next, depth: 0, path: table + key.segments) else { return }
                record(table + key.segments, at: start, value: next..<end)
                index = skipSpaces(end)
                guard isLineEnd(index) else { return }
            }
        }
    }

    /// A table's path with the position of the `[[...]]` entry that each of its parts is in, counted so far.
    private func resolved(_ raw: [String], includingLast: Bool) -> [String] {
        var path: [String] = []
        for (position, segment) in raw.enumerated() {
            path.append(segment)
            if position == raw.count - 1 && !includingLast { break }
            if let count = entryCounts[raw[0...position].joined(separator: Self.separator)] { path.append(String(count)) }
        }
        return path
    }

    /// A key, which may be dotted, bare or quoted: its segments (quotes taken off, escapes read) and where it ends.
    private func readKey(at start: Int) -> (segments: [String], end: Int)? {
        var segments: [String] = []
        var index = start
        while true {
            index = skipSpaces(index)
            guard index < bytes.count else { return nil }
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                guard !TOMLScan.hasTriple(bytes, byte, at: index) else { return nil }
                let string = TOMLScan.skipString(bytes, at: index)
                guard string.terminated else { return nil }
                let inner = Array(bytes[(index + 1)..<(string.end - 1)])
                segments.append(byte == UInt8(ascii: "'") ? String(decoding: inner, as: UTF8.self) : Self.unescaped(inner))
                index = string.end
            } else if isBareKeyByte(byte) {
                var end = index
                while end < bytes.count, isBareKeyByte(bytes[end]) { end += 1 }
                segments.append(String(decoding: bytes[index..<end], as: UTF8.self))
                index = end
            } else {
                return nil
            }
            let afterKey = index
            index = skipSpaces(index)
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") { index += 1; continue }
            return (segments, afterKey)
        }
    }

    /// The text of a basic string: its escapes read. One that is not valid is kept as it is; the library refuses it.
    private static func unescaped(_ inner: [UInt8]) -> String {
        var scalars = String.UnicodeScalarView()
        var text = String(decoding: inner, as: UTF8.self).unicodeScalars.makeIterator()
        func hex(_ count: Int) -> Unicode.Scalar? {
            var value: UInt32 = 0
            for _ in 0..<count {
                guard let digit = text.next(), let number = UInt32(String(digit), radix: 16) else { return nil }
                value = value * 16 + number
            }
            return Unicode.Scalar(value)
        }
        while let scalar = text.next() {
            guard scalar == "\\" else { scalars.append(scalar); continue }
            guard let escape = text.next() else { scalars.append(scalar); break }
            switch escape {
            case "b": scalars.append("\u{08}")
            case "t": scalars.append("\t")
            case "n": scalars.append("\n")
            case "f": scalars.append("\u{0C}")
            case "r": scalars.append("\r")
            case "e": scalars.append("\u{1B}")
            case "\"": scalars.append("\"")
            case "\\": scalars.append("\\")
            case "x": if let value = hex(2) { scalars.append(value) }
            case "u": if let value = hex(4) { scalars.append(value) }
            case "U": if let value = hex(8) { scalars.append(value) }
            default: scalars.append(scalar); scalars.append(escape)
            }
        }
        return String(scalars)
    }

    /// One value, which may be an array or an inline table of more values: where it ends. `nil` when it cannot be followed
    /// (the library says why), or when it is not closed, which is recorded as the problem. `path` is where the value is when it is
    /// the value of a key, so that the keys of an inline table are known as the keys of a table (`general = { terminal = "x" }` has
    /// `general.terminal`); a table inside an array has none.
    private mutating func scanValue(_ start: Int, depth: Int, inside noun: String? = nil, path: [String]? = nil) -> Int? {
        guard start < bytes.count, depth <= ConfigParser.maxNesting else { return nil }
        switch bytes[start] {
        case UInt8(ascii: "\""), UInt8(ascii: "'"):
            let string = TOMLScan.skipString(bytes, at: start)
            return string.terminated ? string.end : nil
        case UInt8(ascii: "["):
            return scanContainer(start, depth: depth, close: UInt8(ascii: "]"), path: nil)
        case UInt8(ascii: "{"):
            return scanContainer(start, depth: depth, close: UInt8(ascii: "}"), path: path)
        default:
            // A number, a date, a boolean, or text that is none of those: up to what ends a value.
            var end = start
            while end < bytes.count, !isValueEnd(bytes[end]) { end += 1 }
            while end > start, bytes[end - 1] == UInt8(ascii: " ") || bytes[end - 1] == UInt8(ascii: "\t") { end -= 1 }
            // Two words, or two numbers, side by side in an array or an inline table are two items that lack a comma. (A
            // date and a time are written with a space between them.)
            if let noun, end > start, bytes[start..<end].contains(UInt8(ascii: " ")),
               String(decoding: bytes[start..<end], as: UTF8.self).firstMatch(of: #/^\d{4}-\d{2}-\d{2} /#) == nil {
                fail(line: line(at: start), "missing `,` between the items of this \(noun)")
                return nil
            }
            return end > start ? end : nil
        }
    }

    /// An array (`close` is `]`) or an inline table (`}`): items separated by commas, with line breaks and comments allowed
    /// between them. The mistakes found here are the ones the library reports as an "internal error" at some other place.
    private mutating func scanContainer(_ start: Int, depth: Int, close: UInt8, path: [String]?) -> Int? {
        let isArray = close == UInt8(ascii: "]")
        let noun = isArray ? "array" : "inline table"
        let closer = isArray ? "]" : "}"
        let openLine = line(at: start)
        var index = start + 1
        var wantsItem = true
        var lastItemEnd = start
        while true {
            index = skipTrivia(index)
            guard index < bytes.count else {
                fail(line: openLine, "\(noun) not closed: missing `\(closer)`")
                return nil
            }
            let byte = bytes[index]
            if byte == close { return index + 1 }
            if byte == UInt8(ascii: ",") {
                guard !wantsItem else { return nil }
                wantsItem = true
                index += 1
                continue
            }
            if !wantsItem {
                // Something that is not a comma or the closing bracket follows an item.
                let here = line(at: index)
                if here == line(at: lastItemEnd) {
                    fail(line: here, "missing `,` between the items of this \(noun)")
                } else if startsStatement(at: index) {
                    fail(line: openLine, "\(noun) not closed: missing `\(closer)` (line \(here) starts something else)")
                } else {
                    fail(line: line(at: lastItemEnd), "missing `,` after this item of the \(noun)")
                }
                return nil
            }
            var entry: (segments: [String], start: Int)?
            if !isArray {
                // `key = value`
                let keyStart = index
                guard let key = readKey(at: index) else { return nil }
                let equals = skipSpaces(key.end)
                guard equals < bytes.count, bytes[equals] == UInt8(ascii: "=") else { return nil }
                index = skipSpaces(equals + 1)
                entry = (key.segments, keyStart)
            }
            let valueStart = index
            let entryPath = path.flatMap { path in entry.map { path + $0.segments } }
            guard let end = scanValue(index, depth: depth + 1, inside: noun, path: entryPath) else { return nil }
            if let entryPath, let entry { record(entryPath, at: entry.start, value: valueStart..<end) }
            lastItemEnd = end - 1
            wantsItem = false
            index = end
        }
    }

    /// Whether a new statement of the file starts here: a table header such as `[menu]`, or `key =`.
    private func startsStatement(at index: Int) -> Bool {
        if bytes[index] == UInt8(ascii: "[") {
            var end = index
            while end < bytes.count, bytes[end] == UInt8(ascii: "[") { end += 1 }
            while end < bytes.count, isBareKeyByte(bytes[end]) || bytes[end] == UInt8(ascii: ".") || bytes[end] == UInt8(ascii: " ") { end += 1 }
            guard end < bytes.count, bytes[end] == UInt8(ascii: "]") else { return false }
            while end < bytes.count, bytes[end] == UInt8(ascii: "]") { end += 1 }
            return isLineEnd(skipSpaces(end))
        }
        guard let key = readKey(at: index) else { return false }
        let next = skipSpaces(key.end)
        return next < bytes.count && bytes[next] == UInt8(ascii: "=")
    }
}
