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

    /// A name or title shown to people: no line break or other control character (`ShellQuoting.containsControlCharacter`), and none of the characters that make it read as something else than it
    /// says (`ConfigBuilder.changesHowTextReads`: a direction override, embedding or isolate, a zero-width space, a word joiner, a byte order mark, a soft hyphen), nor the invisible operators, the
    /// deprecated format characters and the marks and letters that Unicode shows as nothing (U+034F, U+17B4, U+3164...), which `hasMisleadingCharacter` refuses. The Unicode tag characters,
    /// which are past the plane that a pattern of every consumer of a JSON schema can name, are refused by the parser alone.
    static let displayNamePattern = "^[^\\u0000-\\u001f\\u007f-\\u009f\\u00ad\\u034f\\u115f\\u1160\\u17b4\\u17b5\\u200b\\u2028\\u2029\\u202a-\\u202e\\u2060-\\u2064\\u2066-\\u206f\\u3164\\ufeff\\uffa0]*$"

    /// The flag that switches an agent's permission prompts off, as a config gives it: words of letters, digits and `- _ = . : / @ + ,` separated by spaces. It is typed into the shell, so what a shell
    /// reads as more (`;`, `|`, `&`, `$`, quotes, brackets, a backtick) is not allowed in it.
    static let bypassFlagPattern = "^[A-Za-z0-9._=:/@+,-]+( [A-Za-z0-9._=:/@+,-]+)*$"

    /// A file extension: not empty, no dot or slash, and none of what a display name refuses (it becomes part of a file name that Finder shows, so it must not read as something else).
    static let fileExtensionPattern = "^[^./\\u0000-\\u001f\\u007f-\\u009f\\u00ad\\u034f\\u115f\\u1160\\u17b4\\u17b5\\u200b\\u2028\\u2029\\u202a-\\u202e\\u2060-\\u2064\\u2066-\\u206f\\u3164\\ufeff\\uffa0]+$"

    public static var root: [SchemaNode] {
        let terminalIDs = KnownApps.terminals.map(\.id)
        let editorIDs = KnownApps.editors.map(\.id)
        return [
            SchemaNode("version", .integer, "The version of the config format. Only 1 exists.", default: "1", allowed: ["1"]),
            SchemaNode("disabled", .stringArray,
                       "Only for config.local.toml, the settings of this Mac only: the ids of apps (also built-in ones), New File templates and agents to remove on this Mac. Right Here also removes their entries in general.agents, menu.items and services.items, and the presets that use a disabled agent. In config.toml it does nothing, and Right Here reports it.",
                       example: "[\"zed\", \"codex\"]"),
            SchemaNode("general", .table, "Defaults for the actions.", children: [
                SchemaNode("terminal", .string,
                           "The terminal for \"open in terminal\" and for agents. Leave it out to use the first installed terminal. If the named app is not installed, Right Here uses the first installed one, and the doctor says so.",
                           example: "\"ghostty\"; known: " + terminalIDs.joined(separator: ", "), suggested: terminalIDs),
                SchemaNode("editor", .string,
                           "The editor for \"open in editor\". Leave it out to use the first installed editor. If the named app is not installed, Right Here uses the first installed one, and the doctor says so.",
                           example: "\"vscode\"; known: " + editorIDs.joined(separator: ", "), suggested: editorIDs),
                SchemaNode("terminal_placement", .string,
                           "Where a terminal session starts: \"window\", \"tab\", \"split-right\" or \"split-down\". Tabs and splits work in Ghostty and iTerm; Warp opens a tab, and a window for a split. Terminal.app always opens a window. In Ghostty and iTerm a tab or a split needs the permission to control the terminal, which a plain \"open in terminal\" does not need.",
                           default: "\"window\"", allowed: TerminalPlacement.configNames),
                SchemaNode("language", .string,
                           "The language of the Finder menu, the setup window, the alerts and the names of the Quick Actions. Leave it out to follow the language of macOS. The command line and the MCP server stay in English.",
                           allowed: Localizer.supportedLanguages, example: "\"zh-Hans\""),
                SchemaNode("bypass_permissions", .boolean,
                           "Whether AI agents start with the flag that turns off their permission prompts. Each agent can override it under [agent.<id>].",
                           default: "false"),
                SchemaNode("agents", .stringArray,
                           "The agents that the menu offers, in order. `rh setup` fills this list with the agents that it finds, or with the ones that you name with --agents.",
                           example: "[\"claude\", \"codex\"]; built in: " + KnownAgents.all.map(\.id).joined(separator: ", "),
                           suggested: KnownAgents.all.map(\.id))
            ]),
            SchemaNode("menu", .table, "The Finder menu.", children: [
                SchemaNode("items", .stringArray,
                           "The entries, in order. \"-\" is a separator. Any action id from `rh actions` also works. The groups are "
                           + "open-terminal (open in the default terminal), open-editor (open in the default editor), "
                           + "open-with (a submenu of every other installed terminal and editor), agents (one entry for each enabled agent), "
                           + "agents-more (a submenu of the start options, links and other terminals of each agent), "
                           + "new-file (the templates), copy-path (the forms of the path) and "
                           + "presets (a submenu of the prompt presets, which are inside agents-more when the list does not name presets).",
                           default: "[\"open-terminal\", \"open-editor\", \"open-with\", \"agents\", \"agents-more\", \"-\", \"new-file\", \"copy-path\"]",
                           suggested: Array(MenuBuilder.groups).sorted() + ["-"])
            ]),
            SchemaNode("services", .table, "The Quick Actions, which `rh setup` installs.", children: [
                SchemaNode("items", .stringArray,
                           "The action ids to offer. By default: open in the terminal and in the editor, each enabled agent, a new Markdown file, and two forms of the path (full, and from the git root).",
                           example: "[\"open.terminal\", \"agent.claude\", \"copy-path.absolute\"]")
            ]),
            SchemaNode("copy_path", .table, "The \"Copy Path\" submenu.", children: [
                SchemaNode("title", .string, "Your own title for the Copy Path entry or submenu, on one line. If the menu lists the full path on its own, the title is on that entry. The default is \"Copy Path\" in the language of the menu (general.language, or the Mac's).",
                           example: "\"Copy Path\"", pattern: displayNamePattern),
                SchemaNode("styles", .stringArray, "The forms that the menu offers, in order.",
                           default: "[\"absolute\", \"tilde\", \"git-relative\", \"name\", \"shell-escaped\", \"ai-mention\"]",
                           allowed: PathStyle.allCases.map(\.rawValue))
            ]),
            SchemaNode("new_file", .table, "The New File action.", children: [
                SchemaNode("then", .string,
                           "What happens after Right Here makes the file. reveal selects it in Finder. open opens it in the default editor (general.editor). nothing does nothing. If no editor is installed, Finder selects the file instead.",
                           default: "\"reveal\"", allowed: Config.AfterNewFile.allCases.map(\.rawValue)),
                SchemaNode("hidden", .stringArray,
                           "Templates, by id, that the New File submenu leaves out. Each one is still an action of its own (`rh run new-file.<id>`), and a line of the menu can name it.",
                           example: "[\"pptx\"]"),
                SchemaNode("template", .tableArray, "File templates. If you define one, your templates replace the built-in ones (txt, md, docx, xlsx and pptx).",
                           required: ["id", "title", "extension"], children: [
                    SchemaNode("id", .string, "The id in the action id `new-file.<id>`: lowercase letters, digits and dashes.",
                               example: "\"md\"", pattern: identifierPattern),
                    SchemaNode("title", .string,
                               "The name of the kind of document, on one line. The menu shows it as it is inside the New File submenu, and as \"New <title>\" when it stands alone.",
                               example: "\"Markdown Document\"", pattern: displayNamePattern),
                    SchemaNode("base_name", .string, "The file name without the extension, on one line. If the name is taken, Right Here adds a number.", default: "\"untitled\"", pattern: displayNamePattern),
                    SchemaNode("extension", .string, "The file extension, without the dot. It cannot contain a slash.", example: "\"md\"", pattern: fileExtensionPattern),
                    SchemaNode("contents", .string, "The text that the new file starts with.", default: "\"\""),
                    SchemaNode("format", .string,
                               "Makes the file a blank document of this Office format instead of a text: docx (Word), xlsx (Excel) or pptx (PowerPoint). The extension must be the same, and contents must be empty.",
                               allowed: OfficeFormat.allCases.map(\.rawValue)),
                    SchemaNode("open_with", .string,
                               "The app id (`rh apps` lists them) that opens this kind of file after Right Here makes it, if new_file.then is \"open\". If this app is not installed, the default editor opens the file. If no editor is installed, Finder selects the file instead.",
                               example: "\"typora\"")
                ])
            ]),
            SchemaNode("app", .tableArray,
                       "Apps that open folders and files, in addition to the built-in apps. An entry with the id of a built-in app replaces it.",
                       required: ["id", "name"], oneOfRequired: ["bundle_id", "bundle_ids"], children: [
                SchemaNode("id", .string, "The id in `open.app.<id>`: lowercase letters, digits and dashes. It cannot be `link`, `desktop` or `default`, because these words name a launcher after the `@` of `agent.<agent>@<word>`.",
                           example: "\"tower\"", pattern: appIdentifierPattern),
                SchemaNode("name", .string, "The name that people see, on one line.", example: "\"Tower\"", pattern: displayNamePattern),
                SchemaNode("bundle_id", .string, "The bundle identifier of the app.", example: "\"com.fournova.Tower3\""),
                SchemaNode("bundle_ids", .stringArray, "Several bundle identifiers, the preferred one first. Use it instead of bundle_id."),
                SchemaNode("role", .string, "terminal: the app opens a folder. editor and general: the app opens the selection.",
                           default: "\"general\"", allowed: AppDescriptor.Role.allCases.map(\.rawValue)),
                SchemaNode("open_args", .stringArray,
                           "Terminals only. The program and the arguments that open a folder, instead of giving the folder to the app. Right Here replaces `{dir}`, `{shell}` and `{app}` (the installed .app) inside each element. The first element must be an absolute path, or start with `{app}/`. Start the app through `/usr/bin/open -n -b <bundle id> --args ...`. The binary of a terminal keeps running while its window is open, and `rh run` would wait for it (the MCP server stops it after two minutes). Never put `{dir}` inside a string that a shell reads. Give it as an argument of its own.",
                           example: "[\"/usr/bin/open\", \"-n\", \"-b\", \"org.alacritty\", \"--args\", \"--working-directory\", \"{dir}\"]"),
                SchemaNode("run_args", .stringArray,
                           "Terminals only. The program and the arguments that start a typed command (an agent) in a folder. With them, a terminal without a built-in adapter can start agents. The rules of `open_args` apply, and `{command}` must appear. Right Here did not check them on your terminal. Try them with `rh run agent.claude@<id> --dry-run` first.",
                           example: "[\"/usr/bin/open\", \"-n\", \"-b\", \"org.alacritty\", \"--args\", \"--working-directory\", \"{dir}\", \"-e\", \"{shell}\", \"-lic\", \"{command}; exec {shell} -l\"]")
            ]),
            SchemaNode("agent", .tableMap, "AI agents, one table for each agent: `[agent.claude]`. `rh agents` lists the built-in agents. Any command that you want typed into a terminal in the folder works in the same way. For example: `[agent.lazygit]` with `name = \"lazygit\"` and `command = \"lazygit\"`. `rh config add agent.lazygit name=lazygit command=lazygit` makes it and puts it in general.agents. `rh config remove agent.lazygit` takes it out again.",
                       pattern: identifierPattern, children: [
                SchemaNode("name", .string, "The name that people see, on one line. An agent that is not built in needs it.", pattern: displayNamePattern),
                SchemaNode("command", .string, "What Right Here types into the shell to start the agent, with any flags.",
                           example: "\"claude --model opus\""),
                SchemaNode("launcher", .string,
                           "How the agent starts. terminal types the command into a terminal. link uses the agent's own link to a terminal. desktop opens the desktop app of the agent. link and desktop need an agent that has them: Claude Code has both, and Codex has the desktop app. An agent that you define has neither, and `rh config validate` warns if you ask for one.",
                           default: "\"terminal\"", allowed: AgentLauncher.configNames),
                SchemaNode("terminal", .string, "The terminal for launcher = \"terminal\". Leave it out to use general.terminal.", suggested: terminalIDs),
                SchemaNode("prompt_arg", .string,
                           "How the command takes a first prompt that starts an interactive session. Prompt presets (`[[preset]]`) need it. \"positional\" means `tool \"prompt\"`. Or give the flag that carries the prompt, such as \"-i\". It is built in for Claude Code, Codex, Cursor CLI, Factory Droid and Kiro CLI (positional), and for Antigravity, Gemini CLI, Qwen Code and GitHub Copilot (-i). Right Here offers no preset for an agent that is not known to take a prompt. Do not give a flag that runs once and exits (-p or --print in most tools).",
                           example: "\"positional\" or \"--prompt\"", pattern: PromptArgument.pattern),
                SchemaNode("bypass_permissions", .boolean,
                           "Whether this agent starts with the flag that turns off its permission prompts. The flags are --dangerously-skip-permissions for Claude Code and Antigravity, --dangerously-bypass-approvals-and-sandbox for Codex (it also turns off its sandbox), --approval-mode=yolo for Gemini CLI, --force for Cursor CLI, --yolo for Qwen Code and Kimi Code, --trust-all-tools for Kiro CLI, --auto for opencode, --allow-all for GitHub Copilot and --yes-always for aider. Factory Droid, Goose, Muse Code and Amp have no built-in flag: set bypass_permission_arg. The flags of Claude Code, Codex and Antigravity come from the --help of each tool, and the others from the documentation of each tool (ADR 0024). So check a flag with `rh run agent.<id> --bypass-permissions --dry-run` and with the help of the tool. This setting overrides general.bypass_permissions."),
                SchemaNode("bypass_permission_arg", .string,
                           "Your own flag or argument that turns off the permission prompts of this agent. It overrides the built-in flag. Use words of letters, digits and - _ = . : / @ + , separated by spaces. Right Here types it into the shell, so nothing that a shell reads as more than a flag is allowed.",
                           example: "\"--dangerously-skip-permissions\"", pattern: bypassFlagPattern),
                SchemaNode("args", .stringArray,
                           "More arguments that Right Here types after the command of this agent.",
                           example: "[\"--verbose\"]"),
                SchemaNode("variant", .tableArray, "More start options, in the submenu of the agent.", required: ["id", "title"], children: [
                    SchemaNode("id", .string, "The id in `agent.<agent>.<id>`: lowercase letters, digits and dashes.",
                               example: "\"opus\"", pattern: identifierPattern),
                    SchemaNode("title", .string, "The title in the menu, on one line.", example: "\"Use Opus\"", pattern: displayNamePattern),
                    SchemaNode("arguments", .stringArray, "Each element is one argument. Right Here quotes an argument for the shell when it needs quotes. It refuses an argument with a backslash. Put such text in `command`, which Right Here types as it is written, and which can contain arguments.", example: "[\"--model\", \"opus\"]")
                ])
            ]),
            SchemaNode("preset", .tableArray,
                       "Prompt presets. A preset sends a prompt to an agent with the selected files, from the \"Agent Presets\" submenu or with `rh run preset.<id>`. Right Here types the prompt into a terminal as the first argument of the agent, so the agent starts to work on it at once. To leave a prompt in the prompt box instead, use `agent.claude@link`. A preset with the id of a built-in one (review, explain, tests) replaces it. The built-in prompts only ask the agent not to change files. The agent and its permission settings decide whether it obeys.",
                       required: ["id", "title", "prompt"], children: [
                SchemaNode("id", .string, "The id in the action id `preset.<id>`: lowercase letters, digits and dashes.",
                           example: "\"review\"", pattern: identifierPattern),
                SchemaNode("title", .string, "The title inside the Agent Presets submenu, on one line.", example: "\"Review\"", pattern: displayNamePattern),
                SchemaNode("agent", .string,
                           "The agent that runs the preset: a built-in agent, or one under `[agent.<id>]`. It must take a first prompt (see agent.prompt_arg). Leave it out to use the first agent in general.agents.",
                           example: "\"claude\"", suggested: KnownAgents.all.map(\.id)),
                SchemaNode("prompt", .string,
                           "The prompt, on one line. `{files}` is the selected files as @ mentions from the folder, separated by spaces. A preset that uses it needs selected files. `{folder}` is the name of the folder. `{name}` is the name of the first selected item, or the name of the folder when nothing is selected. The prompt cannot contain a line break, another control character or a backslash, and it cannot start with a dash.",
                           example: "\"Review {files} for bugs. Do not modify any files.\""),
                SchemaNode("max_files", .integer,
                           "The largest number of files that one run can name, from 1 to 50. Right Here refuses more, and never cuts the list short.",
                           default: String(AgentPreset.defaultMaxFiles))
            ])
        ]
    }

    // MARK: Documentation

    /// Markdown reference for the config file, printed by `rh docs config`.
    public static func markdown() -> String {
        var lines = [
            "# Config reference", "",
            "File: `~/.config/right-here/config.toml`. Format: TOML.", "",
            "Right Here looks for the file in these places, and uses the first match:", "",
            "1. `RH_CONFIG`: the file itself.",
            "2. `RH_CONFIG_DIR`: its folder.",
            "3. `$XDG_CONFIG_HOME/right-here/`.",
            "4. `~/.config/right-here/`.", "",
            "`RH_LOG_DIR` moves the log folder (default `~/Library/Logs/right-here`). `RH_HOME` points every path of the user at",
            "another folder, to try an install without a change to your own folders. If `RH_CONFIG`, `RH_CONFIG_DIR`, `RH_LOG_DIR`",
            "or `RH_HOME` is set to nothing, `rh` stops with status 64. Empty never means \"not set\": a shell variable that is not",
            "set expands to nothing, and `RH_HOME=$TRIAL rh setup` would then change your own folders.", "",
            "- `rh config validate` checks the file. Add `--strict` to fail on warnings too.",
            "- `rh menu` prints the menu that the config makes.",
            "- `rh config show` prints each file of the config under a line with its name: `config.toml`, then `config.local.toml`",
            "  (the settings of this Mac only) when it exists. `rh config path --all` lists their paths. Right Here reads the files",
            "  in that order, and there is no merged text to print.",
            "- A key that Right Here does not know is a warning, not an error, so the rest of the file still applies. Such a key is",
            "  almost always a typo, so treat warnings as problems.", ""
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
