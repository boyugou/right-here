import Foundation
import Testing
@testable import RightHereCore

/// What `new` would start that `old` (or, without one, the built-in setup) does not, one line each.
private func lines(_ new: String, over old: String? = nil) -> [String] {
    let known = old.map(LaunchCommands.init(configText:)) ?? LaunchCommands(.default)
    return LaunchCommands(configText: new).additions(to: known).map(\.line)
}

private let redefinedTerminal = """
[[app]]
id = "terminal"
name = "Terminal"
bundle_id = "com.apple.Terminal"
role = "terminal"
open_args = ["/usr/bin/id", "-un", "{dir}"]
run_args = ["/bin/sh", "-c", "{command}"]
"""

@Suite("LaunchCommands: what a config can make Right Here start")
struct LaunchCommandsTests {
    @Test func aConfigWithNothingCustomStartsNothingOfItsOwn() {
        #expect(LaunchCommands(configText: "").custom.isEmpty)
        #expect(LaunchCommands(configText: "[general]\nterminal = \"ghostty\"\neditor = \"vscode\"\nagents = [\"claude\", \"codex\"]\n[menu]\nitems = [\"open.terminal\"]\n").custom.isEmpty)
        #expect(LaunchCommands(.default).custom.isEmpty)
    }

    @Test func redefiningABuiltInTerminalWithTemplatesIsListed() {
        let found = lines(redefinedTerminal)
        #expect(found.contains(#"[[app]] terminal open_args = ["/usr/bin/id", "-un", "{dir}"]"#), "\(found)")
        #expect(found.contains(#"[[app]] terminal run_args = ["/bin/sh", "-c", "{command}"]"#), "\(found)")
    }

    @Test func aTemplateTheOtherConfigAlreadyHasIsNotListedAgain() {
        #expect(lines(redefinedTerminal, over: redefinedTerminal).isEmpty)
        #expect(lines(redefinedTerminal + "\n[general]\neditor = \"vscode\"\n", over: redefinedTerminal).isEmpty)
    }

    @Test func aChangedTemplateSaysWhatItWas() {
        let before = redefinedTerminal
        let after = redefinedTerminal.replacingOccurrences(of: "/bin/sh", with: "/bin/zsh")
        let found = lines(after, over: before)
        #expect(found == [#"[[app]] terminal run_args = ["/bin/zsh", "-c", "{command}"] (was ["/bin/sh", "-c", "{command}"])"#], "\(found)")
    }

    @Test func aPlainAppWithoutTemplatesStartsNothingOfItsOwn() {
        let found = lines("[[app]]\nid = \"mine\"\nname = \"Mine\"\nbundle_id = \"com.example.mine\"\nrole = \"editor\"\n")
        #expect(found.isEmpty, "\(found)")
    }

    @Test func anAgentCommandIsListedWhetherCustomOrACallOnABuiltInOne() {
        let custom = lines("[general]\nagents = [\"mine\"]\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine --yes\"\n")
        #expect(custom.contains(#"[agent.mine] command = "mine --yes""#), "\(custom)")
        let builtIn = lines("[agent.claude]\ncommand = \"claude --dangerously-skip-permissions\"\n")
        #expect(builtIn == [#"[agent.claude] command = "claude --dangerously-skip-permissions" (was "claude")"#], "\(builtIn)")
    }

    @Test func variantArgumentsAndTheFirstPromptFlagAreListed() {
        let found = lines("""
        [agent.claude]
        prompt_arg = "-p"
        [[agent.claude.variant]]
        id = "fast"
        title = "Fast"
        arguments = ["--model", "haiku"]
        """)
        #expect(found.contains(#"[agent.claude] prompt_arg = "-p" (was "positional")"#), "\(found)")
        #expect(found.contains(#"[[agent.claude.variant]] fast arguments = ["--model", "haiku"]"#), "\(found)")
    }

    @Test func theDefaultTerminalCountsOnlyWhenItStartsThroughATemplate() {
        #expect(lines("[general]\nterminal = \"terminal\"\n").isEmpty)
        let template = "[[app]]\nid = \"mine\"\nname = \"Mine\"\nbundle_id = \"com.example.mine\"\nrole = \"terminal\"\nrun_args = [\"/bin/echo\", \"{dir}\", \"{command}\"]\n"
        #expect(lines("[general]\nterminal = \"mine\"\n" + template).contains(#"[general] terminal (starts through a command template) = "mine""#))
        #expect(!lines("[general]\nterminal = \"ghostty\"\n" + template).contains { $0.hasPrefix("[general]") })
        // Switching to a template the other config has too is still a change to say so about.
        #expect(lines("[general]\nterminal = \"mine\"\n" + template, over: "[general]\nterminal = \"ghostty\"\n" + template).count == 1)
    }

    @Test func somethingTheOtherConfigHasAndThisLacksIsNotListed() {
        #expect(lines("", over: redefinedTerminal).isEmpty)
        #expect(lines("[general]\nterminal = \"terminal\"\n", over: redefinedTerminal).isEmpty)
    }

    @Test func bytesThatCannotBeReadAsTextCountAsNothingKnown() {
        let known = LaunchCommands(configData: Data([0xff, 0xfe, 0x00]))
        #expect(LaunchCommands(configText: redefinedTerminal).additions(to: known).count == 3)
        // A byte order mark, which the config store drops before parsing, does not hide what follows it.
        #expect(LaunchCommands(configData: Data(("\u{FEFF}" + redefinedTerminal).utf8)) == LaunchCommands(configText: redefinedTerminal))
    }

    @Test func controlCharactersInAValueArePrintedEscaped() {
        let found = lines("""
        [[agent.claude.variant]]
        id = "x"
        title = "X"
        arguments = ["--x\\u001b[2J\\u009b31m", "a\\"b\\\\c"]
        """)
        let text = found.joined(separator: "\n")
        #expect(!text.unicodeScalars.contains { $0.properties.generalCategory == .control && $0 != "\n" }, "a control character reached the printed line")
        #expect(text.contains(#"\u001b[2J\u009b31m"#), "\(text)")
        #expect(text.contains(#""a\"b\\c""#), "quotes and backslashes stay readable: \(text)")
    }
}
