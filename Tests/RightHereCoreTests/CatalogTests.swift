import Foundation
import Testing
@testable import RightHereCore

@Suite("Catalog")
struct CatalogTests {
    @Test func anExecutableIsTheFirstWordOfTheCommand() {
        #expect(AgentDescriptor(id: "a", name: "A", command: "claude --model opus").executable == "claude")
        // The program is what is run, not an assignment in front of it: `FOO=1 claude` is looked up as `claude`, which the login shell finds.
        #expect(AgentDescriptor(id: "a", name: "A", command: "FOO=1 BAR='x y' claude --model opus").executable == "claude")
        #expect(AgentDescriptor(id: "a", name: "A", command: "\"/opt/my tools/claude\" --x").executable == "/opt/my tools/claude")
        #expect(AgentDescriptor(id: "a", name: "A", command: "env claude").executable == "env")
        #expect(AgentDescriptor(id: "a", name: "A", command: "aider").executable == "aider")
        #expect(AgentDescriptor(id: "a", name: "A", command: "").executable == "")
    }

    @Test func rowsCarryEnabledStateInstalledStateAndVariants() {
        var config = Config(enabledAgents: ["claude"])
        config.agents["claude"] = .init(command: "claude --model opus")
        let claude = config.agentRows().first { $0.id == "claude" }
        #expect(claude?.enabled == true)
        #expect(claude?.command == "claude --model opus")
        #expect(claude?.variants == ["continue", "resume"])
        #expect(claude?.terminalLink == true && claude?.desktopLink == true)
        #expect(config.agentRows().first { $0.id == "aider" }?.enabled == false)
        #expect(config.agentRows().map(\.id) == config.allAgents.map(\.id))
        let apps = config.appRows(facts: FakeSystemFacts())
        #expect(apps.map(\.id) == config.allApps.map(\.id))
        #expect(apps.allSatisfy { !$0.installed && $0.bundleID == nil })
    }

    @Test func aRowSaysWhetherTheShellFoundTheCommandOnlyWhenItWasAsked() {
        var config = Config(enabledAgents: ["claude"])
        config.agents["claude"] = .init(command: "claude --model opus")
        #expect(config.agentRows().allSatisfy { $0.foundInShell == nil })
        let asked = config.agentRows(found: ["claude"])
        #expect(asked.first { $0.id == "claude" }?.foundInShell == true, "found by the first word of the command")
        #expect(asked.first { $0.id == "aider" }?.foundInShell == false)
        #expect(asked.map(\.id) == config.agentRows().map(\.id), "the same rows in the same order, asked or not")
    }

    @Test func aRowWordsItsStateForRhAgentsAndAnEnabledAgentThatIsNotFoundSaysSo() {
        // The menu cannot look for a command (that takes a shell), so an enabled agent whose command is missing is still listed.
        var config = Config(enabledAgents: ["claude", "codex"])
        config.agents["codex"] = .init(command: "no-such-command-anywhere")
        let rows = config.agentRows(found: ["claude"])
        func state(_ id: String) -> String? { rows.first { $0.id == id }?.stateText }
        #expect(state("claude") == "enabled, found")
        #expect(state("codex") == "enabled, not found")
        #expect(state("gemini") == "not found; to install it, see https://github.com/google-gemini/gemini-cli")
        #expect(state("muse") == "not found", "an agent with no confirmed install page")
        #expect(config.agentRows(found: ["gemini"]).first { $0.id == "gemini" }?.stateText == "found, not enabled")
        let located = config.agentRows(found: ["claude", "gemini"], locations: ["claude": "/Users/me/.local/bin/claude", "gemini": "gemini"])
        #expect(located.first { $0.id == "claude" }?.stateText == "enabled, found at /Users/me/.local/bin/claude")
        #expect(located.first { $0.id == "gemini" }?.stateText == "found, not enabled", "an alias or a function has no path to show")
        #expect(located.first { $0.id == "claude" }?.location == "/Users/me/.local/bin/claude")
        #expect(config.agentRows().first { $0.id == "codex" }?.stateText == "enabled", "nobody asked the shell, so nothing is claimed")
        #expect(config.agentRows().first { $0.id == "gemini" }?.stateText == "not enabled", "and no agent is said to be missing")
        // The words are for the command line; the JSON has the two facts.
        #expect(!String(decoding: (try? JSONEncoder().encode(rows.first)) ?? Data(), as: UTF8.self).contains("stateText"))
    }

