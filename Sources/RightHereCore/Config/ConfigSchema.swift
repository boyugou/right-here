import Foundation

/// A description of one key of the config file. The schema is the single source of truth: the
/// parser uses it to find unknown keys, `rh docs config` prints it, and `rh config schema`
/// turns it into JSON Schema for editors.
public struct SchemaNode: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case string, integer, boolean, stringArray
        /// A `[table]`.
        case table
        /// An array of tables, `[[name]]`.
        case tableArray
        /// A table of tables keyed by an id, `[name.<id>]`.
        case tableMap
    }

    public var key: String
    public var kind: Kind
    public var summary: String
    public var defaultValue: String?
    public var allowedValues: [String]?
    public var example: String?
    public var children: [SchemaNode]
    /// Keys of a table that must be present.
    public var required: [String]
    /// Keys of a table of which at least one must be present.
    public var oneOfRequired: [String]
    /// A regular expression a string value (or each key of a table map) has to match.
    public var pattern: String?
    /// Values that are usual but not the only ones allowed, such as the ids of the built-in terminals.
    public var suggested: [String]?

    public init(
        _ key: String,
        _ kind: Kind,
        _ summary: String,
        default defaultValue: String? = nil,
        allowed: [String]? = nil,
        example: String? = nil,
        required: [String] = [],
        oneOfRequired: [String] = [],
        pattern: String? = nil,
        suggested: [String]? = nil,
        children: [SchemaNode] = []
    ) {
        self.key = key
        self.kind = kind
        self.summary = summary
        self.defaultValue = defaultValue
        self.allowedValues = allowed
        self.example = example
        self.required = required
        self.oneOfRequired = oneOfRequired
        self.pattern = pattern
        self.suggested = suggested
        self.children = children
    }

    public func child(_ key: String) -> SchemaNode? {
        children.first { $0.key == key }
    }
}

public enum ConfigSchema {
    public static let version = 1

    /// Ids of things the user names (apps, templates, variants, agents).
    /// Matches `ConfigParser.isIdentifier`: no leading dash (it would read as an option on a command line).
    static let identifierPattern = "^[a-z0-9][a-z0-9-]*$"

