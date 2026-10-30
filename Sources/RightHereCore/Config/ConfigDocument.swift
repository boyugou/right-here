import Foundation

/// A config file's text, and the small edits that can be made to it without touching the rest of it (ADR 0026).
///
/// Every edit is the smallest change that does what was asked: the bytes outside the edited value, key or entry are the ones that were there, so a person's
/// comments, order and layout stay theirs. An edit refuses a text that already has errors (it would be editing something it cannot read), a key that is not in the
/// schema, a value of the wrong kind, and any change after which the config has an error it did not have. Nothing here reads or writes a file.
///
/// Paths are spelled as `ConfigDiagnostic` spells them: `general.terminal`, `menu.items`, `agent.claude.args`, and the position of an entry of `[[a]]`, counted
/// from 1, as a segment of its own: `preset.2.title`. A position in an array of strings, or of entries, is counted from 1 too.
public struct ConfigDocument: Sendable, Equatable {
    /// What makes a text acceptable: the errors it has. A file is read on its own (`standalone`), which is what every other Mac reads; the per-machine overlay is read laid
    /// over the shared file, since it may name what only that file defines.
    public struct Validation: Sendable {
        /// Everything the config says about a text, warnings included, with the line each is on.
        public let problems: @Sendable (String) -> [ConfigDiagnostic]

        public init(problems: @escaping @Sendable (String) -> [ConfigDiagnostic]) {
            self.problems = problems
        }

        /// The errors as sentences: what an edit is refused for.
        var errors: @Sendable (String) -> [String] {
            let problems = problems
            return { ConfigDocument.sentences(problems($0)) }
        }

        public static let standalone = Validation { sized($0, ConfigParser.parse($0).diagnostics) }

        /// A text past the size a config may have is an error of its own, whatever else the text says: nothing that reads the config reads it.
        static func sized(_ text: String, _ diagnostics: [ConfigDiagnostic]) -> [ConfigDiagnostic] {
            let bytes = text.utf8.count
            guard bytes > ConfigParser.maxBytes else { return diagnostics }
            return [ConfigDiagnostic(severity: .error, path: "", message: EditError.tooLarge(bytes: bytes).errorDescription ?? "", line: 1)] + diagnostics
        }

        /// What comes from the overlay when `text` is laid over `base`: the shared file's own problems are not the overlay's to fix.
        public static func overlay(over base: String?) -> Validation {
            Validation { text in
                sized(text, ConfigLayers.load(base: base.map(ConfigSource.text) ?? .absent, local: .text(text)).diagnostics.filter { $0.file != nil })
            }
        }
    }

    public enum Value: Sendable, Equatable, Codable {
        case string(String)
        case integer(Int)
        case boolean(Bool)
        case strings([String])
    }

