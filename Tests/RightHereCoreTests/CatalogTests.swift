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
        let claude = config.agentRows.first { $0.id == "claude" }
        #expect(claude?.enabled == true)
        #expect(claude?.command == "claude --model opus")
        #expect(claude?.variants == ["continue", "resume"])
        #expect(claude?.terminalLink == true && claude?.desktopLink == true)
        #expect(config.agentRows.first { $0.id == "aider" }?.enabled == false)
        #expect(config.agentRows.map(\.id) == config.allAgents.map(\.id))
        let apps = config.appRows(facts: FakeSystemFacts())
        #expect(apps.map(\.id) == config.allApps.map(\.id))
        #expect(apps.allSatisfy { !$0.installed && $0.bundleID == nil })
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
