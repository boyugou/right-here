import Foundation
import Testing
@testable import RightHereCore

private func machine() -> FakeSystemFacts {
    FakeSystemFacts(
        directories: ["/Users/tester/code"],
        applications: ["com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"), "com.apple.Terminal": URL(fileURLWithPath: "/Applications/Terminal.app"),
                       "dev.warp.Warp-Stable": URL(fileURLWithPath: "/Applications/Warp.app")]
    )
}

private func config(_ text: String) -> Config { ConfigParser.parse(text).config }

@Suite("AgentOptions: one agent's own settings as something to edit")
struct AgentOptionsTests {
    private func options(_ id: String, _ text: String = "") -> AgentOptionsState {
        AgentOptions.state(id: id, config: config(text), facts: machine(), listedArgs: (try? ConfigDocument(text).elements(of: "agent.\(id).args")) ?? nil)!
    }

    private func apply(_ operations: [ConfigOperation], to text: String) throws -> Config {
        var document = ConfigDocument(text)
        for operation in operations { document = try operation.apply(to: document) }
        return config(document.text)
    }

    @Test func aBuiltInAgentIsAsItIsBuiltAndAnAgentOfTheConfigIsAsTheConfigSaysIt() {
        let claude = options("claude")
        #expect(claude.isBuiltIn && claude.name == "Claude Code" && claude.command == "claude" && claude.builtInCommand == "claude")
        #expect(claude.launcher == .terminal && claude.launchers == [.terminal, .link, .desktop] && claude.terminal == nil && claude.args.isEmpty && claude.bypassOverride == nil)
        #expect(claude.builtInBypassArgument == "--dangerously-skip-permissions")
        #expect(options("codex").launchers == [.terminal, .desktop], "Codex has a desktop app and no terminal link")
        #expect(options("goose").launchers == [.terminal])
        let mine = options("mine", "[agent.mine]\nname = \"Mine\"\ncommand = \"mine --fast\"\nargs = [\"-v\"]\nbypass_permissions = false\nbypass_permission_arg = \"--yes\"\nterminal = \"terminal\"\n")
        #expect(!mine.isBuiltIn && mine.name == "Mine" && mine.command == "mine --fast" && mine.builtInCommand == nil && mine.launchers == [.terminal])
        #expect(mine.args == ["-v"] && mine.bypassOverride == false && mine.bypassArgument == "--yes" && mine.terminal == "terminal")
        #expect(AgentOptions.state(id: "nonsense", config: config(""), facts: machine(), listedArgs: nil) == nil)
    }

    @Test func anAgentThatNamesNoTerminalIsTypedIntoTheTerminalAStartUses() {
        // The default terminal when it is installed, as the plan does (not the first that is installed), and the first that can run a command when it is not.
        #expect(AgentOptions.state(id: "claude", config: config("[general]\nterminal = \"terminal\"\n"), facts: machine(), listedArgs: nil)?.automaticTerminal?.id == "terminal")
        #expect(options("claude").automaticTerminal?.id == "ghostty")
        let warp = AgentOptions.state(id: "claude", config: config("[general]\nterminal = \"warp\"\n"), facts: machine(), listedArgs: nil)
        #expect(warp?.automaticTerminal?.id == "warp" && warp?.automaticTerminal?.runsCommands == false, "a terminal that only opens folders is what a start would use, and it cannot run an agent")
        #expect(AgentOptions.state(id: "claude", config: config(""), facts: FakeSystemFacts(), listedArgs: nil)?.automaticTerminal == nil)
    }

    @Test func theLauncherAndTheTerminalAreWhatTheConfigAsksFor() {
        let link = options("claude", "[agent.claude]\nlauncher = \"link\"\n")
        #expect(link.launcher == .link)
        #expect(options("claude", "[agent.claude]\nlauncher = \"desktop\"\n").launcher == .desktop)
        let chosen = options("claude", "[agent.claude]\nterminal = \"warp\"\n")
        #expect(chosen.launcher == .terminal && chosen.terminal == "warp")
        #expect(options("claude").terminals.map(\.id) == ["ghostty", "terminal"], "Warp only opens folders: an agent cannot be typed into it, so it is not offered")
        let warp = chosen.terminals.last
        #expect(warp?.id == "warp" && warp?.installed == true && warp?.runsCommands == false, "a choice the config makes is shown as it is, so that it can be seen and changed")
        let missing = options("claude", "[agent.claude]\nterminal = \"iterm\"\n")
        #expect(missing.terminals.last?.id == "iterm" && missing.terminals.last?.installed == false, "the choice is shown, as not installed")
    }

