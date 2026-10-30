import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("ConfigParity: how a person changes each setting in the window")
struct ConfigParityTests {
    @Test func everySettingOfTheSchemaHasAnEntryAndNoEntryIsForASettingThatIsGone() {
        let leaves = Set(ConfigSchema.leaves.map(\.key))
        let missing = leaves.subtracting(ConfigParity.editors.keys).sorted()
        #expect(missing.isEmpty, "a setting of the schema that ConfigParity has not looked at: \(missing). Decide how the window changes it (a control, or text on the Config page for now).")
        let stale = Set(ConfigParity.editors.keys).subtracting(leaves).sorted()
        #expect(stale.isEmpty, "listed in ConfigParity but not in the schema: \(stale)")
    }

    @Test func aControlIsInASectionThatHasItsPlaceAndSaysWhatItIs() {
        for (key, editor) in ConfigParity.editors {
            switch editor {
            case .control(let section, let what):
                #expect(SetupTab.allCases.contains(section) && !what.isEmpty, "\(key)")
            case .text(let why):
                #expect(!why.isEmpty && !why.hasSuffix("."), "\(key)")
            }
        }
    }

    /// The settings of an agent's page (`AgentOptions`) as the keys the changes write, with a change made to each.
    private func agentOptionKeys() throws -> Set<String> {
        let facts = FakeSystemFacts()
        let config = ConfigParser.parse("[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n").config
        let mine = try #require(AgentOptions.state(id: "mine", config: config, facts: facts, listedArgs: nil))
        let claude = try #require(AgentOptions.state(id: "claude", config: ConfigParser.parse("").config, facts: facts, listedArgs: nil))
        let operations = AgentOptions.operations(settingName: "Other", of: mine) + AgentOptions.operations(settingCommand: "other --fast", of: claude)
            + AgentOptions.operations(settingLauncher: .link, of: claude) + AgentOptions.operations(settingTerminal: "terminal", of: claude)
            + AgentOptions.operations(settingBypass: true, of: claude) + AgentOptions.operations(settingBypassArgument: "--yes", of: claude)
            + AgentOptions.operations(addingArgument: "--verbose", to: claude) + AgentOptions.operations(settingPromptArgument: "-i", of: claude)
        return Set(operations.flatMap(\.writtenKeys))
    }

