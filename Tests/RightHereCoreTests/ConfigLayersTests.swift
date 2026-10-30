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

    @Test func duplicateIDsInTheOverlayAreTreatedTheSameWithOrWithoutASharedList() {
        let overlay = """
        [[app]]
        id = "foo"
        name = "First"
        bundle_id = "a.first"
        [[app]]
        id = "foo"
        name = "Second"
        bundle_id = "a.second"
        """
        let shared = "[[app]]\nid = \"bar\"\nname = \"Bar\"\nbundle_id = \"a.bar\"\n"
        let withoutAList = layered("version = 1\n", overlay)
        let withAList = layered(shared, overlay)
        // The first definition is used and the second is reported, in both cases, at its place in the overlay.
        #expect(withoutAList.config.apps.map(\.name) == ["First"])
        #expect(withAList.config.apps.map(\.name) == ["Bar", "First"])
        for result in [withoutAList, withAList] {
            let duplicates = result.diagnostics.filter { $0.message.contains("duplicate app id") }
            #expect(duplicates.count == 1, "\(result.diagnostics.map(\.message))")
            #expect(duplicates.first?.path == "app.2.id" && duplicates.first?.file == "config.local.toml", "\(duplicates)")
        }
    }

    @Test func aSharedEntryIsReplacedOnceAndALaterDuplicateInTheOverlayIsAppended() {
        let shared = "[[new_file.template]]\nid = \"note\"\ntitle = \"Shared\"\nextension = \"txt\"\n"
        let overlay = "[[new_file.template]]\nid = \"note\"\ntitle = \"One\"\nextension = \"txt\"\n[[new_file.template]]\nid = \"note\"\ntitle = \"Two\"\nextension = \"md\"\n"
        let result = layered(shared, overlay)
        #expect(result.config.newFile.templates.map(\.title) == ["One"], "the first of the overlay's duplicates wins, as when nothing is shared")
        let duplicate = result.diagnostics.first { $0.message.contains("duplicate template id") }
        #expect(duplicate?.path == "new_file.template.2.id" && duplicate?.file == "config.local.toml", "\(result.diagnostics)")
    }

    @Test func presetsMergeByIDAndAnOverlayPresetDoesNotWipeTheSharedOnes() {
        let base = """
        [general]
        agents = ["claude"]
        [[preset]]
        id = "alpha"
        title = "Alpha"
        prompt = "Alpha {files}"
        [[preset]]
        id = "beta"
        title = "Beta"
        prompt = "Beta {files}"
        """
        let overlay = """
        [[preset]]
        id = "gamma"
        title = "Gamma"
        prompt = "Gamma {files}"
        [[preset]]
        id = "beta"
        title = "Beta Two"
        prompt = "Beta two {files}"
        """
        let result = layered(base, overlay)
        #expect(!result.hasErrors)
        #expect(result.config.presets.map(\.id) == ["review", "explain", "tests", "alpha", "beta", "gamma"])
        #expect(result.config.preset(id: "beta")?.title == "Beta Two")
        #expect(result.config.preset(id: "alpha")?.title == "Alpha")
        // A problem in an overlay preset is reported at its place in the overlay, not in the merged list.
        let broken = layered(base, "[[preset]]\nid = \"gamma\"\ntitle = \"G\"\nprompt = \"{nope}\"\n")
        let problem = broken.diagnostics.first { $0.severity == .error }
        #expect(problem?.file == "config.local.toml" && problem?.path.hasPrefix("preset.1.") == true, "\(broken.diagnostics)")
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

@Suite("ConfigLayers: the overlay's name")
struct ConfigLayersOverlayNameTests {
    @Test("a config file's overlay", arguments: [
        ("config.toml", "config.local.toml"), ("foo.toml", "foo.local.toml"), ("rh.conf", "rh.local.conf"), ("noextension", "noextension.local.toml"),
        ("my.config.toml", "my.config.local.toml")
    ])
    func overlayName(config: String, overlay: String) {
        #expect(ConfigLayers.overlayName(forConfigFile: config) == overlay)
    }

    @Test func theDefaultOverlayIsTheOneOfTheDefaultConfigFile() {
        #expect(ConfigLayers.overlayFileName == "config.local.toml")
        #expect(ConfigLayers.overlayFileName == ConfigLayers.overlayName(forConfigFile: "config.toml"))
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

    @Test func whatNamesADisabledAppFallsBackInsteadOfBecomingAnError() {
        let base = """
        [[app]]
        id = "warpish"
        name = "W"
        bundle_id = "a.w"
        role = "terminal"
        [[app]]
        id = "tower"
        name = "T"
        bundle_id = "a.t"
        [[new_file.template]]
        id = "py"
        title = "Py"
        extension = "py"
        open_with = "tower"
        [agent.claude]
        terminal = "warpish"
        """
        let result = layered(base, "disabled = [\"warpish\", \"tower\"]\n")
        #expect(!result.hasErrors, "\(result.diagnostics.map(\.message))")
        #expect(result.config.apps.isEmpty)
        #expect(result.config.newFile.templates.first { $0.id == "py" }?.openWith == nil)
        #expect(result.config.agents["claude"]?.launcher == nil)
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

    private static let presetOfADisabledAgent = """
    [general]
    agents = ["claude", "myagent"]
    [agent.myagent]
    name = "My Agent"
    command = "myagent"
    prompt_arg = "positional"
    [[preset]]
    id = "mine"
    title = "Mine"
    agent = "myagent"
    prompt = "Look at {files}"
    """

    @Test func aPresetWhoseAgentIsDisabledIsDroppedWithANoteNotAWarning() {
        let result = layered(Self.presetOfADisabledAgent, "disabled = [\"myagent\"]\n")
        #expect(!result.hasErrors, "\(result.diagnostics.map { "\($0.severity) \($0.path): \($0.message)" })")
        #expect(!result.config.presets.contains { $0.id == "mine" })
        // Expected, and nothing can silence it (naming the preset in `disabled` changes nothing), so it must not be a warning:
        // it would fail `validate --strict` for ever and be printed by every `rh menu`.
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics)")
        let note = result.notes.first { $0.message.contains("\"mine\"") }
        #expect(result.notes.count == 1 && note?.severity == .note)
        #expect(note?.file == "config.local.toml", "the overlay's `disabled` is what the person would edit")
        #expect(note?.line == 1 && note?.path == "disabled")
        #expect(note?.message.contains("\"myagent\"") == true)
        #expect(note?.summary(file: URL(fileURLWithPath: "/x/config.toml")).hasPrefix("note: config.local.toml:1 [disabled]: the preset \"mine\" is not offered on this machine") == true)
        // Without the overlay the preset is there and nothing is dropped.
        #expect(layered(Self.presetOfADisabledAgent, nil).config.presets.contains { $0.id == "mine" })
        #expect(layered(Self.presetOfADisabledAgent, nil).notes.isEmpty)
    }

    @Test func aBuiltInAgentThatIsDisabledDropsItsPresetsToo() {
        let base = "[general]\nagents = [\"claude\", \"codex\"]\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nagent = \"codex\"\nprompt = \"Look at {files}\"\n"
        let result = layered(base, "disabled = [\"codex\"]\n")
        #expect(!result.hasErrors)
        #expect(!result.config.presets.contains { $0.id == "mine" })
        #expect(result.config.enabledAgents == ["claude"])
    }

    @Test func menuAndServiceEntriesOfADroppedPresetGoWithIt() {
        let base = Self.presetOfADisabledAgent + "\n[menu]\nitems = [\"preset.mine\", \"open-terminal\", \"preset.review\"]\n[services]\nitems = [\"preset.mine@ghostty\", \"open.terminal\"]\n"
        let result = layered(base, "disabled = [\"myagent\"]\n")
        #expect(result.config.menuItems == ["open-terminal", "preset.review"])
        #expect(result.config.serviceItems == ["open.terminal"])
        #expect(!result.hasErrors)
        #expect(!result.diagnostics.contains { $0.message.contains("not defined") }, "\(result.diagnostics.map(\.message))")
    }

    @Test func droppingAPresetThatReplacedABuiltInOneBringsTheBuiltInBack() {
        let base = "[general]\nagents = [\"claude\", \"myagent\"]\n[agent.myagent]\nname = \"M\"\ncommand = \"m\"\nprompt_arg = \"positional\"\n"
            + "[[preset]]\nid = \"review\"\ntitle = \"Review\"\nagent = \"myagent\"\nprompt = \"Look at {files}\"\n[menu]\nitems = [\"preset.review\"]\n"
        let result = layered(base, "disabled = [\"myagent\"]\n")
        #expect(!result.hasErrors)
        #expect(result.config.preset(id: "review")?.agent == nil, "the built-in review preset is back")
        #expect(result.config.preset(id: "review")?.prompt == AgentPreset.builtIn.first { $0.id == "review" }?.prompt)
        #expect(result.config.menuItems == ["preset.review"], "the entry names a preset that exists")
    }

    @Test func aDisabledTerminalIsRemovedFromPresetEntriesToo() {
        let base = """
        [menu]
        items = ["open.terminal@ghostty", "agent.claude@ghostty", "preset.review@ghostty"]
        [services]
        items = ["open.terminal@ghostty", "preset.review@ghostty"]
        """
        let result = layered(base, "disabled = [\"ghostty\"]\n")
        #expect(result.config.menuItems == [])
        #expect(result.config.serviceItems == [])
    }

    @Test func aBuiltInAppIsReallyRemoved() throws {
        let facts = FakeSystemFacts(
            directories: ["/Users/tester/code"],
            applications: ["com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"), "com.apple.Terminal": URL(fileURLWithPath: "/Applications/Terminal.app"),
                           "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/VSCode.app")])
        let context = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/code"))
        let before = layered("[general]\nagents = [\"claude\"]\n", nil)
        #expect(try Planner(config: before.config, facts: facts).plan(.openTerminal(nil), context: context).steps == [.open(OpenStep(bundleID: "com.mitchellh.ghostty", targets: ["/Users/tester/code"]))])

        let after = layered("[general]\nagents = [\"claude\"]\n", "disabled = [\"ghostty\", \"vscode\"]\n")
        #expect(!after.hasErrors)
        #expect(after.config.app(id: "ghostty") == nil && after.config.app(id: "vscode") == nil)
        #expect(after.config.allApps.contains { $0.id == "terminal" } && !after.config.allApps.contains { ["ghostty", "vscode"].contains($0.id) })
        // The default terminal is the next installed one, and Ghostty cannot be named any more, though it is installed.
        #expect(try Planner(config: after.config, facts: facts).plan(.openTerminal(nil), context: context).steps == [.open(OpenStep(bundleID: "com.apple.Terminal", targets: ["/Users/tester/code"]))])
        #expect(throws: PlanError.unknownTerminal("ghostty")) { try Planner(config: after.config, facts: facts).plan(.openTerminal("ghostty"), context: context) }
        let registry = ActionRegistry(config: after.config, facts: facts)
        #expect(!registry.catalog().contains { $0.id == "open.terminal@ghostty" || $0.id == "open.app.vscode" })
        #expect(ActionRegistry(config: before.config, facts: facts).catalog().contains { $0.id == "open.terminal@ghostty" })
    }

    @Test func anAppTheConfigDefinesUnderABuiltInIdIsRemovedToo() {
        let base = "[[app]]\nid = \"ghostty\"\nname = \"Mine\"\nbundle_id = \"a.mine\"\nrole = \"terminal\"\n"
        let result = layered(base, "disabled = [\"ghostty\"]\n")
        #expect(result.config.app(id: "ghostty") == nil)
        #expect(result.config.apps.isEmpty)
        #expect(!result.hasErrors)
    }
}