    @Test func eachSettingIsOneChangeAndNothingIsWrittenWhenItWouldNotChange() throws {
        let claude = options("claude")
        #expect(AgentOptions.operations(settingCommand: "claude --model opus", of: claude) == [.set("agent.claude.command", .string("claude --model opus"))])
        #expect(AgentOptions.operations(settingCommand: "claude", of: claude).isEmpty && AgentOptions.operations(settingCommand: "  ", of: claude).isEmpty)
        let changed = options("claude", "[agent.claude]\ncommand = \"claude --model opus\"\n")
        #expect(AgentOptions.operations(settingCommand: "claude", of: changed) == [.unset("agent.claude.command")], "the built-in command is the setting taken out")
        #expect(AgentOptions.operations(settingLauncher: .link, of: claude) == [.set("agent.claude.launcher", .string("link"))])
        #expect(AgentOptions.operations(settingLauncher: .desktop, of: options("goose")).isEmpty, "Goose has no desktop app")
        #expect(AgentOptions.operations(settingLauncher: .terminal, of: options("claude", "[agent.claude]\nlauncher = \"link\"\n")) == [.unset("agent.claude.launcher")])
        #expect(AgentOptions.operations(settingTerminal: "terminal", of: claude) == [.set("agent.claude.terminal", .string("terminal"))])
        #expect(AgentOptions.operations(settingTerminal: nil, of: claude).isEmpty && AgentOptions.operations(settingTerminal: nil, of: options("claude", "[agent.claude]\nterminal = \"terminal\"\n")) == [.unset("agent.claude.terminal")])
        #expect(AgentOptions.operations(settingBypass: true, of: claude) == [.set("agent.claude.bypass_permissions", .boolean(true))])
        #expect(AgentOptions.operations(settingBypass: false, of: claude) == [.set("agent.claude.bypass_permissions", .boolean(false))])
        #expect(AgentOptions.operations(settingBypass: nil, of: options("claude", "[agent.claude]\nbypass_permissions = false\n")) == [.unset("agent.claude.bypass_permissions")])
        #expect(AgentOptions.operations(settingBypassArgument: "--yes", of: claude) == [.set("agent.claude.bypass_permission_arg", .string("--yes"))])
        #expect(AgentOptions.operations(settingBypassArgument: "", of: options("claude", "[agent.claude]\nbypass_permission_arg = \"--yes\"\n")) == [.unset("agent.claude.bypass_permission_arg")])
        let mine = options("mine", "[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n")
        #expect(AgentOptions.operations(settingName: "Mine Two", of: mine) == [.set("agent.mine.name", .string("Mine Two"))])
        #expect(AgentOptions.operations(settingName: "Other", of: claude).isEmpty, "a built-in agent has its own name and no other")
    }

    @Test func everyChangeReadsBackAsWhatWasChosen() throws {
        let text = "[agent.claude]\nargs = [\"--a\"]\n"
        let claude = options("claude", text)
        let changed = try apply(AgentOptions.operations(settingCommand: "claude --model opus", of: claude) + AgentOptions.operations(settingLauncher: .link, of: claude)
            + AgentOptions.operations(settingBypass: false, of: claude) + AgentOptions.operations(settingTerminal: "terminal", of: claude), to: text)
        #expect(changed.agent(id: "claude")?.command == "claude --model opus")
        #expect(changed.agents["claude"]?.launcher == .terminalLink && changed.agents["claude"]?.bypassPermissions == false)
        #expect(changed.agents["claude"]?.args == ["--a"], "what else the table holds stays")
    }