    @Test func aShellThatSaidNothingFindsNothingAndSaysNotThatItIsNotThere() {
        // A command the shell did not name is unknown (nil), not false, when it did not get to the end of its answer; one it did name is found.
        var config = Config(enabledAgents: ["claude", "codex"])
        config.agents["codex"] = .init(command: "no-such-command-anywhere")
        let rows = config.agentRows(found: ["claude"], shellAnswered: false)
        func row(_ id: String) -> AgentRow? { rows.first { $0.id == id } }
        #expect(row("claude")?.foundInShell == true)
        #expect(row("codex")?.foundInShell == nil)
        #expect(row("codex")?.stateText == "enabled", "an enabled agent that nobody could look for is not said to be missing")
        #expect(row("gemini")?.foundInShell == nil)
        #expect(row("gemini")?.stateText == "not enabled", "and neither is one that is not enabled")
        #expect(config.agentRows(found: ["claude"], shellAnswered: true).first { $0.id == "gemini" }?.foundInShell == false)
    }

    @Test func aRowReadsBackAsItWasWritten() throws {
        let config = Config(enabledAgents: ["claude"])
        for rows in [config.agentRows(), config.agentRows(found: ["claude", "codex"])] {
            let data = try JSONEncoder().encode(rows)
            #expect(try JSONDecoder().decode([AgentRow].self, from: data) == rows)
            let written = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            #expect(written.allSatisfy { ($0["foundInShell"] == nil) == (rows.first?.foundInShell == nil) }, "not asked, so not said")
        }
    }

    @Test func aConfigLauncherNameMapsToTheLauncher() {
        #expect(AgentLauncher.configNames == ["terminal", "link", "desktop"])
        #expect(AgentLauncher.fromConfig(name: "link", terminal: "ghostty") == .terminalLink)
        #expect(AgentLauncher.fromConfig(name: "desktop", terminal: nil) == .desktop)
        #expect(AgentLauncher.fromConfig(name: "terminal", terminal: "ghostty") == .terminal("ghostty"))
        #expect(AgentLauncher.fromConfig(name: "terminal", terminal: nil) == .terminal(nil))
        #expect(AgentLauncher.fromConfig(name: nil, terminal: "ghostty") == .terminal("ghostty"))
        #expect(AgentLauncher.fromConfig(name: nil, terminal: nil) == nil)
        for word in AgentLauncher.configNames { #expect(ActionRef(parsing: "agent.claude@\(word)") != nil) }
    }

    /// The arguments that continue or resume a session, from each tool's own documentation (ADR 0024); Goose and Muse Code have none here
    /// because what their documentation says about resuming is not consistent or could not be read.
    @Test func theBuiltInContinueAndResumeArgumentsAreTheDocumentedOnes() {
        func variants(_ id: String) -> [String: [String]] {
            Dictionary(uniqueKeysWithValues: (KnownAgents.agent(id: id)?.variants ?? []).map { ($0.id, $0.arguments) })
        }
        #expect(variants("claude") == ["continue": ["--continue"], "resume": ["--resume"]])
        #expect(variants("codex") == ["last": ["resume", "--last"], "resume": ["resume"]])
        #expect(variants("agy") == ["continue": ["--continue"]])
        #expect(variants("gemini") == ["resume": ["--resume", "latest"]])
        #expect(variants("opencode") == ["continue": ["--continue"]])
        #expect(variants("kimi") == ["continue": ["--continue"], "resume": ["--resume"]])
        #expect(variants("copilot") == ["continue": ["--continue"], "resume": ["--resume"]])
        // 2026-10-29: Cursor CLI's `--continue` is "alias for --resume=-1"; what a bare `--resume` does is not said. Factory Droid's
        // `--resume` without an id takes the last modified session. Kiro CLI's `--resume` is "the previous conversation from this directory"
        // and `--resume-picker` opens a picker. Qwen Code documents `--continue` and `--resume` only on its page for headless runs.
        #expect(variants("cursor-cli") == ["continue": ["--continue"]])
        #expect(variants("droid") == ["resume": ["--resume"]])
        #expect(variants("kiro") == ["continue": ["--resume"], "resume": ["--resume-picker"]])
        for id in ["qwen", "goose", "muse", "aider", "amp"] { #expect(variants(id).isEmpty, "\(id)") }
    }

    @Test func allAgentsAppliesTheConfigsCommandOverride() {
        var config = Config()
        config.agents["claude"] = .init(command: "claude --model opus")
        let claude = config.allAgents.first { $0.id == "claude" }
        #expect(claude?.command == "claude --model opus")
        #expect(claude?.executable == "claude")
        #expect(config.allAgents.count == KnownAgents.all.count)
    }
}
