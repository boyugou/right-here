import Foundation
import Testing
@testable import RightHereCore

private func config(_ text: String) -> Config { ConfigParser.parse(text).config }

@Suite("PresetOptions: the prompt presets as lines to edit")
struct PresetOptionsTests {
    private let text = """
    [general]
    agents = ["claude", "codex"]

    [[preset]]
    id = "review"
    title = "Careful review"
    prompt = "Look at {files} and be strict."

    [[preset]]
    id = "mine"
    title = "Mine"
    prompt = "Summarise {files}."
    agent = "codex"
    max_files = 5
    """ + "\n"

    private func state(_ text: String? = nil, entries: [String: PresetRowState.Entry]? = nil) -> PresetsState {
        PresetOptions.state(config: config(text ?? self.text), entries: entries ?? [
            "review": PresetRowState.Entry(target: .shared, position: 1), "mine": PresetRowState.Entry(target: .shared, position: 2)
        ], localizer: .english)
    }

    private func apply(_ change: PresetOptions.Change, to text: String) throws -> Config {
        var document = ConfigDocument(text)
        for operation in change.operations { document = try operation.apply(to: document) }
        return config(document.text)
    }

    @Test func theRowsAreTheBuiltInPresetsWithTheOnesTheConfigTouchesAndThoseItAdds() throws {
        let rows = state().rows
        #expect(rows.map(\.id) == ["review", "explain", "tests", "mine"])
        #expect(rows.map(\.origin) == [.customized, .builtIn, .builtIn, .own])
        #expect(rows[0].title == "Careful review" && rows[0].prompt == "Look at {files} and be strict." && rows[0].entry == PresetRowState.Entry(target: .shared, position: 1))
        #expect(rows[1].title == "Explain" && rows[1].entry == nil, "a built-in title is in the person's language")
        #expect(rows[3].agent == "codex" && rows[3].maxFiles == 5 && rows[2].maxFiles == AgentPreset.defaultMaxFiles)
        #expect(state().agents.map(\.id).contains("claude") && !state().agents.map(\.id).contains("goose"), "an agent that is not known to take a first prompt is not offered")
    }

    @Test func eachFieldIsOneChangeInTheFileThatHoldsTheEntryUnderTheCheckOfItsPlace() throws {
        let rows = state().rows
        let mine = rows[3]
        let title = try #require(PresetOptions.changing(title: "  Short  ", of: mine))
        #expect(title.target == .shared && title.operations == [.expectEntry("mine", at: 2, in: "preset"), .set("preset.2.title", .string("Short"))])
        #expect(try apply(title, to: text).preset(id: "mine")?.title == "Short")
        #expect(PresetOptions.changing(title: "Mine", of: mine) == nil && PresetOptions.changing(title: "   ", of: mine) == nil)
        let prompt = try #require(PresetOptions.changing(prompt: "Read {files}.", of: mine))
        #expect(try apply(prompt, to: text).preset(id: "mine")?.prompt == "Read {files}.")
        #expect(PresetOptions.changing(prompt: " ", of: mine) == nil && PresetOptions.changing(prompt: mine.prompt, of: mine) == nil)
        let agent = try #require(PresetOptions.changing(agent: "claude", of: mine))
        #expect(try apply(agent, to: text).preset(id: "mine")?.agent == "claude")
        let first = try #require(PresetOptions.changing(agent: nil, of: mine))
        #expect(first.operations.last == .unset("preset.2.agent"))
        #expect(try apply(first, to: text).preset(id: "mine")?.agent == nil)
        #expect(PresetOptions.changing(agent: "codex", of: mine) == nil)
        let files = try #require(PresetOptions.changing(maxFiles: 8, of: mine))
        #expect(try apply(files, to: text).preset(id: "mine")?.maxFiles == 8)
        let backToDefault = try #require(PresetOptions.changing(maxFiles: AgentPreset.defaultMaxFiles, of: mine))
        #expect(backToDefault.operations.last == .unset("preset.2.max_files"), "the default is the setting taken out")
        #expect(PresetOptions.changing(maxFiles: 0, of: mine) == nil && PresetOptions.changing(maxFiles: AgentPreset.maxFilesLimit + 1, of: mine) == nil && PresetOptions.changing(maxFiles: 5, of: mine) == nil)
    }

