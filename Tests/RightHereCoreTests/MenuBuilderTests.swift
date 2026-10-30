import Foundation
import Testing
@testable import RightHereCore

private func machine(installed: [String] = ["com.mitchellh.ghostty", "com.apple.Terminal", "com.microsoft.VSCode", "dev.zed.Zed"]) -> FakeSystemFacts {
    FakeSystemFacts(
        directories: ["/Users/tester/code"],
        applications: Dictionary(uniqueKeysWithValues: installed.map { ($0, URL(fileURLWithPath: "/Applications/\($0).app")) })
    )
}

private let background = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/code"))

private func titles(_ nodes: [MenuNode]) -> [String] {
    nodes.map { $0.kind == .separator ? "-" : $0.title }
}

@Suite("MenuBuilder")
struct MenuBuilderTests {
    @Test func defaultMenuHasTerminalEditorOpenWithNewFileAndCopyPath() {
        let menu = MenuBuilder(config: .default, facts: machine()).build(for: background)
        #expect(titles(menu) == ["Open in Ghostty", "Open in Visual Studio Code", "Open With", "-", "New File", "Copy Path"])
    }

    @Test func openWithLeavesOutWhatTheMenuAlreadyOffers() throws {
        let menu = MenuBuilder(config: .default, facts: machine()).build(for: background)
        let submenu = try #require(menu.first { $0.title == "Open With" })
        #expect(titles(submenu.children) == ["Terminal", "-", "Zed"])
    }

    @Test func entriesCarryTheirAppIconAndActionId() throws {
        let menu = MenuBuilder(config: .default, facts: machine()).build(for: background)
        let terminal = try #require(menu.first)
        #expect(terminal.actionID == "open.terminal")
        #expect(terminal.icon == .app("com.mitchellh.ghostty"))
    }

    @Test func submenusUseShortTitles() throws {
        let menu = MenuBuilder(config: .default, facts: machine()).build(for: background)
        let newFile = try #require(menu.first { $0.title == "New File" })
        #expect(titles(newFile.children) == ["Text Document", "Markdown Document", "Word Document", "Excel Workbook", "PowerPoint Presentation"])
        #expect(newFile.children.map(\.actionID) == ["new-file.txt", "new-file.md", "new-file.docx", "new-file.xlsx", "new-file.pptx"])
        // new_file.hidden leaves a template out of the submenu; it stays an action of its own.
        var config = Config.default
        config.newFile.hidden = ["docx", "xlsx", "pptx"]
        let fewer = try #require(MenuBuilder(config: config, facts: machine()).build(for: background).first { $0.title == "New File" })
        #expect(fewer.children.map(\.actionID) == ["new-file.txt", "new-file.md"])
        #expect(ActionRegistry(config: config, facts: machine()).info(.newFile("docx")).available)
        let copy = try #require(menu.first { $0.title == "Copy Path" })
        #expect(titles(copy.children) == ["Full Path", "Path from Home (~)", "Path from Git Root", "File Name", "Shell-Escaped Path", "@ Mention for AI"])
    }

    @Test func newFileEntriesCarryTheIconOfTheirKindOfFile() throws {
        let menu = MenuBuilder(config: .default, facts: machine()).build(for: background)
        let newFile = try #require(menu.first { $0.title == "New File" })
        #expect(newFile.children.map(\.icon) == ["txt", "md", "docx", "xlsx", "pptx"].map { .fileType($0) })
    }

    @Test func explainSaysWhichAgentEntriesStartWithTheirPermissionPromptsOff() throws {
        var config = Config(enabledAgents: ["claude", "codex"])
        config.agents["claude"] = .init(bypassPermissions: true)
        let explained = MenuBuilder(config: config, facts: machine()).explain(for: background)
        let notes = explained.notes.filter { $0.reason.contains("permission prompts switched off") }
        #expect(notes.count == 1)
        #expect(notes.first?.kind == .changed)
        #expect(notes.first?.entry == "Claude Code Here")
        #expect(notes.first?.reason.contains("--dangerously-skip-permissions") == true)
        // The menu itself is the same either way: only the explanation tells.
        #expect(titles(explained.menu) == titles(MenuBuilder(config: Config(enabledAgents: ["claude", "codex"]), facts: machine()).build(for: background)))
    }

