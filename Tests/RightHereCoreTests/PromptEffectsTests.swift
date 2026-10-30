import Foundation
import Testing
@testable import RightHereCore

private func config(_ text: String) -> Config { ConfigParser.parse(text).config }

@Suite("PromptEffects and the effect-level trust check: what a change does to the agents")
struct PromptEffectsTests {
    private let switchedOn = "[general]\nagents = [\"claude\"]\nbypass_permissions = true\n"

    @Test func theAgentsAClickCanStartAreThoseInTheListAndThoseAMenuOrServiceItemNames() {
        #expect(PromptEffects.offeredAgents(config("[general]\nagents = [\"claude\"]\n")) == ["claude"])
        let named = config("[general]\nagents = [\"claude\"]\n\n[menu]\nitems = [\"open-terminal\", \"agent.codex\", \"agent.aider.resume\", \"agent.goose@link\", \"-\"]\n\n[services]\nitems = [\"agent.gemini\"]\n")
        #expect(PromptEffects.offeredAgents(named) == ["claude", "codex", "aider", "goose", "gemini"])
    }

    @Test func anAgentWithAFlagThatIsOfferedStartsWithoutAskingAndOneThatIsNotOfferedDoesNot() {
        let entries = PromptEffects.withoutAsking(config(switchedOn))
        #expect(entries.map(\.agent) == ["claude"] && entries.first?.flag == "--dangerously-skip-permissions" && entries.first?.name == "Claude Code")
        #expect(PromptEffects.withoutAsking(config("[general]\nagents = [\"claude\"]\n")).isEmpty, "the switch is off")
        #expect(PromptEffects.withoutAsking(config(switchedOn + "\n[agent.claude]\nbypass_permissions = false\n")).isEmpty, "its own setting keeps it asking")
    }

    @Test func puttingAnAgentInTheMenuWhileTheSwitchIsOnIsNewAndAskingAgainIsNot() {
        let before = config(switchedOn)
        let added = config(switchedOn.replacingOccurrences(of: "[\"claude\"]", with: "[\"claude\", \"codex\"]"))
        #expect(PromptEffects.newlyWithoutAsking(from: before, to: added).map(\.agent) == ["codex"])
        let named = config(switchedOn + "\n[menu]\nitems = [\"agent.codex\"]\n")
        #expect(PromptEffects.newlyWithoutAsking(from: before, to: named).map(\.agent) == ["codex"])
        #expect(PromptEffects.newlyWithoutAsking(from: added, to: before).isEmpty, "taken out again")
        #expect(PromptEffects.newlyWithoutAsking(from: before, to: before).isEmpty)
        let flagged = config(switchedOn + "\n[agent.claude]\nbypass_permission_arg = \"--yolo\"\n")
        #expect(PromptEffects.newlyWithoutAsking(from: before, to: flagged).map(\.flag) == ["--yolo"], "another flag is new")
    }

