import Foundation
import Testing
@testable import RightHereCore

private func machine() -> FakeSystemFacts {
    FakeSystemFacts(
        directories: ["/Users/tester/code"],
        applications: ["com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"), "com.apple.Terminal": URL(fileURLWithPath: "/Applications/Terminal.app"),
                       "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app"), "dev.zed.Zed": URL(fileURLWithPath: "/Applications/Zed.app"),
                       "com.anthropic.claudefordesktop": URL(fileURLWithPath: "/Applications/Claude.app")]
    )
}

private func config(_ text: String) -> Config { ConfigParser.parse(text).config }

@Suite("GeneralSettings: the terminal, the editor and the agents as something to edit")
struct GeneralSettingsTests {
    /// The state of a config file that is read on its own: what the file writes for the list of agents is what the config says.
    private func state(_ text: String = "") -> GeneralSettingsState {
        GeneralSettings.state(config: config(text), facts: machine(), listedAgents: try? ConfigDocument(text).elements(of: "general.agents") ?? nil)
    }

    @Test func theTerminalsAndEditorsThatAreInstalledAreOfferedBestFirst() {
        let state = state()
        #expect(state.terminals.map(\.id) == ["ghostty", "terminal"] && state.terminals.allSatisfy(\.installed))
        #expect(state.editors.map(\.id) == ["vscode", "zed"] && state.editors.allSatisfy(\.installed))
        #expect(state.terminals.first?.name == "Ghostty" && state.terminals.first?.icon == .app("com.mitchellh.ghostty"))
        #expect(state.terminal == nil && state.usedTerminal == "ghostty", "with none configured the first installed one is used")
        #expect(state.editor == nil && state.usedEditor == "vscode")
    }

    @Test func theConfiguredAppIsTheOneUsedAndAnAppThatIsNotInstalledStillShows() {
        let chosen = state("[general]\nterminal = \"terminal\"\neditor = \"zed\"\n")
        #expect(chosen.terminal == "terminal" && chosen.usedTerminal == "terminal" && chosen.editor == "zed" && chosen.usedEditor == "zed")
        let missing = state("[general]\nterminal = \"iterm\"\n")
        #expect(missing.terminal == "iterm" && missing.usedTerminal == "ghostty", "iTerm is not installed, so another is used meanwhile")
        #expect(missing.terminals.map(\.id) == ["ghostty", "terminal", "iterm"] && missing.terminals.last?.installed == false, "the choice is still shown, as not installed")
    }

