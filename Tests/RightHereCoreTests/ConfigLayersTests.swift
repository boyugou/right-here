import Foundation
import Testing
@testable import RightHereCore

private func layered(_ base: String, _ local: String?) -> ConfigLoadResult {
    ConfigLayers.load(base: .text(base), local: local.map { .text($0) } ?? .absent)
}

private let baseConfig = """
[general]
terminal = "ghostty"
editor = "vscode"
agents = ["claude", "codex"]

[menu]
items = ["open-terminal", "agents", "-", "copy-path"]

[[app]]
id = "alpha"
name = "Alpha"
bundle_id = "a.alpha"

[[app]]
id = "beta"
name = "Beta"
bundle_id = "a.beta"

[[new_file.template]]
id = "note"
title = "Note"
extension = "txt"

[agent.claude]
command = "claude --model opus"

[[agent.claude.variant]]
id = "fast"
title = "Fast"
arguments = ["--fast"]

[[agent.claude.variant]]
id = "slow"
title = "Slow"
arguments = ["--slow"]

[agent.mine]
name = "Mine"
command = "mine"
"""

@Suite("ConfigLayers: merge rules")
struct ConfigLayersMergeTests {
    @Test func scalarsInTheOverlayWin() {
        let result = layered(baseConfig, "[general]\nterminal = \"terminal\"\n[new_file]\nthen = \"open\"\n")
        #expect(result.config.terminal == "terminal")
        #expect(result.config.editor == "vscode")
        #expect(result.config.newFile.then == .open)
        #expect(!result.hasErrors)
    }

    @Test func listsAreReplacedAsAWhole() {
        let result = layered(baseConfig, "[menu]\nitems = [\"copy-path\"]\n[general]\nagents = [\"codex\"]\n")
        #expect(result.config.menuItems == ["copy-path"])
        #expect(result.config.enabledAgents == ["codex"])
    }

    @Test func appsMergeByIDInPlace() {
        let result = layered(baseConfig, "[[app]]\nid = \"alpha\"\nname = \"Alpha Two\"\nbundle_id = \"b.alpha\"\n[[app]]\nid = \"gamma\"\nname = \"Gamma\"\nbundle_id = \"a.gamma\"\n")
        #expect(result.config.apps.map(\.id) == ["alpha", "beta", "gamma"])
        #expect(result.config.apps[0].name == "Alpha Two")
        #expect(result.config.apps[0].bundleIDs == ["b.alpha"])
        #expect(result.config.apps[1].name == "Beta")
    }

    @Test func templatesMergeByID() {
        let result = layered(baseConfig, "[[new_file.template]]\nid = \"note\"\ntitle = \"Notes\"\nextension = \"md\"\n[[new_file.template]]\nid = \"todo\"\ntitle = \"Todo\"\nextension = \"txt\"\n")
        #expect(result.config.newFile.templates.map(\.id) == ["note", "todo"])
        #expect(result.config.newFile.templates[0].fileExtension == "md")
    }

    @Test func anAgentTableMergesKeyByKeyAndVariantsByID() {
        let result = layered(baseConfig, """
        [agent.claude]
        command = "claude --model sonnet"
        [[agent.claude.variant]]
        id = "slow"
        title = "Slower"
        arguments = ["--slower"]
        [[agent.claude.variant]]
        id = "new"
        title = "New"
        """)
        let claude = result.config.agent(id: "claude")
        #expect(claude?.command == "claude --model sonnet")
        let mine = (claude?.variants ?? []).filter { ["fast", "slow", "new"].contains($0.id) }
        #expect(mine.map(\.id) == ["fast", "slow", "new"])
        #expect(mine[1].title == "Slower")
        #expect(!result.hasErrors)
    }

    @Test func aNewAgentCanComeFromTheOverlay() {
        let result = layered(baseConfig, "[general]\nagents = [\"claude\", \"extra\"]\n[agent.extra]\nname = \"Extra\"\ncommand = \"extra\"\n")
        #expect(result.config.agent(id: "extra")?.command == "extra")
        #expect(result.config.enabledAgents == ["claude", "extra"])
    }

    @Test func theOverlayMayNameWhatOnlyTheBaseDefines() {
        let result = layered(baseConfig, "[[new_file.template]]\nid = \"todo\"\ntitle = \"Todo\"\nextension = \"txt\"\nopen_with = \"alpha\"\n[general]\nterminal = \"ghostty\"\n[menu]\nitems = [\"open.app.alpha\", \"agent.mine\"]\n")
        #expect(!result.hasErrors)
        #expect(result.diagnostics.filter { $0.message.contains("not defined") }.isEmpty)
        #expect(result.config.newFile.templates.first { $0.id == "todo" }?.openWith == "alpha")
    }

    @Test func anEmptyOverlayChangesNothing() {
        let plain = ConfigParser.parse(baseConfig)
        let result = layered(baseConfig, "# nothing on this machine\n")
        #expect(result.config == plain.config)
        #expect(result.diagnostics == plain.diagnostics)
    }

    @Test func anOverlayAloneWorksWithoutABase() {
        let result = ConfigLayers.load(base: .absent, local: .text("[general]\nterminal = \"terminal\"\n"))
        #expect(result.config.terminal == "terminal")
    }
}

@Suite("ConfigLayers: disabled")
struct ConfigLayersDisabledTests {
    @Test func removesAppsTemplatesAndAgentDefinitions() {
        let result = layered(baseConfig, "disabled = [\"alpha\", \"note\", \"mine\"]\n")
        #expect(result.config.apps.map(\.id) == ["beta"])
        #expect(!result.config.newFile.templates.contains { $0.id == "note" })
        #expect(result.config.agent(id: "mine") == nil)
    }

