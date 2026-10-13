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
            Output.print(Documentation.listing)
            return
        }
        guard let text = Documentation.text(for: topic) else {
            let close = Documentation.closestTopic(to: topic)
            throw ValidationError("Unknown topic \"\(topic)\".\(close.map { " Did you mean \"\($0)\"?" } ?? "") Run `rh docs` to list them.")
        }
        Output.print(text)
    }
}