@Suite("ConfigLayers: diagnostics")
struct ConfigLayersDiagnosticTests {
    @Test func aProblemInTheOverlayNamesTheOverlay() {
        let result = layered(baseConfig, "[general]\ntermnial = \"x\"\n")
        let unknown = result.diagnostics.first { $0.message == "unknown key" }
        #expect(unknown?.file == "config.local.toml")
        // The line is the one in config.local.toml, where the key is.
        #expect(unknown?.line == 2)
        #expect(unknown?.summary(file: URL(fileURLWithPath: "/x/config.toml")).hasPrefix("warning: config.local.toml:2 [general.termnial]") == true)
    }

    @Test func aProblemInTheBaseKeepsTheBaseName() {
        let result = layered(baseConfig + "\n[copy_path]\nstyles = [\"absolut\"]\n", "[general]\nterminal = \"terminal\"\n")
        let problem = result.diagnostics.first { $0.path == "copy_path.styles" }
        #expect(problem != nil)
        #expect(problem?.file == nil)
        // baseConfig is 39 lines, then `[copy_path]` is line 40 and the key line 41: the shared file's line, not the merged text's.
        #expect(problem?.line == 41)
        #expect(problem?.summary(file: URL(fileURLWithPath: "/x/config.toml")).hasPrefix("error: config.toml:41 [copy_path.styles]") == true)
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

@Suite("ConfigLayers: validating the shared file on its own")
struct ConfigLayersValidateTests {
    private let shared = "[general]\nagents = [\"claude\"]\n[copy_path]\nstyles = [\"absolute\", \"relative\"]\n"
    private let overlay = "[copy_path]\nstyles = [\"tilde\"]\n"

    @Test func anErrorTheOverlayHidesIsReportedForTheSharedFile() throws {
        // As it applies on this Mac there is nothing wrong, and that is what the menu and `rh run` load.
        let applied = ConfigLayers.load(base: .text(shared), local: .text(overlay))
        #expect(applied.diagnostics.isEmpty && applied.config.copyPathStyles == [.tilde])
        // Other Macs read config.toml alone, which is what `validate` shows too.
        let result = ConfigLayers.validate(base: .text(shared), local: .text(overlay))
        let error = try #require(result.diagnostics.first)
        #expect(result.diagnostics.count == 1 && result.hasErrors)
        #expect(error.severity == .error && error.file == nil && error.path == "copy_path.styles" && error.line == 4, "\(error)")
        #expect(error.message.hasPrefix("unknown style \"relative\"; known styles: absolute, tilde"), "\(error.message)")
        #expect(error.message.hasSuffix("; config.local.toml hides it on this Mac, but other Macs read this file as it is"), "\(error.message)")
        #expect(error.summary(file: URL(fileURLWithPath: "/x/config.toml")).hasPrefix("error: config.toml:4 [copy_path.styles]: unknown style"))
        #expect(result.config == applied.config, "validating changes what applies on this Mac")
    }

    @Test func aProblemThatIsNotHiddenIsReportedOnce() {
        // The overlay does not touch the key, so the merged build and the shared file alone find the same thing.
        let result = ConfigLayers.validate(base: .text(shared), local: .text("[general]\neditor = \"vscode\"\n"))
        #expect(result.diagnostics.filter { $0.path == "copy_path.styles" }.count == 1, "\(result.diagnostics)")
        #expect(!result.diagnostics.contains { $0.message.contains("hides it") })
    }

    @Test func anErrorThatIsStillThereWithTheOverlayIsNotCalledHiddenWhateverItsSentenceListsOfChoices() {
        // The merged build lists the terminals the overlay defines among the known ones, so its sentence differs from the one the
        // shared file alone gives; it is the same error, once, and the overlay hides nothing.
        let shared = "[general]\nterminal = \"nope\"\n"
        let overlay = "[[app]]\nid = \"extra-terminal\"\nname = \"E\"\nbundle_id = \"a.b\"\nrole = \"terminal\"\n"
        let result = ConfigLayers.validate(base: .text(shared), local: .text(overlay))
        let errors = result.diagnostics.filter { $0.path == "general.terminal" }
        #expect(errors.count == 1, "\(errors.map(\.message))")
        #expect(errors.first?.message.contains("extra-terminal") == true && errors.first?.message.contains("hides it") == false, "\(errors.map(\.message))")
    }

    @Test func withoutAnOverlayValidateSaysWhatLoadSays() {
        #expect(ConfigLayers.validate(base: .text(shared), local: .absent) == ConfigLayers.load(base: .text(shared), local: .absent))
        #expect(ConfigLayers.validate(base: .absent, local: .text(overlay)) == ConfigLayers.load(base: .absent, local: .text(overlay)))
    }

    @Test("what `push` would refuse is what `validate` reports", arguments: [
        ("[copy_path]\nstyles = [\"relative\"]\n", "[copy_path]\nstyles = [\"tilde\"]\n"),
        ("[general]\nterminal = \"warp-like\"\n", "[[app]]\nid = \"warp-like\"\nname = \"W\"\nbundle_id = \"a.b\"\nrole = \"terminal\"\n"),
        ("[[app]]\nid = \"x\"\nname = \"X\"\n", "[[app]]\nid = \"x\"\nname = \"X\"\nbundle_id = \"a.b\"\n"),
        ("[[new_file.template]]\nid = \"t\"\ntitle = \"T\"\nextension = \"a/b\"\n", "disabled = [\"t\"]\n"),
        ("[general]\nterminal = ghostty\n", "[general]\nterminal = \"terminal\"\n"),
        ("[agent.q]\ncommand = \"q\"\n", "[agent.q]\nname = \"Q\"\n"),
    ])
    func validateAgreesWithPush(shared: String, overlay: String) throws {
        // `push` parses config.toml alone and refuses on its first error (`SyncValidation.check`).
        let pushed = SyncValidation.check(Data(shared.utf8)).first { if case .invalid = $0 { true } else { false } }
        let refusal = try #require(pushed, "the shared file is fine on its own: \(shared)")
        let result = ConfigLayers.validate(base: .text(shared), local: .text(overlay))
        let errors = result.diagnostics.filter { $0.severity == .error && $0.file == nil }
        for alone in ConfigParser.parse(shared).diagnostics where alone.severity == .error {
            #expect(errors.contains { $0.path == alone.path && $0.message.hasPrefix(alone.message) }, "`validate` does not report \(alone.message)")
        }
        if case .invalid(let reason) = refusal { #expect(reason.contains(errors.first?.message.prefix(30) ?? "\u{0}"), "push says \(reason), validate says \(errors.map(\.message))") }
        #expect(result.hasErrors)
    }

    @Test func aKeyNamedLikeACredentialInTheSharedFileIsAnErrorAsPushRefusesIt() throws {
        let text = "[general]\nagents = [\"mine\"]\n[agent.mine]\nname = \"M\"\ncommand = \"m\"\napi_key = \"x\"\n"
        let result = ConfigLayers.validate(base: .text(text), local: .absent)
        let warning = try #require(result.diagnostics.first { $0.path == "agent.mine.api_key" })
        #expect(warning.severity == .error && warning.line == 6 && result.diagnostics.count == 1, "the unknown-key warning and this one are one: \(result.diagnostics)")
        #expect(result.hasErrors, "validate must fail for what push refuses")
        #expect(warning.message.hasPrefix("unknown key; named like a credential: `rh config sync` refuses a config with such a key name"), "\(warning.message)")
        // `load` does not look: the menu has no use for it.
        #expect(ConfigLayers.load(base: .text(text), local: .absent).diagnostics.first?.message == "unknown key")
        // Under a known key there is no unknown-key warning to fold it into, and it stands alone.
        let standalone = ConfigLayers.validate(base: .text("[agent.claude]\ncommand = \"claude\"\n[agent.claude.secrets]\nx = 1\n"), local: .absent)
        #expect(standalone.diagnostics.contains { $0.path == "agent.claude.secrets" && $0.message.contains("credential") })
        // The overlay is never synced, so a key like that there is nobody's business but the person's.
        let local = ConfigLayers.validate(base: .text("[general]\nterminal = \"terminal\"\n"), local: .text("password = 1\n"))
        #expect(!local.diagnostics.contains { $0.message.contains("credential") }, "\(local.diagnostics)")
        // And what `push` says of the same file names the same key.
        let problems = SyncValidation.check(Data(text.utf8))
        #expect(problems.contains(.secretKeys(["agent.mine.api_key"])))
    }
}