    @Test func theArgumentsAreAListChangedByPlaceUnderTheCheckOfTheListThatWasShown() throws {
        let text = "[agent.claude]\nargs = [\"--a\", \"--b\", \"--c\"]\n"
        let claude = options("claude", text)
        #expect(claude.argsAreExact)
        #expect(try apply(AgentOptions.operations(addingArgument: "--d", to: claude), to: text).agents["claude"]?.args == ["--a", "--b", "--c", "--d"])
        #expect(try apply(AgentOptions.operations(removingArgumentAt: 2, of: claude), to: text).agents["claude"]?.args == ["--a", "--c"])
        #expect(try apply(AgentOptions.operations(settingArgumentAt: 2, to: "--bee", of: claude), to: text).agents["claude"]?.args == ["--a", "--bee", "--c"])
        #expect(try apply(AgentOptions.operations(movingArguments: [2], to: 0, of: claude), to: text).agents["claude"]?.args == ["--c", "--a", "--b"])
        #expect(AgentOptions.operations(removingArgumentAt: 4, of: claude).isEmpty && AgentOptions.operations(addingArgument: "  ", to: claude).isEmpty)
        #expect(AgentOptions.operations(settingArgumentAt: 2, to: "--b", of: claude).isEmpty)
        let operations = AgentOptions.operations(removingArgumentAt: 1, of: claude)
        #expect(operations.first == .expect(["--a", "--b", "--c"], in: "agent.claude.args"))
        let meanwhile = try ConfigDocument(text).insertingElement("--z", into: "agent.claude.args", at: 1)
        #expect(throws: ConfigDocument.EditError.changedMeanwhile("agent.claude.args")) { var document = meanwhile; for operation in operations { document = try operation.apply(to: document) } }
        // Nothing is written yet: the first argument writes the list, under the check that it was not written.
        let first = AgentOptions.operations(addingArgument: "--x", to: options("claude"))
        #expect(first == [.expect(nil, in: "agent.claude.args"), .insert("--x", into: "agent.claude.args", at: nil)])
    }