    public static var root: [SchemaNode] {
        let terminalIDs = KnownApps.terminals.map(\.id)
        let editorIDs = KnownApps.editors.map(\.id)
        return [
            SchemaNode("version", .integer, "Config format version. Only 1 exists.", default: "1", allowed: ["1"]),
            SchemaNode("general", .table, "Defaults used by actions.", children: [
                SchemaNode("terminal", .string,
                           "Terminal used by \"open in terminal\" and by agents. Omit it to use the first installed one.",
                           example: "\"ghostty\"; known: " + terminalIDs.joined(separator: ", "), suggested: terminalIDs),
                SchemaNode("editor", .string,
                           "Editor used by \"open in editor\". Omit it to use the first installed one.",
                           example: "\"vscode\"; known: " + editorIDs.joined(separator: ", "), suggested: editorIDs),
                SchemaNode("terminal_placement", .string,
                           "Where a terminal session starts: a new window, or a new tab of the front window. Tabs apply to Ghostty (Terminal.app always opens a window) and need permission to control it, which a plain \"open in terminal\" otherwise does not.",
                           default: "\"window\"", allowed: TerminalPlacement.configNames),
                SchemaNode("agents", .stringArray,
                           "Agents offered in the menu, in order. `rh init` fills this with the agents it finds.",
                           example: "[\"claude\", \"codex\"]; built in: " + KnownAgents.all.map(\.id).joined(separator: ", "),
                           suggested: KnownAgents.all.map(\.id))
            ]),
            SchemaNode("menu", .table, "The Finder context menu.", children: [
                SchemaNode("items", .stringArray,
                           "Entries in order. \"-\" is a separator; any action id from `rh actions` also works. Groups: "
                           + "open-terminal (open in the default terminal), open-editor (open in the default editor), "
                           + "open-with (a submenu of every other installed terminal and editor), agents (one entry per enabled agent), "
                           + "agents-more (a submenu of each agent's variants, deep links and other terminals), "
                           + "new-file (the templates), copy-path (the styles).",
                           default: "[\"open-terminal\", \"open-editor\", \"open-with\", \"agents\", \"agents-more\", \"-\", \"new-file\", \"copy-path\"]",
                           suggested: Array(MenuBuilder.groups).sorted() + ["-"])
            ]),
            SchemaNode("services", .table, "Finder Services (Quick Actions), written by `rh install --services`.", children: [
                SchemaNode("items", .stringArray,
                           "Action ids to offer. By default: open in terminal and editor, each enabled agent, new Markdown file, and two copy-path forms (absolute and from the git root).",
                           example: "[\"open.terminal\", \"agent.claude\", \"copy-path.absolute\"]")
            ]),
            SchemaNode("copy_path", .table, "The \"Copy Path\" submenu.", children: [
                SchemaNode("styles", .stringArray, "Forms offered, in order.",
                           default: "[\"absolute\", \"tilde\", \"git-relative\", \"name\", \"shell-escaped\", \"ai-mention\"]",
                           allowed: PathStyle.allCases.map(\.rawValue))
            ]),
            SchemaNode("new_file", .table, "The \"new file\" action.", children: [
                SchemaNode("then", .string,
                           "What happens after the file is created: reveal selects it in Finder, open opens it in the default editor (general.editor), nothing does nothing.",
                           default: "\"reveal\"", allowed: Config.AfterNewFile.allCases.map(\.rawValue)),
                SchemaNode("template", .tableArray, "File templates. Defining any replaces the built-in txt and md.",
                           required: ["id", "title", "extension"], children: [
                    SchemaNode("id", .string, "Identifier used in the action id `new-file.<id>`; lowercase letters, digits and dashes.",
                               example: "\"md\"", pattern: identifierPattern),
                    SchemaNode("title", .string,
                               "Name of the document type. The menu shows it as is inside the New File submenu, and as \"New <title>\" when it stands alone.",
                               example: "\"Markdown Document\""),
                    SchemaNode("base_name", .string, "File name without extension; numbered on collision.", default: "\"untitled\""),
                    SchemaNode("extension", .string, "File extension without the dot or a slash.", example: "\"md\"", pattern: "^[^./\\u0000]+$"),
                    SchemaNode("contents", .string, "Initial contents.", default: "\"\""),
                    SchemaNode("open_with", .string,
                               "App id (see `rh apps`) that opens this kind of file after it is created, when new_file.then is \"open\". The default editor opens it when this app is not installed.",
                               example: "\"typora\"")
                ])
            ]),
            SchemaNode("app", .tableArray,
                       "Applications to open folders and files with, in addition to the built-in ones. An id of a built-in app replaces it.",
                       required: ["id", "name"], oneOfRequired: ["bundle_id", "bundle_ids"], children: [
                SchemaNode("id", .string, "Identifier used in `open.app.<id>`; lowercase letters, digits and dashes.",
                           example: "\"tower\"", pattern: identifierPattern),
                SchemaNode("name", .string, "Display name.", example: "\"Tower\""),
                SchemaNode("bundle_id", .string, "Bundle identifier of the app.", example: "\"com.fournova.Tower3\""),
                SchemaNode("bundle_ids", .stringArray, "Several bundle identifiers, most preferred first. Use instead of bundle_id."),
                SchemaNode("role", .string, "terminal: opens a folder; editor and general: open the selection.",
                           default: "\"general\"", allowed: AppDescriptor.Role.allCases.map(\.rawValue)),
                SchemaNode("open_args", .stringArray,
                           "Terminals only: the program and arguments that open a folder, instead of handing the folder to the app. `{dir}`, `{shell}` and `{app}` (the installed .app) are replaced inside each element; the first element must be an absolute path or start with `{app}/`. Never write `{dir}` inside a string a shell will read: give it as an argument of its own.",
                           example: "[\"{app}/Contents/MacOS/wezterm\", \"start\", \"--cwd\", \"{dir}\"]"),
                SchemaNode("run_args", .stringArray,
                           "Terminals only: the program and arguments that start a typed command (an agent) in a folder, which lets a terminal without a built-in adapter start agents. As `open_args`, plus `{command}`, which must appear. Not checked on your terminal by Right Here: try it with `rh run agent.claude@<id>` and `--dry-run` first.",
                           example: "[\"{app}/Contents/MacOS/wezterm\", \"start\", \"--cwd\", \"{dir}\", \"--\", \"{shell}\", \"-lic\", \"{command}; exec {shell} -l\"]")
            ]),
            SchemaNode("agent", .tableMap, "AI agents, one table per agent: `[agent.claude]`. Built-in agents are listed by `rh agents`. Any command you want typed into a terminal in the folder works the same way, for example `[agent.lazygit]` with `name = \"lazygit\"` and `command = \"lazygit\"`.",
                       pattern: identifierPattern, children: [
                SchemaNode("name", .string, "Display name. Required for an agent that is not built in."),
                SchemaNode("command", .string, "What is typed into the shell to start the agent, including any flags.",
                           example: "\"claude --model opus\""),
                SchemaNode("launcher", .string,
                           "How the agent starts: terminal types the command into a terminal, link uses the agent's own terminal deep link, desktop opens its desktop app.",
                           default: "\"terminal\"", allowed: ["terminal", "link", "desktop"]),
                SchemaNode("terminal", .string, "Terminal for launcher = \"terminal\". Omit it to use general.terminal.", suggested: terminalIDs),
                SchemaNode("variant", .tableArray, "Extra start options shown in the agent's submenu.", required: ["id", "title"], children: [
                    SchemaNode("id", .string, "Identifier used in `agent.<agent>.<id>`; lowercase letters, digits and dashes.",
                               example: "\"opus\"", pattern: identifierPattern),
                    SchemaNode("title", .string, "Menu title.", example: "\"Use Opus\""),
                    SchemaNode("arguments", .stringArray, "Arguments appended to the command.", example: "[\"--model\", \"opus\"]")
                ])
            ])
        ]
    }