    @Test func aCopyPathTitleNeverGivesTwoListedEntriesOneTitle() {
        let config = Config(menuItems: ["copy-path.absolute", "copy-path.name"], copyPathTitle: "Copy")
        let listed = titles(MenuBuilder(config: config, facts: machine()).build(for: background))
        #expect(listed.count == 2 && listed[0] == "Copy" && listed[1] != "Copy", "titles: \(listed)")
    }

    @Test func theMoreMenuDoesNotRepeatTheTerminalTheAgentEntryAlreadyUses() throws {
        // cmux is the preferred default for opening a folder but cannot be typed into yet, so "Claude Code Here" runs in
        // Terminal; "Claude Code in Terminal" would be the same action twice.
        let facts = machine(installed: ["com.cmuxterm.app", "com.apple.Terminal"])
        let menu = MenuBuilder(config: Config(enabledAgents: ["claude"]), facts: facts).build(for: background)
        let plain = try #require(menu.first { $0.title == "Claude Code Here" })
        #expect(plain.actionID == "agent.claude")
        let more = try #require(menu.first { $0.title == "More Agent Options" })
        #expect(!more.children.compactMap(\.actionID).contains("agent.claude@terminal"))

        // iTerm can be typed into, so "Claude Code Here" runs in iTerm; "Claude Code in iTerm" is not repeated.
        let itermFacts = machine(installed: ["com.googlecode.iterm2", "com.apple.Terminal"])
        let itermMenu = MenuBuilder(config: Config(enabledAgents: ["claude"]), facts: itermFacts).build(for: background)
        let itermMore = try #require(itermMenu.first { $0.title == "More Agent Options" })
        #expect(!itermMore.children.compactMap(\.actionID).contains("agent.claude@iterm"))
        #expect(itermMore.children.compactMap(\.actionID).contains("agent.claude@terminal"))
    }

    @Test func enabledAgentsAppearWithTheirVariantsInTheMoreMenu() throws {
        let config = Config(enabledAgents: ["claude", "codex"])
        let menu = MenuBuilder(config: config, facts: machine()).build(for: background)
        #expect(titles(menu).prefix(5) == ["Open in Ghostty", "Open in Visual Studio Code", "Open With", "Claude Code Here", "Codex Here"])
        let more = try #require(menu.first { $0.title == "More Agent Options" })
        let ids = more.children.compactMap(\.actionID)
        #expect(ids.contains("agent.claude.continue"))
        #expect(ids.contains("agent.claude.resume"))
        #expect(ids.contains("agent.claude@link"))
        #expect(ids.contains("agent.codex.last"))
        #expect(ids.contains("agent.claude@terminal"))
    }

    @Test func uninstalledAppsAreHidden() {
        let menu = MenuBuilder(config: .default, facts: machine(installed: ["com.apple.Terminal"])).build(for: background)
        #expect(titles(menu) == ["Open in Terminal", "-", "New File", "Copy Path"])
    }

    @Test func newFileIsHiddenWithSeveralSelectedItems() {
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/a"), URL(fileURLWithPath: "/Users/tester/code/b")])
        let menu = MenuBuilder(config: .default, facts: machine()).build(for: context)
        #expect(!titles(menu).contains("New File"))
    }

    @Test func configuredLayoutIsFollowedAndTidied() {
        let config = Config(menuItems: ["-", "copy-path", "-", "-", "open.app.zed", "nonsense", "open.terminal@terminal", "-"])
        let menu = MenuBuilder(config: config, facts: machine()).build(for: background)
        #expect(titles(menu) == ["Copy Path", "-", "Open in Zed", "Open in Terminal"])
    }

    @Test func copyPathStylesAreConfigurable() throws {
        let config = Config(menuItems: ["copy-path"], copyPathStyles: [.absolute, .aiMention])
        let menu = MenuBuilder(config: config, facts: machine()).build(for: background)
        #expect(menu.count == 1)
        #expect(menu[0].children.map(\.actionID) == ["copy-path.absolute", "copy-path.ai-mention"])
    }

    @Test func singleStyleBecomesAFlatEntry() {
        let config = Config(menuItems: ["copy-path"], copyPathStyles: [.absolute])
        let menu = MenuBuilder(config: config, facts: machine()).build(for: background)
        #expect(menu.map(\.actionID) == ["copy-path.absolute"])
        #expect(menu.first?.title == "Copy Path")
    }