    @Test func aPresetThatThisMacsFileWritesIsChangedThereAndABuiltInOneIsNotChangedByAField() throws {
        let rows = state(entries: ["review": PresetRowState.Entry(target: .local, position: 3), "mine": PresetRowState.Entry(target: .shared, position: 2)]).rows
        #expect(PresetOptions.changing(title: "x", of: rows[0])?.target == .local)
        #expect(PresetOptions.changing(title: "x", of: rows[0])?.operations.first == .expectEntry("review", at: 3, in: "preset"))
        let builtIn = rows[1]
        #expect(builtIn.origin == .builtIn && PresetOptions.changing(title: "x", of: builtIn) == nil && PresetOptions.changing(prompt: "x", of: builtIn) == nil && PresetOptions.removing(builtIn) == nil)
        #expect(PresetOptions.changing(agent: "claude", of: builtIn) == nil && PresetOptions.changing(maxFiles: 3, of: builtIn) == nil, "no field of a built-in preset is written without an entry")
    }

    @Test func aBuiltInPresetIsMadeTheOwnersByAnEntryWithItsWordsAndTakenOutAgainItIsTheBuiltInOne() throws {
        let plain = "[general]\nagents = [\"claude\"]\n"
        let rows = state(plain, entries: [:]).rows
        let explain = try #require(rows.first { $0.id == "explain" })
        let customize = try #require(PresetOptions.customizing(explain))
        #expect(customize.target == .shared)
        let made = try apply(customize, to: plain)
        #expect(made.preset(id: "explain")?.prompt == explain.prompt && made.preset(id: "explain")?.title == "Explain" && made.presets.count == 3, "replaced in place")
        let alreadyTheOwners = try #require(state().rows.first { $0.id == "review" })
        #expect(PresetOptions.customizing(rows[0]) != nil && PresetOptions.customizing(alreadyTheOwners) == nil, "a built-in id the config already writes is not customized twice")
        // The entry that was made is the row's entry now: change it, then take it out.
        let after = PresetOptions.state(config: made, entries: ["explain": PresetRowState.Entry(target: .shared, position: 1)], localizer: .english)
        let row = try #require(after.row(id: "explain"))
        #expect(row.origin == .customized)
        let changed = try #require(PresetOptions.changing(prompt: "Tell me about {files}.", of: row))
        let edited = try apply(changed, to: ConfigDocument(plain).text + "\n[[preset]]\nid = \"explain\"\ntitle = \"Explain\"\nprompt = \"x\"\n")
        #expect(edited.preset(id: "explain")?.prompt == "Tell me about {files}.")
        let reset = try #require(PresetOptions.removing(row))
        let back = try apply(reset, to: ConfigDocument(plain).text + "\n[[preset]]\nid = \"explain\"\ntitle = \"Explain\"\nprompt = \"x\"\n")
        #expect(back.preset(id: "explain")?.prompt == explain.prompt && back.presets.count == 3, "the built-in preset is back")
    }

    @Test func aPresetOfOnesOwnIsMadeWithATitleAndAPromptAndAnIdThatNothingHas() throws {
        let current = state()
        let made = try #require(PresetOptions.creating(title: "Find Bugs", prompt: "Find bugs in {files}.", in: current))
        #expect(made.id == "find-bugs" && made.change.target == .shared)
        #expect(made.change.operations == [.addEntry(to: "preset", fields: [ConfigField("id", .string("find-bugs")), ConfigField("title", .string("Find Bugs")), ConfigField("prompt", .string("Find bugs in {files}."))], at: nil)])
        #expect(try apply(made.change, to: text).preset(id: "find-bugs")?.prompt == "Find bugs in {files}.")
        #expect(PresetOptions.creating(title: "Review", prompt: "x {files}", in: current)?.id == "review-2", "the id of a built-in preset is taken")
        #expect(PresetOptions.creating(title: "Mine", prompt: "x", in: current, alsoTaken: ["mine-2"])?.id == "mine-3")
        #expect(PresetOptions.creating(title: "ラザ", prompt: "x {files}", in: current)?.id == "preset", "a title with no letter of an id still makes a preset")
        #expect(PresetOptions.creating(title: " ", prompt: "x", in: current) == nil && PresetOptions.creating(title: "A", prompt: "  ", in: current) == nil)
    }

    @Test func aPromptTheConfigWouldRefuseIsRefusedWhereItIsWrittenAndNothingIsWritten() throws {
        let mine = state().rows[3]
        for bad in ["line\nbreak {files}", "back\\slash {files}", "-leading {files}", "unknown {file} placeholder"] {
            let change = try #require(PresetOptions.changing(prompt: bad, of: mine), Comment(rawValue: bad))
            #expect(throws: ConfigDocument.EditError.self, "\(bad.debugDescription)") { try apply(change, to: text) }
        }
    }
}