    @Test func removesABuiltInTemplate() {
        let result = layered("", "disabled = [\"md\"]\n")
        #expect(!result.config.newFile.templates.contains { $0.id == "md" })
        #expect(result.config.newFile.templates.contains { $0.id == "txt" })
    }

    @Test func removesTheIDFromEveryList() {
        let result = layered(baseConfig + "\n[services]\nitems = [\"agent.codex\", \"open.terminal\", \"agent.claude.fast@ghostty\"]\n", """
        disabled = ["codex", "ghostty", "alpha"]
        [menu]
        items = ["open-terminal", "agent.codex", "open.app.alpha", "open.app.beta", "open.terminal@ghostty"]
        """)
        #expect(result.config.enabledAgents == ["claude"])
        #expect(result.config.menuItems == ["open-terminal", "open.app.beta"])
        #expect(result.config.serviceItems == ["open.terminal"])
        #expect(result.config.terminal == nil)
        #expect(!result.hasErrors)
    }

    @Test func aMissingIDIsSimplySkipped() {
        let result = layered(baseConfig, "disabled = [\"not-installed-here\"]\n")
        #expect(result.config.apps.count == 2)
        #expect(result.diagnostics == ConfigParser.parse(baseConfig).diagnostics)
    }

    @Test func inTheSharedFileItIsReportedAndIgnored() {
        let result = layered("disabled = [\"alpha\"]\n" + baseConfig, "")
        #expect(result.config.apps.count == 2)
        #expect(result.diagnostics.contains { $0.path == "disabled" && $0.severity == .warning && $0.message.contains("only meaningful in config.local.toml") && $0.file == nil })
        let alone = ConfigParser.parse("disabled = [\"alpha\"]\n")
        #expect(alone.diagnostics.contains { $0.path == "disabled" && $0.message.contains("only meaningful in config.local.toml") })
    }

    @Test func aWrongTypeIsAnErrorInTheOverlay() {
        let result = layered(baseConfig, "disabled = \"alpha\"\n")
        #expect(result.diagnostics.contains { $0.path == "disabled" && $0.severity == .error && $0.file == "config.local.toml" })
        #expect(result.config.apps.count == 2)
    }
}

@Suite("ConfigLayers: diagnostics")
struct ConfigLayersDiagnosticTests {
    @Test func aProblemInTheOverlayNamesTheOverlay() {
        let result = layered(baseConfig, "[general]\ntermnial = \"x\"\n")
        let unknown = result.diagnostics.first { $0.message == "unknown key" }
        #expect(unknown?.file == "config.local.toml")
        #expect(unknown?.summary(file: URL(fileURLWithPath: "/x/config.toml")).hasPrefix("warning: config.local.toml [general.termnial]") == true)
    }

    @Test func aProblemInTheBaseKeepsTheBaseName() {
        let result = layered(baseConfig + "\n[copy_path]\nstyles = [\"absolut\"]\n", "[general]\nterminal = \"terminal\"\n")
        let problem = result.diagnostics.first { $0.path == "copy_path.styles" }
        #expect(problem != nil)
        #expect(problem?.file == nil)
        #expect(problem?.summary(file: URL(fileURLWithPath: "/x/config.toml")).hasPrefix("error: config.toml [copy_path.styles]") == true)
    }

    @Test func entryPositionsAreThoseOfTheirOwnFile() {
        // Merged list: alpha (base 1), beta (base 2) replaced by an invalid overlay entry, then gamma (overlay 2, invalid too).
        let base = baseConfig + "\n[[app]]\nid = \"delta\"\nname = \"Delta\"\n"
        let overlay = "[[app]]\nid = \"beta\"\nname = \"Beta\"\n[[app]]\nid = \"gamma\"\nname = \"Gamma\"\nbundle_id = \"a.g\"\nrole = \"nonsense\"\n"
        let result = layered(base, overlay)
        let missing = result.diagnostics.filter { $0.message.contains("bundle_id") }
        #expect(missing.count == 2)
        #expect(missing.contains { $0.path == "app.1" && $0.file == "config.local.toml" })
        #expect(missing.contains { $0.path == "app.3" && $0.file == nil })
        let role = result.diagnostics.first { $0.message.contains("nonsense") }
        #expect(role?.path == "app.2.role")
        #expect(role?.file == "config.local.toml")
    }

    @Test func anOverlaySyntaxErrorIsLeftOutAndNamed() {
        let result = layered(baseConfig, "[general\nterminal = \"terminal\"\n")
        let error = result.diagnostics.first { $0.severity == .error }
        #expect(error?.file == "config.local.toml")
        #expect(error?.line == 1)
        #expect(result.config.terminal == "ghostty")
    }

    @Test func aBrokenBaseDoesNotStopTheOverlay() {
        let result = layered("[general\n", "[general]\nterminal = \"terminal\"\n")
        #expect(result.hasErrors)
        #expect(result.diagnostics.first?.file == nil)
        #expect(result.config.terminal == "terminal")
    }

    @Test func nestingIsGuardedInTheOverlayToo() {
        let deep = "a = " + String(repeating: "[", count: 200) + String(repeating: "]", count: 200) + "\n"
        let result = layered(baseConfig, deep)
        #expect(result.diagnostics.contains { $0.file == "config.local.toml" && $0.message.contains("nested") })
        #expect(result.config.terminal == "ghostty")
    }

    @Test func anUnreadableFileIsReportedWithItsName() {
        let reason = ConfigDiagnostic(severity: .error, path: "", message: "The file is 2048 KB; a config is a few kilobytes, so it was not read.")
        let result = ConfigLayers.load(base: .text(baseConfig), local: .unreadable(reason))
        #expect(result.diagnostics.contains { $0.file == "config.local.toml" && $0.message.contains("a few kilobytes") })
        #expect(result.config.terminal == "ghostty")
    }
}