    @Test func customCopyPathTitleIsUsed() {
        let config = Config(menuItems: ["copy-path"], copyPathStyles: [.absolute], copyPathTitle: "Copy Path Clean")
        let menu = MenuBuilder(config: config, facts: machine()).build(for: background)
        #expect(menu.first?.title == "Copy Path Clean")
    }

    @Test func singleNonAbsoluteStyleKeepsSpecificTitleWhenNotCustom() {
        let config = Config(menuItems: ["copy-path"], copyPathStyles: [.tilde])
        let menu = MenuBuilder(config: config, facts: machine()).build(for: background)
        #expect(menu.first?.title == "Copy Path: Path from Home (~)")
    }

    @Test func openWithListsInstalledAppsOnly() throws {
        let config = Config(menuItems: ["open-with"])
        let menu = MenuBuilder(config: config, facts: machine()).build(for: background)
        let submenu = try #require(menu.first)
        #expect(titles(submenu.children) == ["Ghostty", "Terminal", "-", "Visual Studio Code", "Zed"])
    }

    @Test func everyDefaultActionIdParses() {
        let menu = MenuBuilder(config: .default, facts: machine()).build(for: background)
        for id in menu.flatMap(\.actionIDs) {
            #expect(ActionRef(parsing: id) != nil, "\(id) does not parse")
        }
    }

    @Test func menuIsDeterministic() {
        let builder = MenuBuilder(config: .default, facts: machine())
        #expect(builder.build(for: background) == builder.build(for: background))
    }
}

private func flatten(_ nodes: [MenuNode]) -> [MenuNode] {
    nodes.flatMap { [$0] + flatten($0.children) }
}

/// "More Agent Options" lists what the plain "<Agent> Here" entry does not: that entry is whatever the agent's launcher
/// says, so the submenu leaves out that launcher and offers the rest.
@Suite("MenuBuilder: More Agent Options")
struct MoreAgentOptionsTests {
    private let facts = FakeSystemFacts(
        directories: ["/Users/tester/code"],
        applications: [
            "com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"),
            "com.apple.Terminal": URL(fileURLWithPath: "/Applications/Terminal.app"),
            "com.anthropic.claudefordesktop": URL(fileURLWithPath: "/Applications/Claude.app")
        ],
        bundleVersions: ["com.mitchellh.ghostty": "1.3.1"]
    )

    private func menu(_ toml: String) -> (menu: [MenuNode], config: Config) {
        let config = ConfigParser.parse(toml).config
        return (MenuBuilder(config: config, facts: facts).build(for: background), config)
    }

    private func claude(_ launcher: String) -> String { "[general]\nagents = [\"claude\"]\n[agent.claude]\n\(launcher)\n" }

    /// The terminal a plan types the bare command `claude` into, if it does.
    private func typedInto(_ id: String, config: Config) -> String? {
        guard let ref = ActionRef(parsing: id), let plan = try? Planner(config: config, facts: facts).plan(ref, context: background) else { return nil }
        for step in plan.steps {
            guard case .appleScript(let script) = step else { continue }
            // Ghostty is given the folder and the typed text apart; Terminal is given one line that starts with `cd <folder> &&`.
            if script.arguments.count > 1, script.arguments[1] == "claude" { return script.controls }
            if script.arguments.count == 1, script.arguments[0].hasSuffix(" && claude") { return script.controls }
        }
        return nil
    }

    private func more(_ nodes: [MenuNode]) -> [MenuNode] {
        nodes.first { $0.title == "More Agent Options" }?.children ?? []
    }

    @Test("a launcher that is the plain entry is not offered a second time", arguments: ["launcher = \"desktop\"", "launcher = \"link\""])
    func theLauncherOfThePlainEntryIsNotRepeated(launcher: String) {
        let built = menu(claude(launcher))
        let entries = flatten(built.menu).filter { $0.actionID?.hasPrefix("agent.claude") == true }
        let titles = entries.map(\.title)
        #expect(Set(titles).count == titles.count, "the same title more than once: \(entries.map { "\($0.title) (\($0.actionID ?? ""))" })")
        let plain = launcher.contains("desktop") ? "agent.claude@desktop" : "agent.claude@link"
        #expect(!more(built.menu).compactMap(\.actionID).contains(plain), "the plain entry already is \(plain)")
    }

    @Test("an agent that starts in its desktop app or by its link can still be started in the default terminal, from the menu",
          arguments: ["launcher = \"desktop\"", "launcher = \"link\""])
    func theTypedLaunchInTheDefaultTerminalIsOffered(launcher: String) {
        let built = menu(claude(launcher))
        let ids = more(built.menu).compactMap(\.actionID)
        #expect(ids.contains("agent.claude@ghostty"), "\(ids)")
        let typed = flatten(built.menu).compactMap(\.actionID).filter { typedInto($0, config: built.config) != nil }
        #expect(typed.contains("agent.claude@ghostty") && !typed.contains("agent.claude"), "the entries that type `claude` into a terminal: \(typed)")
        #expect(typedInto("agent.claude@ghostty", config: built.config) == "Ghostty")
        #expect(flatten(built.menu).first { $0.actionID == "agent.claude@ghostty" }?.title == "Claude Code in Ghostty")
    }

    @Test func anAgentWithATerminalOfItsOwnIsNotOfferedThatTerminalAgain() {
        // "Claude Code Here" types into Terminal here, so "Claude Code in Terminal" would be the same action twice, and Ghostty,
        // the default terminal the plain entry does not use, has to be there.
        let built = menu(claude("terminal = \"terminal\""))
        #expect(typedInto("agent.claude", config: built.config) == "Terminal")
        let ids = more(built.menu).compactMap(\.actionID)
        #expect(!ids.contains("agent.claude@terminal"), "\(ids)")
        #expect(ids.contains("agent.claude@ghostty"), "\(ids)")
    }

    @Test func theDefaultLauncherIsCoveredByThePlainEntryAndNotRepeated() {
        let built = menu("[general]\nagents = [\"claude\"]\n")
        let ids = more(built.menu).compactMap(\.actionID)
        #expect(!ids.contains("agent.claude@ghostty") && ids.contains("agent.claude@terminal"), "\(ids)")
        #expect(typedInto("agent.claude", config: built.config) == "Ghostty")
    }

    @Test func withoutThePlainEntriesTheSubmenuLeavesNothingOut() {
        // `agents` is not among the entries, so nothing in the menu starts the agent the plain way.
        let built = menu("[general]\nagents = [\"claude\"]\n[menu]\nitems = [\"agents-more\"]\n")
        let ids = more(built.menu).compactMap(\.actionID)
        #expect(ids.contains("agent.claude@ghostty") && ids.contains("agent.claude@terminal") && ids.contains("agent.claude@link"), "\(ids)")
        // An agent named by its own id is the plain entry for that agent only.
        let named = menu("[general]\nagents = [\"claude\", \"codex\"]\n[menu]\nitems = [\"agent.claude\", \"agents-more\"]\n")
        let namedIDs = more(named.menu).compactMap(\.actionID)
        #expect(!namedIDs.contains("agent.claude@ghostty") && namedIDs.contains("agent.codex@ghostty"), "\(namedIDs)")
    }
}

