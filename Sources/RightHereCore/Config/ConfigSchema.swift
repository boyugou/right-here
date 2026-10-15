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

    /// Ids of things the user names (apps, templates, variants, agents); `IDRule` is the rule the parser applies.
    static let identifierPattern = IDRule.pattern

    /// An app's id: an id that is not one of the launcher words of an action id (`agent.<agent>@desktop`), which the parser refuses.
    static let appIdentifierPattern = "^(?!(" + AgentLauncher.reservedWords.sorted().joined(separator: "|") + ")$)" + IDRule.pattern.dropFirst()

    /// A name or title shown to people: no line break or other control character (`ShellQuoting.containsControlCharacter`
    /// is the rule the parser applies).
    static let displayNamePattern = "^[^\\u0000-\\u001f\\u007f-\\u009f\\u2028\\u2029]*$"

    public static var root: [SchemaNode] {
        let terminalIDs = KnownApps.terminals.map(\.id)
        let editorIDs = KnownApps.editors.map(\.id)
        return [
            SchemaNode("version", .integer, "Config format version. Only 1 exists.", default: "1", allowed: ["1"]),
            SchemaNode("disabled", .stringArray,
                       "Only meaningful in config.local.toml, the per-machine overlay: ids of apps (built-in ones included), new-file templates and agents to remove from the shared config on this machine. Entries naming them in general.agents, menu.items and services.items are removed too, and so are presets that use a disabled agent. In config.toml it does nothing and is reported.",
                       example: "[\"zed\", \"codex\"]"),
            SchemaNode("general", .table, "Defaults used by actions.", children: [
                SchemaNode("terminal", .string,
                           "Terminal used by \"open in terminal\" and by agents. Omit it to use the first installed one. A named app that is not installed is replaced by the first installed one; the doctor says so.",
                           example: "\"ghostty\"; known: " + terminalIDs.joined(separator: ", "), suggested: terminalIDs),
                SchemaNode("editor", .string,
                           "Editor used by \"open in editor\". Omit it to use the first installed one. A named app that is not installed is replaced by the first installed one; the doctor says so.",
                           example: "\"vscode\"; known: " + editorIDs.joined(separator: ", "), suggested: editorIDs),
                SchemaNode("terminal_placement", .string,
                           "Where a terminal session starts: \"window\", \"tab\", \"split-right\", or \"split-down\". Tabs and splits apply to Ghostty and iTerm (Terminal.app always opens a window) and need permission to control it, which a plain \"open in terminal\" otherwise does not.",
                           default: "\"window\"", allowed: TerminalPlacement.configNames),
                SchemaNode("bypass_permissions", .boolean,
                           "Whether to launch AI coding agents with flags that bypass tool approval / permission prompts (for autonomous workflows). Can be overridden per agent under [agent.<id>].",
                           default: "false"),
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
                           + "new-file (the templates), copy-path (the styles), "
                           + "presets (a submenu of the prompt presets; without it in the list they are a submenu of agents-more).",
                           default: "[\"open-terminal\", \"open-editor\", \"open-with\", \"agents\", \"agents-more\", \"-\", \"new-file\", \"copy-path\"]",
                           suggested: Array(MenuBuilder.groups).sorted() + ["-"])
            ]),
            SchemaNode("services", .table, "Finder Services (Quick Actions), written by `rh install --services`.", children: [
                SchemaNode("items", .stringArray,
                           "Action ids to offer. By default: open in terminal and editor, each enabled agent, new Markdown file, and two copy-path forms (absolute and from the git root).",
                           example: "[\"open.terminal\", \"agent.claude\", \"copy-path.absolute\"]")
            ]),
            SchemaNode("copy_path", .table, "The \"Copy Path\" submenu.", children: [
                SchemaNode("title", .string, "Custom menu title for the Copy Path entry or submenu (on the entry for the plain path when it is listed on its own); by default \"Copy Path\" in the system language.",
                           example: "\"Copy Path\"", pattern: displayNamePattern),
                SchemaNode("styles", .stringArray, "Forms offered, in order.",
                           default: "[\"absolute\", \"tilde\", \"git-relative\", \"name\", \"shell-escaped\", \"ai-mention\"]",
                           allowed: PathStyle.allCases.map(\.rawValue))
            ]),
            SchemaNode("new_file", .table, "The \"new file\" action.", children: [
                SchemaNode("then", .string,
                           "What happens after the file is created: reveal selects it in Finder, open opens it in the default editor (general.editor), nothing does nothing. With no installed editor the file is selected in Finder instead of opened.",
                           default: "\"reveal\"", allowed: Config.AfterNewFile.allCases.map(\.rawValue)),
                SchemaNode("template", .tableArray, "File templates. Defining any replaces the built-in txt and md.",
                           required: ["id", "title", "extension"], children: [
                    SchemaNode("id", .string, "Identifier used in the action id `new-file.<id>`; lowercase letters, digits and dashes.",
                               example: "\"md\"", pattern: identifierPattern),
                    SchemaNode("title", .string,
                               "Name of the document type, on one line. The menu shows it as is inside the New File submenu, and as \"New <title>\" when it stands alone.",
                               example: "\"Markdown Document\"", pattern: displayNamePattern),
                    SchemaNode("base_name", .string, "File name without extension; numbered on collision.", default: "\"untitled\""),
                    SchemaNode("extension", .string, "File extension without the dot or a slash.", example: "\"md\"", pattern: "^[^./\\u0000]+$"),
                    SchemaNode("contents", .string, "Initial contents.", default: "\"\""),
                    SchemaNode("open_with", .string,
                               "App id (see `rh apps`) that opens this kind of file after it is created, when new_file.then is \"open\". The default editor opens it when this app is not installed. With no installed editor the file is selected in Finder instead of opened.",
                               example: "\"typora\"")
                ])
            ]),
            SchemaNode("app", .tableArray,
                       "Applications to open folders and files with, in addition to the built-in ones. An id of a built-in app replaces it.",
                       required: ["id", "name"], oneOfRequired: ["bundle_id", "bundle_ids"], children: [
                SchemaNode("id", .string, "Identifier used in `open.app.<id>`; lowercase letters, digits and dashes. Not `link`, `desktop` or `default`: after the `@` of `agent.<agent>@<word>` they name a launcher.",
                           example: "\"tower\"", pattern: appIdentifierPattern),
                SchemaNode("name", .string, "Display name, on one line.", example: "\"Tower\"", pattern: displayNamePattern),
                SchemaNode("bundle_id", .string, "Bundle identifier of the app.", example: "\"com.fournova.Tower3\""),
                SchemaNode("bundle_ids", .stringArray, "Several bundle identifiers, most preferred first. Use instead of bundle_id."),
                SchemaNode("role", .string, "terminal: opens a folder; editor and general: open the selection.",
                           default: "\"general\"", allowed: AppDescriptor.Role.allCases.map(\.rawValue)),
                SchemaNode("open_args", .stringArray,
                           "Terminals only: the program and arguments that open a folder, instead of handing the folder to the app. `{dir}`, `{shell}` and `{app}` (the installed .app) are replaced inside each element; the first element must be an absolute path or start with `{app}/`. Start the app through `/usr/bin/open -n -b <bundle id> --args ...`: a terminal's own binary keeps running as long as its window is open, and `rh run` (and the MCP server, which stops it after two minutes) would wait for it. Never write `{dir}` inside a string a shell will read: give it as an argument of its own.",
                           example: "[\"/usr/bin/open\", \"-n\", \"-b\", \"org.alacritty\", \"--args\", \"--working-directory\", \"{dir}\"]"),
                SchemaNode("run_args", .stringArray,
                           "Terminals only: the program and arguments that start a typed command (an agent) in a folder, which lets a terminal without a built-in adapter start agents. As `open_args`, plus `{command}`, which must appear. Not checked on your terminal by Right Here: try it with `rh run agent.claude@<id>` and `--dry-run` first.",
                           example: "[\"/usr/bin/open\", \"-n\", \"-b\", \"org.alacritty\", \"--args\", \"--working-directory\", \"{dir}\", \"-e\", \"{shell}\", \"-lic\", \"{command}; exec {shell} -l\"]")
            ]),
            SchemaNode("agent", .tableMap, "AI agents, one table per agent: `[agent.claude]`. Built-in agents are listed by `rh agents`. Any command you want typed into a terminal in the folder works the same way, for example `[agent.lazygit]` with `name = \"lazygit\"` and `command = \"lazygit\"`.",
                       pattern: identifierPattern, children: [
                SchemaNode("name", .string, "Display name, on one line. Required for an agent that is not built in.", pattern: displayNamePattern),
                SchemaNode("command", .string, "What is typed into the shell to start the agent, including any flags.",
                           example: "\"claude --model opus\""),
                SchemaNode("launcher", .string,
                           "How the agent starts: terminal types the command into a terminal, link uses the agent's own terminal deep link, desktop opens its desktop app. link and desktop need an agent that has one (built in: Claude Code has both, Codex has the desktop app); an agent you define has neither, and `rh config validate` warns when one is asked for.",
                           default: "\"terminal\"", allowed: AgentLauncher.configNames),
                SchemaNode("terminal", .string, "Terminal for launcher = \"terminal\". Omit it to use general.terminal.", suggested: terminalIDs),
                SchemaNode("prompt_arg", .string,
                           "How the command takes a first prompt, which prompt presets (`[[preset]]`) need: \"positional\" for `tool \"prompt\"`, or the flag that carries it, such as \"--prompt\". Claude Code and Codex are built in as positional; presets are not offered for an agent that is not known to take a prompt.",
                           example: "\"positional\" or \"--prompt\"", pattern: PromptArgument.pattern),
                SchemaNode("bypass_permissions", .boolean,
                           "Whether to launch this agent with flags that bypass tool confirmation prompts (e.g. --dangerously-skip-permissions for Claude/Antigravity, --dangerously-bypass-approvals-and-sandbox for Codex, -y for Gemini, --auto-approve for Kimi/Muse). Overrides general.bypass_permissions."),
                SchemaNode("bypass_permission_arg", .string,
                           "Custom flag or argument to bypass confirmation prompts for this agent, overriding the built-in default.",
                           example: "\"--dangerously-skip-permissions\""),
                SchemaNode("args", .stringArray,
                           "Additional arguments typed when launching this agent.",
                           example: "[\"--verbose\"]"),
                SchemaNode("variant", .tableArray, "Extra start options shown in the agent's submenu.", required: ["id", "title"], children: [
                    SchemaNode("id", .string, "Identifier used in `agent.<agent>.<id>`; lowercase letters, digits and dashes.",
                               example: "\"opus\"", pattern: identifierPattern),
                    SchemaNode("title", .string, "Menu title, on one line.", example: "\"Use Opus\"", pattern: displayNamePattern),
                    SchemaNode("arguments", .stringArray, "Each element is one argument, quoted for the shell when it needs it and typed bare when it does not. An argument with a backslash is refused; put such text in `command`, which is typed as written and may contain arguments.", example: "[\"--model\", \"opus\"]")
                ])
            ]),
            SchemaNode("preset", .tableArray,
                       "Prompt presets: a prompt sent to an agent together with the selected files, from the \"Agent Presets\" submenu or `rh run preset.<id>`. The prompt is typed into a terminal as the agent's first argument, so the agent starts working on it at once (it is not left in the prompt box; for that use `agent.claude@link`). Defining a preset under the id of a built-in one (review, explain, tests) replaces it. Built-in prompts only ask the agent not to change files; whether it obeys is up to the agent and its permission settings.",
                       required: ["id", "title", "prompt"], children: [
                SchemaNode("id", .string, "Identifier used in the action id `preset.<id>`; lowercase letters, digits and dashes.",
                           example: "\"review\"", pattern: identifierPattern),
                SchemaNode("title", .string, "Menu title inside the Agent Presets submenu, on one line.", example: "\"Review\"", pattern: displayNamePattern),
                SchemaNode("agent", .string,
                           "Agent that runs it: a built-in agent or one defined under `[agent.<id>]`, which must take a first prompt (see agent.prompt_arg). Omit it to use the first agent in general.agents.",
                           example: "\"claude\"", suggested: KnownAgents.all.map(\.id)),
                SchemaNode("prompt", .string,
                           "The prompt, on one line. `{files}` is the selected files as @-mentions relative to the folder, separated by spaces (a preset that uses it needs files selected); `{folder}` is the folder's name; `{name}` is the name of the first selected item (the folder's name when nothing is selected). It may not hold a line break or other control character, a backslash, or start with a dash.",
                           example: "\"Review {files} for bugs. Do not modify any files.\""),
                SchemaNode("max_files", .integer,
                           "Most files one run may name (1 to 50); more is refused, never cut short.",
                           default: String(AgentPreset.defaultMaxFiles))
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
            "`rh config show` prints each file that makes up the config under a header line that names it (`config.toml`, then",
            "`config.local.toml`, the per-machine overlay, when it exists), and `rh config path --all` lists their paths: the",
            "config is those files read in that order, and there is no merged text to print.",
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
