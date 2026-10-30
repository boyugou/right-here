import Foundation

/// One change a person (or an AI agent working for them) makes to a config file that already exists, so that it says what they
/// asked for. Right Here writes a config only when it creates one; for a file that is there it says which line to change, and
/// to what, and leaves every other character of the file alone.
public struct ConfigEdit: Sendable, Equatable, Encodable {
    public enum Kind: String, Sendable, Encodable {
        /// The key is in the file: change its value.
        case change
        /// The key is not in the file (or is only a commented example): add it.
        case add
    }

    /// The file that decides: `config.local.toml` when it sets the key (it wins on this Mac), else `config.toml`.
    public var file: String
    /// `general.terminal`, `general.editor` or `general.agents`; `general` for the whole table, when the file has none to put them in (all
    /// the missing settings are one edit, since a table written twice is an error that throws the whole file away); `disabled` in the
    /// per-machine overlay, when its list is what keeps a setting from reaching this Mac.
    public var key: String
    public var kind: Kind
    /// The line to change, or the commented example or the `[general]` header to add it under; `nil` when the file shows none.
    public var line: Int?
    /// The value as it stands in the file, for `change`.
    public var current: String?
    /// The value to write, as TOML: `"ghostty"` or `["claude", "codex"]`; for a table, the table as text, its header first.
    public var value: String
    /// What to do, in a sentence.
    public var instruction: String
}

public enum ConfigEdits {
    /// The edits that make the config say what `choices` ask for. Each choice that the config already has is left out; a choice
    /// that was not made asks for nothing. `config` is the config as it is read now (both files merged), `base` and `local` are
    /// the texts of `config.toml` and `config.local.toml`, `nil` for a file that is not there.
    public static func needed(for choices: SetupChoices, config: Config, base: String?, local: String?,
                              baseName: String = "config.toml", localName: String = "config.local.toml") -> [ConfigEdit] {
        var wanted: [(key: String, name: String, value: String)] = []
        if let terminal = choices.terminal, config.terminal != terminal { wanted.append(("general.terminal", "terminal", quoted(terminal))) }
        if let editor = choices.editor, config.editor != editor { wanted.append(("general.editor", "editor", quoted(editor))) }
        if let agents = choices.agents, config.enabledAgents != agents {
            wanted.append(("general.agents", "agents", "[" + agents.map(quoted).joined(separator: ", ") + "]"))
        }

        // The per-machine overlay wins over the shared file, so a key it sets is the one to change.
        var files: [(name: String, text: String)] = []
        if let local { files.append((localName, local)) }
        if let base { files.append((baseName, base)) }
        var edits: [ConfigEdit] = []
        // What the file has no table for: one edit adds the table with all of it (the edits are made one after the other by whoever reads
        // them, and a table written twice is a syntax error).
        var tableLines: [(name: String, value: String)] = []
        var tableFile: (name: String, text: String)?
        // The ids that the overlay's `disabled` turns off although a file says to turn them on.
        var turnedOff: [String] = []
        for entry in wanted {
            if let holder = files.first(where: { TOMLOutline($0.text).rawValue(of: entry.key) != nil }) {
                if let written = TOMLOutline(holder.text).rawValue(of: entry.key), sameValue(written, entry.value) {
                    // The file says it already, so there is nothing to change in it: what keeps it from reaching this Mac is not in this key.
                    turnedOff += idsKeptOut(of: entry, config: config)
                    continue
                }
                edits.append(change(entry.key, name: entry.name, value: entry.value, in: holder))
            } else if let target = files.first(where: { $0.name == baseName }) ?? files.first {
                if let edit = add(entry.key, name: entry.name, value: entry.value, to: target) {
                    edits.append(edit)
                } else {
                    tableLines.append((entry.name, entry.value))
                    tableFile = target
                }
            }
        }
        if let tableFile, !tableLines.isEmpty { edits.append(addTable(tableLines, to: tableFile)) }
        if let local, let edit = turnOn(turnedOff, in: (localName, local)) { edits.append(edit) }
        return edits
    }

    /// Whether two ways of writing a TOML value are the same value (`["a","b"]` and `["a", "b"]`, `'a'` and `"a"`).
    private static func sameValue(_ written: String, _ wanted: String) -> Bool {
        guard let first = ConfigParser.readTree("value = \(written)\n").tree?["value"],
              let second = ConfigParser.readTree("value = \(wanted)\n").tree?["value"] else { return false }
        return first == second
    }

    /// The ids of a setting that the config does not have although it was asked for.
    private static func idsKeptOut(of entry: (key: String, name: String, value: String), config: Config) -> [String] {
        guard let tree = ConfigParser.readTree("value = \(entry.value)\n").tree?["value"] else { return [] }
        let wanted = (tree.arrayValue ?? [tree]).compactMap { value -> String? in if case .string(let id) = value { return id } else { return nil } }
        switch entry.key {
        case "general.terminal": return wanted.filter { $0 != config.terminal }
        case "general.editor": return wanted.filter { $0 != config.editor }
        default: return wanted.filter { !config.enabledAgents.contains($0) }
        }
    }

