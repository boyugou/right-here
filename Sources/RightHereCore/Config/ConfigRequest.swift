import Foundation

/// What a person or an agent asks of the config, in the words `rh config` and the MCP tool share: a verb, a setting, and the values or the item it is about. The window
/// builds `ConfigOperation`s directly (a drag knows the places); a request names things by their text and their id, and is turned into operations against the file as it is now.
public struct ConfigRequest: Sendable, Equatable {
    public enum Verb: String, Sendable, CaseIterable, Equatable {
        case set, unset, add, remove, move
    }

    /// What is wrong with the request itself, before the file is looked at any further.
    public enum Problem: Error, LocalizedError, Equatable {
        /// Something is missing or malformed.
        case usage(String)
        /// It names an item or an entry the file does not have.
        case notFound(String)

        public var errorDescription: String? {
            switch self {
            case .usage(let text), .notFound(let text): return text
            }
        }
    }

    public var verb: Verb
    /// The setting or list: `general.terminal`, `menu.items`, `preset`.
    public var key: String
    /// `set`: the value, or the items of a list. `add`: the items, or for a list of tables, and for an agent of one's own (`agent.<id>`), the fields as `name=value`.
    public var values: [String]
    /// `remove` and `move`: the item's text, or the entry's id.
    public var item: String?
    /// `remove` and `move`: the item's place, from 1, instead of its name.
    public var position: Int?
    /// `move`: where to, from 1, or `first` or `last`.
    public var to: String?
    /// `add`: where, from 1, or `first` or `last`; the end without it.
    public var at: String?

    public init(_ verb: Verb, _ key: String, values: [String] = [], item: String? = nil, position: Int? = nil, to: String? = nil, at: String? = nil) {
        self.verb = verb
        self.key = key
        self.values = values
        self.item = item
        self.position = position
        self.to = to
        self.at = at
    }

    /// The changes this asks for, on `document` as it is now. Throws `Problem` for a request that is not one, and `ConfigDocument.EditError` for a setting or a value the
    /// config does not have.
    /// - Parameter defaultList: The list a setting comes to while the file does not write it (`ConfigDefaults`). Adding to such a list, taking an item out of it or moving one is a
    ///   change of that list as it is: the list is written first, and then changed.
    ///   - seedEntries: The entries that a list of tables comes with while the config defines none (the built-in templates, which any template of the config's own replaces). Adding an entry to such a
    ///     list writes them first, except one that the request gives the id of: that one is replaced, as it is in the config.
    public func operations(in document: ConfigDocument, defaultList: (String) -> [String]? = { _ in nil }, seedEntries: (String) -> [ConfigOperation] = { _ in [] }) throws -> [ConfigOperation] {
        let node = try ConfigDocument.node(at: key)
        var document = document
        var seed: [ConfigOperation] = []
        if [.add, .remove, .move].contains(verb), node.kind == .stringArray, let list = defaultList(key), ((try? document.elements(of: key)) ?? nil) == nil {
            seed = [.set(key, .strings(list))]
            document = try document.setting(key, to: .strings(list))
        }
        if verb == .add, node.kind == .tableArray {
            let given = (try? fields(entry: true))?.first { $0.key == "id" }
            seed = seedEntries(key).filter { operation in
                guard case .addEntry(_, let fields, _) = operation, let id = fields.first(where: { $0.key == "id" })?.value else { return true }
                return id != given?.value
            }
        }
        if node.kind == .tableMap, [.add, .remove].contains(verb) { return try operationsForTable(in: document, defaultList: defaultList) }
        return seed + (try operations(for: node, in: document))
    }

    private func operations(for node: SchemaNode, in document: ConfigDocument) throws -> [ConfigOperation] {
        switch verb {
        case .set:
            return [.set(key, try ConfigDocument.value(from: values, at: key))]
        case .unset:
            return [.unset(key)]
        case .add:
            let count = Self.count(of: key, node: node, document: document)
            let first = try at.map { try Self.place($0, count: count, name: "at", endIsAllowed: true) }
            switch node.kind {
            case .stringArray:
                guard !values.isEmpty else { throw Problem.usage("Name the items to add.") }
                return values.enumerated().map { index, item in .insert(item, into: key, at: first.map { $0 + index }) }
            case .tableArray:
                return [.addEntry(to: key, fields: try fields(entry: true), at: first)]
            default:
                throw Problem.usage("\"\(key)\" is not a list: use `rh config set` for a setting.")
            }
        case .remove:
            try requireList(node, instead: "use `rh config unset` for a setting.")
            let place = try resolve(node: node, document: document)
            return [node.kind == .tableArray ? .removeEntry(at: place, from: key) : .remove(at: place, from: key)]
        case .move:
            try requireList(node, instead: nil)
            let from = try resolve(node: node, document: document)
            guard let to else { throw Problem.usage("Say where to move it: to is a place from 1, first or last.") }
            let place = try Self.place(to, count: Self.count(of: key, node: node, document: document), name: "to", endIsAllowed: false)
            return [node.kind == .tableArray ? .moveEntry(from: from, to: place, in: key) : .move(from: from, to: place, in: key)]
        }
    }

