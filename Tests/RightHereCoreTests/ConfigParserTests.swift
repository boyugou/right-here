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
        #expect(Set(properties.keys) == ["version", "general", "menu", "services", "copy_path", "new_file", "app", "agent"])
        #expect(decoded["$schema"] as? String == "http://json-schema.org/draft-07/schema#")
    }

    @Test func everyFullConfigKeyIsInTheSchema() {
        let result = ConfigParser.parse(fullConfig)
        #expect(!result.diagnostics.contains { $0.message == "unknown key" })
    }
}

@Suite("Config strictness")
struct ConfigStrictnessTests {
    private func parse(_ text: String) -> ConfigLoadResult { ConfigParser.parse(text) }

    @Test func aDuplicateAppIdIsAnErrorAndTheFirstWins() {
        let result = parse("""
        [[app]]
        id = "tower"
        name = "First"
        bundle_id = "a.b.c"

        [[app]]
        id = "tower"
        name = "Second"
        bundle_id = "d.e.f"
        """)
        #expect(result.hasErrors)
        #expect(result.diagnostics.contains { $0.message.contains("duplicate app id") && $0.path == "app.2.id" })
        #expect(result.config.apps.map(\.name) == ["First"])
    }

    @Test func anAppWithABuiltInIdReplacesItAndIsWarnedAbout() throws {
        let result = parse("""
        [[app]]
        id = "typora"
        name = "My Typora"
        bundle_id = "com.example.typora"
        role = "editor"
        """)
        #expect(!result.hasErrors)
        let warning = try #require(result.diagnostics.first { $0.severity == .warning })
        #expect(warning.message.contains("replaces the built-in app \"typora\""))
        #expect(result.config.app(id: "typora")?.name == "My Typora")
        // The listing has one Typora, the replacement, not two.
        let typoras = result.config.allApps.filter { $0.id == "typora" }
        #expect(typoras.map(\.name) == ["My Typora"])
        #expect(Set(result.config.allApps.map(\.id)).count == result.config.allApps.count)
    }

    @Test func aDuplicateTemplateIdIsAnError() {
        let result = parse("""
        [[new_file.template]]
        id = "py"
        title = "Python"
        extension = "py"

        [[new_file.template]]
        id = "py"
        title = "Python Again"
        extension = "py"
        """)
        #expect(result.diagnostics.contains { $0.message.contains("duplicate template id") })
        #expect(result.config.newFile.templates.map(\.title) == ["Python"])
    }

    @Test func aVariantIdThatAgentsAlreadyHasIsAnError() {
        let result = parse("""
        [agent.claude]
        [[agent.claude.variant]]
        id = "continue"
        title = "Mine"
        arguments = ["-c"]

        [[agent.claude.variant]]
        id = "opus"
        title = "Opus"
        arguments = ["--model", "opus"]

        [[agent.claude.variant]]
        id = "opus"
        title = "Opus Again"
        """)
        #expect(result.diagnostics.filter { $0.message.contains("is already used by agent") }.count == 2)
        #expect(result.config.agent(id: "claude")?.variants.map(\.id) == ["continue", "resume", "opus"])
    }

    @Test("a template file name cannot leave the folder", arguments: ["../escaped", "a/b", ".", "..", ""])
    func aTemplateBaseNameStaysInsideTheFolder(baseName: String) {
        let result = parse("""
        [[new_file.template]]
        id = "x"
        title = "X"
        base_name = "\(baseName)"
        extension = "txt"
        """)
        #expect(result.hasErrors)
        #expect(result.diagnostics.contains { $0.path.hasSuffix("base_name") })
        #expect(result.config.newFile.templates == NewFileTemplate.builtIn)
    }

    @Test func anExtensionWithASlashHiddenBehindACombiningMarkIsRefused() {
        let result = parse("""
        [[new_file.template]]
        id = "x"
        title = "X"
        extension = "md/\u{301}x"
        """)
        #expect(result.hasErrors)
    }

    @Test("an agent command that cannot be typed into a terminal is refused when the file is read", arguments: ["claude\nrm -rf ~", "claude\u{1b}[2J", "a\rb"])
    func aCommandWithControlCharactersIsAnError(command: String) {
        let escaped = command.unicodeScalars.map { $0.value < 0x20 ? String(format: "\\u%04X", $0.value) : String($0) }.joined()
        let result = parse("[agent.claude]\ncommand = \"\(escaped)\"\n")
        #expect(result.diagnostics.contains { $0.path == "agent.claude.command" && $0.severity == .error })
        #expect(result.config.agent(id: "claude")?.command == "claude")
    }

    @Test("terminal_placement accepts window and tab and defaults to a window", arguments: [("window", TerminalPlacement.newWindow), ("tab", .newTab)])
    func terminalPlacement(name: String, expected: TerminalPlacement) {
        let result = parse("[general]\nterminal_placement = \"\(name)\"\n")
        #expect(result.diagnostics.isEmpty)
        #expect(result.config.terminalPlacement == expected)
        #expect(parse("").config.terminalPlacement == .newWindow)
    }

