import Foundation
import Testing
@testable import RightHereCore

@Suite("ActionRef")
struct ActionRefTests {
    @Test("canonical ids parse and print back unchanged", arguments: [
        "copy-path.absolute", "copy-path.git-relative", "copy-path.ai-mention",
        "open.terminal", "open.terminal@ghostty", "open.editor", "open.app.zed",
        "agent.claude", "agent.claude.continue", "agent.claude@ghostty", "agent.claude.continue@ghostty",
        "agent.codex@desktop", "agent.claude@link", "agent.claude@default", "agent.claude@terminal",
        "new-file.md", "reveal"
    ])
    func roundTrip(id: String) throws {
        let ref = try #require(ActionRef(parsing: id))
        #expect(ref.id == id)
    }

    @Test func parsedShapes() {
        #expect(ActionRef(parsing: "copy-path.tilde") == .copyPath(.tilde))
        #expect(ActionRef(parsing: "open.terminal") == .openTerminal(nil))
        #expect(ActionRef(parsing: "open.terminal@ghostty") == .openTerminal("ghostty"))
        #expect(ActionRef(parsing: "agent.claude") == .agent(id: "claude", variant: nil, launcher: nil))
        #expect(ActionRef(parsing: "agent.claude.continue@ghostty")
                == .agent(id: "claude", variant: "continue", launcher: .terminal("ghostty")))
        #expect(ActionRef(parsing: "agent.claude@link") == .agent(id: "claude", variant: nil, launcher: .terminalLink))
        #expect(ActionRef(parsing: "agent.codex@desktop") == .agent(id: "codex", variant: nil, launcher: .desktop))
        #expect(ActionRef(parsing: "agent.claude@default") == .agent(id: "claude", variant: nil, launcher: .terminal(nil)))
        // "terminal" is the id of Terminal.app, not a keyword.
        #expect(ActionRef(parsing: "agent.claude@terminal") == .agent(id: "claude", variant: nil, launcher: .terminal("terminal")))
    }

    @Test("malformed ids are rejected", arguments: [
        "", "copy-path", "copy-path.nope", "copy-path.absolute@x", "open", "open.terminal@", "open.terminal@Bad",
        "open.editor@x", "open.app", "open.app.zed.extra", "agent", "agent.", "agent.claude.a.b",
        "agent.claude@", "new-file", "new-file.md@x", "reveal.x", "user", "Copy-Path.absolute",
        "copy-path.absolute ", "agent.claude/../x", "agent.-claude", "open.terminal@ghostty@x",
        // Once reserved for actions defined in the config, which do not exist.
        "user.build-all", "user.x@ghostty"
    ])
    func rejects(id: String) {
        #expect(ActionRef(parsing: id) == nil)
    }
}
