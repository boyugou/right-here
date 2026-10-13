import Testing
@testable import RightHereCore

@Suite("Catalog")
struct CatalogTests {
    @Test func anExecutableIsTheFirstWordOfTheCommand() {
        #expect(AgentDescriptor(id: "a", name: "A", command: "claude --model opus").executable == "claude")
        #expect(AgentDescriptor(id: "a", name: "A", command: "aider").executable == "aider")
        #expect(AgentDescriptor(id: "a", name: "A", command: "").executable == "")
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
