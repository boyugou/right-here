import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("App Intent invocation")
struct IntentInvocationTests {
    @Test func aFolderTravelsAfterADoubleDashAsOneArgument() throws {
        let folder = "/Users/me/my code/-rf; touch x"
        #expect(try IntentCommand.openTerminal(folder: folder).arguments() == ["run", "open.terminal", "--origin", "cli", "--", folder])
        #expect(try IntentCommand.startAgent(agent: "claude", folder: folder).arguments() == ["run", "agent.claude", "--origin", "cli", "--", folder])
        #expect(try IntentCommand.newFile(template: "md", folder: folder).arguments() == ["run", "new-file.md", "--origin", "cli", "--", folder])
        #expect(try IntentCommand.copyPath(style: .gitRelative, path: folder).arguments() == ["run", "copy-path.git-relative", "--origin", "cli", "--", folder])
    }

    @Test func anIdThatIsNotOneWordIsRefused() {
        for bad in ["", "claude.continue", "claude@ghostty", "a b", "x;y", "../x"] {
            #expect(throws: IntentCommand.Invalid.self) { try IntentCommand.startAgent(agent: bad, folder: "/tmp").arguments() }
            #expect(throws: IntentCommand.Invalid.self) { try IntentCommand.newFile(template: bad, folder: "/tmp").arguments() }
        }
    }

    @Test func aRelativePathIsRefused() {
        #expect(throws: IntentCommand.Invalid.self) { try IntentCommand.openTerminal(folder: "code").arguments() }
        #expect(throws: IntentCommand.Invalid.self) { try IntentCommand.openTerminal(folder: "").arguments() }
    }

    @Test func everyPathStyleMakesAnActionIDThatParses() throws {
        for style in PathStyle.allCases {
            let arguments = try IntentCommand.copyPath(style: style, path: "/tmp").arguments()
            #expect(ActionRef(parsing: arguments[1]) == .copyPath(style))
        }
    }

    @Test func agentsAreTheEnabledOrFoundOnes() {
        let json = """
        [{"id":"claude","name":"Claude Code","command":"claude","enabled":true,"foundInShell":true,"variants":[],"terminalLink":false,"desktopLink":false},
         {"id":"codex","name":"Codex","command":"codex","enabled":false,"foundInShell":true,"variants":[],"terminalLink":false,"desktopLink":false},
         {"id":"aider","name":"Aider","command":"aider","enabled":false,"foundInShell":false,"variants":[],"terminalLink":false,"desktopLink":false}]
        """
        #expect(IntentCatalog.agents(fromJSON: Data(json.utf8)) == [IntentChoice(id: "claude", name: "Claude Code"), IntentChoice(id: "codex", name: "Codex")])
        #expect(IntentCatalog.agents(fromJSON: Data()) == [])
    }

    @Test func templatesComeFromTheNewFileActions() {
        let json = """
        [{"id":"reveal","title":"Reveal","shortTitle":"Reveal","group":"reveal","available":true},
         {"id":"new-file.md","title":"New Markdown File","shortTitle":"Markdown","group":"new-file","available":true},
         {"id":"new-file.bad","title":"New Bad","shortTitle":"Bad","group":"new-file","available":false}]
        """
        #expect(IntentCatalog.templates(fromJSON: Data(json.utf8)) == [IntentChoice(id: "md", name: "Markdown")])
    }

    @Test func rhsOwnWordsComeBackOnSuccessAndFailure() async throws {
        let ok = ProcessResult(status: 0, standardOutput: "ok: Open in Ghostty\n")
        #expect(try IntentRunner.interpret(ok) == "Open in Ghostty")
        let failed = ProcessResult(status: 1, standardError: "error: no terminal is installed\n")
        #expect(throws: IntentRunner.Failure(text: "error: no terminal is installed")) { try IntentRunner.interpret(failed) }
        let slow = ProcessResult(status: 15, terminatedAfter: .seconds(60))
        #expect(throws: IntentRunner.Failure.self) { try IntentRunner.interpret(slow) }
    }
}