    @Test func aListThatThisMacChangesIsNotChangedByPlace() {
        let shared = "[agent.claude]\nargs = [\"--a\", \"--a\"]\n"
        let duplicated = AgentOptions.state(id: "claude", config: config(shared), facts: machine(), listedArgs: ["--a", "--a"])!
        #expect(duplicated.args == ["--a", "--a"], "the config keeps both")
        #expect(AgentOptions.operations(removingArgumentAt: 1, of: AgentOptionsState(id: "x", name: "x", isBuiltIn: false, command: "x", builtInCommand: nil, launcher: .terminal, launchers: [.terminal],
                                                                                       terminal: nil, terminals: [], bypassOverride: nil, bypassArgument: nil, builtInBypassArgument: nil,
                                                                                       args: ["--a"], listedArgs: ["--a", "--b"])).isEmpty)
    }

    @Test func anAgentOfOnesOwnGetsAnIdFromItsNameThatNoOtherAgentHas() {
        #expect(AgentOptions.identifier(for: "lazygit", taken: []) == "lazygit")
        #expect(AgentOptions.identifier(for: "My Tool (fast)!", taken: []) == "my-tool-fast")
        #expect(AgentOptions.identifier(for: "  --Weird--  ", taken: []) == "weird")
        #expect(AgentOptions.identifier(for: "lazygit", taken: ["lazygit", "lazygit-2"]) == "lazygit-3")
        #expect(AgentOptions.identifier(for: "Claude Code", taken: []) == "claude-code")
        #expect(AgentOptions.identifier(for: "claude", taken: []) == "claude-2", "a built-in agent's id is taken")
        #expect(AgentOptions.identifier(for: "コード", taken: []) == nil && AgentOptions.identifier(for: "---", taken: []) == nil)
        #expect(AgentOptions.identifier(for: "Ünï", taken: []) == "n")
    }

    @Test func anAgentIsCreatedWithItsNameAndCommandAndPutInTheMenuInOneChange() throws {
        let text = "[general]\nagents = [\"claude\"]\n"
        let general = GeneralSettings.state(config: config(text), facts: machine(), listedAgents: ["claude"])
        let made = try #require(AgentOptions.operations(creating: "Lazy Git", command: "lazygit", in: general))
        #expect(made.id == "lazy-git")
        #expect(made.operations == [.expect(["claude"], in: "general.agents"), .addTable("agent.lazy-git", fields: [ConfigField("name", .string("Lazy Git")), ConfigField("command", .string("lazygit"))]),
                                    .insert("lazy-git", into: "general.agents", at: nil)])
        let result = try apply(made.operations, to: text)
        #expect(result.enabledAgents == ["claude", "lazy-git"] && result.agent(id: "lazy-git")?.command == "lazygit" && result.agent(id: "lazy-git")?.name == "Lazy Git")
        #expect(ConfigTrust.approvals(for: made.operations).map(\.key) == ["agent.*.command"], "a program: an assistant would only propose it")
        #expect(AgentOptions.operations(creating: "", command: "x", in: general) == nil && AgentOptions.operations(creating: "X", command: "  ", in: general) == nil)
        // A name with no letter or digit of an id is not a reason to refuse: the program it starts gives the id, and a name that says nothing of it gets `agent`.
        #expect(AgentOptions.operations(creating: "ラザギット", command: "/usr/local/bin/lazygit --paging", in: general)?.id == "lazygit")
        #expect(AgentOptions.operations(creating: "---", command: "x", in: general)?.id == "x")
        #expect(AgentOptions.operations(creating: "ラザギット", command: "コマンド", in: general)?.id == "agent")
        #expect(AgentOptions.operations(creating: "ラザギット", command: "claude", in: general)?.id == "claude-2", "the id of a built-in agent is taken")
        let named = try #require(AgentOptions.operations(creating: "ラザギット", command: "lazygit", in: general))
        #expect(try apply(named.operations, to: text).agent(id: "lazygit")?.name == "ラザギット", "the name stays what the person typed")
        // In a config that does not list the agents, the list is made.
        let none = GeneralSettings.state(config: config(""), facts: machine(), listedAgents: nil)
        let first = try #require(AgentOptions.operations(creating: "Mine", command: "mine", in: none))
        #expect(try apply(first.operations, to: "").enabledAgents == ["mine"])
        // Not when the list is not the one that is shown.
        let duplicated = GeneralSettings.state(config: config("[general]\nagents = [\"claude\", \"claude\"]\n"), facts: machine(), listedAgents: ["claude", "claude"])
        #expect(AgentOptions.operations(creating: "Mine", command: "mine", in: duplicated) == nil)
    }

    @Test func anAgentOfOnesOwnIsTakenOutOfTheMenuAndThenOutOfTheConfig() throws {
        let text = "[general]\nagents = [\"claude\", \"mine\", \"other\"]\n\n# Mine.\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n\n[agent.other]\nname = \"Other\"\ncommand = \"other\"\n"
        let general = GeneralSettings.state(config: config(text), facts: machine(), listedAgents: ["claude", "mine", "other"])
        let removal = try #require(AgentOptions.operations(removing: options("mine", text), in: general))
        let operations = removal.all
        // The list goes first: a list that names an agent nobody defines is a config that does not read.
        #expect(operations == [.expect(["claude", "mine", "other"], in: "general.agents"), .remove(at: 2, from: "general.agents"), .removeTable("agent.mine")])
        #expect(removal.isListed && removal.list.count == 2 && removal.table == [.removeTable("agent.mine")], "two groups, for a list and a table that are in two files")
        let result = try apply(operations, to: text)
        #expect(result.enabledAgents == ["claude", "other"] && result.agents["mine"] == nil && result.agent(id: "mine") == nil && result.agent(id: "other")?.command == "other")
        #expect(ConfigTrust.approvals(for: operations).map(\.key) == ["agent.*.command"], "an assistant that proposes it waits")
        #expect(throws: ConfigDocument.EditError.self) { try apply([.removeTable("agent.mine"), .remove(at: 2, from: "general.agents")], to: text) }
    }

    @Test func anAgentThatIsNotInTheMenuIsTakenOutOfTheConfigOnly() throws {
        let text = "[general]\nagents = [\"claude\"]\n\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n"
        let general = GeneralSettings.state(config: config(text), facts: machine(), listedAgents: ["claude"])
        let removal = try #require(AgentOptions.operations(removing: options("mine", text), in: general))
        #expect(removal.all == [.expect(["claude"], in: "general.agents"), .removeTable("agent.mine")] && !removal.isListed)
        #expect(try apply(removal.all, to: text).agent(id: "mine") == nil)
    }

    @Test func aBuiltInAgentIsNotTakenOutAndNeitherIsOneFromAListThatIsNotTheOneShown() {
        let general = GeneralSettings.state(config: config("[general]\nagents = [\"claude\"]\n"), facts: machine(), listedAgents: ["claude"])
        #expect(AgentOptions.operations(removing: options("claude"), in: general) == nil, "it is in the app, not in the config")
        let text = "[general]\nagents = [\"claude\", \"mine\", \"mine\"]\n\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n"
        let duplicated = GeneralSettings.state(config: config(text), facts: machine(), listedAgents: ["claude", "mine", "mine"])
        #expect(AgentOptions.operations(removing: options("mine", text), in: duplicated) == nil)
        #expect(AgentOptions.operations(removing: options("mine", text), in: general) == nil, "an agent the list shown does not have")
    }

    @Test func theBuiltInFlagTypedOutIsTheSettingTakenOutAsTheCommandIs() {
        let claude = options("claude")
        #expect(AgentOptions.operations(settingBypassArgument: "--dangerously-skip-permissions", of: claude).isEmpty, "that is what it has")
        let own = options("claude", "[agent.claude]\nbypass_permission_arg = \"--yolo\"\n")
        #expect(AgentOptions.operations(settingBypassArgument: "--dangerously-skip-permissions", of: own) == [.unset("agent.claude.bypass_permission_arg")], "a later version's better flag then reaches the agent")
        #expect(AgentOptions.operations(settingBypassArgument: "  ", of: own) == [.unset("agent.claude.bypass_permission_arg")] && AgentOptions.operations(settingBypassArgument: "--yolo", of: own).isEmpty)
        #expect(AgentOptions.operations(settingBypassArgument: "--yolo", of: claude) == [.set("agent.claude.bypass_permission_arg", .string("--yolo"))])
    }

    @Test func anArgumentIsTrimmedAndAnIdIsNoLongerThanAToolTakes() {
        let claude = options("claude")
        #expect(AgentOptions.operations(addingArgument: "  --verbose ", to: claude) == [.expect(nil, in: "agent.claude.args"), .insert("--verbose", into: "agent.claude.args", at: nil)])
        let withArgs = options("claude", "[agent.claude]\nargs = [\"--a\"]\n")
        #expect(AgentOptions.operations(settingArgumentAt: 1, to: " --a ", of: withArgs).isEmpty, "the same once trimmed")
        #expect(AgentOptions.operations(settingArgumentAt: 1, to: " --b ", of: withArgs) == [.expect(["--a"], in: "agent.claude.args"), .replace(at: 1, in: "agent.claude.args", with: "--b")])
        let long = String(repeating: "Long name ", count: 30)
        let id = AgentOptions.identifier(for: long, taken: [])
        #expect((id?.count ?? 0) <= AgentOptions.maxIdentifierLength && id?.hasSuffix("-") == false && id?.hasPrefix("long-name-long-name") == true, "\(id ?? "nil")")
        #expect(AgentOptions.identifier(for: String(repeating: "a", count: 47) + " b", taken: []) == String(repeating: "a", count: 47), "cut where a dash would end it")
    }

    @Test func anArgumentThatTheFieldDidNotShowIsNotWrittenOverAnotherOne() {
        let list = options("claude", "[agent.claude]\nargs = [\"--a\", \"--b\"]\n")
        #expect(AgentOptions.operations(settingArgumentAt: 2, to: "--bee", of: list, expecting: "--b") == [.expect(["--a", "--b"], in: "agent.claude.args"), .replace(at: 2, in: "agent.claude.args", with: "--bee")])
        #expect(AgentOptions.operations(settingArgumentAt: 2, to: "--bee", of: list, expecting: "--c").isEmpty, "the field showed `--c`, which is not at place 2")
        #expect(AgentOptions.operations(settingArgumentAt: 2, to: "--bee", of: list).count == 2, "without a field's word on it, the place is what is asked")
    }
}
