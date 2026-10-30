import ArgumentParser
import Foundation
import RightHereCore
import RightHereMCP

struct Docs: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print built-in documentation.",
        discussion: """
        Topics, written for people and for AI agents: \(Documentation.topics.joined(separator: ", ")). Without a topic, they are listed \
        with what each covers. `start` is the place to begin.
        """
    )

    @Argument(help: "A topic, for example start or actions. Without one, the topics are listed.")
    var topic: String?

    func run() throws {
        guard let topic else {
            Output.print(Documentation.listing)
            return
        }
        guard let text = Guides.text(for: topic) else {
            let close = Documentation.closestTopic(to: topic)
            throw ValidationError("Unknown topic \"\(topic)\".\(close.map { " Did you mean \"\($0)\"?" } ?? "") Run `rh docs` to list them.")
        }
        Output.print(text)
    }
}
