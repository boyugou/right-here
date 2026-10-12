import ArgumentParser
import Foundation
import RightHereCore

struct Docs: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print built-in documentation.",
        discussion: """
        Topics: config (every setting), actions (the action id grammar), agent-setup (how an AI agent \
        should configure Right Here for a person). The text is meant to be read by people and by AI agents.
        """
    )

    @Argument(help: "config, actions or agent-setup. Without a topic, the topics are listed.")
    var topic: String?

    func run() throws {
        switch topic {
        case nil:
            Output.print("Topics:\n  config       every setting in config.toml, with defaults and examples\n  actions      the action id grammar\n  agent-setup  how an AI agent should set up Right Here")
        case "config"?:
            Output.print(ConfigSchema.markdown())
        case "actions"?:
            Output.print(Self.actionsDoc)
        case "agent-setup"?:
            Output.print(Self.agentSetupDoc)
        default:
            throw ValidationError("Unknown topic \"\(topic ?? "")\". Run `rh docs` to list them.")
        }
    }

    static let actionsDoc = """
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
    """

    static let agentSetupDoc = """
    # Setting up Right Here (for AI agents)

    Goal: leave the person with a working Finder menu without making them click through settings.

    1. Run `rh doctor --json`. Fix every entry whose status is "fail" using its "fix" text. Entries with
       status "needs-user" are things only the person can do (for example switching a Finder extension on
       in System Settings); tell them exactly what the entry says.
    2. Run `rh init` if there is no config file, then read it. It is TOML with comments.
    3. Edit `config.toml` to match what the person asked for. `rh docs config` lists every key.
       Prefer small edits; never delete the person's comments.
    4. Run `rh config validate --json`. Fix every error. Unknown-key warnings usually carry a suggestion.
    5. Run `rh menu` to preview the menu and confirm it matches the request.
    6. To test an action without side effects, use `rh run <action> --dry-run`.

    Rules of thumb:
    - Agents start in the folder that was right-clicked. The command typed is the agent's own command, so
      the person's PATH, version managers and aliases apply.
    - Paths with line breaks or control characters are refused for typed launches.
    - Use ids from `rh actions`; `rh docs actions` explains the grammar.
    """
}
