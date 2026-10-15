import ArgumentParser
import Foundation
import RightHereKit
import RightHereMCP

struct MCP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Run the MCP server for AI agents (standard input and output).",
        discussion: """
        Point an MCP client at this command. In Claude Code:

          claude mcp add right-here -- rh mcp

        The server offers the same actions as `rh`, as tools: `rh docs mcp` lists them, with the framing and the setup for other clients.
        """
    )

    func run() async {
        await MCPServer().serve()
    }
}

struct FinderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "finder",
        abstract: "Ask Finder what is selected.",
        subcommands: [Selection.self]
    )

    struct Selection: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the selected items and the folder of the frontmost Finder window as JSON.",
            discussion: "The first run makes macOS ask whether the app you ran rh from may control Finder."
        )

        func run() async throws {
            do {
                try Output.json(try await FinderQuery().current())
            } catch {
                throw Output.fail("error: " + error.localizedDescription)
            }
        }
    }
}
