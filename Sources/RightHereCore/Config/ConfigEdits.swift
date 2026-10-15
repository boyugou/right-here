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
    /// `general.terminal`, `general.editor` or `general.agents`.
    public var key: String
    public var kind: Kind
    /// The line to change, or the commented example or the `[general]` header to add it under; `nil` when the file shows none.
    public var line: Int?
    /// The value as it stands in the file, for `change`.
    public var current: String?
    /// The value to write, as TOML: `"ghostty"` or `["claude", "codex"]`.
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
        for entry in wanted {
            if let holder = files.first(where: { TOMLOutline($0.text).rawValue(of: entry.key) != nil }) {
                edits.append(change(entry.key, name: entry.name, value: entry.value, in: holder))
            } else if let target = files.first(where: { $0.name == baseName }) ?? files.first {
                edits.append(add(entry.key, name: entry.name, value: entry.value, to: target))
            }
        }
        return edits
    }

    private static func quoted(_ id: String) -> String { "\"\(id)\"" }

    private static func change(_ key: String, name: String, value: String, in file: (name: String, text: String)) -> ConfigEdit {
        let outline = TOMLOutline(file.text)
        let current = outline.rawValue(of: key)
        let line = outline.lines[key]
        let located = line.map { " on line \($0)" } ?? ""
        let instruction: String
        if let current, current.contains("\n") {
            instruction = "In \(file.name)\(located), change the list that starts there (it runs over several lines) to \(name) = \(value)."
        } else {
            instruction = "In \(file.name)\(located), change \(name) = \(current ?? "…") to \(name) = \(value)."
        }
        return ConfigEdit(file: file.name, key: key, kind: .change, line: line, current: current, value: value, instruction: instruction)
    }

    private static func add(_ key: String, name: String, value: String, to file: (name: String, text: String)) -> ConfigEdit {
        let outline = TOMLOutline(file.text)
        if let example = commentedExample(of: name, in: file.text) {
            return ConfigEdit(file: file.name, key: key, kind: .add, line: example, current: nil, value: value,
                              instruction: "In \(file.name), line \(example) is a commented example of this setting: replace it with \(name) = \(value) (it belongs in the [general] table).")
        }
        if let header = outline.lines["general"] {
            if outline.rawValue(of: "general") != nil {
                return ConfigEdit(file: file.name, key: key, kind: .add, line: header, current: nil, value: value,
                                  instruction: "In \(file.name), the general table is written inline on line \(header): add \(name) = \(value) inside it.")
            }
            return ConfigEdit(file: file.name, key: key, kind: .add, line: header, current: nil, value: value,
                              instruction: "In \(file.name), add the line \(name) = \(value) under [general] (line \(header)).")
        }
        return ConfigEdit(file: file.name, key: key, kind: .add, line: nil, current: nil, value: value,
                          instruction: "In \(file.name), add a [general] table at the end of the file with the line \(name) = \(value).")
    }

    /// The first line that is a comment of the form `# terminal = "ghostty"`, which a fresh config has for a setting nothing was
    /// found for.
    private static func commentedExample(of name: String, in text: String) -> Int? {
        for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            guard trimmed.first == "#" else { continue }
            let rest = trimmed.dropFirst().drop { $0 == " " || $0 == "\t" }
            guard rest.hasPrefix(name) else { continue }
            if rest.dropFirst(name.count).drop(while: { $0 == " " || $0 == "\t" }).first == "=" { return offset + 1 }
        }
        return nil
    }
}
