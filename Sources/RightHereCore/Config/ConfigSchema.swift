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

    public init(
        _ key: String,
        _ kind: Kind,
        _ summary: String,
        default defaultValue: String? = nil,
        allowed: [String]? = nil,
        example: String? = nil,
        children: [SchemaNode] = []
    ) {
        self.key = key
        self.kind = kind
        self.summary = summary
        self.defaultValue = defaultValue
        self.allowedValues = allowed
        self.example = example
        self.children = children
    }

    public func child(_ key: String) -> SchemaNode? {
        children.first { $0.key == key }
    }
}

public enum ConfigSchema {
    public static let version = 1

    public static var root: [SchemaNode] {
        let terminalIDs = KnownApps.terminals.map(\.id)
        let editorIDs = KnownApps.editors.map(\.id)
        return [
            SchemaNode("version", .integer, "Config format version. Only 1 exists.", default: "1"),
            SchemaNode("general", .table, "Defaults used by actions.", children: [
                SchemaNode("terminal", .string,
                           "Terminal used by \"open in terminal\" and by agents. Omit it to use the first installed one.",
                           example: "\"ghostty\"; known: " + terminalIDs.joined(separator: ", ")),
                SchemaNode("editor", .string,
                           "Editor used by \"open in editor\". Omit it to use the first installed one.",
                           example: "\"vscode\"; known: " + editorIDs.joined(separator: ", ")),
                SchemaNode("agents", .stringArray,
                           "Agents offered in the menu, in order. `rh init` fills this with the agents it finds.",
                           example: "[\"claude\", \"codex\"]; built in: " + KnownAgents.all.map(\.id).joined(separator: ", "))
            ]),
            SchemaNode("menu", .table, "The Finder context menu.", children: [
                SchemaNode("items", .stringArray,
                           "Entries in order. Groups: open-terminal, open-editor, open-with, agents, agents-more, new-file, copy-path. \"-\" is a separator. Any action id from `rh actions` also works.",
                           default: "[\"open-terminal\", \"open-editor\", \"agents\", \"agents-more\", \"-\", \"new-file\", \"copy-path\"]")
            ]),
            SchemaNode("copy_path", .table, "The \"Copy Path\" submenu.", children: [
                SchemaNode("styles", .stringArray, "Forms offered, in order.",
                           default: "[\"absolute\", \"tilde\", \"git-relative\", \"name\", \"shell-escaped\", \"ai-mention\"]",
                           example: "any of: " + PathStyle.allCases.map(\.rawValue).joined(separator: ", "))
            ]),
            SchemaNode("new_file", .table, "The \"new file\" action.", children: [
                SchemaNode("then", .string, "What happens after the file is created.",
                           default: "\"reveal\"", allowed: Config.AfterNewFile.allCases.map(\.rawValue)),
                SchemaNode("template", .tableArray, "File templates. Defining any replaces the built-in txt and md.", children: [
                    SchemaNode("id", .string, "Identifier used in the action id `new-file.<id>`.", example: "\"md\""),
                    SchemaNode("title", .string, "Menu title.", example: "\"Markdown Document\""),
                    SchemaNode("base_name", .string, "File name without extension; numbered on collision.", default: "\"untitled\""),
                    SchemaNode("extension", .string, "File extension without the dot.", example: "\"md\""),
                    SchemaNode("contents", .string, "Initial contents.", default: "\"\"")
                ])
            ]),
            SchemaNode("app", .tableArray, "Applications to open folders and files with, in addition to the built-in ones.", children: [
                SchemaNode("id", .string, "Identifier used in `open.app.<id>`; lowercase letters, digits and dashes.", example: "\"tower\""),
                SchemaNode("name", .string, "Display name.", example: "\"Tower\""),
                SchemaNode("bundle_id", .string, "Bundle identifier of the app.", example: "\"com.fournova.Tower3\""),
                SchemaNode("bundle_ids", .stringArray, "Several bundle identifiers, most preferred first. Use instead of bundle_id."),
                SchemaNode("role", .string, "terminal: opens a folder; editor and general: open the selection.",
                           default: "\"general\"", allowed: AppDescriptor.Role.allCases.map(\.rawValue))
            ]),
            SchemaNode("agent", .tableMap, "AI agents, one table per agent: `[agent.claude]`. Built-in agents are listed by `rh agents`.", children: [
                SchemaNode("name", .string, "Display name. Required for an agent that is not built in."),
                SchemaNode("command", .string, "What is typed into the shell to start the agent, including any flags.",
                           example: "\"claude --model opus\""),
                SchemaNode("launcher", .string,
                           "How the agent starts: terminal types the command into a terminal, link uses the agent's own terminal deep link, desktop opens its desktop app.",
                           default: "\"terminal\"", allowed: ["terminal", "link", "desktop"]),
                SchemaNode("terminal", .string, "Terminal for launcher = \"terminal\". Omit it to use general.terminal."),
                SchemaNode("variant", .tableArray, "Extra start options shown in the agent's submenu.", children: [
                    SchemaNode("id", .string, "Identifier used in `agent.<agent>.<id>`.", example: "\"opus\""),
                    SchemaNode("title", .string, "Menu title.", example: "\"Use Opus\""),
                    SchemaNode("arguments", .stringArray, "Arguments appended to the command.", example: "[\"--model\", \"opus\"]")
                ])
            ])
        ]
    }

    // MARK: Documentation

    /// Markdown reference for the config file, printed by `rh docs config`.
    public static func markdown() -> String {
        var lines = ["# Config reference", "",
                     "File: `~/.config/right-here/config.toml` (override with `RH_CONFIG`). Format: TOML.",
                     "Validate with `rh config validate`. Print the effective menu with `rh menu`.", ""]
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
                if let allowed = node.allowedValues { lines.append("  - one of: " + allowed.map { "`\($0)`" }.joined(separator: ", ")) }
                if let value = node.defaultValue { lines.append("  - default: `\(value)`") }
                if let example = node.example { lines.append("  - example: \(example)") }
                render(node.children, path: node.kind == .tableMap ? path + [node.key, "<id>"] : path + [node.key])
            }
        }
        render(root, path: [])
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: JSON Schema

    /// A JSON Schema (draft-07) describing the config, usable by TOML-aware editors.
    public static func jsonSchema() -> [String: Any] {
        func schema(for node: SchemaNode) -> [String: Any] {
            var result: [String: Any] = ["description": node.summary]
            switch node.kind {
            case .string:
                result["type"] = "string"
                if let allowed = node.allowedValues { result["enum"] = allowed }
            case .integer:
                result["type"] = "integer"
            case .boolean:
                result["type"] = "boolean"
            case .stringArray:
                result["type"] = "array"
                result["items"] = ["type": "string"]
            case .table:
                result.merge(objectSchema(node.children)) { $1 }
            case .tableArray:
                result["type"] = "array"
                result["items"] = objectSchema(node.children)
            case .tableMap:
                result["type"] = "object"
                result["additionalProperties"] = objectSchema(node.children)
            }
            return result
        }
        func objectSchema(_ nodes: [SchemaNode]) -> [String: Any] {
            [
                "type": "object",
                "additionalProperties": false,
                "properties": Dictionary(uniqueKeysWithValues: nodes.map { ($0.key, schema(for: $0)) })
            ]
        }
        var result = objectSchema(root)
        result["$schema"] = "http://json-schema.org/draft-07/schema#"
        result["title"] = "Right Here config"
        return result
    }
}
