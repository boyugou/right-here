import Foundation
import Testing
@testable import RightHereCore

private let fullConfig = """
version = 1

[general]
terminal = "ghostty"
editor = "vscode"

[new_file]
then = "open"

[[new_file.template]]
id = "py"
title = "Python Script"
base_name = "script"
extension = "py"
contents = "print('hi')\\n"

[[app]]
id = "tower"
name = "Tower"
bundle_id = "com.fournova.Tower3"
role = "general"

[[app]]
id = "warpish"
name = "Warpish"
bundle_ids = ["a.b.c", "a.b.d"]
role = "terminal"

[agent.claude]
launcher = "terminal"
terminal = "warpish"
command = "claude --model opus"

[[agent.claude.variant]]
id = "danger"
title = "Skip Permissions"
arguments = ["--dangerously-skip-permissions"]

[agent.mine]
name = "My Agent"
command = "myagent --fast"
launcher = "desktop"
"""

@Suite("ConfigParser")
struct ConfigParserTests {
    @Test func emptyFileGivesDefaults() {
        let result = ConfigParser.parse("")
        #expect(result.config == .default)
        #expect(result.diagnostics.isEmpty)
    }

    @Test func fullConfigIsReadCompletely() throws {
        let result = ConfigParser.parse(fullConfig)
        #expect(result.diagnostics == [])
        let config = result.config
        #expect(config.terminal == "ghostty")
        #expect(config.editor == "vscode")
        #expect(config.newFile.then == .open)
        #expect(config.newFile.templates == [NewFileTemplate(id: "py", title: "Python Script", baseName: "script", fileExtension: "py", contents: "print('hi')\n")])
        #expect(config.apps.map(\.id) == ["tower", "warpish"])
        #expect(config.apps[1].bundleIDs == ["a.b.c", "a.b.d"])
        #expect(config.apps[1].role == .terminal)

        let claude = try #require(config.agent(id: "claude"))
        #expect(claude.command == "claude --model opus")
        #expect(claude.variants.map(\.id) == ["continue", "resume", "danger"])
        #expect(config.agents["claude"]?.launcher == .terminal("warpish"))

        let mine = try #require(config.agent(id: "mine"))
        #expect(mine.name == "My Agent")
        #expect(config.agents["mine"]?.launcher == .desktop)
    }

    @Test func syntaxErrorReportsTheLineAndFallsBackToDefaults() throws {
        let result = ConfigParser.parse("version = 1\n[general\nterminal = \"x\"\n")
        #expect(result.config == .default)
        let error = try #require(result.diagnostics.first)
        #expect(error.severity == .error)
        #expect(error.line != nil)
        #expect(error.message.hasPrefix("TOML syntax error"))
    }

    @Test func unknownKeysWarnWithASuggestion() throws {
        let result = ConfigParser.parse("[general]\ntermnial = \"ghostty\"\n")
        #expect(!result.hasErrors)
        let warning = try #require(result.diagnostics.first)
        #expect(warning.path == "general.termnial")
        #expect(warning.suggestion == "did you mean \"terminal\"?")
    }

    @Test func unknownTopLevelTableWarns() throws {
        let result = ConfigParser.parse("[genral]\nterminal = \"ghostty\"\n")
        let warning = try #require(result.diagnostics.first)
        #expect(warning.severity == .warning)
        #expect(warning.suggestion == "did you mean \"general\"?")
    }

    @Test func wrongTypeIsAnError() throws {
        let result = ConfigParser.parse("[general]\nterminal = 3\n")
        let error = try #require(result.diagnostics.first)
        #expect(error.severity == .error)
        #expect(error.path == "general.terminal")
        #expect(result.config.terminal == nil)
    }

    @Test func unknownTerminalListsTheKnownOnes() throws {
        let result = ConfigParser.parse("[general]\nterminal = \"ghostyy\"\n")
        let error = try #require(result.diagnostics.first)
        #expect(error.message.contains("unknown terminal"))
        #expect(error.message.contains("ghostty"))
        #expect(error.suggestion == "did you mean \"ghostty\"?")
    }

    @Test func unknownEditorSuggestsAnApp() throws {
        let result = ConfigParser.parse("[general]\neditor = \"vscod\"\n")
        let error = try #require(result.diagnostics.first)
        #expect(error.suggestion == "did you mean \"vscode\"?")
    }

