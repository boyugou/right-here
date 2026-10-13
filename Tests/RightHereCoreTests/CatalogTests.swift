import Foundation
import Testing
@testable import RightHereCore

@Suite("Catalog")
struct CatalogTests {
    @Test func anExecutableIsTheFirstWordOfTheCommand() {
        #expect(AgentDescriptor(id: "a", name: "A", command: "claude --model opus").executable == "claude")
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

    @Test func allAgentsAppliesTheConfigsCommandOverride() {
        var config = Config()
        config.agents["claude"] = .init(command: "claude --model opus")
        let claude = config.allAgents.first { $0.id == "claude" }
        #expect(claude?.command == "claude --model opus")
        #expect(claude?.executable == "claude")
        #expect(config.allAgents.count == KnownAgents.all.count)
    }
}
