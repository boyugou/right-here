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
            Output.print(Documentation.config)
        case "actions"?:
            Output.print(Documentation.actions)
        case "agent-setup"?:
            Output.print(Documentation.agentSetup)
        default:
            throw ValidationError("Unknown topic \"\(topic ?? "")\". Run `rh docs` to list them.")
        }
    }
}