/// `explain` is the menu plus what it leaves out and changes, built by the same code, so what it says cannot disagree with the menu.
@Suite("MenuBuilder: explain")
struct MenuExplainTests {
    private let folder = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/code"))

    private func facts(_ installed: [String], directories: Set<String> = ["/Users/tester/code"], versions: [String: String] = [:]) -> FakeSystemFacts {
        FakeSystemFacts(directories: directories, applications: Dictionary(uniqueKeysWithValues: installed.map { ($0, URL(fileURLWithPath: "/Applications/\($0).app")) }), bundleVersions: versions)
    }

    private func explain(_ toml: String, _ machine: FakeSystemFacts, _ context: HereContext? = nil) -> MenuExplanation {
        MenuBuilder(config: ConfigParser.parse(toml).config, facts: machine).explain(for: context ?? folder)
    }

    @Test func theMenuItExplainsIsTheMenuBuildMakes() {
        let machine = facts(["com.mitchellh.ghostty", "com.apple.Terminal", "com.microsoft.VSCode"], versions: ["com.mitchellh.ghostty": "1.3.1"])
        let several = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/a"), URL(fileURLWithPath: "/Users/tester/code/b")])
        for toml in ["", "[general]\nagents = [\"claude\", \"codex\"]\n", "[general]\nterminal = \"iterm\"\neditor = \"zed\"\nagents = [\"claude\"]\n",
                     "[menu]\nitems = [\"agents-more\", \"presets\", \"nonsense\", \"open.app.zed\"]\n[general]\nagents = [\"claude\"]\n"] {
            let config = ConfigParser.parse(toml).config
            let builder = MenuBuilder(config: config, facts: machine)
            for context in [folder, several] { #expect(builder.explain(for: context).menu == builder.build(for: context), "\(toml)") }
        }
    }

    @Test func anAppThatIsNotInstalledAndAnEmptyAgentListAreSaidWithTheirReasons() {
        let explained = explain("", facts(["com.apple.Terminal"]))
        #expect(explained.leftOut.map(\.line) == [
            "Open in Editor: No editor is installed.",
            "Open With: no other terminal or editor is installed.",
            "Agents: none is enabled; general.agents lists none."
        ], "\(explained.leftOut.map(\.line))")
        #expect(explained.changed.isEmpty)
        #expect(explained.emptyMenuSummary == nil, "New File and Copy Path are there")
    }

    @Test func aDefaultThatAnotherAppReplacedIsSaidAsAChange() {
        let machine = facts(["com.mitchellh.ghostty", "com.microsoft.VSCode"], versions: ["com.mitchellh.ghostty": "1.3.1"])
        let explained = explain("[general]\nterminal = \"iterm\"\neditor = \"zed\"\nagents = [\"claude\"]\n", machine)
        #expect(explained.changed.map(\.line) == [
            "Open in Ghostty: iTerm is not installed; Ghostty is used instead.",
            "Open in Visual Studio Code: Zed is not installed; Visual Studio Code is used instead."
        ], "\(explained.changed.map(\.line))")
        #expect(explained.menu.first?.title == "Open in Ghostty")
        // The agents are typed into the same replacement, and the same sentence is not said twice.
        #expect(explain("[general]\nterminal = \"iterm\"\nagents = [\"claude\"]\n", machine).changed.count == 1)
    }

    @Test func aTerminalThatCannotRunACommandIsTheAgentsFallbackAndSaysSoOnItsOwn() {
        // Warp opens a folder; Terminal has to take the agents.
        let machine = facts(["dev.warp.Warp-Stable", "com.apple.Terminal"])
        let explained = explain("[general]\nterminal = \"iterm\"\nagents = [\"claude\"]\n", machine)
        #expect(explained.changed.map(\.line) == [
            "Open in Warp: iTerm is not installed; Warp is used instead.",
            "Agents: iTerm is not installed; Terminal is used instead."
        ], "\(explained.changed.map(\.line))")
    }

    @Test func presetsOnAFolderAreLeftOutWithTheSentenceRunSays() {
        let machine = facts(["com.mitchellh.ghostty"], versions: ["com.mitchellh.ghostty": "1.3.1"])
        let toml = "[general]\nagents = [\"claude\"]\n"
        for context in [folder, HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code")])] {
            let explained = explain(toml, FakeSystemFacts(directories: ["/Users/tester/code"], applications: machine.applications, bundleVersions: machine.bundleVersions), context)
            #expect(explained.leftOut.contains { $0.entry == "Agent Presets" && $0.reason.contains("select one or more files") }, "\(explained.leftOut.map(\.line))")
        }
    }

    @Test func severalSelectedItemsAndAnEmptyCopyPathAreSaid() {
        let machine = facts(["com.apple.Terminal"])
        let several = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/a"), URL(fileURLWithPath: "/Users/tester/code/b")])
        #expect(explain("", machine, several).leftOut.contains { $0.entry == "New File" && $0.reason.contains("several items are selected") })
        let none = explain("[copy_path]\nstyles = []\n", machine)
        #expect(none.leftOut.contains { $0.line == "Copy Path: copy_path.styles lists no style." })
    }

    @Test func anEntryTheConfigNamesIsSaidWhetherItIsUnknownOrNotInstalled() {
        let explained = explain("[menu]\nitems = [\"open.app.zed\", \"nonsense\", \"copy-path\"]\n", facts(["com.apple.Terminal"]))
        #expect(explained.leftOut.map(\.line) == ["Open in Zed: Zed is not installed.", "nonsense: it is not a menu group or an action id."], "\(explained.leftOut.map(\.line))")
    }

    @Test func whatThePerMachineOverlayDisabledIsToldApartFromWhatWasNeverThere() {
        // `Config` keeps the apps the overlay removed; the agents are the ones the shared file enables and the merged config does not.
        let machine = facts(["com.apple.Terminal", "dev.zed.Zed"])
        var merged = Config(enabledAgents: ["codex"], menuItems: ["agents", "open.app.zed"])
        merged.disabledApps = ["zed"]
        let shared = Config(enabledAgents: ["claude", "codex"])
        let explained = MenuBuilder(config: merged, facts: machine).explain(for: folder, sharedConfig: shared, overlayName: "config.local.toml")
        #expect(explained.leftOut.map(\.line).contains("Claude Code Here: the agent is disabled on this Mac by config.local.toml."), "\(explained.leftOut.map(\.line))")
        #expect(explained.leftOut.map(\.line).contains("Open in Zed: Zed is disabled on this Mac by config.local.toml."), "\(explained.leftOut.map(\.line))")
        // Without the shared file's agents nothing is guessed.
        #expect(!MenuBuilder(config: merged, facts: machine).explain(for: folder).leftOut.contains { $0.reason.contains("disabled on this Mac") && $0.entry.contains("Claude") })
    }

    @Test func aMenuThatIsEmptyForAFolderSaysWhy() {
        let machine = facts(["com.apple.Terminal"])
        let toml = "[general]\nagents = []\n[copy_path]\nstyles = []\n[menu]\nitems = [\"agents\", \"presets\", \"agents-more\", \"copy-path\"]\n"
        let explained = explain(toml, machine)
        #expect(explained.menu.isEmpty)
        #expect(explained.emptyMenuSummary == "the Finder menu would be empty for a folder: Agents: none is enabled; general.agents lists none; Copy Path: copy_path.styles lists no style")
        let listless = explain("[menu]\nitems = []\n", machine)
        #expect(listless.menu.isEmpty && listless.leftOut.map(\.line) == ["Menu: menu.items lists no entry."])
    }
}

