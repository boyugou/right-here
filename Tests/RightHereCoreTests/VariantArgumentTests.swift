import Foundation
import Testing
@testable import RightHereCore

private let appFolder = "/Users/tester/code/app"

private let machine = FakeSystemFacts(
    directories: ["/Users/tester/code", appFolder],
    applications: ["com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"), "com.apple.Terminal": URL(fileURLWithPath: "/Applications/Terminal.app")],
    bundleVersions: ["com.mitchellh.ghostty": "1.3.1"]
)

private let folder = HereContext(origin: .container, container: URL(fileURLWithPath: appFolder))

/// The text a plan types into Ghostty (it is given the folder and the text apart).
private func typedText(_ plan: LaunchPlan) throws -> String {
    guard case .appleScript(let script)? = plan.steps.first, script.arguments.count > 1 else { throw VariantTestFailure("expected a typed launch, got \(plan.steps)") }
    return script.arguments[1]
}

private struct VariantTestFailure: Error { init(_ message: String) { self.message = message }; let message: String }

/// A config whose `claude` prints each word it is given, NUL-terminated, with one variant carrying `arguments`.
private func printingConfig(_ arguments: [String], command: String = "printf '%s\\0'") -> Config {
    Config(enabledAgents: ["claude"], agents: ["claude": .init(command: command, variants: [.init(id: "mine", title: "Mine", arguments: arguments)])])
}

private let mine = ActionRef.agent(id: "claude", variant: "mine", launcher: nil)

@Suite("Agent variants: each argument is one word of the typed line")
struct VariantArgumentTests {
    @Test func theBuiltInVariantsAreTypedExactlyAsTheyAlwaysWere() throws {
        // Words that need no quoting stay bare, so quoting the arguments changes nothing for them.
        let planner = Planner(config: Config(enabledAgents: ["claude", "codex", "gemini", "opencode"]), facts: machine)
        for (id, expected) in [("agent.claude.continue", "claude --continue"), ("agent.claude.resume", "claude --resume"), ("agent.codex.last", "codex resume --last"),
                               ("agent.codex.resume", "codex resume"), ("agent.gemini.resume", "gemini --resume latest"), ("agent.opencode.continue", "opencode --continue")] {
            let ref = try #require(ActionRef(parsing: id))
            #expect(try typedText(planner.plan(ref, context: folder)) == expected, "\(id)")
        }
    }

    @Test func anArgumentThatNeedsQuotingReachesTheAgentAsOneArgumentAndNotAsShellSyntax() throws {
        // `arguments` read like an argv, but were typed as raw text: the second element split at the space and `;` ended the command.
        let config = printingConfig(["--append-system-prompt", "be brief; echo $HOME `id`"], command: "claude --model opus")
        let typed = try typedText(Planner(config: config, facts: machine).plan(mine, context: folder))
        #expect(typed == "claude --model opus --append-system-prompt 'be brief; echo $HOME `id`'", "\(typed)")
    }

    @Test("a start option whose argument has a line break or another control character is an error, and the start option is left out", arguments: ["two\\nlines", "a\\rb", "bell\\u0007", "esc\\u001b[31m"])
    func anArgumentThatCannotBeTypedIsRefusedWhereItIsWritten(argument: String) {
        let result = ConfigParser.parse("[[agent.claude.variant]]\nid = \"mine\"\ntitle = \"Mine\"\narguments = [\"--ok\", \"\(argument)\"]\n")
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.map(\.path) == ["agent.claude.variant.1.arguments"], "\(result.diagnostics)")
        #expect(result.config.agent(id: "claude")?.variants.contains { $0.id == "mine" } == false)
    }

    private static let hostile = [
        "plain.txt", "it's", "a'b'c", "a b", "$(touch CANARY)", "`touch CANARY`", "$HOME and ${PATH}", "semi;colon && pipe | redirect > CANARY",
        "--help", "-rf", "~tilde", "star*?[glob]", "bang!history", "#hash", "{folder}", "%s%n", "日本語 パス", "emoji 🚀", "''", "'; touch CANARY; '", ""
    ]

    @Test("the typed line is read back by a real shell as exactly the arguments", arguments: ["/bin/sh", "/bin/bash", "/bin/zsh"])
    func roundTrip(shell: String) throws {
        let directory = try makeScratchDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        for arguments in Self.hostile.map({ [$0] }) + [Self.hostile] {
            let typed = try typedText(Planner(config: printingConfig(arguments), facts: machine).plan(mine, context: folder))
            let words = try Shell.run(shell, typed, in: directory).split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            #expect(words == arguments + [""], "\(shell) read \(typed.debugDescription) as \(words)")
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("CANARY").path))
    }

    @Test func theCommandIsATypedLineAndGoesInAsWritten() throws {
        let config = Config(enabledAgents: ["claude"], agents: ["claude": .init(command: "claude --model \"opus 4\" --verbose", variants: [.init(id: "mine", title: "Mine", arguments: ["--resume"])])])
        let planner = Planner(config: config, facts: machine)
        #expect(try typedText(planner.plan(.agent(id: "claude", variant: nil, launcher: nil), context: folder)) == "claude --model \"opus 4\" --verbose")
        #expect(try typedText(planner.plan(mine, context: folder)) == "claude --model \"opus 4\" --verbose --resume")
    }

    @Test func aBackslashIsRefusedAndTheMenuAndRunSayItInTheSameWords() throws {
        // Fish reads a backslash inside single quotes differently from the other shells, so no quoting is right for every shell
        // (presets refuse one for the same reason); `command` is typed as written and is where such text belongs.
        let config = printingConfig(["--pattern", "a\\'b"])
        let reason = try #require(ActionRegistry(config: config, facts: machine).info(mine).unavailableReason)
        #expect(reason.contains("has a backslash") && reason.contains("`command`") && reason.contains("\"mine\""), Comment(rawValue: reason))
        #expect(throws: PlanError.unsupported(reason)) { try Planner(config: config, facts: machine).plan(mine, context: folder) }
        // The agent's plain entry does not use the variant and stays available.
        #expect(ActionRegistry(config: config, facts: machine).info(.agent(id: "claude", variant: nil, launcher: nil)).available)
    }

    @Test func aControlCharacterInAnArgumentIsStillRefusedForTyping() {
        let config = printingConfig(["line\nbreak"])
        #expect(throws: PlanError.self) { try Planner(config: config, facts: machine).plan(mine, context: folder) }
    }
}