    @Test func anUnknownPlacementIsAnErrorWithAReplacement() throws {
        let result = parse("[general]\nterminal_placement = \"tabs\"\n")
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.replacement == "tab")
        #expect(result.config.terminalPlacement == .newWindow)
    }

    @Test func aTemplateCanNameTheAppThatOpensIt() {
        let result = parse("""
        [new_file]
        then = "open"

        [[new_file.template]]
        id = "md"
        title = "Markdown"
        extension = "md"
        open_with = "typora"
        """)
        #expect(result.diagnostics.isEmpty)
        #expect(result.config.newFile.templates.first?.openWith == "typora")
    }

    @Test func anUnknownOpenWithAppIsAnErrorWithASuggestion() throws {
        let result = parse("""
        [[new_file.template]]
        id = "md"
        title = "Markdown"
        extension = "md"
        open_with = "typoraa"
        """)
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.path == "new_file.template.1.open_with")
        #expect(diagnostic.replacement == "typora")
        #expect(result.config.newFile.templates.first?.openWith == nil)
    }

    @Test func openWithMayNameAnAppTheConfigDefines() {
        let result = parse("""
        [[app]]
        id = "mine"
        name = "Mine"
        bundle_id = "a.b.c"
        role = "editor"

        [[new_file.template]]
        id = "md"
        title = "Markdown"
        extension = "md"
        open_with = "mine"
        """)
        #expect(result.diagnostics.isEmpty)
    }

    @Test func aTypoCarriesTheLikelyReplacementForTools() throws {
        let result = parse("[general]\nagnts = [\"codex\"]\n")
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.suggestion == "did you mean \"agents\"?")
        #expect(diagnostic.replacement == "agents")
    }

    @Test func aWrongValueCarriesTheReplacementToo() throws {
        let result = parse("[general]\nterminal = \"ghostyy\"\n")
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.replacement == "ghostty")
    }

    @Test func aDiagnosticWithoutACandidateHasNoReplacement() throws {
        let result = parse("[general]\nzzzzzzzzzz = 1\n")
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.replacement == nil)
    }

    @Test func aTypoedMenuEntryIsWarnedAboutWithAReplacement() throws {
        let result = parse("[menu]\nitems = [\"open-terminl\"]\n")
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.replacement == "open-terminal")
    }
}

@Suite("ConfigSchema documentation and JSON Schema")
struct ConfigSchemaDetailTests {
    private var schema: [String: Any] { ConfigSchema.jsonSchema() }

    private func property(_ path: [String]) -> [String: Any]? {
        var node: [String: Any]? = schema
        for key in path {
            var next = (node?["properties"] as? [String: Any])?[key] as? [String: Any]
            if next == nil, let items = node?["items"] as? [String: Any] { next = (items["properties"] as? [String: Any])?[key] as? [String: Any] }
            if next == nil, let extra = node?["additionalProperties"] as? [String: Any] { next = (extra["properties"] as? [String: Any])?[key] as? [String: Any] }
            node = next
        }
        return node
    }

    @Test func theDocumentationNamesEveryWayTheConfigIsLocated() {
        let text = ConfigSchema.markdown()
        for name in ["RH_CONFIG", "RH_CONFIG_DIR", "XDG_CONFIG_HOME", "RH_LOG_DIR", "--strict"] {
            #expect(text.contains(name), "the config reference does not mention \(name)")
        }
    }

    @Test func theDocumentationExplainsGroupsAndWhatHappensAfterANewFile() {
        let text = ConfigSchema.markdown()
        for fragment in ["open-with (", "agents-more (", "opens it in the default editor", "New <title>"] {
            #expect(text.contains(fragment), "missing: \(fragment)")
        }
    }

    @Test func theSchemaRequiresWhatTheValidatorRequires() throws {
        let template = try #require(property(["new_file", "template"]))
        _ = template
        let templates = try #require((property(["new_file"])?["properties"] as? [String: Any])?["template"] as? [String: Any])
        #expect((templates["items"] as? [String: Any])?["required"] as? [String] == ["id", "title", "extension"])
        let apps = try #require((schema["properties"] as? [String: Any])?["app"] as? [String: Any])
        let appItems = try #require(apps["items"] as? [String: Any])
        #expect(appItems["required"] as? [String] == ["id", "name"])
        #expect((appItems["anyOf"] as? [[String: Any]])?.count == 2)
    }

    @Test func theSchemaListsTheAllowedValues() throws {
        #expect(property(["version"])?["enum"] as? [Int] == [1])
        let styles = try #require(property(["copy_path", "styles"]))
        #expect((styles["items"] as? [String: Any])?["enum"] as? [String] == PathStyle.allCases.map(\.rawValue))
        #expect(property(["new_file", "then"])?["enum"] as? [String] == ["reveal", "open", "nothing"])
    }

    @Test func idsMustLookLikeIds() throws {
        let apps = try #require((schema["properties"] as? [String: Any])?["app"] as? [String: Any])
        let id = try #require(((apps["items"] as? [String: Any])?["properties"] as? [String: Any])?["id"] as? [String: Any])
        #expect(id["pattern"] as? String == "^[a-z0-9-]+$")
        let agents = try #require((schema["properties"] as? [String: Any])?["agent"] as? [String: Any])
        #expect((agents["propertyNames"] as? [String: Any])?["pattern"] as? String == "^[a-z0-9-]+$")
    }

    @Test func knownTerminalsAreSuggestedNotEnforced() throws {
        let terminal = try #require(property(["general", "terminal"]))
        #expect(terminal["enum"] == nil)
        #expect((terminal["examples"] as? [String])?.contains("ghostty") == true)
    }
}