    @Test func anAppOfTheConfigIsOfferedWhenItIsInstalled() {
        let text = "[[app]]\nid = \"tower\"\nname = \"Tower\"\nbundle_id = \"com.fournova.Tower3\"\nrole = \"terminal\"\n"
        let facts = FakeSystemFacts(directories: [], applications: ["com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"), "com.fournova.Tower3": URL(fileURLWithPath: "/Applications/Tower.app")])
        let state = GeneralSettings.state(config: config(text), facts: facts, listedAgents: nil)
        #expect(state.terminals.map(\.id) == ["ghostty", "tower"])
    }

    @Test func placementAndPermissionPromptsAreTheConfigs() {
        #expect(state().placement == .newWindow && !state().bypassPermissions)
        let set = state("[general]\nterminal_placement = \"split-right\"\nbypass_permissions = true\n")
        #expect(set.placement == .splitRight && set.bypassPermissions)
    }

    @Test func theAgentsOfTheMenuComeFirstInTheirOrderAndTheOthersAfterThem() {
        let state = state("[general]\nagents = [\"codex\", \"claude\"]\n")
        #expect(state.enabledAgents.map(\.id) == ["codex", "claude"])
        #expect(state.agents.prefix(2).map(\.id) == ["codex", "claude"] && state.agents.dropFirst(2).allSatisfy { !$0.enabled })
        #expect(Set(state.agents.map(\.id)) == Set(KnownAgents.all.map(\.id)) && state.agents.count == KnownAgents.all.count)
        #expect(state.agents.first?.name == "Codex")
        #expect(self.state("[general]\nagents = []\n").enabledAgents.isEmpty)
    }

    @Test func anAgentOfTheConfigIsAmongThemWithItsOwnName() {
        let state = state("[agent.mytool]\nname = \"My Tool\"\ncommand = \"mytool\"\n\n[general]\nagents = [\"mytool\"]\n")
        #expect(state.enabledAgents.map(\.id) == ["mytool"] && state.enabledAgents.first?.name == "My Tool")
        #expect(state.agents.dropFirst().allSatisfy { !$0.enabled })
    }

    @Test func anAgentThatHasItsOwnAppShowsItsIcon() {
        let state = state("[general]\nagents = [\"claude\"]\n")
        let claude = state.agents.first { $0.id == "claude" }
        #expect(claude?.icon == .app("com.anthropic.claudefordesktop") || claude?.icon == .symbol("terminal"), "\(String(describing: claude?.icon))")
        #expect(state.agents.allSatisfy { $0.icon != nil })
    }

    // MARK: The changes

    private func apply(_ operations: [ConfigOperation], to text: String) throws -> Config {
        var document = ConfigDocument(text)
        for operation in operations { document = try operation.apply(to: document) }
        return config(document.text)
    }

    @Test func eachSettingIsOneSet() throws {
        #expect(GeneralSettings.operations(settingTerminal: "iterm") == [.set("general.terminal", .string("iterm"))])
        #expect(GeneralSettings.operations(settingEditor: "zed") == [.set("general.editor", .string("zed"))])
        #expect(GeneralSettings.operations(settingTerminal: nil) == [.unset("general.terminal")], "automatic is no setting at all")
        #expect(GeneralSettings.operations(settingEditor: nil) == [.unset("general.editor")])
        #expect(GeneralSettings.operations(settingPlacement: .splitDown) == [.set("general.terminal_placement", .string("split-down"))])
        #expect(GeneralSettings.operations(settingBypassPermissions: true) == [.set("general.bypass_permissions", .boolean(true))])
        let text = "[general]\nterminal = \"ghostty\" # mine\n"
        let changed = try apply(GeneralSettings.operations(settingTerminal: "terminal") + GeneralSettings.operations(settingEditor: "zed")
            + GeneralSettings.operations(settingPlacement: .newTab) + GeneralSettings.operations(settingBypassPermissions: true), to: text)
        #expect(changed.terminal == "terminal" && changed.editor == "zed" && changed.terminalPlacement == .newTab && changed.bypassPermissions)
    }

    @Test func anAgentIsEnabledAtTheEndAndDisabledByItsPlace() throws {
        let text = "[general]\nagents = [\"claude\", \"codex\"]\n"
        let state = state(text)
        #expect(try apply(GeneralSettings.operations(enabling: "gemini", in: state), to: text).enabledAgents == ["claude", "codex", "gemini"])
        #expect(try apply(GeneralSettings.operations(disabling: "claude", in: state), to: text).enabledAgents == ["codex"])
        #expect(try apply(GeneralSettings.operations(disabling: "codex", in: state), to: text).enabledAgents == ["claude"])
        #expect(GeneralSettings.operations(disabling: "claude", in: state) == [.expect(["claude", "codex"], in: "general.agents"), .remove(at: 1, from: "general.agents")])
        #expect(GeneralSettings.operations(enabling: "claude", in: state).isEmpty, "it is enabled already")
        #expect(GeneralSettings.operations(enabling: "nonsense", in: state).isEmpty, "no such agent")
        #expect(GeneralSettings.operations(disabling: "gemini", in: state).isEmpty, "it is not enabled")
    }

    @Test func theFirstAgentIsEnabledInAFileThatListsNone() throws {
        let state = state("[general]\nterminal = \"ghostty\"\n")
        #expect(state.enabledAgents.isEmpty)
        let enabled = try apply(GeneralSettings.operations(enabling: "claude", in: state), to: "[general]\nterminal = \"ghostty\"\n")
        #expect(enabled.enabledAgents == ["claude"] && enabled.terminal == "ghostty")
    }

    /// What SwiftUI's `onMove` does to an array.
    private func moved(_ items: [String], from source: IndexSet, to destination: Int) -> [String] {
        let moving = source.sorted().map { items[$0] }
        var rest = items.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: moving, at: destination - source.filter { $0 < destination }.count)
        return rest
    }

    @Test func aDragOfTheAgentsEndsWhereSwiftUIWouldPutThem() throws {
        let text = "[general]\nagents = [\"claude\", \"codex\", \"gemini\", \"opencode\"]\n"
        let state = state(text)
        let items = state.enabledAgents.map(\.id)
        #expect(items == ["claude", "codex", "gemini", "opencode"])
        for from in 0..<items.count {
            for destination in 0...items.count {
                let expected = moved(items, from: IndexSet(integer: from), to: destination)
                #expect(try apply(GeneralSettings.operations(movingAgents: IndexSet(integer: from), to: destination, in: state), to: text).enabledAgents == expected, "\(from) to \(destination)")
            }
        }
        #expect(GeneralSettings.operations(movingAgents: [1], to: 1, in: state).isEmpty)
        #expect(GeneralSettings.operations(movingAgents: [9], to: 0, in: state).isEmpty, "only the enabled agents can be dragged")
    }

    @Test func aMoveKeepsTheCommentsOfTheAgents() throws {
        let text = "[general]\nagents = [\n    \"claude\", # my favourite\n    # the other\n    \"codex\",\n]\n"
        var document = ConfigDocument(text)
        for operation in GeneralSettings.operations(movingAgents: [1], to: 0, in: state(text)) { document = try operation.apply(to: document) }
        #expect(document.text == "[general]\nagents = [\n    # the other\n    \"codex\",\n    \"claude\", # my favourite\n]\n")
    }
}

