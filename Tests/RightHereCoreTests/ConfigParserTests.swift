import Foundation
import Testing
@testable import RightHereCore

private let fullConfig = """
version = 1

[general]
terminal = "ghostty"
editor = "vscode"
agents = ["mine"]

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
launcher = "terminal"

[agent.codex]
launcher = "desktop"
"""

@Suite("ConfigParser")
struct ConfigParserTests {
    @Test func anEntryOfTheMenuThatIsListedTwiceIsSaid() {
        let result = ConfigParser.parse("[menu]\nitems = [\"open-terminal\", \"open-editor\", \"-\", \"open-editor\", \"-\"]\n")
        #expect(result.diagnostics.contains { $0.message.contains("\"open-editor\" is listed twice") }, "\(result.diagnostics.map(\.message))")
        #expect(!result.diagnostics.contains { $0.message.contains("\"-\" is listed twice") }, "separators may repeat")
        #expect(result.config.menuItems == ["open-terminal", "open-editor", "-", "open-editor", "-"], "the list is as the file says: the window's editor changes it by place")
    }

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
        #expect(config.agents["mine"]?.launcher == .terminal(nil))
        #expect(config.agents["codex"]?.launcher == .desktop)
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

    @Test func anIdForACustomActionIsNeitherAMenuEntryNorAService() throws {
        // `user.<id>` was reserved for actions defined in the config; there are none, so it is not an id at all.
        let result = ConfigParser.parse("[menu]\nitems = [\"user.build\", \"reveal\"]\n[services]\nitems = [\"user.build\", \"reveal\"]\n")
        #expect(result.diagnostics.map(\.path) == ["menu.items", "services.items"])
        #expect(result.diagnostics.map(\.severity) == [.warning, .warning])
        #expect(result.diagnostics[0].message == "\"user.build\" is neither a menu group nor an action id")
        #expect(result.diagnostics[1].message.hasPrefix("\"user.build\" is not an action id"))
        #expect(result.config.serviceItems == ["reveal"])
    }

    @Test("an app with a built-in terminal's bundle identifier, in any case, has to be a terminal: a terminal handed a file runs it", arguments: [
        ("com.apple.Terminal", "editor"), ("com.apple.terminal", "editor"), ("COM.APPLE.TERMINAL", "general"), ("com.mitchellh.ghostty", "editor"), ("com.googlecode.iterm2", "general")
    ])
    func aTerminalsBundleIdentifierWithAnotherRoleIsRefused(bundle: String, role: String) {
        let result = ConfigParser.parse("[[app]]\nid = \"mine\"\nname = \"Mine\"\nbundle_id = \"\(bundle)\"\nrole = \"\(role)\"\n")
        #expect(result.hasErrors && result.config.apps.isEmpty, "\(bundle) as \(role)")
        #expect(result.diagnostics.contains { $0.message.contains("a terminal handed a file runs it") })
        let several = ConfigParser.parse("[[app]]\nid = \"mine\"\nname = \"Mine\"\nbundle_ids = [\"com.example.x\", \"\(bundle)\"]\nrole = \"\(role)\"\n")
        #expect(several.hasErrors && several.config.apps.isEmpty, "the second of several identifiers counts as well")
        let fine = ConfigParser.parse("[[app]]\nid = \"mine\"\nname = \"Mine\"\nbundle_id = \"\(bundle)\"\nrole = \"terminal\"\n")
        #expect(!fine.hasErrors && fine.config.apps.map(\.role) == [.terminal], "a terminal stays a terminal")
        #expect(!ConfigParser.parse("[[app]]\nid = \"mine\"\nname = \"Mine\"\nbundle_id = \"com.example.editor\"\nrole = \"editor\"\n").hasErrors)
    }

    /// A zero-width joiner made "Hel\u{200D}per" another name than "Helper", though both show as "Helper Here"; and a title of one's own could repeat
    /// a built-in start option in the language that the menu shows it in ("Letzte Sitzung fortsetzen" next to the German built-in "continue").
    @Test func twoNamesThatReadAlikeAreOneNameAndABuiltInTitleIsTakenInEveryLanguage() {
        let joined = ConfigParser.parse("[agent.a]\nname = \"Helper\"\ncommand = \"a\"\n\n[agent.b]\nname = \"Hel\u{200D}per\"\ncommand = \"b\"\n")
        #expect(joined.hasErrors && joined.config.customAgents.map(\.id) == ["a"], "\(joined.diagnostics)")
        #expect(ConfigParser.parse("[agent.work]\nname = \"Cla\u{200D}ude Code\"\ncommand = \"claude\"\n").hasErrors, "next to the built-in Claude Code")
        #expect(ConfigParser.parse("[agent.work]\nname = \"Ｃｌａｕｄｅ Code\"\ncommand = \"claude\"\n").hasErrors, "full-width letters read the same")
        let german = Localizer(languages: ["de"]).string(.variantContinue)
        let translated = ConfigParser.parse("[[agent.claude.variant]]\nid = \"mine\"\ntitle = \"\(german)\"\narguments = [\"--a\"]\n")
        #expect(translated.hasErrors, "\(german) is what the German menu calls the built-in start option")
        #expect(!ConfigParser.parse("[agent.a]\nname = \"Helper Two\"\ncommand = \"a\"\n").hasErrors)
    }

    @Test func anAgentIsNotCalledWhatAnotherAgentIsCalledAndNeitherIsAStartOptionOfOneAgent() {
        let twice = ConfigParser.parse("[agent.a]\nname = \"Same\"\ncommand = \"a\"\n\n[agent.b]\nname = \" same \"\ncommand = \"b\"\n")
        #expect(twice.hasErrors && twice.config.customAgents.map(\.id) == ["a"], "the second is left out, whatever the case and the spaces")
        #expect(twice.diagnostics.contains { $0.message.contains("another agent is already called") })
        let builtIn = ConfigParser.parse("[agent.work]\nname = \"Claude Code\"\ncommand = \"claude --model x\"\n")
        #expect(builtIn.hasErrors && builtIn.config.customAgents.isEmpty, "a built-in agent's name is taken as well")
        #expect(!ConfigParser.parse("[agent.work]\nname = \"Claude Code (work)\"\ncommand = \"claude\"\n").hasErrors)
        let variants = ConfigParser.parse("[[agent.claude.variant]]\nid = \"a\"\ntitle = \"Fast\"\narguments = [\"--a\"]\n\n[[agent.claude.variant]]\nid = \"b\"\ntitle = \"fast\"\narguments = [\"--b\"]\n")
        #expect(variants.hasErrors && variants.config.agent(id: "claude")?.variants.map(\.id).contains("b") == false && variants.config.agent(id: "claude")?.variants.map(\.id).contains("a") == true)
        let continued = ConfigParser.parse("[[agent.claude.variant]]\nid = \"mine\"\ntitle = \"\(KnownAgents.agent(id: "claude")?.variants.first?.title ?? "")\"\narguments = [\"--a\"]\n")
        #expect(continued.hasErrors, "a built-in start option's title is taken")
        let elsewhere = ConfigParser.parse("[[agent.claude.variant]]\nid = \"a\"\ntitle = \"Fast\"\narguments = [\"--a\"]\n\n[[agent.codex.variant]]\nid = \"a\"\ntitle = \"Fast\"\narguments = [\"--a\"]\n")
        #expect(!elsewhere.hasErrors, "two agents may each have a start option of one title")
    }