    /// The edit that takes `ids` out of the overlay's `disabled`, when that is what turns them off; `nil` when it is not (what is in the
    /// way is then something the config check says, and there is no line to change).
    private static func turnOn(_ ids: [String], in file: (name: String, text: String)) -> ConfigEdit? {
        let outline = TOMLOutline(file.text)
        guard !ids.isEmpty, let current = outline.rawValue(of: "disabled"),
              let tree = ConfigParser.readTree(file.text).tree?["disabled"]?.arrayValue else { return nil }
        let disabled = tree.compactMap { value -> String? in if case .string(let id) = value { return id } else { return nil } }
        let off = ids.filter(disabled.contains)
        guard !off.isEmpty else { return nil }
        // What the file holds is its text, which can have come through the sync folder: the ids that stay are shown with control and invisible characters as escapes,
        // and the sentence fences them (and the list as it stands) when one is not an id, as `change` does for the text it quotes (ADR 0020).
        let kept = disabled.filter { !off.contains($0) }
        let value = "[" + kept.map { quoted($0.withControlCharactersEscaped) }.joined(separator: ", ") + "]"
        let shownValue = kept.allSatisfy(IDRule.isValid) ? value : Fence.wrap(value)
        let shownCurrent = current.split(separator: "\n", omittingEmptySubsequences: false).map { String($0).withControlCharactersEscaped }.joined(separator: "\n")
        let line = outline.lines["disabled"]
        let located = line.map { " on line \($0)" } ?? ""
        let names = off.joined(separator: ", ")
        let what = current.contains("\n") ? "change the list that starts there (it runs over several lines) to disabled = \(shownValue)" : "change disabled = \(Fence.wrap(shownCurrent)) to disabled = \(shownValue)"
        return ConfigEdit(file: file.name, key: "disabled", kind: .change, line: line, current: shownCurrent, value: value,
                          instruction: "In \(file.name)\(located), \(what): the list turns \(names) off on this Mac, so the setting in the other file does not reach it here.")
    }

    private static func quoted(_ id: String) -> String { "\"\(id)\"" }

    private static func change(_ key: String, name: String, value: String, in file: (name: String, text: String)) -> ConfigEdit {
        let outline = TOMLOutline(file.text)
        let raw = outline.rawValue(of: key)
        // What the file holds is the person's text, or a config's that came through the sync folder: it is shown with its control and invisible characters as
        // escapes, in the sentence and in `current`, like every other place that quotes the config. The line breaks of a list stay in `current`, which only JSON carries.
        let current = raw?.split(separator: "\n", omittingEmptySubsequences: false).map { String($0).withControlCharactersEscaped }.joined(separator: "\n")
        let line = outline.lines[key]
        let located = line.map { " on line \($0)" } ?? ""
        let instruction: String
        if let raw, raw.contains("\n") {
            instruction = "In \(file.name)\(located), change the list that starts there (it runs over several lines) to \(name) = \(value)."
        } else {
            // The text of the file is fenced as data: an agent that follows this sentence to the letter must not read what the file says as part of it.
            instruction = "In \(file.name)\(located), change \(name) = \(current.map(Fence.wrap) ?? "…") to \(name) = \(value)."
        }
        return ConfigEdit(file: file.name, key: key, kind: .change, line: line, current: current, value: value, instruction: instruction)
    }

    /// The edit that adds one setting to a file that does not have it; `nil` when the file has no `[general]` table at all, for which
    /// `addTable` makes one edit for every setting.
    private static func add(_ key: String, name: String, value: String, to file: (name: String, text: String)) -> ConfigEdit? {
        let outline = TOMLOutline(file.text)
        guard let header = outline.lines["general"] else { return nil }
        if outline.rawValue(of: "general") != nil {
            return ConfigEdit(file: file.name, key: key, kind: .add, line: header, current: nil, value: value,
                              instruction: "In \(file.name), the general table is written inline on line \(header): add \(name) = \(value) inside it.")
        }
        if let example = commentedExample(of: name, in: file.text, under: header) {
            return ConfigEdit(file: file.name, key: key, kind: .add, line: example, current: nil, value: value,
                              instruction: "In \(file.name), line \(example) is a commented example of this setting: replace it with \(name) = \(value) (it belongs in the [general] table).")
        }
        return ConfigEdit(file: file.name, key: key, kind: .add, line: header, current: nil, value: value,
                          instruction: "In \(file.name), add the line \(name) = \(value) under [general] (line \(header)).")
    }

    /// One edit that adds the `[general]` table, with every setting the file lacks, at the end of the file.
    private static func addTable(_ lines: [(name: String, value: String)], to file: (name: String, text: String)) -> ConfigEdit {
        let assignments = lines.map { "\($0.name) = \($0.value)" }
        let table = (["[general]"] + assignments).joined(separator: "\n")
        let what = lines.count == 1 ? "the line \(assignments[0])" : "the lines \(assignments.joined(separator: "; ")) (each on a line of its own)"
        return ConfigEdit(file: file.name, key: "general", kind: .add, line: nil, current: nil, value: table,
                          instruction: "In \(file.name), add a [general] table at the end of the file with \(what).")
    }

    /// The first line of the `[general]` table (the one whose header is on line `header`) that is a comment of the form
    /// `# terminal = "ghostty"`, which a fresh config has for a setting nothing was found for. One outside the table, above its header
    /// or under the next one, would put the setting in another table.
    private static func commentedExample(of name: String, in text: String, under header: Int) -> Int? {
        for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where offset + 1 > header {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            if trimmed.first == "[" { return nil }
            guard trimmed.first == "#" else { continue }
            let rest = trimmed.dropFirst().drop { $0 == " " || $0 == "\t" }
            guard rest.hasPrefix(name) else { continue }
            if rest.dropFirst(name.count).drop(while: { $0 == " " || $0 == "\t" }).first == "=" { return offset + 1 }
        }
        return nil
    }
}
