import Foundation

/// Built-in documentation, printed by `rh docs` and served by the MCP server.
public enum Documentation {
    public static let actions = """
    # Action ids

    `rh run <id>` runs an action. `rh actions` lists the ones available on this machine.

        copy-path.<style>              copy the path of the selection (or the folder)
                                       styles: \(PathStyle.allCases.map(\.rawValue).joined(separator: ", "))
        open.terminal[@<terminal>]     open the folder in the default terminal, or in <terminal>
        open.editor                    open the selection in the default editor
        open.app.<app>                 open the selection with any app (see `rh apps`)
        agent.<agent>[.<variant>][@<launcher>]
                                       start an AI agent in the folder (see `rh agents`)
                                       launcher: a terminal id, "default" (the default terminal),
                                       "link" (the agent's own terminal deep link, reuses its
                                       last terminal) or "desktop" (its desktop app)
        new-file.<template>            create an empty file next to the selection or in the folder
        reveal                         select the items in Finder

    Examples:

        rh run copy-path.git-relative src/main.swift
        rh run agent.claude.continue@ghostty ~/code/project
        rh run agent.codex@desktop ~/code/project
        rh run new-file.md --container ~/notes

    Add --dry-run to see the plan without running it, and --json for machine-readable output.

    `rh actions` marks an action available when it can run on this machine (the terminal or app is
    installed, the terminal can run commands). It does not check that an agent's own command is
    installed: `rh agents` shows which agent commands your login shell finds.
    """

    public static let agentSetup = """
    # Setting up Right Here (for AI agents)

    Goal: leave the person with a working Finder menu without making them click through settings.

    1. Run `rh doctor --json`. Fix every entry whose status is "fail" using its "fix" text. Entries with
       status "needs-user" are things only the person can do (for example switching a Finder extension on
       in System Settings); tell them exactly what the entry says.
    2. Run `rh init` if there is no config file, then read it. It is TOML with comments.
    3. Edit `config.toml` to match what the person asked for. `rh docs config` lists every key.
       Prefer small edits; never delete the person's comments.
    4. Run `rh config validate --json --strict`. Fix every error and every warning: an unknown key is
       only a warning because the rest of the file still applies, but it is almost always a typo, and
       whatever it was meant to set is then silently missing. The `replacement` field of a diagnostic
       is the likely fix. `--strict` exits with status 1 until the file is clean.
    5. Run `rh menu --container <a folder>` to preview the menu and confirm it matches the request.
    6. To test an action without side effects, use `rh run <action> --dry-run --json`.
    7. The Finder menu reads the config each time it opens, so menu edits take effect at once. Quick
       Actions (Services) are files written by `rh install --services`: run it after changing
       `[services]` or the menu titles, and check `rh doctor` afterwards.
    8. Only if the person wants agents to start in a terminal, and agrees to a window opening and closing for
       a second, run `rh doctor --probe-launch`: the Finder extension starts a throwaway terminal session
       and proves a typed command runs there. The first time, macOS asks whether Right Here may control
       the terminal; tell the person to click Allow and run it again if it reports "needs-user".

    Rules of thumb:
    - Agents start in the folder that was right-clicked. The command typed is the agent's own command, so
      the person's PATH, version managers and aliases apply.
    - Paths with line breaks or control characters are refused for typed launches.
    - Use ids from `rh actions`; `rh docs actions` explains the grammar.
    - When something does not work (no menu, a click that does nothing, a permission prompt), read
      `rh docs troubleshooting` before guessing.
    """

    public static let config = ConfigSchema.markdown()

    /// The topics, in the order they are listed, with a one-line summary each. Every surface that names topics
    /// (`rh docs`, the MCP docs tool) takes them from here.
    public static let topicSummaries: [(name: String, summary: String)] = [
        ("config", "every setting in config.toml, with defaults and examples"),
        ("actions", "the action id grammar"),
        ("agent-setup", "how an AI agent should set up Right Here"),
        ("troubleshooting", "the menu does not appear, a click does nothing, permission prompts")
    ]

    public static let topics = topicSummaries.map(\.name)

    /// The topic list `rh docs` prints without an argument.
    public static var listing: String {
        "Topics:\n" + topicSummaries.map { "  " + $0.name.padding(toLength: 17, withPad: " ", startingAt: 0) + $0.summary }.joined(separator: "\n")
    }

    /// The topic a mistyped word most likely meant.
    public static func closestTopic(to word: String) -> String? {
        let word = word.lowercased()
        return topics.first { !word.isEmpty && ($0.hasPrefix(word) || word.hasPrefix($0)) }
    }

    public static func text(for topic: String) -> String? {
        switch topic {
        case "config": return config
        case "actions": return actions
        case "agent-setup": return agentSetup
        default: return guides[topic]
        }
    }
}