    @Test func aNameOnABuiltInAgentAndBothBundleKeysAreSaidToDoNothing() {
        let named = ConfigParser.parse("[agent.claude]\nname = \"Other\"\n")
        #expect(!named.hasErrors && named.diagnostics.contains { $0.severity == .warning && $0.message.contains("keeps its name") })
        let both = ConfigParser.parse("[[app]]\nid = \"x\"\nname = \"X\"\nbundle_id = \"com.example.a\"\nbundle_ids = [\"com.example.b\"]\n")
        #expect(!both.hasErrors && both.diagnostics.contains { $0.severity == .warning && $0.message.contains("bundle_id is ignored") } && both.config.apps.first?.bundleIDs == ["com.example.b"])
    }

    @Test func anActionListedTwiceInTheQuickActionsIsListedOnce() {
        let result = ConfigParser.parse("[services]\nitems = [\"open.terminal\", \"agent.claude\", \"open.terminal\"]\n")
        #expect(result.config.serviceItems == ["open.terminal", "agent.claude"] && result.diagnostics.contains { $0.message.contains("listed twice") })
    }

    @Test func aNameLongerThanAFileSystemTakesIsRefusedWhereItIsWrittenAndATemplateStartsSmall() {
        let long = String(repeating: "A", count: ConfigBuilder.longestName + 1), fits = String(repeating: "A", count: ConfigBuilder.longestName)
        for text in ["[agent.work]\nname = \"\(long)\"\ncommand = \"work\"\n", "[[app]]\nid = \"x\"\nname = \"\(long)\"\nbundle_id = \"com.example.x\"\n",
                     "[[preset]]\nid = \"p\"\ntitle = \"\(long)\"\nprompt = \"Look at {files}.\"\n", "[[new_file.template]]\nid = \"t\"\ntitle = \"\(long)\"\nextension = \"t\"\n",
                     "[copy_path]\ntitle = \"\(long)\"\n"] {
            let result = ConfigParser.parse(text)
            #expect(result.hasErrors && result.diagnostics.contains { $0.message.contains("is longer than 120 characters") }, Comment(rawValue: text))
        }
        #expect(!ConfigParser.parse("[agent.work]\nname = \"\(fits)\"\ncommand = \"work\"\n").hasErrors, "120 characters fit")
        let big = String(repeating: "x", count: ConfigBuilder.largestContents + 1)
        let heavy = ConfigParser.parse("[[new_file.template]]\nid = \"t\"\ntitle = \"T\"\nextension = \"t\"\ncontents = \"\(big)\"\n")
        #expect(heavy.hasErrors && !heavy.config.newFile.templates.contains { $0.id == "t" } && heavy.diagnostics.contains { $0.message.contains("a new file starts small") })
        let ok = ConfigParser.parse("[[new_file.template]]\nid = \"t\"\ntitle = \"T\"\nextension = \"t\"\ncontents = \"\(String(big.dropFirst()))\"\n")
        #expect(!ok.hasErrors && ok.config.newFile.templates.first?.contents.utf8.count == ConfigBuilder.largestContents)
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
        #expect(Set(properties.keys) == ["version", "disabled", "general", "menu", "services", "copy_path", "new_file", "app", "agent", "preset"])
        #expect(decoded["$schema"] as? String == "http://json-schema.org/draft-07/schema#")
    }

    @Test func everyFullConfigKeyIsInTheSchema() {
        let result = ConfigParser.parse(fullConfig)
        #expect(!result.diagnostics.contains { $0.message == "unknown key" })
    }
}