@Suite("GeneralSettings: the agents are changed by place in the list the file has")
struct GeneralSettingsPlaceTests {
    private func state(shared: String, overlay: String? = nil) -> GeneralSettingsState {
        let merged = overlay.map { ConfigLayers.load(base: .text(shared), local: .text($0)).config } ?? config(shared)
        return GeneralSettings.state(config: merged, facts: machine(), listedAgents: try? ConfigDocument(shared).elements(of: "general.agents") ?? nil)
    }

    private func apply(_ operations: [ConfigOperation], to text: String) throws -> String {
        var document = ConfigDocument(text)
        for operation in operations { document = try operation.apply(to: document) }
        return document.text
    }

    @Test func anAgentListedTwiceIsNotEditedByPlace() throws {
        // The config reads this as claude and codex; the file has three items, so the second row is the third item.
        let text = "[general]\nagents = [\"claude\", \"claude\", \"codex\"]\n"
        let state = state(shared: text)
        #expect(state.enabledAgents.map(\.id) == ["claude", "codex"] && state.listedAgents == ["claude", "claude", "codex"])
        #expect(!state.agentsAreExact)
        #expect(GeneralSettings.operations(disabling: "codex", in: state).isEmpty, "removing place 2 would take out the second claude and leave codex")
        #expect(GeneralSettings.operations(movingAgents: [1], to: 0, in: state).isEmpty)
        #expect(GeneralSettings.operations(enabling: "gemini", in: state).isEmpty)
    }

    @Test func anAgentThatThisMacTurnsOffIsNotEditedByPlace() throws {
        let shared = "[general]\nagents = [\"claude\", \"codex\", \"gemini\"]\n"
        let state = state(shared: shared, overlay: "disabled = [\"claude\"]\n")
        #expect(state.enabledAgents.map(\.id) == ["codex", "gemini"], "this Mac has no Claude Code in its menu")
        #expect(state.listedAgents == ["claude", "codex", "gemini"] && !state.agentsAreExact)
        // Place 1 of the agents shown is codex; place 1 of the file is claude.
        #expect(GeneralSettings.operations(disabling: "codex", in: state).isEmpty)
        #expect(GeneralSettings.operations(movingAgents: [1], to: 0, in: state).isEmpty)
    }

    @Test func aListThatIsAsTheFileSaysIsExact() {
        let text = "[general]\nagents = [\"claude\", \"codex\"]\n"
        #expect(state(shared: text).agentsAreExact)
        #expect(state(shared: text, overlay: "disabled = [\"zed\"]\n").agentsAreExact, "turning off what the list does not name changes nothing")
        #expect(state(shared: "").agentsAreExact, "no list and no agents")
        #expect(state(shared: "[general]\nagents = []\n").agentsAreExact)
    }

