import Foundation
import Testing
@testable import RightHereCore

@Suite("AgentBypassPermissions")
struct AgentBypassPermissionsTests {
    /// The flags of Claude Code, Codex and Antigravity were read from their own `--help` on a Mac that has them. The others come from each
    /// tool's documentation and have not been run here: a wrong one makes that tool refuse the unknown option, nothing worse, and the
    /// config can replace any of them (`bypass_permission_arg`).
    @Test func theBuiltInBypassFlagsAreTheOnesDocumented() {
        #expect(KnownAgents.agy.bypassPermissionArgument == "--dangerously-skip-permissions")
        #expect(KnownAgents.claude.bypassPermissionArgument == "--dangerously-skip-permissions")
        #expect(KnownAgents.codex.bypassPermissionArgument == "--dangerously-bypass-approvals-and-sandbox")
        #expect(KnownAgents.gemini.bypassPermissionArgument == "-y")
        #expect(KnownAgents.opencode.bypassPermissionArgument == "--auto")
        #expect(KnownAgents.kimi.bypassPermissionArgument == "--auto-approve")
        #expect(KnownAgents.muse.bypassPermissionArgument == "--auto-approve")
        #expect(KnownAgents.aider.bypassPermissionArgument == "--yes-always")
        #expect(KnownAgents.copilot.bypassPermissionArgument == "--allow-all")
    }

    @Test func globalBypassPermissionsAppliesFlagToAgents() {
        var config = Config(enabledAgents: ["claude", "agy", "codex", "gemini"])
        config.bypassPermissions = true

        let claude = config.agent(id: "claude")
        #expect(claude?.command == "claude --dangerously-skip-permissions")

        let agy = config.agent(id: "agy")
        #expect(agy?.command == "agy --dangerously-skip-permissions")

        let codex = config.agent(id: "codex")
        #expect(codex?.command == "codex --dangerously-bypass-approvals-and-sandbox")

        let gemini = config.agent(id: "gemini")
        #expect(gemini?.command == "gemini -y")
    }

    @Test func perAgentBypassPermissionsOverridesGlobalDefault() {
        var config = Config(enabledAgents: ["claude", "gemini"])
        config.bypassPermissions = true
        config.agents["gemini"] = .init(bypassPermissions: false)
        config.agents["claude"] = .init(bypassPermissions: true)

        #expect(config.agent(id: "claude")?.command == "claude --dangerously-skip-permissions")
        #expect(config.agent(id: "gemini")?.command == "gemini")
    }

    @Test func perAgentBypassCanEnableEvenIfGlobalIsDisabled() {
        var config = Config(enabledAgents: ["claude", "gemini"])
        config.bypassPermissions = false
        config.agents["claude"] = .init(bypassPermissions: true)

        #expect(config.agent(id: "claude")?.command == "claude --dangerously-skip-permissions")
        #expect(config.agent(id: "gemini")?.command == "gemini")
    }

    @Test func customBypassFlagOverridesBuiltInDefault() {
        var config = Config()
        config.agents["claude"] = .init(
            bypassPermissions: true,
            bypassPermissionArgument: "--custom-skip"
        )
        #expect(config.agent(id: "claude")?.command == "claude --custom-skip")
    }

    @Test func bypassFlagIsNotDuplicatedIfAlreadyInCommand() {
        var config = Config()
        config.bypassPermissions = true
        config.agents["claude"] = .init(command: "claude --dangerously-skip-permissions --model opus")

        #expect(config.agent(id: "claude")?.command == "claude --dangerously-skip-permissions --model opus")
    }

    @Test func extraArgsAreAppendedAndQuoted() {
        var config = Config()
        config.agents["claude"] = .init(
            bypassPermissions: true,
            args: ["--verbose", "my custom value"]
        )
        #expect(config.agent(id: "claude")?.command == "claude --dangerously-skip-permissions --verbose 'my custom value'")
    }

    @Test func resolutionTypedLineIncludesBypassAndVariant() throws {
        var config = Config()
        config.bypassPermissions = true
        let agent = try #require(config.agent(id: "claude"))
        let variant = agent.variants.first { $0.id == "continue" }

        let result = AgentLaunchResolution.typedLine(agent: agent, variant: variant)
        guard case .success(let line) = result else { Issue.record("failed to type line: \(result)"); return }
        #expect(line == "claude --dangerously-skip-permissions --continue")
    }

    @Test func tomlParserReadsBypassPermissionsAndArgs() {
        let toml = """
        [general]
        bypass_permissions = true

        [agent.claude]
        bypass_permissions = false
        args = ["--model", "sonnet-3.7"]

        [agent.agy]
        bypass_permissions = true
        bypass_permission_arg = "--dangerously-skip-permissions"
        """

        let result = ConfigParser.parse(toml)
        #expect(result.diagnostics.isEmpty, "diagnostics: \(result.diagnostics)")
        #expect(result.config.bypassPermissions == true)
        #expect(result.config.agents["claude"]?.bypassPermissions == false)
        #expect(result.config.agents["claude"]?.args == ["--model", "sonnet-3.7"])
        #expect(result.config.agents["agy"]?.bypassPermissions == true)
        #expect(result.config.agents["agy"]?.bypassPermissionArgument == "--dangerously-skip-permissions")

        let claude = result.config.agent(id: "claude")
        #expect(claude?.command == "claude --model sonnet-3.7")

        let agy = result.config.agent(id: "agy")
        #expect(agy?.command == "agy --dangerously-skip-permissions")
    }
}