    // MARK: Documentation

    /// Markdown reference for the config file, printed by `rh docs config`.
    public static func markdown() -> String {
        var lines = [
            "# Config reference", "",
            "File: `~/.config/right-here/config.toml`. Format: TOML.",
            "Where it is read from, first match wins: `RH_CONFIG` (the file itself), `RH_CONFIG_DIR` (its folder),",
            "`$XDG_CONFIG_HOME/right-here/`, then `~/.config/right-here/`. `RH_LOG_DIR` moves the log folder",
            "(default `~/Library/Logs/right-here`). `RH_HOME` points every per-user path at another folder, to try",
            "an install without touching your own.", "",
            "Validate with `rh config validate` (add `--strict` to fail on warnings too). Print the effective menu with `rh menu`.",
            "A key the file does not know is a warning, not an error, so everything else still applies; it is",
            "almost always a typo, so treat warnings as problems.", ""
        ]
        func render(_ nodes: [SchemaNode], path: [String]) {
            for node in nodes {
                let full = (path + [node.key]).joined(separator: ".")
                var heading = "`\(full)`"
                switch node.kind {
                case .table: heading += " (table)"
                case .tableArray: heading = "`[[\(full)]]` (array of tables)"
                case .tableMap: heading = "`[\(full).<id>]` (table per id)"
                case .string: heading += " (string)"
                case .integer: heading += " (integer)"
                case .boolean: heading += " (boolean)"
                case .stringArray: heading += " (array of strings)"
                }
                lines.append("- \(heading): \(node.summary)")
                if let allowed = node.allowedValues {
                    lines.append("  - " + (node.kind == .stringArray ? "any of: " : "one of: ") + allowed.map { "`\($0)`" }.joined(separator: ", "))
                }
                if !node.required.isEmpty { lines.append("  - each entry needs: " + node.required.map { "`\($0)`" }.joined(separator: ", ")) }
                if !node.oneOfRequired.isEmpty { lines.append("  - each entry needs one of: " + node.oneOfRequired.map { "`\($0)`" }.joined(separator: ", ")) }
                if let value = node.defaultValue { lines.append("  - default: `\(value)`") }
                if let example = node.example { lines.append("  - example: \(example)") }
                render(node.children, path: node.kind == .tableMap ? path + [node.key, "<id>"] : path + [node.key])
            }
        }
        render(root, path: [])
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: JSON Schema

    /// A JSON Schema (draft-07) describing the config, usable by TOML-aware editors. It is stricter than
    /// the validator in one way on purpose: it rejects unknown keys, so an editor underlines a typo, while
    /// `rh` only warns about it and keeps applying the rest of the file.
    public static func jsonSchema() -> [String: Any] {
        func schema(for node: SchemaNode) -> [String: Any] {
            var result: [String: Any] = ["description": node.summary]
            switch node.kind {
            case .string:
                result["type"] = "string"
                if let allowed = node.allowedValues { result["enum"] = allowed }
                if let pattern = node.pattern { result["pattern"] = pattern }
                if let suggested = node.suggested { result["examples"] = suggested }
            case .integer:
                result["type"] = "integer"
                if let allowed = node.allowedValues { result["enum"] = allowed.compactMap(Int.init) }
            case .boolean:
                result["type"] = "boolean"
            case .stringArray:
                result["type"] = "array"
                var items: [String: Any] = ["type": "string"]
                if let allowed = node.allowedValues { items["enum"] = allowed }
                if let suggested = node.suggested { items["examples"] = suggested }
                result["items"] = items
            case .table:
                result.merge(objectSchema(node)) { $1 }
            case .tableArray:
                result["type"] = "array"
                result["items"] = objectSchema(node)
            case .tableMap:
                result["type"] = "object"
                result["additionalProperties"] = objectSchema(node)
                if let pattern = node.pattern { result["propertyNames"] = ["pattern": pattern] }
            }
            return result
        }
        func objectSchema(_ node: SchemaNode) -> [String: Any] {
            objectSchema(node.children, required: node.required, oneOfRequired: node.oneOfRequired)
        }
        func objectSchema(_ nodes: [SchemaNode], required: [String] = [], oneOfRequired: [String] = []) -> [String: Any] {
            var result: [String: Any] = [
                "type": "object",
                "additionalProperties": false,
                "properties": Dictionary(uniqueKeysWithValues: nodes.map { ($0.key, schema(for: $0)) })
            ]
            if !required.isEmpty { result["required"] = required }
            if !oneOfRequired.isEmpty { result["anyOf"] = oneOfRequired.map { ["required": [$0]] } }
            return result
        }
        var result = objectSchema(root)
        result["$schema"] = "http://json-schema.org/draft-07/schema#"
        result["title"] = "Right Here config"
        return result
    }
}
