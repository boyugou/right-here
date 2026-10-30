import Foundation
import Testing
@testable import RightHereCore

@Suite("ConfigTrust: what an agent may change by itself")
struct ConfigTrustTests {
    @Test func everySettingOfTheSchemaIsDecidedOnce() {
        let program = Set(ConfigTrust.programKeys.keys)
        let leaves = ConfigSchema.leaves.map(\.key)
        #expect(Set(leaves).count == leaves.count, "a setting is listed twice")
        #expect(program.isDisjoint(with: ConfigTrust.plainKeys), "decided both ways: \(program.intersection(ConfigTrust.plainKeys).sorted())")
        let undecided = leaves.filter { !program.contains($0) && !ConfigTrust.plainKeys.contains($0) }
        #expect(undecided.isEmpty, "a setting of the schema that ConfigTrust has not looked at: \(undecided). Decide whether an agent may change it by itself.")
        let stale = program.union(ConfigTrust.plainKeys).subtracting(leaves)
        #expect(stale.isEmpty, "named in ConfigTrust but not in the schema: \(stale.sorted())")
    }

    @Test func theSettingsThatWaitForThePersonAreThoseOfTheDecision() {
        // ADR 0026, D5: what decides which program starts or switches an agent's prompts off.
        #expect(Set(ConfigTrust.programKeys.keys) == [
            "app.*.bundle_id", "app.*.bundle_ids", "app.*.role", "app.*.open_args", "app.*.run_args",
            "agent.*.command", "agent.*.args", "agent.*.prompt_arg", "agent.*.bypass_permission_arg", "agent.*.variant.*.arguments",
            "agent.*.bypass_permissions", "general.bypass_permissions", "new_file.template.*.contents"
        ])
        for (key, reason) in ConfigTrust.programKeys { #expect(!reason.isEmpty && !reason.hasSuffix("."), "\(key)") }
    }

    private func approvals(_ operation: ConfigOperation) -> [String] {
        ConfigTrust.approvals(for: [operation]).map(\.key)
    }

    @Test func writingAProgramIsProposedAndNamedWithItsReason() {
        #expect(approvals(.set("agent.claude.command", .string("/tmp/evil"))) == ["agent.*.command"])
        #expect(ConfigTrust.approvals(for: [.set("agent.claude.command", .string("x"))]) == [.init(key: "agent.*.command", reason: "it is the program that starts the agent")])
        #expect(approvals(.set("agent.claude.args", .strings(["-p"]))) == ["agent.*.args"])
        #expect(approvals(.insert("--yolo", into: "agent.claude.args", at: nil)) == ["agent.*.args"])
        #expect(approvals(.set("app.2.bundle_id", .string("com.example.x"))) == ["app.*.bundle_id"])
        #expect(approvals(.set("app.2.open_args", .strings(["/bin/sh"]))) == ["app.*.open_args"])
        #expect(approvals(.set("agent.claude.variant.1.arguments", .strings(["x"]))) == ["agent.*.variant.*.arguments"])
        #expect(approvals(.set("agent.claude.prompt_arg", .string("--prompt"))) == ["agent.*.prompt_arg"])
    }

    @Test func switchingPromptsOffIsProposedAndSwitchingThemOnIsNot() {
        #expect(approvals(.set("general.bypass_permissions", .boolean(true))) == ["general.bypass_permissions"])
        #expect(approvals(.set("agent.claude.bypass_permissions", .boolean(true))) == ["agent.*.bypass_permissions"])
        #expect(approvals(.set("general.bypass_permissions", .boolean(false))).isEmpty)
        #expect(approvals(.set("agent.claude.bypass_permissions", .boolean(false))).isEmpty)
    }

    @Test func anEntryIsProposedForTheFieldsThatDefineAProgramOnly() {
        let app = [ConfigField("id", .string("tower")), ConfigField("name", .string("Tower")), ConfigField("bundle_id", .string("com.fournova.Tower3")), ConfigField("role", .string("terminal"))]
        #expect(ConfigTrust.approvals(for: [.addEntry(to: "app", fields: app, at: nil)]).map(\.key) == ["app.*.bundle_id", "app.*.role"])
        let preset = [ConfigField("id", .string("review")), ConfigField("title", .string("Review")), ConfigField("prompt", .string("Review {files}")), ConfigField("agent", .string("claude"))]
        #expect(approvals(.addEntry(to: "preset", fields: preset, at: nil)).isEmpty, "a prompt is text for an agent that asks before it acts")
        let variant = [ConfigField("id", .string("fast")), ConfigField("arguments", .strings(["--fast"]))]
        #expect(approvals(.addEntry(to: "agent.claude.variant", fields: variant, at: nil)) == ["agent.*.variant.*.arguments"])
    }

    @Test func takingOutOrMovingWhatDecidesAProgramIsProposedToo() {
        // Taking something out is not always taking power away: a per-agent `bypass_permissions = false` is what keeps one agent asking when the general switch is on, and an
        // argument may be the one that keeps an agent in its sandbox.
        #expect(approvals(.unset("agent.claude.bypass_permissions")) == ["agent.*.bypass_permissions"])
        #expect(approvals(.unset("agent.claude.command")) == ["agent.*.command"])
        #expect(approvals(.unset("agent.claude.args")) == ["agent.*.args"])
        #expect(approvals(.unset("agent.claude.bypass_permission_arg")) == ["agent.*.bypass_permission_arg"])
        #expect(approvals(.remove(at: 1, from: "agent.claude.args")) == ["agent.*.args"])
        #expect(approvals(.move(from: 1, to: 2, in: "agent.claude.args")) == ["agent.*.args"])
        #expect(approvals(.unset("app.2.open_args")) == ["app.*.open_args"])
    }

    @Test func takingBackAnAgentsFreedomOrChoosingAmongWhatThePersonHasIsNotProposed() {
        #expect(approvals(.unset("general.bypass_permissions")).isEmpty, "the general switch off again can only make agents ask")
        #expect(approvals(.removeEntry(at: 1, from: "app")).isEmpty)
        #expect(approvals(.moveEntry(from: 1, to: 2, in: "app")).isEmpty)
        #expect(approvals(.set("agent.claude.args", .strings([]))).isEmpty, "a list with nothing in it starts nothing")
        #expect(approvals(.unset("general.editor")).isEmpty && approvals(.unset("agent.claude.name")).isEmpty && approvals(.unset("preset.1.prompt")).isEmpty)
        for operation: ConfigOperation in [
            .set("general.terminal", .string("iterm")), .set("general.agents", .strings(["claude"])), .insert("agents", into: "menu.items", at: 1),
            .set("preset.1.prompt", .string("anything")), .set("copy_path.title", .string("x")), .set("agent.claude.terminal", .string("iterm")),
            .set("new_file.template.1.extension", .string("txt")), .set("new_file.template.1.base_name", .string("notes")), .set("new_file.template.1.open_with", .string("zed"))
        ] {
            #expect(approvals(operation).isEmpty, "\(operation.summary)")
        }
    }

    @Test func whatANewFileHoldsIsProposedBecauseTheToolThatMakesTheFileTakesTheFolderFromWhoeverAsks() {
        // An assistant that can only call tools could otherwise write a login item into the folder that starts programs: a template's contents, and `right_here_run new-file.<id>` with that folder.
        #expect(approvals(.set("new_file.template.1.contents", .string("#!/bin/sh\n"))) == ["new_file.template.*.contents"])
        #expect(ConfigTrust.approvals(for: [.set("new_file.template.1.contents", .string("x"))]).first?.reason == "it becomes a file that something on this Mac may run (a script, a login item)")
        let fields = [ConfigField("id", .string("py")), ConfigField("title", .string("Python")), ConfigField("extension", .string("py"))]
        #expect(approvals(.addEntry(to: "new_file.template", fields: fields, at: nil)).isEmpty)
        #expect(approvals(.addEntry(to: "new_file.template", fields: fields + [ConfigField("contents", .string("print(1)\n"))], at: nil)) == ["new_file.template.*.contents"])
        #expect(approvals(.addEntry(to: "new_file.template", fields: fields + [ConfigField("contents", .string(""))], at: nil)).isEmpty, "an empty file starts nothing")
        #expect(approvals(.set("new_file.template.1.contents", .string(""))).isEmpty && approvals(.unset("new_file.template.1.contents")).isEmpty)
    }

    @Test func whatANewFileHoldsIsProposedWhicheverWayTheChangeIsSpelled() {
        let before = ConfigParser.parse("[[new_file.template]]\nid = \"py\"\ntitle = \"Python\"\nextension = \"py\"\ncontents = \"print(1)\\n\"\n").config
        func keys(_ text: String) -> [String] { ConfigTrust.approvals(changingFrom: before, to: ConfigParser.parse(text).config).map(\.key) }
        let head = "[[new_file.template]]\nid = \"py\"\ntitle = \"Python\"\nextension = \"py\"\n"
        #expect(keys(head + "contents = \"print(1)\\n\"\n").isEmpty, "the same contents asks for nothing")
        #expect(keys(head + "contents = \"print(2)\\n\"\n") == ["new_file.template.*.contents"])
        #expect(keys(head + "[[new_file.template]]\nid = \"plist\"\ntitle = \"P\"\nextension = \"plist\"\ncontents = \"<plist/>\"\n") == ["new_file.template.*.contents"], "a template that is new")
        #expect(keys(head).isEmpty, "contents taken out leaves an empty file")
        #expect(ConfigTrust.approvals(changingFrom: ConfigParser.parse("").config, to: ConfigParser.parse("").config).isEmpty, "the built-in templates are what they were")
    }

    // MARK: What a change does to the apps and to the terminals that a click starts through a template

    private func merged(_ shared: String, _ local: String? = nil) -> Config {
        ConfigLayers.load(base: .text(shared), local: local.map(ConfigSource.text) ?? .absent).config
    }

    private let sharedTerminal = "[general]\nterminal = \"myterm\"\n[[app]]\nid = \"myterm\"\nname = \"MyTerm\"\nbundle_id = \"com.apple.Terminal\"\nrole = \"terminal\"\nopen_args = [\"/usr/bin/open\", \"-a\", \"Terminal\", \"{dir}\"]\nrun_args = [\"/bin/sh\", \"-c\", \"echo shared: {command}\", \"{dir}\"]\n"
    private let localTerminal = "[[app]]\nid = \"myterm\"\nname = \"MyTerm\"\nbundle_id = \"com.apple.Terminal\"\nrole = \"terminal\"\nopen_args = [\"/usr/bin/open\", \"-a\", \"Terminal\", \"{dir}\"]\nrun_args = [\"/usr/bin/env\", \"{command}\", \"{dir}\"]\n"

    @Test func takingOutThisMacsOwnAppThatReplacesTheSharedOneWaitsBecauseTheSharedProgramComesBack() {
        let before = merged(sharedTerminal, localTerminal)
        let after = merged(sharedTerminal)
        // The program of the app, and the choice of it as the default terminal, which is now another program under the same choice.
        #expect(Set(ConfigTrust.approvals(changingFrom: before, to: after).map(\.key)) == ["app.*.run_args", "terminal.*.template"])
        #expect(ConfigTrust.approvals(changingFrom: before, to: before).isEmpty && ConfigTrust.approvals(changingFrom: after, to: after).isEmpty)
        // The same for the role (this Mac's own "this is a terminal" is what keeps files from being handed to it) and for the identifiers that decide which app is opened.
        let editor = "[[app]]\nid = \"rio\"\nname = \"Rio\"\nbundle_id = \"com.apple.TextEdit\"\nrole = \"editor\"\n"
        let terminal = editor.replacingOccurrences(of: "\"editor\"", with: "\"terminal\"")
        #expect(ConfigTrust.approvals(changingFrom: merged(editor, terminal), to: merged(editor)).map(\.key) == ["app.*.role"])
        #expect(ConfigTrust.approvals(changingFrom: merged(editor, editor.replacingOccurrences(of: "TextEdit", with: "Notes")), to: merged(editor)).map(\.key) == ["app.*.bundle_ids"])
    }

    @Test func anAppWhoseTemplateOpensAFolderOtherwiseThanBeforeOrThatIsNewWithATemplateWaits() {
        let app = "[[app]]\nid = \"myterm\"\nname = \"MyTerm\"\nbundle_id = \"com.example.myterm\"\nrole = \"terminal\"\nopen_args = [\"/usr/bin/open\", \"-a\", \"MyTerm\", \"{dir}\"]\n"
        let other = app.replacingOccurrences(of: "\"-a\", \"MyTerm\"", with: "\"-b\", \"com.example.other\"")
        #expect(ConfigTrust.approvals(changingFrom: merged(app), to: merged(other)).map(\.key) == ["app.*.open_args"], "only the program that opens a folder changed")
        // An app that is new through a route that writes no program key (the other file's `disabled` no longer hides it) and starts through a template.
        #expect(ConfigTrust.approvals(changingFrom: merged(""), to: merged(app)).map(\.key) == ["app.*.run_args"])
        let plain = "[[app]]\nid = \"notes\"\nname = \"Notes\"\nbundle_id = \"com.example.notes\"\nrole = \"editor\"\n"
        #expect(ConfigTrust.approvals(changingFrom: merged(""), to: merged(plain)).isEmpty, "an app with no template of its own starts nothing of its own")
    }

    @Test func aTerminalThatStartsThroughATemplateAndIsChosenWhereItWasNotWaitsWhoeverMakesTheChoice() {
        let defined = "[[app]]\nid = \"remote\"\nname = \"Remote Shell\"\nbundle_id = \"com.apple.Terminal\"\nrole = \"terminal\"\nrun_args = [\"/usr/bin/ssh\", \"build-server\", \"cd {dir} && {command}\"]\n"
        let base = merged("[general]\nterminal = \"terminal\"\nagents = [\"claude\"]\n" + defined)
        func keys(_ text: String) -> [String] { ConfigTrust.approvals(changingFrom: base, to: merged("[general]\nagents = [\"claude\"]\n" + defined + text)).map(\.key) }
        #expect(ConfigTrust.approvals(changingFrom: base, to: merged("[general]\nterminal = \"remote\"\nagents = [\"claude\"]\n" + defined)).map(\.key) == ["terminal.*.template"], "the default terminal")
        #expect(keys("[agent.claude]\nterminal = \"remote\"\n") == ["terminal.*.template"], "an agent's own terminal")
        #expect(keys("[menu]\nitems = [\"open.terminal@remote\"]\n") == ["terminal.*.template"], "an item of the menu")
        #expect(keys("[services]\nitems = [\"agent.claude@remote\"]\n") == ["terminal.*.template"], "an item of the Quick Actions")
        #expect(keys("[menu]\nitems = [\"open.terminal@ghostty\"]\n").isEmpty, "a terminal that comes with Right Here starts no program of the person's")
        // Chosen already, and still: nothing changed.
        let chosen = merged("[general]\nterminal = \"remote\"\nagents = [\"claude\"]\n" + defined)
        #expect(ConfigTrust.approvals(changingFrom: chosen, to: chosen).isEmpty)
        // An app that takes the id of the terminal that is chosen is another program under the same choice.
        let replaced = merged("[general]\nterminal = \"terminal\"\nagents = [\"claude\"]\n" + defined.replacingOccurrences(of: "id = \"remote\"", with: "id = \"terminal\""))
        #expect(ConfigTrust.approvals(changingFrom: base, to: replaced).map(\.key).contains("terminal.*.template"), "the id decides what the choice means")
    }

    @Test func severalOperationsAreOneListWithEachSettingOnce() {
        let operations: [ConfigOperation] = [
            .set("agent.claude.args", .strings(["a"])), .insert("b", into: "agent.claude.args", at: nil), .set("agent.codex.args", .strings(["c"])),
            .set("general.terminal", .string("iterm"))
        ]
        #expect(ConfigTrust.approvals(for: operations).map(\.key) == ["agent.*.args"])
    }

    @Test func aRewriteOfTheWholeFileIsNeverAnAssistantsToMake() {
        #expect(ConfigTrust.approvals(for: [.replaceText("[general]\nterminal = \"ghostty\"\n")]).map(\.key) == ["*"])
        #expect(ConfigTrust.approvals(for: [.replaceText("a"), .replaceText("b")]).count == 1)
        #expect(ConfigTrust.approvals(for: [.replaceText("a")]).first?.reason == "it rewrites the whole file, and a program may be among what it says")
    }

    @Test func aPathThatIsNoSettingProposesNothingAndTheEditRefusesIt() {
        #expect(approvals(.set("agent.claude.nope", .string("x"))).isEmpty)
        #expect(approvals(.set("preset.first.prompt", .string("x"))).isEmpty)
        #expect(approvals(.set("", .string("x"))).isEmpty)
    }

    @Test func settingsAreSpelledGenerally() {
        #expect(ConfigSchema.genericKey(of: "general.terminal") == "general.terminal")
        #expect(ConfigSchema.genericKey(of: "preset.2.prompt") == "preset.*.prompt")
        #expect(ConfigSchema.genericKey(of: "preset.2") == "preset.*")
        #expect(ConfigSchema.genericKey(of: "agent.claude.args") == "agent.*.args")
        #expect(ConfigSchema.genericKey(of: "agent.claude") == "agent.*")
        #expect(ConfigSchema.genericKey(of: "agent.claude.variant.3.arguments") == "agent.*.variant.*.arguments")
        #expect(ConfigSchema.genericKey(of: "new_file.template.1.contents") == "new_file.template.*.contents")
        #expect(ConfigSchema.genericKey(of: "preset.first.prompt") == nil)
        #expect(ConfigSchema.genericKey(of: "preset.prompt") == nil)
        #expect(ConfigSchema.genericKey(of: "general.nope") == nil)
        #expect(ConfigSchema.genericKey(of: "a..b") == nil)
    }

    /// A name for each kind of operation. The switch has no default, so a kind that is added does not compile until it is named here, which is where this test asks for an example of it.
    private func kind(_ operation: ConfigOperation) -> String {
        switch operation {
        case .set: "set"
        case .unset: "unset"
        case .insert: "insert"
        case .remove: "remove"
        case .replace: "replace"
        case .move: "move"
        case .expect: "expect"
        case .expectEntry: "expectEntry"
        case .addEntry: "addEntry"
        case .addTable: "addTable"
        case .removeTable: "removeTable"
        case .removeEntry: "removeEntry"
        case .moveEntry: "moveEntry"
        case .replaceText: "replaceText"
        }
    }

    @Test func everyOperationSurvivesBeingStoredAndRead() throws {
        // A proposal is stored as JSON in a folder that anything that runs as the person can write to, and read back to be shown and applied.
        let operations: [ConfigOperation] = [
            .set("general.terminal", .string("iterm")), .set("general.bypass_permissions", .boolean(true)), .set("preset.1.max_files", .integer(3)),
            .set("general.agents", .strings(["claude", "codex"])), .unset("general.editor"), .insert("open-with", into: "menu.items", at: 2),
            .insert("open-with", into: "menu.items", at: nil), .remove(at: 1, from: "menu.items"), .move(from: 3, to: 1, in: "menu.items"),
            .replace(at: 2, in: "agent.claude.args", with: "--verbose"), .expect(["a", "b"], in: "menu.items"), .expect(nil, in: "services.items"), .expectEntry("review", at: 1, in: "preset"),
            .addEntry(to: "preset", fields: [ConfigField("id", .string("a")), ConfigField("max_files", .integer(2))], at: 2), .removeEntry(at: 1, from: "preset"),
            .addTable("agent.lazygit", fields: [ConfigField("name", .string("lazygit")), ConfigField("command", .string("lazygit")), ConfigField("args", .strings(["-p"]))]),
            .removeTable("agent.lazygit"), .moveEntry(from: 2, to: 1, in: "preset"), .replaceText("[general]\n")
        ]
        #expect(Set(operations.map(kind)).count == 14, "one example of each kind: \(Set(operations.map(kind)).sorted())")
        let data = try JSONEncoder().encode(operations)
        #expect(try JSONDecoder().decode([ConfigOperation].self, from: data) == operations)
    }

    @Test func anEmptyTextWaitsForThePersonForEverySettingThatDecidesAProgramExceptWhatANewFileHolds() {
        // `bypass_permission_arg = ""` takes away the flag that the guard of a preset knows: an empty text is not "nothing that can start anything" for a setting of this list.
        var checked = 0
        for leaf in ConfigSchema.leaves where leaf.node.kind == .string && ConfigTrust.programKeys[leaf.key] != nil {
            var segments = leaf.key.split(separator: ".").map(String.init)
            for index in segments.indices where segments[index] == "*" { segments[index] = segments[index - 1] == "agent" ? "claude" : "1" }
            let path = segments.joined(separator: ".")
            let waits = ConfigTrust.approvals(for: [.set(path, .string(""))]).map(\.key)
            #expect(waits == (leaf.key == "new_file.template.*.contents" ? [] : [leaf.key]), "set \(path) \"\"")
            checked += 1
        }
        #expect(checked >= 6, "the loop looked at the string settings of the list")
        #expect(ConfigTrust.approvals(for: [.addEntry(to: "app", fields: [ConfigField("id", .string("x")), ConfigField("name", .string("X")), ConfigField("bundle_id", .string(""))], at: nil)]).map(\.key) == ["app.*.bundle_id"])
        #expect(ConfigTrust.approvals(for: [.addTable("agent.mine", fields: [ConfigField("name", .string("Mine")), ConfigField("command", .string(""))])]).map(\.key) == ["agent.*.command"])
    }

    @Test func aFlagThatSwitchesThePromptsOffWaitsForThePersonWhereverItIsTyped() {
        let before = ConfigParser.parse("[general]\nagents = [\"claude\"]\n").config
        func keys(_ text: String) -> [String] { ConfigTrust.approvals(changingFrom: before, to: ConfigParser.parse(text).config).map(\.key) }
        let head = "[general]\nagents = [\"claude\"]\n\n[agent.claude]\n"
        #expect(keys(head + "args = [\"--dangerously-skip-permissions\"]\n").contains("agent.*.bypass_permissions"))
        #expect(keys(head + "prompt_arg = \"--dangerously-skip-permissions\"\n").contains("agent.*.bypass_permissions"))
        #expect(keys(head + "command = \"claude --dangerously-skip-permissions\"\n").contains("agent.*.bypass_permissions"))
        #expect(keys(head + "\n[[agent.claude.variant]]\nid = \"yolo\"\ntitle = \"Yolo\"\narguments = [\"--dangerously-skip-permissions\"]\n").contains("agent.*.bypass_permissions"))
        #expect(!keys(head + "args = [\"--verbose\"]\n").contains("agent.*.bypass_permissions"))
        // Already there, it is not a change.
        let typed = ConfigParser.parse(head + "args = [\"--dangerously-skip-permissions\"]\n").config
        #expect(!ConfigTrust.approvals(changingFrom: typed, to: ConfigParser.parse(head + "args = [\"--dangerously-skip-permissions\", \"--verbose\"]\n").config).map(\.key).contains("agent.*.bypass_permissions"))
    }

    @Test func aFlagThatIsTypedForAnAgentThatIsNotInTheMenuYetWaitsAsWell() {
        // Not offered by anything now, so no click starts it; but the next change that puts it in the menu would only look like a menu change, so the flag is the person's to decide when it is typed.
        let before = ConfigParser.parse("[general]\nagents = [\"claude\"]\n").config
        let after = ConfigParser.parse("[general]\nagents = [\"claude\"]\n\n[agent.codex]\nargs = [\"--dangerously-bypass-approvals-and-sandbox\"]\n").config
        #expect(PromptEffects.withoutAsking(after).isEmpty, "no click starts it yet")
        #expect(ConfigTrust.approvals(changingFrom: before, to: after).map(\.key).contains("agent.*.bypass_permissions"))
        #expect(!ConfigTrust.approvals(changingFrom: after, to: after).map(\.key).contains("agent.*.bypass_permissions"), "the same flag is not a change")
    }
}
