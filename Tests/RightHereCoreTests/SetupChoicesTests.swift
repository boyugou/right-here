import Foundation
import Testing
@testable import RightHereCore

@Suite("What a person says they use")
struct SetupChoicesTests {
    @Test func knownIdsAreTakenAsTheyAre() throws {
        let choices = try SetupChoices.parse(terminal: "ghostty", editor: "zed", agents: "claude,codex")
        #expect(choices == SetupChoices(terminal: "ghostty", editor: "zed", agents: ["claude", "codex"]))
        #expect(!choices.isEmpty)
    }

    @Test func nothingSaidIsEmptyAndLeavesEverythingToTheMachine() throws {
        let choices = try SetupChoices.parse(terminal: nil, editor: nil, agents: nil)
        #expect(choices.isEmpty)
        #expect(choices.terminal == nil && choices.editor == nil && choices.agents == nil)
    }

    @Test func agentsAreTrimmedAndListedOnce() throws {
        #expect(try SetupChoices.parse(terminal: nil, editor: nil, agents: " claude , codex,claude").agents == ["claude", "codex"])
    }

    @Test func noneIsAChoiceAndMeansNoAgentAtAll() throws {
        let choices = try SetupChoices.parse(terminal: nil, editor: nil, agents: "none")
        #expect(choices.agents == [])
        #expect(!choices.isEmpty)
    }

    @Test func everyBuiltInIdIsAccepted() throws {
        for app in KnownApps.terminals { #expect(try SetupChoices.parse(terminal: app.id, editor: nil, agents: nil).terminal == app.id) }
        for app in KnownApps.editors { #expect(try SetupChoices.parse(terminal: nil, editor: app.id, agents: nil).editor == app.id) }
        for agent in KnownAgents.all { #expect(try SetupChoices.parse(terminal: nil, editor: nil, agents: agent.id).agents == [agent.id]) }
    }

    private func refusal(terminal: String? = nil, editor: String? = nil, agents: String? = nil) -> String {
        do {
            _ = try SetupChoices.parse(terminal: terminal, editor: editor, agents: agents)
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    @Test func aMisspeltTerminalNamesTheClosestOneAndListsTheOthers() {
        let text = refusal(terminal: "ghosty")
        #expect(text.contains("Unknown terminal \"ghosty\" (did you mean \"ghostty\"?)"), "\(text)")
        for terminal in KnownApps.terminals { #expect(text.contains(terminal.id), "the list lacks \(terminal.id)") }
        #expect(text.contains("rh apps"))
    }

    @Test func aNameIsNotAnIdButLeadsToIt() {
        #expect(refusal(editor: "Visual Studio Code").contains("did you mean \"vscode\"?"))
        #expect(refusal(agents: "Claude Code").contains("did you mean \"claude\"?"))
    }

    @Test func anEditorIsNotATerminalAndTheMessageSaysWhichFlagToUse() {
        let text = refusal(terminal: "vscode")
        #expect(text.contains("\"vscode\" is an editor, not a terminal"), "\(text)")
        #expect(text.contains("--editor vscode"))
        let reverse = refusal(editor: "ghostty")
        #expect(reverse.contains("\"ghostty\" is a terminal, not an editor"), "\(reverse)")
        #expect(reverse.contains("--terminal ghostty"))
    }

    @Test func aMisspeltAgentListsTheAgentsAndSaysWhereOthersAreDefined() {
        let text = refusal(agents: "claude,claud")
        #expect(text.contains("Unknown agent \"claud\" (did you mean \"claude\"?)"), "\(text)")
        for agent in KnownAgents.all { #expect(text.contains(agent.id), "the list lacks \(agent.id)") }
        #expect(text.contains("[agent.<id>]"))
    }

    @Test("a list that is empty, has an empty item, or mixes none with agents is refused", arguments: ["", "claude,", ",claude", "claude,,codex", "none,claude", "claude,none"])
    func malformedAgentLists(list: String) {
        #expect(!refusal(agents: list).isEmpty, "\(list.debugDescription) was accepted")
    }

    @Test func aTextThatActsOnATerminalIsEscapedInTheMessage() {
        let text = refusal(terminal: "x\u{1B}[2Jy")
        #expect(!text.unicodeScalars.contains("\u{1B}"))
        #expect(text.contains("\\u001b"))
    }

    @Test func aTerminalThatCannotRunCommandsIsAdviceForAgentsOnly() {
        let warning = SetupChoices.agentTerminalWarning(terminal: "warp", agents: ["claude"])
        #expect(warning?.contains("Warp cannot run commands") == true, "\(warning ?? "nil")")
        #expect(warning?.contains("ghostty") == true)
        #expect(SetupChoices.agentTerminalWarning(terminal: "warp", agents: []) == nil)
        #expect(SetupChoices.agentTerminalWarning(terminal: "ghostty", agents: ["claude"]) == nil)
        #expect(SetupChoices.agentTerminalWarning(terminal: nil, agents: ["claude"]) == nil)
    }

    @Test func whatIsSaidOverridesWhatWasFoundAndTheRestIsKept() {
        let found = DetectedEnvironment(terminal: "ghostty", editor: "vscode", agents: ["claude", "codex"])
        #expect(found.applying(SetupChoices()) == found)
        #expect(found.applying(SetupChoices(terminal: "terminal")) == DetectedEnvironment(terminal: "terminal", editor: "vscode", agents: ["claude", "codex"]))
        #expect(found.applying(SetupChoices(agents: [])) == DetectedEnvironment(terminal: "ghostty", editor: "vscode", agents: []))
        #expect(found.applying(SetupChoices(terminal: "kitty", editor: "zed", agents: ["agy"])) == DetectedEnvironment(terminal: "kitty", editor: "zed", agents: ["agy"]))
    }

    @Test func aConfigMadeFromChoicesSaysThemAndValidatesClean() {
        let detected = DetectedEnvironment(terminal: "ghostty", editor: "vscode", agents: ["claude"]).applying(SetupChoices(terminal: "terminal", editor: "zed", agents: ["claude", "codex"]))
        let result = ConfigParser.parse(ConfigTemplate.render(detected))
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics)")
        #expect(result.config.terminal == "terminal")
        #expect(result.config.editor == "zed")
        #expect(result.config.enabledAgents == ["claude", "codex"])
    }

    @Test func noAgentsMakesAConfigWithNoAgentThatStillValidates() {
        let result = ConfigParser.parse(ConfigTemplate.render(DetectedEnvironment(terminal: "terminal", editor: "vscode", agents: [])))
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics)")
        #expect(result.config.enabledAgents.isEmpty)
    }
}
