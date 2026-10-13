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

    @Test func agentsAreTheEnabledOrFoundOnes() throws {
        // The rows `rh agents --json` writes, written the way it writes them: the intents read the very type it prints.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let rows = Config(enabledAgents: ["claude"]).agentRows(found: ["claude", "codex"])
        #expect(IntentCatalog.agents(fromJSON: try encoder.encode(rows)) == [IntentChoice(id: "claude", name: "Claude Code"), IntentChoice(id: "codex", name: "Codex")])
        #expect(IntentCatalog.agents(fromJSON: Data()) == [])
    }

    @Test func anAgentThatWasNotLookedUpIsOfferedOnlyWhenEnabled() throws {
        let rows = Config(enabledAgents: ["claude"]).agentRows()
        #expect(IntentCatalog.agents(fromJSON: try JSONEncoder().encode(rows)) == [IntentChoice(id: "claude", name: "Claude Code")])
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

    /// What `rh run` writes when the config has problems and the action then fails: the problems first, the reason last.
    private static let withConfigProblems = """
    warning: config.toml [general.termnial]: unknown key (did you mean "terminal"?)
    error: config.toml [general.terminal]: unknown terminal "nope"; known terminals: ghostty, terminal. The first installed terminal is used instead.
    error: config.local.toml:3 [agent.mine.command]: the command has a line break or control character, so it cannot be typed into a terminal
    error: no terminal is installed

    """

    @Test func aFailureShowsOnlyTheLineThatSaysWhy() async throws {
        #expect(throws: IntentRunner.Failure(text: "error: no terminal is installed")) {
            try IntentRunner.interpret(ProcessResult(status: 1, standardError: Self.withConfigProblems))
        }
        // Through the whole path an intent takes.
        let runner = FakeProcessRunner(results: [ProcessResult(status: 1, standardError: Self.withConfigProblems)])
        await #expect(throws: IntentRunner.Failure(text: "error: no terminal is installed")) {
            try await IntentRunner(helper: "/Applications/Right Here.app/Contents/Helpers/rh", runner: runner).perform(.openTerminal(folder: "/Users/tester/code"))
        }
    }

    @Test func theArgumentParsersOwnFormComesLastToo() {
        let stderr = """
        error: config.toml [general.terminal]: unknown terminal "nope"
        Error: "/a/link/.." has `..` after a symbolic link, which the file system reads differently from the text.
        Usage: rh run <action> [--origin <origin>] [--container <container>] [<paths> ...]
          See 'rh run --help' for more information.
        """
        #expect(IntentRunner.failureReason(standardError: stderr) == "Error: \"/a/link/..\" has `..` after a symbolic link, which the file system reads differently from the text.")
    }

    @Test func nothingButConfigProblemsIsNoAnswerAndNoneOfItIsShown() {
        let stderr = "warning: config.toml [general.termnial]: unknown key\nerror: config.toml:2 [agent.mine.command]: the command is empty\n"
        #expect(IntentRunner.failureReason(standardError: stderr) == nil)
        #expect(throws: IntentRunner.Failure(text: "rh exited with status 1.")) { try IntentRunner.interpret(ProcessResult(status: 1, standardError: stderr)) }
        #expect(throws: IntentRunner.Failure(text: "rh exited with status 2.")) { try IntentRunner.interpret(ProcessResult(status: 2)) }
    }

    @Test func aReasonThatMerelyNamesATomlFileIsStillTheReason() {
        #expect(IntentRunner.failureReason(standardError: "error: /Users/me/notes.toml is not a folder\n") == "error: /Users/me/notes.toml is not a folder")
    }
}