    @Test func theEffectCheckSeesTheArgumentsThatAreEmptiedAndTheVariantThatIsReplaced() {
        let sandboxed = config("[general]\nagents = [\"codex\"]\n\n[agent.codex]\nargs = [\"--sandbox\", \"read-only\"]\n\n[[agent.codex.variant]]\nid = \"ro\"\ntitle = \"Read-only\"\narguments = [\"--sandbox\", \"read-only\"]\n")
        func keys(_ text: String) -> [String] { ConfigTrust.approvals(changingFrom: sandboxed, to: config(text)).map(\.key) }
        #expect(keys("[general]\nagents = [\"codex\"]\n\n[agent.codex]\nargs = []\n\n[[agent.codex.variant]]\nid = \"ro\"\ntitle = \"Read-only\"\narguments = [\"--sandbox\", \"read-only\"]\n") == ["agent.*.args"])
        #expect(keys("[general]\nagents = [\"codex\"]\n\n[agent.codex]\nargs = [\"--sandbox\", \"read-only\"]\n\n[[agent.codex.variant]]\nid = \"ro\"\ntitle = \"Read-only\"\narguments = []\n") == ["agent.*.variant.*.arguments"])
        #expect(keys("[general]\nagents = [\"codex\"]\n\n[agent.codex]\nargs = [\"--sandbox\", \"read-only\"]\ncommand = \"codex --fast\"\n\n[[agent.codex.variant]]\nid = \"ro\"\ntitle = \"Read-only\"\narguments = [\"--sandbox\", \"read-only\"]\n") == ["agent.*.command"])
        // What starts nothing new is nothing to approve: a variant that is gone, a title, the menu, the same arguments.
        #expect(keys("[general]\nagents = [\"codex\"]\n\n[agent.codex]\nargs = [\"--sandbox\", \"read-only\"]\n").isEmpty)
        #expect(keys("[general]\nagents = [\"codex\"]\nterminal = \"terminal\"\n\n[agent.codex]\nargs = [\"--sandbox\", \"read-only\"]\n\n[[agent.codex.variant]]\nid = \"ro\"\ntitle = \"Another title\"\narguments = [\"--sandbox\", \"read-only\"]\n").isEmpty)
        // A variant that is new, and an agent that is new, start something the person has not seen.
        #expect(keys("[general]\nagents = [\"codex\"]\n\n[agent.codex]\nargs = [\"--sandbox\", \"read-only\"]\n\n[[agent.codex.variant]]\nid = \"new\"\ntitle = \"New\"\narguments = [\"--x\"]\n") == ["agent.*.variant.*.arguments"])
        #expect(keys("[general]\nagents = [\"codex\"]\n\n[agent.codex]\nargs = [\"--sandbox\", \"read-only\"]\n\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n") == ["agent.*.command"])
        #expect(ConfigTrust.approvals(changingFrom: config(switchedOn), to: config(switchedOn.replacingOccurrences(of: "[\"claude\"]", with: "[\"claude\", \"codex\"]"))).map(\.key) == ["agent.*.bypass_permissions"])
    }

    @Test func aFlagThatSwitchesThePromptsOffCountsWhereverTheAgentTypesIt() {
        let head = "[general]\nagents = [\"claude\"]\n\n[agent.claude]\n"
        let flag = "--dangerously-skip-permissions"
        #expect(PromptEffects.withoutAsking(config(head + "args = [\"\(flag)\"]\n")).map(\.flag) == [flag])
        #expect(PromptEffects.withoutAsking(config(head + "command = \"claude \(flag)\"\n")).map(\.flag) == [flag])
        #expect(PromptEffects.withoutAsking(config(head + "prompt_arg = \"\(flag)\"\n")).map(\.flag) == [flag])
        #expect(PromptEffects.withoutAsking(config(head + "\n[[agent.claude.variant]]\nid = \"yolo\"\ntitle = \"Yolo\"\narguments = [\"\(flag)\"]\n")).map(\.flag) == [flag])
        #expect(PromptEffects.withoutAsking(config(head + "args = [\"--verbose\"]\n")).isEmpty)
        let before = config(head + "args = [\"--verbose\"]\n")
        #expect(PromptEffects.newlyWithoutAsking(from: before, to: config(head + "args = [\"--verbose\", \"\(flag)\"]\n")).map(\.agent) == ["claude"], "an edit that adds the flag is a change that starts an agent without asking")
        let typed = config(head + "args = [\"\(flag)\"]\n")
        #expect(PromptEffects.newlyWithoutAsking(from: typed, to: config(head + "args = [\"\(flag)\", \"--verbose\"]\n")).isEmpty, "a flag that was there is not new")
    }

    @Test("the flag is seen behind what the shell makes of the command: an assignment or a wrapper, another case, $'…', a redirection", arguments: [
        "FOO=1 claude --dangerously-skip-permissions", "env claude --dangerously-skip-permissions", "exec claude --dangerously-skip-permissions", "Claude --dangerously-skip-permissions",
        "claude $'--dangerously-skip-permissions'", "claude --dangerously-skip-permissions>&1"
    ])
    func theFlagIsSeenBehindWhatTheShellMakesOfTheCommand(command: String) {
        let text = "[general]\nagents = [\"claude\", \"work\"]\n\n[agent.work]\nname = \"Work\"\ncommand = \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"\nprompt_arg = \"positional\"\n"
        #expect(PromptEffects.withoutAsking(config(text)).map(\.agent).contains("work"), "\(command)")
        let before = config("[general]\nagents = [\"claude\", \"work\"]\n\n[agent.work]\nname = \"Work\"\ncommand = \"claude\"\nprompt_arg = \"positional\"\n")
        #expect(ConfigTrust.approvals(changingFrom: before, to: config(text)).map(\.key).contains("agent.*.bypass_permissions"), "\(command)")
    }
}