    @Test func everyChangeIsHeldToTheListThatWasShown() throws {
        let text = "[general]\nagents = [\"claude\", \"codex\"]\n"
        let state = state(shared: text)
        let operations = GeneralSettings.operations(movingAgents: [1], to: 0, in: state)
        #expect(operations.first == .expect(["claude", "codex"], in: "general.agents"))
        let meanwhile = try ConfigDocument(text).insertingElement("gemini", into: "general.agents", at: 1)
        #expect(throws: ConfigDocument.EditError.changedMeanwhile("general.agents")) {
            var document = meanwhile
            for operation in operations { document = try operation.apply(to: document) }
        }
        #expect(try apply(operations, to: text) == "[general]\nagents = [\"codex\", \"claude\"]\n")
    }

    @Test func theFirstAgentIsAddedOnlyToAFileThatStillWritesNoList() throws {
        let state = state(shared: "[general]\nterminal = \"ghostty\"\n")
        let operations = GeneralSettings.operations(enabling: "claude", in: state)
        #expect(operations == [.expect(nil, in: "general.agents"), .insert("claude", into: "general.agents", at: nil)])
        #expect(throws: ConfigDocument.EditError.changedMeanwhile("general.agents")) {
            _ = try apply(operations, to: "[general]\nagents = [\"codex\"]\n")
        }
    }
}

@Suite("GeneralSettings: what the terminal can do, and what the permission switch would add")
struct GeneralSettingsCapabilityTests {
    private func state(_ text: String = "", applications: [String: URL]? = nil) -> GeneralSettingsState {
        let facts = applications.map { FakeSystemFacts(directories: [], applications: $0) } ?? machine()
        return GeneralSettings.state(config: config(text), facts: facts, listedAgents: nil)
    }

    @Test func onlyGhosttyAndITermOfferMoreThanAWindowAndWarpATab() {
        let all = TerminalPlacement.allCases
        #expect(state().placements == all, "Ghostty is the first installed terminal")
        #expect(state("[general]\nterminal = \"terminal\"\n").placements == [.newWindow], "Terminal opens a window whatever the config says")
        let iterm = ["com.googlecode.iterm2": URL(fileURLWithPath: "/Applications/iTerm.app")]
        #expect(state("[general]\nterminal = \"iterm\"\n", applications: iterm).placements == all)
        let warp = ["dev.warp.Warp-Stable": URL(fileURLWithPath: "/Applications/Warp.app")]
        #expect(state("[general]\nterminal = \"warp\"\n", applications: warp).placements == [.newWindow, .newTab])
        for id in ["wezterm", "kitty", "alacritty", "cmux"] {
            let bundle = KnownApps.terminal(id: id)?.bundleIDs.first ?? ""
            #expect(state("[general]\nterminal = \"\(id)\"\n", applications: [bundle: URL(fileURLWithPath: "/Applications/X.app")]).placements == [.newWindow], "\(id)")
        }
        #expect(GeneralSettings.state(config: config(""), facts: FakeSystemFacts(directories: [], applications: [:]), listedAgents: nil).placements == [.newWindow], "no terminal at all")
    }

    @Test func aPlacementTheTerminalLacksIsSaidToOpenAWindow() {
        let warp = ["dev.warp.Warp-Stable": URL(fileURLWithPath: "/Applications/Warp.app")]
        let kitty = ["net.kovidgoyal.kitty": URL(fileURLWithPath: "/Applications/kitty.app")]
        let split = state("[general]\nterminal = \"warp\"\nterminal_placement = \"split-right\"\n", applications: warp)
        #expect(split.placementFallback == .noSplits)
        #expect(split.effectivePlacement == .newWindow, "the Overview's menu shows the window that opens, not the split Warp does not have")
        #expect(state("[general]\nterminal = \"warp\"\nterminal_placement = \"tab\"\n", applications: warp).effectivePlacement == .newTab)
        #expect(state("[general]\nterminal = \"warp\"\nterminal_placement = \"tab\"\n", applications: warp).placementFallback == nil)
        #expect(state("[general]\nterminal = \"kitty\"\nterminal_placement = \"tab\"\n", applications: kitty).placementFallback == .windowOnly)
        #expect(state("[general]\nterminal = \"kitty\"\n", applications: kitty).placementFallback == nil, "a window is what kitty has")
        #expect(state("[general]\nterminal_placement = \"split-down\"\n").placementFallback == nil, "Ghostty has splits")
    }

