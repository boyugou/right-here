import Foundation

/// Lays a per-machine overlay (`config.local.toml`) over the shared config (`config.toml`).
///
/// - Tables merge key by key: a scalar or a list the overlay sets replaces the base value as a whole
///   (`menu.items`, `general.agents` and every other list are never merged element by element).
/// - Entries with an `id` (`[[app]]`, `[[preset]]`, `[[new_file.template]]`, `[[agent.<id>.variant]]`) merge by id: the
///   overlay entry replaces the base entry of that id in place, and an entry with a new id is appended. An overlay
///   entry never replaces an earlier entry of the overlay: a second entry with an id is a duplicate, appended so that it
///   is reported (the first definition is used) whether or not the base has entries of that kind.
/// - `[agent.<id>]` is a table like the others, so an overlay can change one key of an agent the base defines
///   (its `command`) and the base's variants stay.
/// - `disabled = ["id", ...]` in the overlay removes those ids from the merged result: app, template and agent
///   definitions, the ids in `general.agents`, `menu.items` and `services.items` (an entry that names the id as an agent,
///   an app, a terminal to open in or a preset's terminal), a default terminal or editor of that id, and every preset
///   whose agent it is.
struct ConfigMerge {
    enum Layer: Equatable, Sendable { case base, local }

    struct Origin: Equatable {
        var layer: Layer
        /// The 1-based position of the entry in its own file.
        var index: Int
    }

    struct Result {
        var root: [String: TOMLValue]
        /// Where a key came from, by dotted path: keys with a value of their own, and tables only one file has.
        var keyOrigins: [String: Layer]
        /// For each array of tables, where each merged element came from.
        var arrayOrigins: [String: [Origin]]
        var disabled: Set<String>
        /// The overlay's `disabled` is not a list of strings.
        var disabledProblem: Bool
        /// Presets removed because the agent they name is disabled.
        var droppedPresets: [DroppedPreset]
    }

    struct DroppedPreset: Equatable {
        var id: String
        var agent: String
    }

    private var keyOrigins: [String: Layer] = [:]
    private var arrayOrigins: [String: [Origin]] = [:]
    private var droppedPresets: [DroppedPreset] = []

    static let idKeyedArrays: Set<String> = ["app", "template", "variant", "preset"]

    static func merge(base: [String: TOMLValue], local: [String: TOMLValue]) -> Result {
        var merger = ConfigMerge()
        var overlay = local
        var problem = false
        var disabled = Set<String>()
        if let value = overlay.removeValue(forKey: "disabled") {
            if let items = value.arrayValue, items.allSatisfy({ if case .string = $0 { return true } else { return false } }) {
                for case .string(let id) in items { disabled.insert(id) }
            } else {
                problem = true
            }
        }
        var inherited = base
        inherited.removeValue(forKey: "disabled")
        var root = merger.mergeTables(base: inherited, local: overlay, path: [])
        merger.apply(disabled: disabled, to: &root)
        return Result(root: root, keyOrigins: merger.keyOrigins, arrayOrigins: merger.arrayOrigins, disabled: disabled, disabledProblem: problem,
                      droppedPresets: merger.droppedPresets)
    }

    private mutating func mergeTables(base: [String: TOMLValue], local: [String: TOMLValue], path: [String]) -> [String: TOMLValue] {
        var result: [String: TOMLValue] = [:]
        for key in Set(base.keys).union(local.keys) {
            let here = path + [key]
            switch (base[key], local[key]) {
            case (let value?, nil):
                result[key] = value
                record(value, layer: .base, path: here)
            case (nil, let value?):
                result[key] = value
                record(value, layer: .local, path: here)
            case (.table(let inherited)?, .table(let overlay)?):
                result[key] = .table(mergeTables(base: inherited, local: overlay, path: here))
            case (let inherited?, let overlay?):
                if Self.idKeyedArrays.contains(key), let merged = mergeByID(base: inherited, local: overlay, path: here) {
                    result[key] = merged
                } else {
                    result[key] = overlay
                    record(overlay, layer: .local, path: here)
                }
            default:
                break
            }
        }
        return result
    }

    /// `nil` when either side is not a list of tables, in which case the overlay's value replaces the base's.
    private mutating func mergeByID(base: TOMLValue, local: TOMLValue, path: [String]) -> TOMLValue? {
        guard let inherited = base.arrayValue, let overlay = local.arrayValue,
              inherited.allSatisfy({ $0.tableValue != nil }), overlay.allSatisfy({ $0.tableValue != nil }) else { return nil }
        var items = inherited
        var origins = inherited.indices.map { Origin(layer: .base, index: $0 + 1) }
        // A shared entry is replaced at most once. The overlay's own duplicates are appended, not merged into each other,
        // so they are reported the way they are when the shared file has no entry of that kind (the first is used).
        var replaced = Set<Int>()
        for (offset, entry) in overlay.enumerated() {
            let origin = Origin(layer: .local, index: offset + 1)
            if let id = Self.id(of: entry), let position = inherited.indices.first(where: { Self.id(of: items[$0]) == id }), replaced.insert(position).inserted {
                items[position] = entry
                origins[position] = origin
            } else {
                items.append(entry)
                origins.append(origin)
            }
        }
        arrayOrigins[Self.dotted(path)] = origins
        return .array(items)
    }

    /// A path as `ConfigDiagnostic` spells it, which is how origins are looked up: a diagnostic stores its path with
    /// control characters escaped, so a key that has one has to be filed under the same spelling.
    private static func dotted(_ path: [String]) -> String {
        path.map(\.withControlCharactersEscaped).joined(separator: ".")
    }