    public enum EditError: Error, Equatable, LocalizedError {
        /// The text has an error already, so an edit would be made blind.
        case unreadable(String)
        case invalidPath(String)
        case unknownKey(String)
        case wrongKind(path: String, expected: String)
        case invalidValue(path: String, reason: String)
        case notFound(String)
        case outOfRange(path: String, position: Int, count: Int)
        /// The key is written inside an inline table or with dotted keys, which an edit does not rewrite.
        case inlineTable(String)
        case wouldBeInvalid(String)
        /// A list is not what the caller read: something else changed it after that, so a change by position would land on another item.
        case changedMeanwhile(String)
        /// The text would be larger than a config may be: the Finder menu, `rh` and the MCP server refuse to read one, and the edit could not be undone.
        case tooLarge(bytes: Int)
        /// A table is made that is in the config already.
        case exists(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let why):
                return "The config cannot be edited as it is: \(why) Fix that first (`rh config validate` says where)."
            case .invalidPath(let path):
                return "\"\(path.withControlCharactersEscaped)\" is not a path: use the names of `rh docs config` joined by dots, and the position of an entry as a number (preset.2.title)."
            case .unknownKey(let path):
                return "\"\(path)\" is not a setting of the config (`rh docs config` lists them)."
            case .wrongKind(let path, let expected):
                return "\"\(path)\" takes \(expected)."
            case .invalidValue(let path, let reason):
                return "\"\(path)\": \(reason)."
            case .notFound(let path):
                return "\"\(path)\" is not in the config."
            case .outOfRange(let path, let position, let count):
                return "\"\(path)\" has \(count) \(count == 1 ? "item" : "items"): there is no position \(position)."
            case .inlineTable(let path):
                return "\"\(path)\" is written as an inline table or with dotted keys, which an edit leaves alone: change that line as text."
            case .wouldBeInvalid(let message):
                return "That change would make the config invalid: \(message)"
            case .changedMeanwhile(let path):
                return "\"\(path)\" is not what it was when it was read: something changed it since. Read it again and repeat the change."
            case .tooLarge(let bytes):
                return "The config would be \(bytes / 1024) KB, and Right Here reads at most \(ConfigParser.maxBytes / 1024) KB: a config is a few kilobytes."
            case .exists(let path):
                return "\"\(path)\" is in the config already."
            }
        }
    }

    public let text: String
    public let validation: Validation

    public init(_ text: String, validation: Validation = .standalone) {
        self.text = text
        self.validation = validation
    }

    public static func == (left: ConfigDocument, right: ConfigDocument) -> Bool {
        left.text == right.text
    }

    func makeLayout() throws -> Layout {
        try Layout(text, validation: validation)
    }

    // MARK: Reading

    /// The value of the key at `path`, as it is written in the file.
    public func rawValue(at path: String) -> String? {
        TOMLOutline(text).rawValue(of: path)
    }

    /// The `id` of the entry at `position` (from 1) of `[[table]]`; `nil` when there is no such entry or it has no id.
    public func entryID(at position: Int, in table: String) -> String? {
        TOMLOutline(text).rawValue(of: "\(table).\(position).id").flatMap(Self.unquoted)
    }

    /// The `id` of every entry of `[[table]]` in the order they are written, `nil` for one that has none (or that is not written as a string): one reading of the text for all of them.
    public func entryIDs(in table: String) -> [String?] {
        let outline = TOMLOutline(text)
        var ids: [String?] = []
        while outline.lines["\(table).\(ids.count + 1)"] != nil {
            ids.append(outline.rawValue(of: "\(table).\(ids.count + 1).id").flatMap(Self.unquoted))
        }
        return ids
    }

    /// The `id` of every entry of the list of tables `table` as the parser reads the text, whatever way the entries are written (headers, or an inline array that the outline does not number). What
    /// a new entry has to keep away from: an id that this has is in use, shown or not.
    public func parsedEntryIDs(in table: String) -> Set<String> {
        guard let tree = ConfigParser.readTree(text).tree else { return [] }
        var value: TOMLValue? = .table(tree)
        for segment in table.split(separator: ".") { value = value?.tableValue?[String(segment)] }
        return Set((value?.arrayValue ?? []).compactMap { entry in
            if case .string(let id)? = entry.tableValue?["id"] { id } else { nil }
        })
    }

    /// This document, when the entry at `position` of `[[table]]` is the one with this `id`; otherwise a refusal. A change to `preset.2.title` that waited for the person's yes was
    /// made for the entry that stood at 2 then, and a file in which another entry stands there now is not the one it was made for.
    public func requiringEntry(_ id: String, at position: Int, in table: String) throws -> ConfigDocument {
        guard entryID(at: position, in: table) == id else { throw EditError.changedMeanwhile("\(table).\(position)") }
        return self
    }

    /// The position (from 1) of the entry of `[[table]]` whose `id` is this one.
    public func position(ofEntryWithID id: String, in table: String) -> Int? {
        let outline = TOMLOutline(text)
        var position = 1
        while outline.lines["\(table).\(position)"] != nil {
            if let raw = outline.rawValue(of: "\(table).\(position).id"), Self.unquoted(raw) == id { return position }
            position += 1
        }
        return nil
    }

    /// The position (from 1) of the first element of the list of text at `path` that is `element`.
    public func position(ofElement element: String, in path: String) throws -> Int? {
        let segments = try Self.segments(path)
        let node = try Self.schemaNode(path: path, segments: segments)
        guard node.kind == .stringArray else { throw EditError.wrongKind(path: path, expected: Self.expectation(of: node)) }
        let layout = try makeLayout()
        guard let range = layout.outline.valueRanges[path] else { return nil }
        let array = try Self.array(in: layout, range: range, path: path)
        return array.elements.firstIndex { Self.unquoted($0.text) == element }.map { $0 + 1 }
    }

    /// The items of the list of text at `path` as the file writes them, in order; `nil` when the file does not write the list (which is not the same as an empty one).
    public func elements(of path: String) throws -> [String]? {
        let segments = try Self.segments(path)
        let node = try Self.schemaNode(path: path, segments: segments)
        guard node.kind == .stringArray else { throw EditError.wrongKind(path: path, expected: Self.expectation(of: node)) }
        let layout = try makeLayout()
        guard let range = layout.outline.valueRanges[path] else { return nil }
        return try Self.array(in: layout, range: range, path: path).elements.map { Self.unquoted($0.text) ?? $0.text }
    }

    /// This document, when the list of text at `path` is exactly `items` (`nil`: the file does not write it); otherwise a refusal. A change by position is made against a list the
    /// person was shown, and what else edits the file (an assistant, `rh config`, another window) can have changed it since: the check is made on the text the change is made on.
    public func requiringElements(_ items: [String]?, in path: String) throws -> ConfigDocument {
        guard try elements(of: path) == items else { throw EditError.changedMeanwhile(path) }
        return self
    }

    /// How many items the list of text at `path` has in the file; none when the file does not write it.
    public func elementCount(of path: String) -> Int {
        guard let raw = rawValue(at: path), let array = TOMLArrayText(raw) else { return 0 }
        return array.elements.count
    }

    /// The schema's description of the setting at `path`.
    public static func node(at path: String) throws -> SchemaNode {
        try schemaNode(path: path, segments: try segments(path))
    }

    /// How many entries `[[table]]` has.
    public func entryCount(of table: String) -> Int {
        let outline = TOMLOutline(text)
        var count = 0
        while outline.lines["\(table).\(count + 1)"] != nil { count += 1 }
        return count
    }

    // MARK: Values

    /// Sets the key at `path` to `value`: the value is replaced where it is written (an array keeps its layout, but not the comments inside it), or the key is
    /// added at the end of its table, which is made at the end of the file when the file has none.
    public func setting(_ path: String, to value: Value) throws -> ConfigDocument {
        let segments = try Self.segments(path)
        let node = try Self.schemaNode(path: path, segments: segments)
        try Self.require(node, accepts: value, path: path)
        let layout = try makeLayout()
        if let range = layout.outline.valueRanges[path] {
            let old = String(decoding: layout.bytes[range], as: UTF8.self)
            return try checked(layout.replacing(range, with: Self.render(value, like: old)))
        }
        return try checked(layout.insertingKey(segments, rendered: Self.render(value, like: nil), path: path))
    }

    /// Removes the key at `path` (the lines it is on, with a comment at the end of them); comments above it stay.
    public func removing(_ path: String) throws -> ConfigDocument {
        let segments = try Self.segments(path)
        let node = try Self.schemaNode(path: path, segments: segments)
        guard ![.table, .tableMap, .tableArray].contains(node.kind) else {
            throw EditError.wrongKind(path: path, expected: "one setting, not a table: unset the settings of a table one by one, remove an entry of a list as an entry, and an agent of your own with `rh config remove agent.<id>`")
        }
        let layout = try makeLayout()
        guard let range = layout.outline.valueRanges[path], let first = layout.outline.lines[path] else { throw EditError.notFound(path) }
        if layout.isInsideInlineTable(segments) { throw EditError.inlineTable(path) }
        let last = layout.line(atOffset: max(range.lowerBound, range.upperBound - 1))
        return try checked(layout.removingLines(first...last))
    }

    /// The whole text replaced by `text`, as somebody who edits the file as text writes it. It has to read (the Finder menu and every command depend on it), so a text with an
    /// error is refused with the first one; the text this document holds may have errors, which is how the file that does not read is put right.
    public func replacingText(_ text: String) throws -> ConfigDocument {
        if text.utf8.count > ConfigParser.maxBytes { throw EditError.tooLarge(bytes: text.utf8.count) }
        if let error = validation.errors(text).first { throw EditError.wouldBeInvalid(error) }
        return ConfigDocument(text, validation: validation)
    }

    // MARK: Arrays of strings

    /// Adds an element to the array of strings at `path`, at `position` (from 1; at the end without one). The key is made when it is not there.
    public func insertingElement(_ element: String, into path: String, at position: Int? = nil) throws -> ConfigDocument {
        let segments = try Self.segments(path)
        let node = try Self.schemaNode(path: path, segments: segments)
        guard node.kind == .stringArray else { throw EditError.wrongKind(path: path, expected: Self.expectation(of: node)) }
        guard !element.trimmingCharacters(in: .whitespaces).isEmpty else { throw EditError.invalidValue(path: path, reason: "an item cannot be empty") }
        try Self.requireNoBackslash([element], path: path)
        let layout = try makeLayout()
        guard let range = layout.outline.valueRanges[path] else {
            guard position == nil || position == 1 else { throw EditError.outOfRange(path: path, position: position ?? 0, count: 0) }
            return try setting(path, to: .strings([element]))
        }
        var array = try Self.array(in: layout, range: range, path: path)
        let at = position ?? array.elements.count + 1
        guard (1...array.elements.count + 1).contains(at) else { throw EditError.outOfRange(path: path, position: at, count: array.elements.count) }
        array.insert(Self.basicString(element), at: at - 1)
        return try checked(layout.replacing(range, with: array.rendered()))
    }

    /// Removes the element at `position` (from 1), with the comment lines directly above it and the comment at the end of its line.
    public func removingElement(at position: Int, from path: String) throws -> ConfigDocument {
        let segments = try Self.segments(path)
        let node = try Self.schemaNode(path: path, segments: segments)
        guard node.kind == .stringArray else { throw EditError.wrongKind(path: path, expected: Self.expectation(of: node)) }
        let layout = try makeLayout()
        guard let range = layout.outline.valueRanges[path] else { throw EditError.notFound(path) }
        var array = try Self.array(in: layout, range: range, path: path)
        guard (1...max(array.elements.count, 1)).contains(position), position <= array.elements.count else {
            throw EditError.outOfRange(path: path, position: position, count: array.elements.count)
        }
        array.remove(at: position - 1)
        return try checked(layout.replacing(range, with: array.rendered()))
    }

    /// Writes `element` in place of the element at `position` (from 1): the comment lines above it and the comment at the end of its line stay with it, which taking the element out and
    /// putting another in its place would not do.
    public func replacingElement(at position: Int, in path: String, with element: String) throws -> ConfigDocument {
        let segments = try Self.segments(path)
        let node = try Self.schemaNode(path: path, segments: segments)
        guard node.kind == .stringArray else { throw EditError.wrongKind(path: path, expected: Self.expectation(of: node)) }
        guard !element.trimmingCharacters(in: .whitespaces).isEmpty else { throw EditError.invalidValue(path: path, reason: "an item cannot be empty") }
        try Self.requireNoBackslash([element], path: path)
        let layout = try makeLayout()
        guard let range = layout.outline.valueRanges[path] else { throw EditError.notFound(path) }
        var array = try Self.array(in: layout, range: range, path: path)
        guard (1...max(array.elements.count, 1)).contains(position), position <= array.elements.count else {
            throw EditError.outOfRange(path: path, position: position, count: array.elements.count)
        }
        array.replace(at: position - 1, with: Self.basicString(element))
        return try checked(layout.replacing(range, with: array.rendered()))
    }

    /// Moves the element at `from` (from 1) so that it is at `to`, with its comments.
    public func movingElement(from: Int, to: Int, in path: String) throws -> ConfigDocument {
        let segments = try Self.segments(path)
        let node = try Self.schemaNode(path: path, segments: segments)
        guard node.kind == .stringArray else { throw EditError.wrongKind(path: path, expected: Self.expectation(of: node)) }
        let layout = try makeLayout()
        guard let range = layout.outline.valueRanges[path] else { throw EditError.notFound(path) }
        var array = try Self.array(in: layout, range: range, path: path)
        for position in [from, to] where !(1...max(array.elements.count, 1)).contains(position) || position > array.elements.count {
            throw EditError.outOfRange(path: path, position: position, count: array.elements.count)
        }
        array.move(from: from - 1, to: to - 1)
        return try checked(layout.replacing(range, with: array.rendered()))
    }

    /// The value that command-line arguments stand for at `path`, as the schema reads that setting: one text (taken as it is, never read as TOML), one whole number,
    /// `true` or `false`, or any number of texts for a list.
    public static func value(from arguments: [String], at path: String) throws -> Value {
        let node = try schemaNode(path: path, segments: try segments(path))
        func single() throws -> String {
            guard arguments.count == 1 else {
                throw EditError.invalidValue(path: path, reason: "it takes one value, and \(arguments.count) were given (put a text that has spaces in quotes)")
            }
            return arguments[0]
        }
        switch node.kind {
        case .string:
            return .string(try single())
        case .integer:
            let text = try single()
            guard let number = Int(text) else { throw EditError.invalidValue(path: path, reason: "\"\(text.withControlCharactersEscaped)\" is not a whole number") }
            return .integer(number)
        case .boolean:
            switch try single() {
            case "true": return .boolean(true)
            case "false": return .boolean(false)
            case let other: throw EditError.invalidValue(path: path, reason: "it is true or false, not \"\(other.withControlCharactersEscaped)\"")
            }
        case .stringArray:
            return .strings(arguments)
        case .table, .tableArray, .tableMap:
            throw EditError.wrongKind(path: path, expected: expectation(of: node))
        }
    }

    // MARK: Checks

    /// The errors in some diagnostics, as sentences; warnings (a key the schema does not know) are the person's to read, not a reason to refuse an edit.
    static func sentences(_ diagnostics: [ConfigDiagnostic]) -> [String] {
        diagnostics.filter { $0.severity == .error }.map { diagnostic in
            (diagnostic.line.map { "line \($0): " } ?? "") + (diagnostic.path.isEmpty ? "" : "[\(diagnostic.path)] ") + diagnostic.message
        }
    }

    /// The edited text, after a check that it is a config that reads: no error, where there was none before.
    func checked(_ new: String) throws -> ConfigDocument {
        if new.utf8.count > ConfigParser.maxBytes { throw EditError.tooLarge(bytes: new.utf8.count) }
        if let error = validation.errors(new).first { throw EditError.wouldBeInvalid(error) }
        return ConfigDocument(new, validation: validation)
    }

    // MARK: Paths and the schema

    static func segments(_ path: String) throws -> [String] {
        let parts = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy(Self.isBareKeyByte) }) else {
            throw EditError.invalidPath(path)
        }
        return parts
    }

    private static func isBareKeyByte(_ byte: UInt8) -> Bool {
        (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x30 && byte <= 0x39) || byte == 0x5F || byte == 0x2D
    }

    /// The schema node a path names; the position of an entry (`preset.2`) and the id of a table per id (`agent.claude`) are skipped on the way.
    static func schemaNode(path: String, segments: [String]) throws -> SchemaNode {
        var level = ConfigSchema.root
        var found: SchemaNode?
        var index = 0
        while index < segments.count {
            guard let node = level.first(where: { $0.key == segments[index] }) else { throw EditError.unknownKey(path) }
            found = node
            index += 1
            switch node.kind {
            case .tableMap:
                if index < segments.count { index += 1 }
            case .tableArray:
                if index < segments.count {
                    // Anything below an entry names the entry first: `preset.2.title`, never `preset.title`.
                    guard Int(segments[index]) != nil else { throw EditError.unknownKey(path) }
                    index += 1
                }
            default:
                break
            }
            level = node.children
        }
        guard let found else { throw EditError.unknownKey(path) }
        return found
    }

    private static func expectation(of node: SchemaNode) -> String {
        switch node.kind {
        case .string: return "text"
        case .integer: return "a whole number"
        case .boolean: return "true or false"
        case .stringArray: return "a list of text"
        case .table, .tableArray, .tableMap: return "a table, which is not a value"
        }
    }

    /// An argument of an agent with a backslash is refused when the agent starts: shells do not all read one the same way inside quotes. It is refused where it is written, with the way out.
    static func requireNoBackslash(_ items: [String], path: String) throws {
        guard let key = ConfigSchema.genericKey(of: path), key == "agent.*.args" || key == "agent.*.variant.*.arguments", items.contains(where: { $0.contains("\\") }) else { return }
        throw EditError.invalidValue(path: path, reason: "an argument with a backslash is refused when the agent starts, since shells do not all read one the same way inside quotes: put such text in the command")
    }

    static func require(_ node: SchemaNode, accepts value: Value, path: String) throws {
        switch (node.kind, value) {
        case (.string, .string(let text)):
            if let allowed = node.allowedValues, !allowed.contains(text) {
                throw EditError.invalidValue(path: path, reason: "it is one of \(allowed.joined(separator: ", "))")
            }
        case (.stringArray, .strings(let items)):
            if items.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) { throw EditError.invalidValue(path: path, reason: "an item cannot be empty") }
            try requireNoBackslash(items, path: path)
        case (.integer, .integer), (.boolean, .boolean):
            break
        default:
            throw EditError.wrongKind(path: path, expected: expectation(of: node))
        }
    }

    // MARK: Rendering

    /// A TOML basic string.
    static func basicString(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    out += "\\u" + String(format: "%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// The text of a value; an array is laid out the way the value it replaces was (one line, or one element to a line).
    static func render(_ value: Value, like old: String?) -> String {
        switch value {
        case .string(let text): return basicString(text)
        case .integer(let number): return String(number)
        case .boolean(let flag): return flag ? "true" : "false"
        case .strings(let list):
            let items = list.map(basicString)
            if let old, let existing = TOMLArrayText(old) { return existing.replacingElements(with: items).rendered() }
            let oneLine = "[" + items.joined(separator: ", ") + "]"
            if oneLine.count <= 72 { return oneLine }
            return "[\n" + items.map { "    \($0),\n" }.joined() + "]"
        }
    }

    private static func array(in layout: Layout, range: Range<Int>, path: String) throws -> TOMLArrayText {
        let raw = String(decoding: layout.bytes[range], as: UTF8.self)
        guard let array = TOMLArrayText(raw) else { throw EditError.inlineTable(path) }
        return array
    }

    /// The text of a string as the parser reads it: a basic or a literal string, on one line or several, with its escapes. `nil` for what is not a string.
    static func unquoted(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2, let first = text.first, first == "\"" || first == "'" else { return nil }
        // The common string, on one line with no escape and no third quote, is what is between the quotes; the parser decides the rest.
        if text.last == first, !text.hasPrefix(String(repeating: first, count: 3)), !text.dropFirst().dropLast().contains(where: { $0 == first || $0 == "\\" || $0 == "\n" || $0 == "\r" }) {
            return String(text.dropFirst().dropLast())
        }
        guard case .string(let decoded)? = ConfigParser.readTree("v = " + text).tree?["v"] else { return nil }
        return decoded
    }
}