    @Test func aTerminalThatOnlyOpensFoldersCannotStartAgents() {
        let warp = ["dev.warp.Warp-Stable": URL(fileURLWithPath: "/Applications/Warp.app")]
        let chosen = state("[general]\nterminal = \"warp\"\n", applications: warp)
        #expect(chosen.usedTerminal == "warp" && !chosen.usedTerminalRunsCommands)
        #expect(chosen.terminals.first { $0.id == "warp" }?.runsCommands == false)
        #expect(state().usedTerminalRunsCommands && state().terminals.allSatisfy { $0.runsCommands })
        #expect(state().editors.allSatisfy { $0.runsCommands }, "an editor is not asked to run commands")
    }

    @Test func eachAgentSaysWhatThePermissionSwitchWouldAddToIt() {
        let state = state("[general]\nagents = [\"claude\", \"goose\"]\n[agent.goose]\nbypass_permissions = false\n[agent.mytool]\nname = \"My Tool\"\ncommand = \"mytool\"\nbypass_permission_arg = \"--yes\"\nbypass_permissions = true\n")
        func agent(_ id: String) -> GeneralSettingsState.Agent? { state.agents.first { $0.id == id } }
        #expect(agent("claude")?.bypassFlag == "--dangerously-skip-permissions" && agent("claude")?.bypassOverride == nil)
        #expect(agent("codex")?.bypassFlag == "--dangerously-bypass-approvals-and-sandbox", "the flag that also turns the sandbox off is the one shown")
        #expect(agent("goose")?.bypassFlag == nil && agent("goose")?.bypassOverride == false, "Goose has no flag of its own, and this one says no")
        #expect(agent("mytool")?.bypassFlag == "--yes" && agent("mytool")?.bypassOverride == true)
    }

    @Test func theSwitchSaysWhatItWouldDoToEachAgentOfTheMenu() {
        let text = "[general]\nagents = [\"claude\", \"codex\", \"goose\", \"gemini\"]\n[agent.gemini]\nbypass_permissions = false\n"
        let lines = state(text).bypassLines
        #expect(lines.map(\.agent) == ["Claude Code", "Codex", "Goose", "Gemini CLI"])
        #expect(lines[0].outcome == .flag("--dangerously-skip-permissions"))
        #expect(lines[1].outcome == .flag("--dangerously-bypass-approvals-and-sandbox"))
        #expect(lines[2].outcome == .noFlag, "Goose has no flag of its own")
        #expect(lines[3].outcome == .keepsAsking, "and its own setting beats the general one")
    }

    @Test func theSwitchAlsoSaysWhatItWouldDoToAnAgentThatAnItemOfTheMenuOrTheQuickActionsNames() {
        // Codex is not in the list of agents, and a click on "Codex Here" in the Quick Actions starts it: with the switch on, without asking.
        let text = "[general]\nagents = [\"claude\"]\n[services]\nitems = [\"open.terminal\", \"agent.codex\"]\n"
        let state = state(text)
        #expect(state.agents.first { $0.id == "codex" }?.offered == true && state.agents.first { $0.id == "goose" }?.offered == false)
        #expect(state.bypassLines.map(\.agent) == ["Claude Code", "Codex"], "\(state.bypassLines)")
        #expect(state.bypassLines.last?.outcome == .flag("--dangerously-bypass-approvals-and-sandbox"))
    }

    @Test func aMenuWithNoAgentsSaysItForEveryAgentThereIs() {
        let lines = state("[general]\nagents = []\n").bypassLines
        #expect(lines.count == KnownAgents.all.count && lines.first?.agent == "Claude Code")
    }

    @Test func theNamesOfWhatIsUsedWhenNothingIsConfigured() {
        #expect(state().automaticTerminalName == "Ghostty" && state().automaticEditorName == "Visual Studio Code")
        #expect(state("[general]\nterminal = \"terminal\"\n").automaticTerminalName == "Ghostty", "the best one that is installed, not the one that is chosen")
        #expect(GeneralSettings.state(config: config(""), facts: FakeSystemFacts(directories: [], applications: [:]), listedAgents: nil).automaticTerminalName == nil)
    }

    @Test func anAgentCarriesTheCommandThatStartsIt() {
        let state = state("[agent.mytool]\nname = \"My Tool\"\ncommand = \"mytool --fast\"\n[general]\nagents = [\"mytool\"]\n")
        #expect(state.agents.first { $0.id == "mytool" }?.command == "mytool --fast")
        #expect(state.agents.first { $0.id == "claude" }?.command == "claude")
    }
}
