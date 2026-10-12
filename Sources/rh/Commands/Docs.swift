import ArgumentParser
import Foundation
import RightHereCore

struct Docs: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print built-in documentation.",
        discussion: """
        Topics: config (every setting), actions (the action id grammar), agent-setup (how an AI agent \
        should configure Right Here for a person), troubleshooting (the menu does not appear, a click does \
        nothing, permission prompts). The text is meant to be read by people and by AI agents.
        """
    )

    @Argument(help: "config, actions, agent-setup or troubleshooting. Without a topic, the topics are listed.")
    var topic: String?

    func run() throws {
        guard let topic else {
            Output.print("""
            Topics:
              config           every setting in config.toml, with defaults and examples
              actions          the action id grammar
              agent-setup      how an AI agent should set up Right Here
              troubleshooting  the menu does not appear, a click does nothing, permission prompts
            """)
            return
        }
        guard let text = Documentation.text(for: topic) else {
            throw ValidationError("Unknown topic \"\(topic)\". Run `rh docs` to list them.")
        }
        Output.print(text)
    }
}
