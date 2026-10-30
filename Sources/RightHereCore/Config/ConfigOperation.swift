import Foundation

/// A key and its value, as a new entry of `[[preset]]` or `[[app]]` is written: `title = "Review"`.
public struct ConfigField: Sendable, Equatable {
    public var key: String
    public var value: ConfigDocument.Value

    public init(_ key: String, _ value: ConfigDocument.Value) {
        self.key = key
        self.value = value
    }
}

/// One change to a config file, as the window, `rh config` and the MCP tool ask for it: they all build one of these and `ConfigDocument` does it. Positions count from 1.
public enum ConfigOperation: Sendable, Equatable {
    case set(String, ConfigDocument.Value)
    case unset(String)
    /// An element into a list of text (`menu.items`, `general.agents`); at the end without a position.
    case insert(String, into: String, at: Int? = nil)
    case remove(at: Int, from: String)
    /// Another text in place of the item at this place of a list of text, with its comments kept.
    case replace(at: Int, in: String, with: String)
    case move(from: Int, to: Int, in: String)
    /// Writes nothing: refuses the whole edit unless the list of text is exactly these items (`nil`: the file does not write it). A window that changes a list by position
    /// puts this first, with the list it showed, so that a change made meanwhile by something else is refused and not applied to another item.
    case expect([String]?, in: String)
    /// Writes nothing: refuses the whole edit unless the entry at this place of `[[table]]` has this `id`. A proposal that names an entry by its place keeps it with it.
    case expectEntry(String, at: Int, in: String)
    /// A new entry of `[[preset]]`, `[[app]]` and the like.
    case addEntry(to: String, fields: [ConfigField], at: Int? = nil)
    /// A new table of a table per id (`[agent.lazygit]`) with the fields it needs, made at once.
    case addTable(String, fields: [ConfigField])
    /// The table of a table per id taken out whole, with the tables below it.
    case removeTable(String)
    case removeEntry(at: Int, from: String)
    case moveEntry(from: Int, to: Int, in: String)
    /// The whole file as text, for the window's text editor. The text has to read; nothing of the file's old layout is kept, since the text is what its author made of it.
    case replaceText(String)

    /// The document after the change. Unsetting what is not set is not an error: the setting is as it was asked to be.
    public func apply(to document: ConfigDocument) throws -> ConfigDocument {
        switch self {
        case .set(let path, let value):
            return try document.setting(path, to: value)
        case .unset(let path):
            do {
                return try document.removing(path)
            } catch ConfigDocument.EditError.notFound(let missing) where missing == path {
                return document
            }
        case .insert(let element, let path, let position):
            return try document.insertingElement(element, into: path, at: position)
        case .remove(let position, let path):
            return try document.removingElement(at: position, from: path)
        case .replace(let position, let path, let element):
            return try document.replacingElement(at: position, in: path, with: element)
        case .move(let from, let to, let path):
            return try document.movingElement(from: from, to: to, in: path)
        case .expect(let items, let path):
            return try document.requiringElements(items, in: path)
        case .expectEntry(let id, let position, let table):
            return try document.requiringEntry(id, at: position, in: table)
        case .addEntry(let table, let fields, let position):
            return try document.addingEntry(to: table, fields: fields.map { ($0.key, $0.value) }, at: position)
        case .addTable(let path, let fields):
            return try document.addingTable(path, fields: fields.map { ($0.key, $0.value) })
        case .removeTable(let path):
            return try document.removingTable(path)
        case .removeEntry(let position, let table):
            return try document.removingEntry(at: position, from: table)
        case .moveEntry(let from, let to, let table):
            return try document.movingEntry(from: from, to: to, in: table)
        case .replaceText(let text):
            return try document.replacingText(text)
        }
    }

    /// What it does, in a line: for the history, for the answer and for the card a person decides on. A value in it is the one somebody else wrote, so the characters that draw
    /// nothing or turn the text around (U+202E, a zero-width space, a tag character) are written as escapes: what is read is what would be written.
    public var summary: String {
        plainSummary.withControlCharactersEscaped
    }

    private var plainSummary: String {
        func shown(_ text: String) -> String { text.count > 90 ? String(text.prefix(87)) + "..." : text }
        switch self {
        case .set(let path, let value):
            // A list on one line, however it would be laid out in the file.
            let written: String
            if case .strings(let items) = value { written = "[" + items.map(ConfigDocument.basicString).joined(separator: ", ") + "]" } else { written = ConfigDocument.render(value, like: nil).replacingOccurrences(of: "\n", with: " ") }
            return shown("set \(path) = \(written)")
        case .unset(let path):
            return "unset \(path)"
        case .insert(let element, let path, let position):
            return shown("add \(ConfigDocument.basicString(element)) to \(path)" + (position.map { " at \($0)" } ?? ""))
        case .remove(let position, let path):
            return "remove item \(position) of \(path)"
        case .replace(let position, let path, let element):
            return shown("replace item \(position) of \(path) with \(ConfigDocument.basicString(element))")
        case .move(let from, let to, let path):
            return "move item \(from) of \(path) to \(to)"
        case .expect(_, let path):
            return "check that \(path) is as it was read"
        case .expectEntry(_, let position, let table):
            return "check that entry \(position) of \(table) is the one it was for"
        case .addEntry(let table, let fields, let position):
            let name = fields.first { $0.key == "id" }.flatMap { field -> String? in if case .string(let id) = field.value { return id } else { return nil } }
            return shown("add the \(table) entry" + (name.map { " \(ConfigDocument.basicString($0))" } ?? "") + (position.map { " at \($0)" } ?? ""))
        case .addTable(let path, _):
            return "add the \(path) table"
        case .removeTable(let path):
            return "remove the \(path) table"
        case .removeEntry(let position, let table):
            return "remove entry \(position) of \(table)"
        case .moveEntry(let from, let to, let table):
            return "move entry \(from) of \(table) to \(to)"
        case .replaceText:
            return "edit the text of the file"
        }
    }

    /// The settings and lists it writes where the file names them, as they are spelled in the file: what another file of the config may set as well.
    public var settingPaths: [String] {
        switch self {
        case .set(let path, _), .unset(let path), .insert(_, let path, _), .remove(_, let path), .replace(_, let path, _), .move(_, _, let path):
            return [path]
        case .expect, .expectEntry, .addEntry, .addTable, .removeTable, .removeEntry, .moveEntry, .replaceText:
            return []
        }
    }

    /// The settings it writes, spelled generally (`ConfigSchema.genericKey`): `preset.*.prompt`, `general.terminal`, `menu.items`, `agent.*.args`.
    public var writtenKeys: [String] {
        func generic(_ path: String) -> String { ConfigSchema.genericKey(of: path) ?? path }
        switch self {
        case .set(let path, _), .unset(let path), .insert(_, let path, _), .remove(_, let path), .replace(_, let path, _), .move(_, _, let path):
            return [generic(path)]
        case .addEntry(let table, let fields, _):
            return fields.map { generic("\(table).1.\($0.key)") }
        case .addTable(let path, let fields):
            return fields.map { generic("\(path).\($0.key)") }
        case .removeTable(let path):
            return [generic(path)]
        case .removeEntry(_, let table), .moveEntry(_, _, let table):
            return [generic("\(table).1")]
        case .replaceText:
            return ["*"]
        case .expect, .expectEntry:
            return []
        }
    }

    /// A check and not a change: it says nothing about what was done, so the history and the summaries leave it out.
    public var isCheck: Bool {
        switch self {
        case .expect, .expectEntry: true
        default: false
        }
    }
}

extension ConfigOperation: Codable {}
extension ConfigField: Codable {}