    /// The settings of a start option's page (`AgentVariants`, and the argument list it shares with the agent) as the keys the changes write, with a start option made.
    private func variantOptionKeys() throws -> Set<String> {
        let text = "[[agent.claude.variant]]\nid = \"mine\"\ntitle = \"Mine\"\narguments = [\"--x\"]\n"
        let state = try #require(AgentOptions.state(id: "claude", config: ConfigParser.parse(text).config, facts: FakeSystemFacts(), listedArgs: nil,
                                                    variantEntries: ["mine": EntryLocation(target: .shared, position: 1)], listedVariantArguments: ["mine": ["--x"]]))
        let mine = try #require(state.variants.first)
        let operations = (AgentVariants.changing(title: "Other", of: mine, agent: "claude")?.operations ?? []) + mine.arguments.adding("--y") + mine.arguments.setting(at: 1, to: "--z")
            + (AgentVariants.creating(title: "New", agent: state)?.operations ?? [])
        return Set(operations.flatMap(\.writtenKeys))
    }

    /// The settings of a preset's page (`PresetOptions`) as the keys the changes write, with a change made to each and a new preset made.
    private func presetOptionKeys() throws -> Set<String> {
        let own = ConfigParser.parse("[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\nagent = \"codex\"\nmax_files = 5\n").config
        let state = PresetOptions.state(config: own, entries: ["mine": PresetRowState.Entry(target: .shared, position: 1)], localizer: .english)
        let mine = try #require(state.row(id: "mine"))
        let changes = [PresetOptions.changing(title: "Other", of: mine), PresetOptions.changing(prompt: "Read {files}.", of: mine), PresetOptions.changing(agent: "claude", of: mine),
                       PresetOptions.changing(maxFiles: 8, of: mine), PresetOptions.creating(title: "New", prompt: "Do {files}.", in: state)?.change]
        return Set(changes.compactMap { $0 }.flatMap(\.operations).flatMap(\.writtenKeys))
    }

    /// The settings of a template's page and of "After a file is made" (`NewFileOptions`) as the keys the changes write, with a change made to each and a new template made.
    private func newFileOptionKeys() throws -> Set<String> {
        let own = ConfigParser.parse("[[new_file.template]]\nid = \"mine\"\ntitle = \"Mine\"\nextension = \"md\"\n").config
        let state = NewFileOptions.state(config: own, entries: ["mine": EntryLocation(target: .shared, position: 1)], facts: FakeSystemFacts(), localizer: .english)
        let mine = try #require(state.row(id: "mine"))
        let changes = [NewFileOptions.changing(title: "Other", of: mine), NewFileOptions.changing(baseName: "other", of: mine), NewFileOptions.changing(fileExtension: "txt", of: mine),
                       NewFileOptions.changing(contents: "x", of: mine), NewFileOptions.changing(openWith: "zed", of: mine),
                       NewFileOptions.creating(title: "New", fileExtension: "py", in: state)?.change]
        return Set((changes.compactMap { $0 }.flatMap(\.operations) + NewFileOptions.operations(settingThen: .open, in: state)
                    + NewFileOptions.operations(settingShown: false, of: mine, in: state)).flatMap(\.writtenKeys))
    }

    /// The settings of an app's page and of the form that adds one (`AppOptions`) as the keys the changes write, with a change made to each and a new app made.
    private func appOptionKeys() throws -> Set<String> {
        let own = ConfigParser.parse("[[app]]\nid = \"mine\"\nname = \"Mine\"\nbundle_id = \"com.example.Mine\"\n").config
        let state = AppOptions.state(config: own, entries: ["mine": EntryLocation(target: .shared, position: 1)], facts: FakeSystemFacts())
        let mine = try #require(state.row(id: "mine"))
        let changes = [AppOptions.changing(name: "Other", of: mine), AppOptions.changing(role: .editor, of: mine),
                       AppOptions.creating(name: "New", bundleID: "com.example.New", role: .terminal, in: state)?.change]
        return Set(changes.compactMap { $0 }.flatMap(\.operations).flatMap(\.writtenKeys))
    }

    @Test func theSettingsThatHaveAControlAreThoseTheEditorsWrite() throws {
        // The editors of the window write these keys (GeneralSettings, MenuEditor, AgentOptions): each has to be a control here, or the registry says a person cannot do what the window does,
        // and each control has an editor that writes it.
        let written = Set(["general.terminal", "general.editor", "general.terminal_placement", "general.bypass_permissions", "general.agents", "general.language", "menu.items", "copy_path.title", "copy_path.styles", "services.items"]).union(try agentOptionKeys()).union(try presetOptionKeys()).union(try newFileOptionKeys()).union(try variantOptionKeys()).union(try appOptionKeys())
        let controls = Set(ConfigParity.editors.compactMap { key, editor -> String? in if case .control = editor { key } else { nil } })
        #expect(controls == written)
        #expect(Set((GeneralSettings.operations(settingLanguage: "de") + GeneralSettings.operations(settingLanguage: nil)).flatMap(\.writtenKeys)) == ["general.language"])
        #expect(try agentOptionKeys().count == 8, "an agent's name, command, launcher, terminal, args, the two settings of the permission prompts and how it takes a first prompt")
        #expect(try variantOptionKeys() == ["agent.*.variant.*.id", "agent.*.variant.*.title", "agent.*.variant.*.arguments"])
        #expect(try appOptionKeys() == ["app.*.id", "app.*.name", "app.*.bundle_id", "app.*.role"])
        #expect(try presetOptionKeys() == ["preset.*.id", "preset.*.title", "preset.*.prompt", "preset.*.agent", "preset.*.max_files"])
        #expect(try newFileOptionKeys() == ["new_file.then", "new_file.hidden", "new_file.template.*.id", "new_file.template.*.title", "new_file.template.*.base_name", "new_file.template.*.extension",
                                           "new_file.template.*.contents", "new_file.template.*.open_with"])
        // The two lists of the Finder menu page write the keys they say.
        let copyPath = CopyPathOptions.state(config: ConfigParser.parse("").config, localizer: .english, listed: nil)
        #expect(Set((CopyPathOptions.operations(adding: .parent, to: copyPath) + CopyPathOptions.operations(settingTitle: "Paths", in: copyPath)).flatMap(\.writtenKeys)) == ["copy_path.styles", "copy_path.title"])
        let quick = QuickActionsOptions.state(config: ConfigParser.parse("").config, facts: FakeSystemFacts(), localizer: .english, listed: nil)
        #expect(Set(QuickActionsOptions.operations(adding: "copy-path.name", to: quick).flatMap(\.writtenKeys)) == ["services.items"])
        for key in ConfigParity.textOnly { #expect(!written.contains(key)) }
    }
}
