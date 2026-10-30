import Foundation

/// What `rh setup` found on the machine, or what the person said.
public struct DetectedEnvironment: Sendable, Equatable {
    public var terminal: String?
    public var editor: String?
    public var agents: [String]

    public init(terminal: String? = nil, editor: String? = nil, agents: [String] = []) {
        self.terminal = terminal
        self.editor = editor
        self.agents = agents
    }
}

public enum ConfigTemplate {
    /// The text of a fresh config file: what was detected is set, everything else is a commented example.
    public static func render(_ detected: DetectedEnvironment) -> String {
        func line(_ key: String, _ value: String?, example: String) -> String {
            value.map { "\(key) = \"\($0)\"" } ?? "# \(key) = \"\(example)\""
        }
        let terminals = KnownApps.terminals.map(\.id).joined(separator: ", ")
        let editors = KnownApps.editors.prefix(8).map(\.id).joined(separator: ", ")
        let agents = detected.agents.isEmpty ? "# agents = [\"claude\", \"codex\"]" : "agents = [" + detected.agents.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
        let menu = MenuBuilder.defaultItems.map { "\"\($0)\"" }.joined(separator: ", ")
        let styles = Config.defaultCopyPathStyles.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")

        return """
        # Right Here configuration. This file is yours: edit it by hand or ask an AI agent to.
        #   rh config validate   check this file
        #   rh docs config       every setting, with examples
        #   rh menu              preview the Finder menu this file produces
        version = 1

        [general]
        # Terminal for "Open in Terminal" and for agents. Known: \(terminals)
        \(line("terminal", detected.terminal, example: "ghostty"))
        # Editor for "Open in Editor". Known: \(editors), and more (rh apps)
        \(line("editor", detected.editor, example: "vscode"))
        # Agents offered in the menu. Known: \(KnownAgents.all.map(\.id).joined(separator: ", "))
        \(agents)

        # The Finder menu, in order. "-" is a separator.
        # [menu]
        # items = [\(menu)]

        # Where a terminal session starts: "window" (default), "tab", "split-right", or "split-down" (Ghostty & iTerm).
        # To change it, add this line to the [general] table above (it does not belong under the tables below):
        #   terminal_placement = "tab"
        # The language of the Finder menu, the setup window, the alerts and the Quick Actions (leave it out to follow macOS):
        #   language = "zh-Hans"

        # Forms offered under "Copy Path".
        # [copy_path]
        # styles = [\(styles)]

        # New files. then = "open" opens the file after creating it; a template can name the app that opens it.
        # Defining any template replaces the built-in Text and Markdown ones, so list the ones you want.
        # [new_file]
        # then = "open"
        # [[new_file.template]]
        # id = "md"
        # title = "Markdown Document"
        # extension = "md"
        # open_with = "typora"

        # An agent can start another way: launcher = "terminal" (default), "link" or "desktop" (the last two only for
        # built-in agents that have a deep link or a desktop app: Claude Code, Codex).
        # [agent.claude]
        # launcher = "terminal"
        # command = "claude"

        # Prompt presets (Agent Presets in the menu: review, explain, tests are built in). The prompt is typed as the
        # agent's first argument, so the agent starts on it at once. {files} = the selected files as @-mentions.
        # [[preset]]
        # id = "lint"
        # title = "Check Style"
        # prompt = "Check {files} for style problems. Do not modify any files."

        """
    }
}