@Suite("ActionRegistry")
struct ActionRegistryTests {
    @Test func catalogHasUniqueIds() {
        let ids = ActionRegistry(config: .default, facts: machine()).catalog().map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func availabilityFollowsInstalledApps() throws {
        let registry = ActionRegistry(config: .default, facts: machine(installed: ["com.apple.Terminal"]))
        let zed = registry.info(.openApp("zed"))
        #expect(!zed.available)
        #expect(zed.unavailableReason == "Zed is not installed.")
        #expect(registry.info(.openTerminal("terminal")).available)
    }

    @Test func agentsAreAvailableWhenTheTerminalCanRunCommands() {
        let info = ActionRegistry(config: .default, facts: machine()).info(.agent(id: "claude", variant: nil, launcher: nil))
        #expect(info.title == "Claude Code Here")
        #expect(info.available)
    }

    @Test func agentsAreUnavailableWhileTheTerminalCannotRunCommands() {
        let facts = machine(installed: ["dev.warp.Warp-Stable"])
        let info = ActionRegistry(config: Config(terminal: "warp"), facts: facts).info(.agent(id: "claude", variant: nil, launcher: nil))
        #expect(!info.available)
        #expect(info.unavailableReason == "Warp cannot run commands yet. Choose another terminal for this agent.")
    }

    @Test func agentLinksNeedNoTerminalAdapter() {
        let registry = ActionRegistry(config: .default, facts: machine(installed: ["com.anthropic.claudefordesktop"]))
        #expect(registry.info(.agent(id: "claude", variant: nil, launcher: .terminalLink)).available)
        #expect(registry.info(.agent(id: "claude", variant: nil, launcher: .desktop)).available)
        #expect(!ActionRegistry(config: .default, facts: machine()).info(.agent(id: "claude", variant: nil, launcher: .desktop)).available)
    }
}

@Suite("Menu with replaced apps")
struct MenuReplacedAppTests {
    @Test func aReplacedBuiltInAppAppearsOnceInOpenWith() throws {
        var config = Config.default
        config.menuItems = ["open-with"]
        config.apps = [AppDescriptor(id: "zed", name: "My Zed", bundleIDs: ["com.example.zed"], role: .editor)]
        let facts = FakeSystemFacts(
            directories: ["/Users/tester/code"],
            applications: ["com.example.zed": URL(fileURLWithPath: "/Applications/Zed.app"), "dev.zed.Zed": URL(fileURLWithPath: "/Applications/Z.app"),
                           "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Code.app")]
        )
        let menu = MenuBuilder(config: config, facts: facts).build(for: HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/code")))
        let group = try #require(menu.first)
        let zeds = group.children.filter { $0.actionID == "open.app.zed" }
        #expect(zeds.count == 1)
        #expect(zeds.first?.title.contains("My Zed") == true)
    }
}