    @Test func badEnumValue() throws {
        let result = ConfigParser.parse("[new_file]\nthen = \"launch\"\n")
        let error = try #require(result.diagnostics.first)
        #expect(error.path == "new_file.then")
        #expect(error.message.contains("reveal"))
    }

    @Test func futureVersionIsRejected() {
        #expect(ConfigParser.parse("version = 2\n").hasErrors)
    }

    @Test func customAgentNeedsNameAndCommand() throws {
        let result = ConfigParser.parse("[agent.mine]\nname = \"Mine\"\n")
        #expect(result.hasErrors)
        #expect(result.config.agent(id: "mine") == nil)
    }

    @Test func appNeedsABundleID() {
        #expect(ConfigParser.parse("[[app]]\nid = \"x\"\nname = \"X\"\n").hasErrors)
    }

    @Test func badIdentifiersAreRejected() {
        #expect(ConfigParser.parse("[[app]]\nid = \"My App\"\nname = \"X\"\nbundle_id = \"a.b\"\n").hasErrors)
        #expect(ConfigParser.parse("[[new_file.template]]\nid = \"-x\"\ntitle = \"T\"\nextension = \"x\"\n").hasErrors)
    }

    @Test func templateExtensionHasNoDot() {
        #expect(ConfigParser.parse("[[new_file.template]]\nid = \"t\"\ntitle = \"T\"\nextension = \".txt\"\n").hasErrors)
    }

    @Test func agentTableWrittenAsAnArrayIsReported() {
        #expect(ConfigParser.parse("[[agent]]\nname = \"x\"\n").hasErrors)
    }

    @Test func menuAgentsAndCopyPathSettingsAreRead() {
        let result = ConfigParser.parse("""
        [general]
        agents = ["claude", "codex"]

        [menu]
        items = ["open-terminal", "-", "copy-path"]

        [copy_path]
        styles = ["absolute", "ai-mention"]
        """)
        #expect(result.diagnostics == [])
        #expect(result.config.enabledAgents == ["claude", "codex"])
        #expect(result.config.menuItems == ["open-terminal", "-", "copy-path"])
        #expect(result.config.copyPathStyles == [.absolute, .aiMention])
    }

    @Test func unknownAgentInTheListIsReportedWithASuggestion() throws {
        let result = ConfigParser.parse("[general]\nagents = [\"claud\"]\n")
        let error = try #require(result.diagnostics.first)
        #expect(error.path == "general.agents")
        #expect(error.suggestion == "did you mean \"claude\"?")
        #expect(result.config.enabledAgents.isEmpty)
    }

    @Test func customAgentCanBeEnabled() {
        let result = ConfigParser.parse("""
        [general]
        agents = ["mine"]

        [agent.mine]
        name = "Mine"
        command = "mine"
        """)
        #expect(result.diagnostics == [])
        #expect(result.config.enabledAgents == ["mine"])
    }

    @Test func unknownCopyPathStyleIsReported() throws {
        let result = ConfigParser.parse("[copy_path]\nstyles = [\"absolut\"]\n")
        let error = try #require(result.diagnostics.first)
        #expect(error.suggestion == "did you mean \"absolute\"?")
    }

    @Test func validConfigPartsApplyEvenWhenAnotherPartFails() {
        let result = ConfigParser.parse("[general]\nterminal = \"nope\"\neditor = \"zed\"\n")
        #expect(result.hasErrors)
        #expect(result.config.editor == "zed")
        #expect(result.config.terminal == nil)
    }
}

@Suite("ConfigSchema")
struct ConfigSchemaTests {
    @Test func markdownDocumentsEveryTopLevelKey() {
        let text = ConfigSchema.markdown()
        for key in ["version", "general.terminal", "new_file.then", "[[new_file.template]]", "[[app]]", "[agent.<id>]", "agent.<id>.launcher"] {
            #expect(text.contains(key), "missing \(key)")
        }
    }

    @Test func jsonSchemaIsValidJSONWithTheTopLevelProperties() throws {
        let object = ConfigSchema.jsonSchema()
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(decoded["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["version", "general", "menu", "copy_path", "new_file", "app", "agent"])
        #expect(decoded["$schema"] as? String == "http://json-schema.org/draft-07/schema#")
    }

    @Test func everyFullConfigKeyIsInTheSchema() {
        let result = ConfigParser.parse(fullConfig)
        #expect(!result.diagnostics.contains { $0.message == "unknown key" })
    }
}