/// A TOML basic string for any text: control characters and quotes escaped.
private enum JSONValueString {
    static func quote(_ text: String) throws -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7f { out += String(format: "\\u%04X", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
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

    @Test func aBuiltInTerminalRedefinedAsAnEditorIsRefusedAndTheBuiltInOneStaysTheDefaultTerminal() throws {
        let result = parse("""
        [general]
        terminal = "ghostty"

        [[app]]
        id = "ghostty"
        name = "Ghostty as an editor"
        bundle_id = "com.mitchellh.ghostty"
        role = "editor"
        """)
        // The entry itself is refused (a terminal handed a file runs it), so it replaces nothing: the choice reads the built-in terminal.
        let error = try #require(result.diagnostics.first { $0.severity == .error })
        #expect(error.message.contains("a terminal handed a file runs it") && result.config.apps.isEmpty)
        #expect(result.config.terminal == "ghostty")
    }

    @Test func aRedefinedTerminalKeepsWorkingAsTheDefaultWhenItIsStillATerminal() {
        let result = parse("""
        [general]
        terminal = "ghostty"

        [[app]]
        id = "ghostty"
        name = "My Ghostty"
        bundle_id = "com.example.ghostty"
        role = "terminal"
        """)
        #expect(!result.hasErrors)
        #expect(result.config.terminal == "ghostty")
    }

    @Test func aTerminalCannotBeTheDefaultEditor() throws {
        let result = parse("""
        [general]
        editor = "ghostty"
        """)
        let error = try #require(result.diagnostics.first { $0.path == "general.editor" && $0.severity == .error })
        #expect(error.message.contains("is a terminal"))
        #expect(result.config.editor == nil)
    }

    @Test func aGeneralRoleAppMayBeTheDefaultEditor() {
        let result = parse("""
        [general]
        editor = "viewer"

        [[app]]
        id = "viewer"
        name = "Viewer"
        bundle_id = "com.example.viewer"
        """)
        #expect(!result.hasErrors)
        #expect(result.config.editor == "viewer")
    }

    @Test func aCustomAgentThatIsNotInTheAgentsListIsWarnedAboutBecauseTheMenuHidesIt() throws {
        let result = parse("""
        [agent.lazygit]
        name = "lazygit"
        command = "lazygit"
        """)
        let warning = try #require(result.diagnostics.first { $0.path == "agent.lazygit" })
        #expect(warning.severity == .warning)
        #expect(warning.message.contains("general.agents"))
        let listed = parse("""
        [general]
        agents = ["lazygit"]
        [agent.lazygit]
        name = "lazygit"
        command = "lazygit"
        """)
        #expect(listed.diagnostics.isEmpty)
    }

    @Test func oneBadAgentCommandIsOneErrorNotThree() {
        let result = parse("""
        [general]
        agents = ["lazygit"]
        [agent.lazygit]
        name = "lazygit"
        command = "lazygit\\nrm -rf ~"
        """)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, Comment(rawValue: "\(errors.map(\.message))"))
        #expect(errors.first?.path == "agent.lazygit.command")
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

    @Test func aCopyPathTitleWithAControlCharacterIsRefusedLikeEveryOtherName() {
        let result = parse("[copy_path]\ntitle = \"A\\u001B[31mRED\\u001B]0;pwned\\u0007Z\"\n")
        #expect(result.config.copyPathTitle == nil)
        #expect(result.diagnostics.contains { $0.severity == .error && $0.path == "copy_path.title" })
        #expect(parse("[copy_path]\ntitle = \"Copy it\"\n").config.copyPathTitle == "Copy it")
    }

    @Test("terminal_placement accepts valid placement names and defaults to a window", arguments: [
        ("window", TerminalPlacement.newWindow),
        ("tab", .newTab),
        ("split-right", .splitRight),
        ("split-down", .splitDown)
    ])
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

    @Test func theLanguageIsOneTheAppHasAndWhatThePersonReadsFollowsIt() throws {
        let german = parse("[general]\nlanguage = \"de\"\n")
        #expect(german.diagnostics.isEmpty && german.config.language == "de")
        #expect(german.config.localizer.string(.menuNewText) == Localizer(languages: ["de"]).string(.menuNewText))
        #expect(parse("").config.language == nil && parse("").config.localizer == .system, "no language follows the system's")
        let unknown = parse("[general]\nlanguage = \"klingon\"\n")
        #expect(unknown.diagnostics.first?.severity == .error && unknown.config.language == nil)
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

    @Test("open_with can never name a terminal: a terminal handed a file runs it", arguments: ["terminal", "ghostty", "iterm"])
    func openWithRefusesATerminal(app: String) throws {
        let result = parse("""
        [[new_file.template]]
        id = "cmd"
        title = "Command"
        extension = "command"
        open_with = "\(app)"
        """)
        let error = try #require(result.diagnostics.first { $0.path == "new_file.template.1.open_with" && $0.severity == .error })
        #expect(error.message.contains("terminal"))
        #expect(result.config.newFile.templates.first { $0.id == "cmd" }?.openWith == nil, "the setting must not survive")
    }

    @Test func openWithRefusesAnAppTheConfigTurnedIntoATerminal() throws {
        let result = parse("""
        [[app]]
        id = "viewer"
        name = "Viewer"
        bundle_id = "com.example.viewer"
        role = "terminal"

        [[new_file.template]]
        id = "x"
        title = "X"
        extension = "x"
        open_with = "viewer"
        """)
        #expect(result.diagnostics.contains { $0.path == "new_file.template.1.open_with" && $0.severity == .error })
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
        for name in ["RH_CONFIG", "RH_CONFIG_DIR", "XDG_CONFIG_HOME", "RH_LOG_DIR", "RH_HOME", "--strict"] {
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
        #expect(id["pattern"] as? String == ConfigSchema.appIdentifierPattern)
        let agents = try #require((schema["properties"] as? [String: Any])?["agent"] as? [String: Any])
        #expect((agents["propertyNames"] as? [String: Any])?["pattern"] as? String == ConfigSchema.identifierPattern)
    }

    @Test("the schema's id pattern and the parser's id rule accept exactly the same ids",
          arguments: ["a", "a-b", "0", "0a", "a0-", "-a", "-", "--x", "A", "a_b", "a b", "", "é", "a.b", "a/b", "x\n"])
    func theIdPatternMatchesTheParser(id: String) throws {
        // ICU's `$` also matches before a final line feed, which ECMA-262 (the dialect JSON Schema names) does
        // not, so the match has to cover the whole text to count.
        let regex = try NSRegularExpression(pattern: ConfigSchema.identifierPattern)
        let whole = NSRange(id.startIndex..., in: id)
        let matches = regex.firstMatch(in: id, range: whole)?.range == whole
        #expect(matches == IDRule.isValid(id), "pattern and parser disagree about \(id.debugDescription)")
    }

    @Test("the schema's extension pattern and the parser's extension rule agree",
          arguments: ["md", "tar", "a b", "", ".md", "m.d", "a/b", "a\u{0}b", "mdé", "m\u{301}/d"])
    func theExtensionPatternMatchesTheParser(ext: String) throws {
        let template = try #require(ConfigSchema.root.first { $0.key == "new_file" }?.child("template")?.child("extension"))
        let regex = try NSRegularExpression(pattern: try #require(template.pattern))
        let whole = NSRange(ext.startIndex..., in: ext)
        let matches = regex.firstMatch(in: ext, range: whole)?.range == whole
        let parsed = ConfigParser.parse("[[new_file.template]]\nid = \"t\"\ntitle = \"T\"\nextension = \(try JSONValueString.quote(ext))\n")
        let accepted = !parsed.hasErrors && parsed.config.newFile.templates.contains { $0.id == "t" }
        #expect(matches == accepted, "pattern and parser disagree about \(ext.debugDescription)")
    }

    @Test func knownTerminalsAreSuggestedNotEnforced() throws {
        let terminal = try #require(property(["general", "terminal"]))
        #expect(terminal["enum"] == nil)
        #expect((terminal["examples"] as? [String])?.contains("ghostty") == true)
    }
}

@Suite("Documentation topics")
struct DocumentationTopicTests {
    @Test func everyListedTopicHasText() {
        // The MCP guide is written by RightHereMCP, which reads the tools from the code (`Guides`); every other topic has its text here.
        for topic in Documentation.topics where topic != Documentation.mcpTopic {
            #expect(Documentation.text(for: topic)?.isEmpty == false, "no text for \(topic)")
        }
        #expect(Documentation.topics.first == "start", "the quick start is listed first")
        #expect(Documentation.text(for: "nope") == nil)
    }

    @Test func theListingAndTheSuggestionComeFromTheSameTopics() {
        for topic in Documentation.topics { #expect(Documentation.listing.contains("  \(topic) ")) }
        #expect(Documentation.closestTopic(to: "troubleshoot") == "troubleshooting")
        #expect(Documentation.closestTopic(to: "") == nil)
        #expect(Documentation.closestTopic(to: "zzz") == nil)
    }

    @Test func theTroubleshootingGuideMatchesTheFileInTheRepository() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/TROUBLESHOOTING.md")
        let source = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(Documentation.text(for: "troubleshooting")?.trimmingCharacters(in: .whitespacesAndNewlines) == source)
    }
}

@Suite("Config diagnostics for lists and commands")
struct ConfigListDiagnosticTests {
    @Test func anEmptyAgentCommandIsAnError() {
        for command in ["", "   "] {
            let result = ConfigParser.parse("[general]\nagents = [\"mine\"]\n[agent.mine]\nname = \"Mine\"\ncommand = \"\(command)\"\n")
            #expect(result.hasErrors && result.diagnostics.contains { $0.message.contains("command is empty") }, Comment(rawValue: "\(result.diagnostics)"))
        }
    }

    @Test func anActionIdThatNamesNothingIsWarnedAbout() {
        let text = "[menu]\nitems = [\"agent.nosuch\", \"open.terminal@nosuch\", \"new-file.zzz\", \"agent.claude.contiune\", \"agent.cluade\", \"open.terminal\", \"agent.claude.continue\"]\n"
        let warnings = ConfigParser.parse(text).diagnostics.filter { $0.severity == .warning }
        #expect(warnings.count == 5, Comment(rawValue: "\(warnings)"))
        #expect(warnings.contains { $0.message.contains("agent.cluade") && $0.replacement == "agent.claude" })
        #expect(warnings.contains { $0.message.contains("agent.claude.contiune") && $0.replacement == "agent.claude.continue" })
    }

    @Test func anAgentListedTwiceIsWarnedAboutAndEnabledOnce() {
        let result = ConfigParser.parse("[general]\nagents = [\"claude\", \"claude\", \"codex\"]\n")
        #expect(result.diagnostics.contains { $0.severity == .warning && $0.message.contains("listed twice") })
        #expect(result.config.enabledAgents == ["claude", "codex"])
    }

    @Test func aStyleListedTwiceIsWarnedAboutAndKeptOnce() {
        let result = ConfigParser.parse("[copy_path]\nstyles = [\"name\", \"absolute\", \"name\"]\n")
        #expect(result.diagnostics.contains { $0.severity == .warning && $0.message.contains("listed twice") })
        #expect(result.config.copyPathStyles == [.name, .absolute])
    }

    @Test func anEmptyMenuIsWarnedAbout() {
        for items in ["[]", "[\"-\"]"] {
            let result = ConfigParser.parse("[menu]\nitems = \(items)\n")
            #expect(result.diagnostics.contains { $0.severity == .warning && $0.message.contains("menu will be empty") })
        }
        #expect(!ConfigParser.parse("[menu]\nitems = [\"copy-path\"]\n").diagnostics.contains { $0.message.contains("menu will be empty") })
    }
}

@Suite("Config text that used to trap the TOML library")
struct TrappingTextTests {
    @Test("a text cut off inside an open bracket is a syntax error", arguments: ["[\"\"", "[ ''", "[[\"\"", "x = 1\n[\"\"", "[\"\".\"\""])
    func truncatedHeader(text: String) {
        let result = ConfigParser.parse(text)
        #expect(result.hasErrors)
    }

    @Test func aValidFileWithoutAFinalNewlineStillParses() {
        #expect(!ConfigParser.parse("[general]\nterminal = \"ghostty\"").hasErrors)
    }
}


@Suite("Truncated configs")
struct TruncatedConfigTests {
    /// A file cut off anywhere (a disk that filled up, a half-saved editor buffer) must be a diagnostic, never a crash:
    /// the TOML library traps on some inputs that end at an unlucky byte.
    @Test func everyPrefixOfARealConfigParses() {
        let template = ConfigTemplate.render(DetectedEnvironment(terminal: "ghostty", editor: "vscode", agents: ["claude", "codex"]))
        for text in [template, fullConfig] {
            let bytes = Array(text.utf8)
            for length in 0...bytes.count {
                guard let prefix = String(bytes: bytes[0..<length], encoding: .utf8) else { continue }
                _ = ConfigParser.parse(prefix)
            }
        }
    }

    @Test func everyOpenBracketCutOffAfterAKeyOrAQuotePairIsAnErrorNotACrash() {
        var failures: [String] = []
        for lead in ["", "x = 1\n", "[general]\n", "  "] {
            for open in ["[", "[[", "[ ", "[a.", "[[a.", "x = [", "x = {", "x = [[", "x = {a=", "x = {a = ["] {
                for tail in ["\"\"", "''", "\"a\"", "'a'", "\"\".\"\"", "''.''", "a", "a.b", "1", "\"\" ", ""] {
                    let result = ConfigParser.parse(lead + open + tail)
                    if !result.hasErrors { failures.append(lead + open + tail) }
                }
            }
        }
        #expect(failures.isEmpty, "parsed without an error: \(failures.prefix(5))")
    }

    @Test func theSameWithEveryByteReplacedByAQuoteOrBracket() {
        let bytes = Array(fullConfig.utf8)
        for index in stride(from: 0, to: bytes.count, by: 3) {
            for replacement in [UInt8(ascii: "\""), UInt8(ascii: "'"), UInt8(ascii: "["), UInt8(ascii: "]"), UInt8(ascii: "{"), UInt8(ascii: "="), UInt8(ascii: "\n")] {
                var changed = bytes
                changed[index] = replacement
                if let text = String(bytes: changed, encoding: .utf8) { _ = ConfigParser.parse(text); _ = ConfigParser.parse(String(text.dropLast(text.count / 2))) }
            }
        }
    }
}

@Suite("New-file template names")
struct TemplateNameLengthTests {
    private func parse(baseName: String, ext: String = "md") -> ConfigLoadResult {
        ConfigParser.parse("[[new_file.template]]\nid = \"t\"\ntitle = \"T\"\nbase_name = \"\(baseName)\"\nextension = \"\(ext)\"\n")
    }

    @Test func aNameTooLongForTheFileSystemIsAnErrorAtValidationTime() {
        #expect(parse(baseName: String(repeating: "a", count: 300)).hasErrors)
        #expect(parse(baseName: String(repeating: "é", count: 130)).hasErrors, "counted in bytes, not characters")
    }

    @Test func aLongButFittingNameIsAccepted() {
        #expect(!parse(baseName: String(repeating: "a", count: 200)).hasErrors)
    }
}

@Suite("Config: the flag that switches an agent's permission prompts off")
struct BypassFlagTests {
    @Test("the flag that switches an agent's prompts off is a flag: words of plain characters, and shell syntax is an error", arguments: [
        "--dangerously-skip-permissions; touch /tmp/x", "--yes && touch x", "--yes | tee x", "--yes $(id)", "--yes `id`", "--yes > f", "'--yes'", "\"--yes\"", "--yes\\n", "--a (b)", "--a {b}", "--a*"
    ])
    func aFlagWithShellSyntaxIsRefusedWhereItIsWritten(flag: String) {
        let toml = flag.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let result = ConfigParser.parse("[agent.claude]\nbypass_permission_arg = \"\(toml)\"\n")
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.map(\.path) == ["agent.claude.bypass_permission_arg"], "\(flag.debugDescription): \(result.diagnostics)")
        #expect(result.config.agents["claude"]?.bypassPermissionArgument == nil)
    }

    @Test("a flag is accepted when it is made of words of plain characters", arguments: ["--yolo", "--approval-mode=yolo", "--permission-mode bypassPermissions", "--allow-all-tools", "-y", "--yes-always", "--sandbox=none:/tmp/x,y+z@1"])
    func aPlainFlagIsAccepted(flag: String) {
        let result = ConfigParser.parse("[agent.claude]\nbypass_permission_arg = \"\(flag)\"\n")
        #expect(!result.hasErrors && result.config.agents["claude"]?.bypassPermissionArgument == flag, "\(result.diagnostics)")
        let node = ConfigSchema.root.first { $0.key == "agent" }?.child("bypass_permission_arg")
        #expect(node?.pattern == ConfigSchema.bypassFlagPattern && (try? NSRegularExpression(pattern: ConfigSchema.bypassFlagPattern))?.firstMatch(in: flag, range: NSRange(flag.startIndex..., in: flag)) != nil)
    }
}

@Suite("Config: names and titles shown to people")
struct DisplayNameTests {
    /// What a terminal acts on, as TOML escapes: an escape sequence that sets the clipboard, a C1 control, a line break, a
    /// line separator, a bell.
    static let hostile = ["Evil\\u001b]52;c;aGk=\\u0007", "x\\u009b31m", "two\\nlines", "a\\u2028b", "bell\\u0007", "a\\u007fb"]

    private func errors(_ result: ConfigLoadResult) -> [ConfigDiagnostic] { result.diagnostics.filter { $0.severity == .error } }

    @Test("an app's name with a control character is an error, and the app is left out", arguments: hostile)
    func appName(name: String) {
        let result = ConfigParser.parse("[[app]]\nid = \"evil\"\nname = \"\(name)\"\nbundle_id = \"a.b\"\n")
        #expect(errors(result).map(\.path) == ["app.1.name"], "\(result.diagnostics)")
        #expect(errors(result).first?.message == "the name has a line break or control character")
        #expect(result.config.apps.isEmpty)
    }

    /// What reads as something other than it says: a direction override, an embedding, an isolate, a zero-width space, a word joiner, a byte order mark, a soft hyphen, a tag character.
    static let misleading = ["a\\u202eb", "a\\u202ab", "a\\u2066b\\u2069", "a\\u200bb", "a\\u2060b", "a\\ufeffb", "a\\u00adb", "Claude\\U000e0041", "a\\u2062\\u2063b", "x😀\\ufe00\\ufe01y"]

    @Test("a name that reads as something else than it says is an error on every kind of name", arguments: misleading)
    func misleadingName(name: String) {
        let agent = ConfigParser.parse("[general]\nagents = [\"evil\"]\n[agent.evil]\nname = \"\(name)\"\ncommand = \"evil\"\n")
        #expect(errors(agent).map(\.path) == ["agent.evil.name"] && errors(agent).first?.message.hasPrefix("the name has a character that changes how it reads") == true, "\(agent.diagnostics)")
        #expect(agent.config.agent(id: "evil") == nil)
        let preset = ConfigParser.parse("[[preset]]\nid = \"evil\"\ntitle = \"\(name)\"\nprompt = \"Look at {files}\"\n")
        #expect(errors(preset).map(\.path) == ["preset.1.title"] && preset.config.preset(id: "evil") == nil)
        let variant = ConfigParser.parse("[agent.claude]\n[[agent.claude.variant]]\nid = \"evil\"\ntitle = \"\(name)\"\narguments = [\"--x\"]\n")
        #expect(errors(variant).map(\.path) == ["agent.claude.variant.1.title"])
        let copyPath = ConfigParser.parse("[copy_path]\ntitle = \"\(name)\"\n")
        #expect(errors(copyPath).map(\.path) == ["copy_path.title"])
    }

    @Test("a custom agent's name with a control character is one error, and the agent is left out", arguments: hostile)
    func agentName(name: String) {
        let result = ConfigParser.parse("[general]\nagents = [\"evil\"]\n[agent.evil]\nname = \"\(name)\"\ncommand = \"evil\"\n")
        #expect(errors(result).map(\.path) == ["agent.evil.name"], "no second complaint about the agent the config just lost: \(result.diagnostics)")
        #expect(result.config.agent(id: "evil") == nil)
        #expect(result.config.enabledAgents.isEmpty)
    }

    @Test("a new-file template's title with a control character is an error, and the template is left out", arguments: hostile)
    func templateTitle(title: String) {
        let result = ConfigParser.parse("[[new_file.template]]\nid = \"evil\"\ntitle = \"\(title)\"\nextension = \"txt\"\n")
        #expect(errors(result).map(\.path) == ["new_file.template.1.title"], "\(result.diagnostics)")
        #expect(result.config.newFile.templates == NewFileTemplate.builtIn)
    }

    @Test("a template's file name and extension are held to what every name is: a control character or a character that changes how it reads is an error, and the template is left out", arguments: hostile + misleading)
    func templateFileName(name: String) {
        let base = ConfigParser.parse("[[new_file.template]]\nid = \"evil\"\ntitle = \"Evil\"\nbase_name = \"\(name)\"\nextension = \"txt\"\n")
        #expect(errors(base).map(\.path) == ["new_file.template.1.base_name"], "\(base.diagnostics)")
        #expect(base.config.newFile.templates == NewFileTemplate.builtIn)
        let ext = ConfigParser.parse("[[new_file.template]]\nid = \"evil\"\ntitle = \"Evil\"\nextension = \"\(name)\"\n")
        #expect(errors(ext).map(\.path) == ["new_file.template.1.extension"], "\(ext.diagnostics)")
        #expect(ext.config.newFile.templates == NewFileTemplate.builtIn)
    }

    @Test func aTemplateInAnyScriptHasAFileNameAndAnExtension() {
        for (name, ext) in [("無題", "txt"), ("Sans titre", "md"), ("بدون\u{200F} عنوان", "txt"), ("naïve café", "markdown"), ("a b", "tar gz")] {
            let result = ConfigParser.parse("[[new_file.template]]\nid = \"fine\"\ntitle = \"Fine\"\nbase_name = \"\(name)\"\nextension = \"\(ext)\"\n")
            #expect(!result.hasErrors && result.config.newFile.templates.map(\.baseName) == [name], "\(name.debugDescription): \(result.diagnostics)")
        }
    }

    @Test("an agent variant's title with a control character is an error, and the variant is left out", arguments: hostile)
    func variantTitle(title: String) {
        let result = ConfigParser.parse("[agent.claude]\n[[agent.claude.variant]]\nid = \"evil\"\ntitle = \"\(title)\"\narguments = [\"--x\"]\n")
        #expect(errors(result).map(\.path) == ["agent.claude.variant.1.title"], "\(result.diagnostics)")
        #expect(result.config.agent(id: "claude")?.variants.map(\.id) == ["continue", "resume"])
    }

    @Test("a preset's title with a control character is an error, and the preset is left out", arguments: hostile)
    func presetTitle(title: String) {
        let result = ConfigParser.parse("[[preset]]\nid = \"evil\"\ntitle = \"\(title)\"\nprompt = \"Look at {files}\"\n")
        #expect(errors(result).map(\.path) == ["preset.1.title"], "\(result.diagnostics)")
        #expect(result.config.preset(id: "evil") == nil)
    }

    @Test func ordinaryNamesInAnyScriptAreAccepted() {
        // Right-to-left marks are part of names in Arabic and Hebrew; they are not what this refuses.
        for name in ["Tower", "Éditeur de texte", "日本語のエディタ", "محرر\u{200F} النصوص", "Name with  two spaces", "", "می\u{200C}خواهم", "👨\u{200D}👩\u{200D}👧", "Tower\u{200E}"] {
            let result = ConfigParser.parse("[[app]]\nid = \"fine\"\nname = \"\(name)\"\nbundle_id = \"a.b\"\n")
            #expect(!result.hasErrors && result.config.apps.map(\.name) == [name], "\(name.debugDescription): \(result.diagnostics)")
        }
    }

    @Test("the schema's pattern for a name and the parser's rule agree", arguments: ["Tower", "", "é", "a\n", "a\u{1b}", "a\u{85}", "a\u{9b}", "a\u{2028}", "a\u{2029}", "a\u{7f}", "a\u{200F}b", "a\tb", "a\u{202E}b", "a\u{2066}b", "a\u{200B}b", "a\u{2060}", "a\u{FEFF}", "a\u{AD}b", "a\u{200D}b", "a\u{200E}b", "a\u{2062}b", "a\u{206B}b", "a\u{34F}b", "R\u{17B4}eview", "\u{3164}", "a\u{FFA0}"])
    func theNamePatternMatchesTheParser(name: String) throws {
        let node = try #require(ConfigSchema.root.first { $0.key == "app" }?.child("name"))
        let regex = try NSRegularExpression(pattern: try #require(node.pattern))
        let whole = NSRange(name.startIndex..., in: name)
        let matches = regex.firstMatch(in: name, range: whole)?.range == whole
        let parsed = ConfigParser.parse("[[app]]\nid = \"t\"\nname = \(try JSONValueString.quote(name))\nbundle_id = \"a.b\"\n")
        #expect(matches == !parsed.hasErrors, "pattern and parser disagree about \(name.debugDescription)")
        // Every title and name in the schema carries the same pattern.
        for (table, key) in [("app", "name"), ("agent", "name")] {
            #expect(ConfigSchema.root.first { $0.key == table }?.child(key)?.pattern == ConfigSchema.displayNamePattern)
        }
        #expect(ConfigSchema.root.first { $0.key == "preset" }?.child("title")?.pattern == ConfigSchema.displayNamePattern)
        #expect(ConfigSchema.root.first { $0.key == "new_file" }?.child("template")?.child("title")?.pattern == ConfigSchema.displayNamePattern)
        #expect(ConfigSchema.root.first { $0.key == "new_file" }?.child("template")?.child("base_name")?.pattern == ConfigSchema.displayNamePattern)
        #expect(ConfigSchema.root.first { $0.key == "agent" }?.child("variant")?.child("title")?.pattern == ConfigSchema.displayNamePattern)
    }
}

@Suite("Config: launchers an agent cannot use, and the menu naming what general.agents does not list")
struct AgentLauncherDiagnosticTests {
    private func warnings(_ text: String) -> [ConfigDiagnostic] { ConfigParser.parse(text).diagnostics.filter { $0.severity == .warning } }

    @Test("a custom agent cannot start through a link or the desktop app, and validate says so", arguments: [("link", "terminal link"), ("desktop", "desktop app link")])
    func aCustomAgentHasNoLink(launcher: String, kind: String) throws {
        let found = warnings("[general]\nagents = [\"a2\"]\n[agent.a2]\nname = \"A2\"\ncommand = \"a2\"\nlauncher = \"\(launcher)\"\n")
        let warning = try #require(found.first { $0.path == "agent.a2.launcher" }, "\(found)")
        #expect(warning.message.contains("an agent that is not built in has no \(kind)") && warning.message.contains("rh run agent.a2"), "\(warning.message)")
        #expect(found.count == 1)
    }

    @Test func aBuiltInAgentWithoutThatLinkGetsTheSameWarningAndOneWithItDoesNot() throws {
        func warning(_ text: String) -> ConfigDiagnostic? { warnings(text).first { $0.path.hasSuffix("launcher") } }
        #expect(warning("[agent.claude]\nlauncher = \"link\"\n") == nil)
        #expect(warning("[agent.claude]\nlauncher = \"desktop\"\n") == nil)
        #expect(warning("[agent.codex]\nlauncher = \"desktop\"\n") == nil)
        #expect(warning("[agent.codex]\nlauncher = \"terminal\"\n") == nil)
        let codex = try #require(warning("[agent.codex]\nlauncher = \"link\"\n"))
        #expect(codex.message.contains("Codex has no terminal link (only Claude Code has one)"), "\(codex.message)")
        let gemini = try #require(warning("[agent.gemini]\nlauncher = \"desktop\"\n"))
        #expect(gemini.message.contains("Gemini CLI has no desktop app link (only Claude Code and Codex have one)"), "\(gemini.message)")
    }

    @Test("an agent that menu.items names is offered, so it is not said to be hidden", arguments: ["agent.lazygit", "agent.lazygit.fast", "agent.lazygit@ghostty"])
    func aMenuEntryOffersAnAgentTheListDoesNot(entry: String) {
        let text = "[menu]\nitems = [\"\(entry)\", \"agents\"]\n[agent.lazygit]\nname = \"lazygit\"\ncommand = \"lazygit\"\n[[agent.lazygit.variant]]\nid = \"fast\"\ntitle = \"Fast\"\n"
        #expect(!warnings(text).contains { $0.path == "agent.lazygit" }, "\(warnings(text))")
    }

    @Test func theWarningStaysWhenNothingOffersTheAgent() {
        let agent = "[agent.lazygit]\nname = \"lazygit\"\ncommand = \"lazygit\"\n"
        #expect(warnings(agent).contains { $0.path == "agent.lazygit" && $0.message.contains("not in general.agents") })
        // Groups name no agent: `agents` lists the enabled ones.
        #expect(warnings("[menu]\nitems = [\"agents\", \"agents-more\"]\n" + agent).contains { $0.path == "agent.lazygit" })
        // Another agent's entry offers that agent, not this one.
        #expect(warnings("[menu]\nitems = [\"agent.claude\"]\n" + agent).contains { $0.path == "agent.lazygit" })
    }

    @Test func aPresetThatMenuItemsListsIsOfferedWhateverItsAgent() {
        let preset = "[general]\nagents = [\"claude\"]\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nagent = \"codex\"\nprompt = \"Look at {files}\"\n"
        #expect(warnings(preset).contains { $0.path == "preset.1.agent" && $0.message.contains("not in general.agents") })
        #expect(warnings("[menu]\nitems = [\"presets\"]\n" + preset).contains { $0.path == "preset.1.agent" && $0.message.contains("not in general.agents") }, "the group offers only the presets of enabled agents")
        #expect(!warnings("[menu]\nitems = [\"preset.mine\"]\n" + preset).contains { $0.message.contains("not in general.agents") })
        #expect(!warnings("[menu]\nitems = [\"preset.mine@terminal\"]\n" + preset).contains { $0.message.contains("not in general.agents") })
    }
}

@Suite("Config: what a value was when it is not what was asked for")
struct ConfigValueDiagnosticTests {
    private func only(_ text: String) throws -> ConfigDiagnostic {
        let result = ConfigParser.parse(text)
        #expect(result.diagnostics.count == 1, "\(result.diagnostics)")
        return try #require(result.diagnostics.first)
    }

    @Test("a value of the wrong kind says what it is, and the line", arguments: [
        ("[general]\nterminal = 5\n", "general.terminal", "expected a string, found an integer", 2),
        ("[general]\nterminal = true\n", "general.terminal", "expected a string, found a boolean", 2),
        ("[general]\nterminal = 1.5\n", "general.terminal", "expected a string, found a number with a decimal point", 2),
        ("[general]\nterminal = 1979-05-27\n", "general.terminal", "expected a string, found a date or time", 2),
        ("[general]\nterminal = [\"a\"]\n", "general.terminal", "expected a string, found an array", 2),
        ("[general]\nterminal = { a = 1 }\n", "general.terminal", "expected a string, found a table", 2),
        ("# one\n[general]\nagents = [1, 2]\n", "general.agents", "expected an array of strings, found an integer as item 1", 3),
        ("[general]\nagents = [\"claude\", true]\n", "general.agents", "expected an array of strings, found a boolean as item 2", 2),
        ("[general]\nagents = 5\n", "general.agents", "expected an array of strings, found an integer", 2),
        ("general = \"x\"\n", "general", "expected a table, found a string", 1),
        ("[[agent]]\nname = \"x\"\n", "agent", "expected a table, found an array", 1),
        ("app = \"x\"\n", "app", "expected an array of tables, written [[app]], found a string", 1),
        ("[[preset]]\nid = \"p\"\ntitle = \"P\"\nprompt = \"x\"\nmax_files = \"ten\"\n", "preset.1.max_files", "expected an integer, found a string", 5),
    ])
    func wrongKind(text: String, path: String, message: String, line: Int) throws {
        let found = try only(text)
        #expect(found.path == path && found.message == message && found.line == line && found.severity == .error, "\(found)")
    }

    @Test func textWithoutQuotesSaysSoAndOffersTheQuotedText() throws {
        let found = try only("[general]\nterminal = ghostty\n")
        #expect(found.message == "expected a string, found text without quotes")
        #expect(found.suggestion == "write it in quotes: \"ghostty\"" && found.replacement == "\"ghostty\"", "\(found)")
        #expect(found.line == 2)
        // Inside a list: the item, without a replacement (the raw text of one item is not known).
        let item = try only("[general]\nagents = [\"claude\", codex]\n")
        #expect(item.message == "expected an array of strings, found text without quotes as item 2" && item.replacement == nil)
    }

    @Test func aStringWhereAListWasMeantOffersTheList() throws {
        let found = try only("[general]\nagents = \"claude\"\n")
        #expect(found.message == "expected an array of strings, found a string" && found.replacement == "[\"claude\"]", "\(found)")
    }

    @Test func aStringWithABadEscapeSaysWhySinceItIsAStringAfterAll() throws {
        let found = try only("[general]\nterminal = \"gh\\qostty\"\n")
        #expect(found.message.hasPrefix("expected a string, found a value that is not valid (illegal escape character 'q'"), "\(found.message)")
        #expect(found.message.contains("single quotes"))
    }

    @Test func aValueTheMergeCannotTypeIsKeptAsWrittenSoTheRestOfTheFileStillApplies() throws {
        // `readTree` found no kind for `ghostty` or for the bad escape and dropped the whole shared file with "contains a value
        // of a kind this build cannot read", so the editor and everything else in it were lost the moment an overlay existed.
        let base = "[general]\nterminal = ghostty\neditor = \"vscode\"\n[[preset]]\nid = \"p\"\ntitle = \"P\"\nprompt = \"look \\d\"\n"
        let plain = ConfigParser.parse(base)
        let layered = ConfigLayers.load(base: .text(base), local: .text("[general]\nagents = [\"claude\"]\n"))
        #expect(layered.config.editor == "vscode" && layered.config.enabledAgents == ["claude"], "\(layered.diagnostics)")
        #expect(!layered.diagnostics.contains { $0.message.contains("a kind this build cannot read") })
        // The problems are the ones the file alone has, at the same lines, and nothing else is said.
        #expect(layered.diagnostics == plain.diagnostics, "\(layered.diagnostics)")
        #expect(plain.diagnostics.map(\.path) == ["general.terminal", "preset.1.prompt"] && plain.diagnostics.map(\.line) == [2, 7])
        // With an empty overlay the merge path says the same as the plain one, which the fuzz test also holds.
        #expect(ConfigLayers.load(base: .text(base), local: .text("# nothing here\n")).diagnostics == plain.diagnostics)
    }

    @Test func anUntypedValueInTheOverlayIsKeptToo() throws {
        let layered = ConfigLayers.load(base: .text("[general]\neditor = \"vscode\"\n"), local: .text("[general]\nterminal = ghostty\nagents = [\"codex\"]\n"))
        #expect(layered.config.editor == "vscode" && layered.config.enabledAgents == ["codex"])
        let found = try #require(layered.diagnostics.first)
        #expect(found.file == "config.local.toml" && found.line == 2 && found.path == "general.terminal" && found.message == "expected a string, found text without quotes", "\(found)")
    }

    @Test func aMissingKeyIsNamedAndAWrongTypedOneIsNotSaidTwice() {
        func messages(_ text: String) -> [String] { ConfigParser.parse(text).diagnostics.map(\.message) }
        #expect(messages("[[app]]\nid = \"x\"\n") == ["an app needs id and name (missing: name)"])
        #expect(messages("[[new_file.template]]\nid = \"y\"\n") == ["a template needs id, title and extension (missing: title and extension)"])
        #expect(messages("[[preset]]\nid = \"z\"\n") == ["a preset needs id, title and prompt (missing: title and prompt)"])
        #expect(messages("[agent.q]\ncommand = \"q\"\n") == ["an agent that is not built in needs name and command (missing: name)"])
        #expect(messages("[agent.claude]\n[[agent.claude.variant]]\nid = \"v\"\n") == ["a variant needs id and title (missing: title)"])
        // The key is there with the wrong type: one error, the type's, not "needs id" as well.
        #expect(messages("[[app]]\nid = 5\nname = \"X\"\nbundle_id = \"a.b\"\n") == ["expected a string, found an integer"])
    }

    @Test func anAgentWithoutANameIsOneErrorNotTwo() {
        let result = ConfigParser.parse("[general]\nagents = [\"mything\"]\n[agent.mything]\ncommand = \"x\"\n[[preset]]\nid = \"p\"\ntitle = \"P\"\nagent = \"mything\"\nprompt = \"x {files}\"\n")
        #expect(result.diagnostics.map(\.path) == ["agent.mything"], "\(result.diagnostics)")
        let invalidID = ConfigParser.parse("[general]\nagents = [\"Bad Id\"]\n[agent.\"Bad Id\"]\nname = \"B\"\ncommand = \"b\"\n")
        #expect(invalidID.diagnostics.count == 1 && invalidID.diagnostics.first?.path == "agent.Bad Id", "\(invalidID.diagnostics)")
    }

    @Test func anEnumErrorListsTheValidValues() throws {
        let found = try only("[copy_path]\nstyles = [\"absolute\", \"relative\"]\n")
        #expect(found.message.hasPrefix("unknown style \"relative\"; known styles: absolute, tilde, git-relative"), "\(found.message)")
        for style in PathStyle.allCases { #expect(found.message.contains(style.rawValue)) }
    }

    @Test("a name finds the id it is the name of", arguments: [
        ("[general]\neditor = \"Visual Studio Code\"\n", "general.editor", "vscode"),
        ("[general]\nterminal = \"Ghostty\"\n", "general.terminal", "ghostty"),
        ("[general]\nagents = [\"Claude Code\"]\n", "general.agents", "claude"),
        ("[general]\nagents = [\"Gemini CLI\"]\n", "general.agents", "gemini"),
        ("[[new_file.template]]\nid = \"t\"\ntitle = \"T\"\nextension = \"md\"\nopen_with = \"Typora\"\n", "new_file.template.1.open_with", "typora"),
    ])
    func didYouMeanByName(text: String, path: String, id: String) throws {
        let found = try #require(ConfigParser.parse(text).diagnostics.first { $0.path == path })
        #expect(found.replacement == id && found.suggestion == "did you mean \"\(id)\"?", "\(found)")
    }

    @Test func aKeyThatBelongsInAnotherTableSaysWhere() throws {
        func hint(_ text: String) throws -> ConfigDiagnostic { try #require(ConfigParser.parse(text).diagnostics.first { $0.message == "unknown key" }) }
        let placement = try hint("[copy_path]\nterminal_placement = \"tab\"\n")
        #expect(placement.suggestion == "\"terminal_placement\" belongs in [general]" && placement.replacement == nil, "\(placement)")
        #expect(try hint("[copy_path]\nitems = []\n").suggestion == "\"items\" is a key of [menu] and [services]")
        #expect(try hint("[menu]\nagents = [\"claude\"]\n").suggestion == "\"agents\" belongs in [general]")
        #expect(try hint("[general]\ncommand = \"x\"\n").suggestion == "\"command\" belongs in [agent.<id>]")
        #expect(try hint("[general]\nvariant = 1\n").suggestion == "\"variant\" belongs in [agent.<id>]")
        // Too many homes to be a hint; and a typo of a key of this table is a typo first.
        #expect(try hint("[copy_path]\nid = \"x\"\n").suggestion == nil)
        #expect(try hint("[copy_path]\nstyls = []\n").suggestion == "did you mean \"styles\"?")
        #expect(try hint("[copy_path]\nzzzzzzzzzz = 1\n").suggestion == nil)
    }

    @Test func problemsComeInTheOrderOfTheFile() {
        let result = ConfigParser.parse("[general]\ntermnial = \"x\"\nagnts = []\nedtor = \"x\"\n[menu]\nitemz = []\n")
        #expect(result.diagnostics.map(\.path) == ["general.termnial", "general.agnts", "general.edtor", "menu.itemz"])
        #expect(result.diagnostics.map(\.line) == [2, 3, 4, 6])
    }
}

@Suite("Config: app ids that are launcher words")
struct AppIDLauncherWordTests {
    @Test("an app cannot have the id of a launcher word, which agent.<agent>@<word> reads as one", arguments: ["link", "desktop", "default"])
    func reserved(id: String) throws {
        for role in ["terminal", "editor", "general"] {
            let result = ConfigParser.parse("[[app]]\nid = \"\(id)\"\nname = \"X\"\nbundle_id = \"a.b\"\nrole = \"\(role)\"\n")
            let error = try #require(result.diagnostics.first, "accepted as \(role)")
            #expect(result.diagnostics.count == 1 && error.severity == .error && error.path == "app.1.id" && error.line == 2, "\(result.diagnostics)")
            #expect(error.message.contains("cannot be an app id") && error.message.contains("agent.<agent>@\(id)"), "\(error.message)")
            #expect(result.config.apps.isEmpty && result.config.app(id: id) == nil)
        }
    }

    @Test func theWordsAreTheOnesTheActionIdGrammarReads() throws {
        #expect(AgentLauncher.reservedWords == ["link", "desktop", "default"])
        for word in AgentLauncher.reservedWords {
            // As a launcher, never as the terminal of that name.
            switch try #require(ActionRef(parsing: "agent.claude@\(word)")) {
            case .agent(_, _, .terminal(let terminal)?): #expect(terminal == nil, "\(word) is read as a terminal id")
            case .agent(_, _, .terminalLink?), .agent(_, _, .desktop?): break
            default: Issue.record("\(word) is not a launcher word")
            }
        }
        // `terminal` is no launcher word to the action id: `agent.claude@terminal` is the terminal called terminal.
        #expect(ActionRef(parsing: "agent.claude@terminal") == .agent(id: "claude", variant: nil, launcher: .terminal("terminal")))
    }

    @Test("close ids are fine", arguments: ["desktops", "links", "defaults", "my-default", "default2", "terminal"])
    func closeIDs(id: String) {
        let result = ConfigParser.parse("[[app]]\nid = \"\(id)\"\nname = \"X\"\nbundle_id = \"a.b\"\n")
        #expect(!result.diagnostics.contains { $0.path == "app.1.id" && $0.message.contains("cannot be an app id") }, "\(result.diagnostics)")
        #expect(result.config.apps.map(\.id) == [id])
    }

    @Test("the schema's pattern for an app id and the parser agree", arguments: ["tower", "link", "desktop", "default", "desktops", "a-b", "-a", "A", "", "default-", "x\n", "terminal"])
    func theAppIDPatternMatchesTheParser(id: String) throws {
        let regex = try NSRegularExpression(pattern: ConfigSchema.appIdentifierPattern)
        let whole = NSRange(id.startIndex..., in: id)
        let matches = regex.firstMatch(in: id, range: whole)?.range == whole
        let parsed = ConfigParser.parse("[[app]]\nid = \(try JSONValueString.quote(id))\nname = \"X\"\nbundle_id = \"a.b\"\n")
        let accepted = !parsed.diagnostics.contains { $0.path == "app.1.id" && $0.severity == .error }
        #expect(matches == accepted, "pattern and parser disagree about \(id.debugDescription)")
    }
}
