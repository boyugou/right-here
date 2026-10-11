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
    @Test func defaultMenuHasTerminalEditorNewFileAndCopyPath() {
        let menu = MenuBuilder(config: .default, facts: machine()).build(for: background)
        #expect(titles(menu) == ["Open in Ghostty", "Open in Visual Studio Code", "-", "New File", "Copy Path"])
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
        #expect(titles(newFile.children) == ["Text Document", "Markdown Document"])
        #expect(newFile.children.map(\.actionID) == ["new-file.txt", "new-file.md"])
        let copy = try #require(menu.first { $0.title == "Copy Path" })
        #expect(titles(copy.children) == ["Full Path", "Path from Home (~)", "Path from Git Root", "File Name", "Shell-Escaped Path", "@ Mention for AI"])
    }

    @Test func enabledAgentsAppearWithTheirVariantsInTheMoreMenu() throws {
        let config = Config(enabledAgents: ["claude", "codex"])
        let menu = MenuBuilder(config: config, facts: machine()).build(for: background)
        #expect(titles(menu).prefix(4) == ["Open in Ghostty", "Open in Visual Studio Code", "Claude Code Here", "Codex Here"])
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
        #expect(info.unavailableReason == "Warp cannot run commands yet.")
    }

    @Test func agentLinksNeedNoTerminalAdapter() {
        let registry = ActionRegistry(config: .default, facts: machine(installed: ["com.anthropic.claudefordesktop"]))
        #expect(registry.info(.agent(id: "claude", variant: nil, launcher: .terminalLink)).available)
        #expect(registry.info(.agent(id: "claude", variant: nil, launcher: .desktop)).available)
        #expect(!ActionRegistry(config: .default, facts: machine()).info(.agent(id: "claude", variant: nil, launcher: .desktop)).available)
    }
}