    /// The table of an agent of one's own (`agent.lazygit`) made or taken out. The window does both with its entry in the menu in the same change, since an agent that is not in the menu is
    /// one nobody can start and a list that names an agent nobody defines is a config that does not read, and so does this: the table is added first and listed after it, and unlisted before
    /// it is taken out.
    private func operationsForTable(in document: ConfigDocument, defaultList: (String) -> [String]?) throws -> [ConfigOperation] {
        let parts = key.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts[0] == "agent", !parts[1].isEmpty else {
            throw Problem.usage("Name the agent: `agent.<id>`, for example `agent.lazygit`.")
        }
        let id = parts[1]
        let listKey = "general.agents"
        let listed = (try? document.elements(of: listKey)) ?? nil
        if verb == .add {
            var operations: [ConfigOperation] = []
            if listed == nil, let list = defaultList(listKey) { operations.append(.set(listKey, .strings(list))) }
            else if let listed { operations.append(.expect(listed, in: listKey)) }
            return operations + [.addTable(key, fields: try fields(entry: false)), .insert(id, into: listKey, at: nil)]
        }
        guard document.tableIDs(of: "agent").contains(id) else { throw Problem.notFound("There is no agent \"\(id.withControlCharactersEscaped)\" of your own in this file.") }
        var operations: [ConfigOperation] = []
        if let listed, let place = listed.firstIndex(of: id) { operations += [.expect(listed, in: listKey), .remove(at: place + 1, from: listKey)] }
        return operations + [.removeTable(key)]
    }

    // MARK: Pieces

    private func requireList(_ node: SchemaNode, instead hint: String?) throws {
        guard node.kind == .stringArray || node.kind == .tableArray else {
            throw Problem.usage("\"\(key)\" is not a list" + (hint.map { ": " + $0 } ?? "."))
        }
    }

    /// The fields of a new entry (or of the table of an agent of one's own): `name=value`, a name given twice making a list for a setting that takes one.
    private func fields(entry: Bool) throws -> [ConfigField] {
        guard !values.isEmpty else { throw Problem.usage("Give the fields of the entry as name=value.") }
        var order: [String] = []
        var given: [String: [String]] = [:]
        for argument in values {
            guard let equals = argument.firstIndex(of: "="), equals != argument.startIndex else {
                throw Problem.usage("\"\(argument.withControlCharactersEscaped)\" is not a field: write name=value.")
            }
            let name = String(argument[..<equals])
            if given[name] == nil { order.append(name) }
            given[name, default: []].append(String(argument[argument.index(after: equals)...]))
        }
        return try order.map { name in ConfigField(name, try ConfigDocument.value(from: given[name] ?? [], at: entry ? "\(key).1.\(name)" : "\(key).\(name)")) }
    }

    /// The place of the item this names, from 1: by its place when one is given, else by its text (a list of text) or its id (a list of entries).
    private func resolve(node: SchemaNode, document: ConfigDocument) throws -> Int {
        if let position {
            guard position >= 1 else { throw Problem.usage("position counts from 1.") }
            return position
        }
        guard let item else { throw Problem.usage("Name the item (or give a position).") }
        let found = node.kind == .tableArray ? document.position(ofEntryWithID: item, in: key) : try document.position(ofElement: item, in: key)
        guard let found else {
            throw Problem.notFound("\(key) has \(node.kind == .tableArray ? "no entry with the id" : "no item") \"\(item.withControlCharactersEscaped)\".")
        }
        return found
    }

    /// A place given as a number, or `first` or `last` of what has `count` items. A new item may also go after the last (`endIsAllowed`).
    private static func place(_ text: String, count: Int, name: String, endIsAllowed: Bool) throws -> Int {
        switch text {
        case "first": return 1
        case "last": return endIsAllowed ? count + 1 : max(count, 1)
        default:
            guard let number = Int(text), number >= 1 else { throw Problem.usage("\(name) takes a place from 1, first or last, not \"\(text.withControlCharactersEscaped)\".") }
            return number
        }
    }

    /// How many items a list has now.
    static func count(of key: String, node: SchemaNode, document: ConfigDocument) -> Int {
        node.kind == .tableArray ? document.entryCount(of: key) : document.elementCount(of: key)
    }
}