    private static func id(of entry: TOMLValue) -> String? {
        if case .string(let id)? = entry.tableValue?["id"] { return id }
        return nil
    }

    /// The agent a `[[preset]]` entry names.
    private static func agent(of entry: TOMLValue) -> String? {
        if case .string(let agent)? = entry.tableValue?["agent"] { return agent }
        return nil
    }

    private mutating func record(_ value: TOMLValue, layer: Layer, path: [String]) {
        keyOrigins[Self.dotted(path)] = layer
        if let items = value.arrayValue, value.isTableArray {
            arrayOrigins[Self.dotted(path)] = items.indices.map { Origin(layer: layer, index: $0 + 1) }
        }
        if let table = value.tableValue {
            for (key, child) in table { record(child, layer: layer, path: path + [key]) }
        }
    }

    // MARK: disabled

    private mutating func apply(disabled: Set<String>, to root: inout [String: TOMLValue]) {
        guard !disabled.isEmpty else { return }
        let byID: (TOMLValue) -> Bool = { item in Self.id(of: item).map(disabled.contains) ?? false }
        filterEntries(&root, at: ["app"], dropping: byID)
        filterEntries(&root, at: ["new_file", "template"], dropping: byID)
        // A preset runs with one agent. Without it the preset cannot run on this machine, and left in place it would be
        // an error about an agent that was removed on purpose: it is dropped, and the caller reports that.
        droppedPresets = filterEntries(&root, at: ["preset"]) { Self.agent(of: $0).map(disabled.contains) ?? false }
            .map { DroppedPreset(id: Self.id(of: $0) ?? "", agent: Self.agent(of: $0) ?? "") }
        if case .table(var agents)? = root["agent"] {
            for id in disabled { agents.removeValue(forKey: id) }
            // What names a disabled app falls back to the default, instead of becoming an error on this machine.
            for (id, value) in agents {
                if case .table(var table) = value, case .string(let terminal)? = table["terminal"], disabled.contains(terminal) {
                    table.removeValue(forKey: "terminal")
                    agents[id] = .table(table)
                }
            }
            root["agent"] = .table(agents)
        }
        Self.update(&root, at: ["new_file", "template"]) { value in
            guard let items = value.arrayValue else { return value }
            return .array(items.map { item in
                guard var table = item.tableValue, case .string(let app)? = table["open_with"], disabled.contains(app) else { return item }
                table.removeValue(forKey: "open_with")
                return .table(table)
            })
        }
        Self.update(&root, at: ["general", "agents"]) { Self.filterStrings($0) { !disabled.contains($0) } }
        for key in ["terminal", "editor"] {
            if case .table(var general)? = root["general"], case .string(let id)? = general[key], disabled.contains(id) {
                general.removeValue(forKey: key)
                root["general"] = .table(general)
            }
        }
        // A dropped preset that replaced a built-in one leaves the built-in one behind, and entries naming it stay valid.
        let goneIDs = Set(droppedPresets.map(\.id)).subtracting(AgentPreset.builtIn.map(\.id))
        for path in [["menu", "items"], ["services", "items"]] {
            Self.update(&root, at: path) { value in
                Self.filterStrings(value) { entry in
                    guard let ref = ActionRef(parsing: entry) else { return true }
                    if case .preset(let id, _) = ref, goneIDs.contains(id) { return false }
                    return !Self.referencedIDs(ref).contains(where: disabled.contains)
                }
            }
        }
    }

    private static func referencedIDs(_ ref: ActionRef) -> [String] {
        switch ref {
        case .openTerminal(let id?): return [id]
        case .openApp(let id), .newFile(let id): return [id]
        case .agent(let id, _, let launcher):
            if case .terminal(let terminal?)? = launcher { return [id, terminal] }
            return [id]
        case .preset(_, let terminal?): return [terminal]
        default: return []
        }
    }

    /// Takes the entries of the array of tables at `path` that `drop` picks out, keeps the origins of the rest in step,
    /// and returns what it took.
    @discardableResult
    private mutating func filterEntries(_ root: inout [String: TOMLValue], at path: [String], dropping drop: (TOMLValue) -> Bool) -> [TOMLValue] {
        let key = Self.dotted(path)
        let origins = arrayOrigins[key]
        var keptOrigins: [Origin] = []
        var dropped: [TOMLValue] = []
        Self.update(&root, at: path) { value in
            guard let items = value.arrayValue else { return value }
            var kept: [TOMLValue] = []
            for (position, item) in items.enumerated() {
                if drop(item) { dropped.append(item); continue }
                kept.append(item)
                if let origins, position < origins.count { keptOrigins.append(origins[position]) }
            }
            return .array(kept)
        }
        if origins != nil { arrayOrigins[key] = keptOrigins }
        return dropped
    }

    private static func filterStrings(_ value: TOMLValue, keep: (String) -> Bool) -> TOMLValue {
        guard let items = value.arrayValue else { return value }
        return .array(items.filter { if case .string(let text) = $0 { return keep(text) } else { return true } })
    }

    private static func update(_ table: inout [String: TOMLValue], at path: [String], _ change: (TOMLValue) -> TOMLValue) {
        guard let first = path.first, let value = table[first] else { return }
        if path.count == 1 {
            table[first] = change(value)
        } else if case .table(var nested) = value {
            update(&nested, at: Array(path.dropFirst()), change)
            table[first] = .table(nested)
        }
    }
}
