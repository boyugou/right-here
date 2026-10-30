import Foundation
import Testing
@testable import RightHereCore

/// Entries of an array of tables (`[[preset]]`, `[[app]]`, …) are added, removed and moved as whole blocks; the rest of the file stays where it is.
@Suite("ConfigDocument: entries")
struct ConfigDocumentEntriesTests {
    private let sample = """
    [general]
    agents = ["claude"]

    # Presets I use.
    [[preset]]
    id = "alpha"
    title = "Alpha"
    prompt = "Alpha {files}"

    [[preset]]
    id = "beta"
    title = "Beta" # short
    prompt = "Beta {files}"

    [[preset]]
    id = "gamma"
    title = "Gamma"
    prompt = "Gamma {files}"

    [copy_path]
    title = "Copy Path"
    """ + "\n"

    /// The ids of the presets the file defines, in the order the config gives them (the built-in presets come first, and one that a file redefines keeps its place).
    private func ids(_ text: String) -> [String] {
        let builtIn = Set(AgentPreset.builtIn.map(\.id))
        return ConfigParser.parse(text).config.presets.map(\.id).filter { !builtIn.contains($0) }
    }

    private func nonBlankLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.sorted()
    }

    // MARK: Moving

    @Test func anEntryMovesWithItsCommentAndNothingElseChanges() throws {
        let edited = try ConfigDocument(sample).movingEntry(from: 1, to: 3, in: "preset")
        #expect(ids(edited.text) == ["beta", "gamma", "alpha"])
        #expect(edited.text.hasPrefix("[general]\nagents = [\"claude\"]\n\n"))
        #expect(edited.text.hasSuffix("[copy_path]\ntitle = \"Copy Path\"\n"))
        #expect(nonBlankLines(edited.text) == nonBlankLines(sample), "no line was lost, added or changed")
        // The comment above the first entry belongs to it.
        #expect(edited.text.contains("# Presets I use.\n[[preset]]\nid = \"alpha\""))
    }

    @Test("every move gives the order asked for and keeps every line", arguments: [(1, 2), (1, 3), (2, 1), (2, 3), (3, 1), (3, 2), (2, 2)])
    func everyMoveOfThreeEntries(from: Int, to: Int) throws {
        var expected = ["alpha", "beta", "gamma"]
        expected.insert(expected.remove(at: from - 1), at: to - 1)
        let edited = try ConfigDocument(sample).movingEntry(from: from, to: to, in: "preset")
        #expect(ids(edited.text) == expected)
        #expect(nonBlankLines(edited.text) == nonBlankLines(sample))
        #expect(!edited.text.contains("\n\n\n"), "blank lines are not piled up")
        #expect(edited.text.hasSuffix("\n") && edited.text.contains("\n\n[copy_path]\n"))
        // Twice, to be sure the text it leaves is one that can be edited again.
        #expect(ids(try edited.movingEntry(from: to, to: from, in: "preset").text) == ["alpha", "beta", "gamma"])
    }

    @Test func aMoveInATextWithoutAFinalLineBreakGivesOne() throws {
        let bare = "[[preset]]\nid = \"a\"\ntitle = \"A\"\nprompt = \"A {files}\"\n\n[[preset]]\nid = \"b\"\ntitle = \"B\"\nprompt = \"B {files}\""
        let edited = try ConfigDocument(bare).movingEntry(from: 2, to: 1, in: "preset")
        #expect(ids(edited.text) == ["b", "a"])
        #expect(edited.text.hasPrefix("[[preset]]\nid = \"b\""))
    }

    // MARK: Removing

    @Test func anEntryIsRemovedWithItsCommentAndItsBlankLine() throws {
        let middle = try ConfigDocument(sample).removingEntry(at: 2, from: "preset")
        #expect(ids(middle.text) == ["alpha", "gamma"])
        #expect(!middle.text.contains("short") && !middle.text.contains("\n\n\n"))
        let first = try ConfigDocument(sample).removingEntry(at: 1, from: "preset")
        #expect(ids(first.text) == ["beta", "gamma"] && !first.text.contains("Presets I use"))
    }

    @Test func theLastEntryOfTheFileTakesTheBlankLineAboveItWithIt() throws {
        let text = "[general]\nagents = [\"claude\"]\n\n[[preset]]\nid = \"a\"\ntitle = \"A\"\nprompt = \"A {files}\"\n"
        let edited = try ConfigDocument(text).removingEntry(at: 1, from: "preset")
        #expect(edited.text == "[general]\nagents = [\"claude\"]\n")
    }

    @Test func removingEveryEntryLeavesAnUsableConfig() throws {
        var document = ConfigDocument(sample)
        for _ in 0..<3 { document = try document.removingEntry(at: 1, from: "preset") }
        #expect(ids(document.text).isEmpty && document.text.contains("[copy_path]"))
        #expect(throws: ConfigDocument.EditError.notFound("preset")) { try document.removingEntry(at: 1, from: "preset") }
    }

    // MARK: Adding

    @Test func anEntryIsAddedAfterTheLastOneAndTheTextThatFollowsStaysAfterIt() throws {
        let fields: [(key: String, value: ConfigDocument.Value)] = [("id", .string("fix")), ("title", .string("Fix")), ("prompt", .string("Fix {files}"))]
        let edited = try ConfigDocument(sample).addingEntry(to: "preset", fields: fields)
        #expect(ids(edited.text) == ["alpha", "beta", "gamma", "fix"])
        #expect(edited.text.contains("prompt = \"Gamma {files}\"\n\n[[preset]]\nid = \"fix\"\ntitle = \"Fix\"\nprompt = \"Fix {files}\"\n\n[copy_path]"))
    }

    @Test func anEntryIsAddedBeforeAnotherOne() throws {
        let fields: [(key: String, value: ConfigDocument.Value)] = [("id", .string("fix")), ("title", .string("Fix")), ("prompt", .string("Fix {files}"))]
        let first = try ConfigDocument(sample).addingEntry(to: "preset", fields: fields, at: 1)
        #expect(ids(first.text) == ["fix", "alpha", "beta", "gamma"])
        #expect(first.text.contains("[general]\nagents = [\"claude\"]\n\n[[preset]]\nid = \"fix\"") || first.text.contains("# Presets I use.") == false || first.text.contains("[[preset]]\nid = \"fix\""))
        let middle = try ConfigDocument(sample).addingEntry(to: "preset", fields: fields, at: 3)
        #expect(ids(middle.text) == ["alpha", "beta", "fix", "gamma"])
    }

    @Test func theFirstEntryOfAKindIsMadeAtTheEndOfTheText() throws {
        let text = "[general]\nagents = [\"claude\"]\n"
        let fields: [(key: String, value: ConfigDocument.Value)] = [("id", .string("fix")), ("title", .string("Fix")), ("prompt", .string("Fix {files}"))]
        let edited = try ConfigDocument(text).addingEntry(to: "preset", fields: fields)
        #expect(edited.text == text + "\n[[preset]]\nid = \"fix\"\ntitle = \"Fix\"\nprompt = \"Fix {files}\"\n")
        let again = try edited.addingEntry(to: "preset", fields: [("id", .string("two")), ("title", .string("Two")), ("prompt", .string("Two {files}"))])
        #expect(ids(again.text) == ["fix", "two"])
    }

    @Test func anEntryThatLacksWhatItNeedsOrHoldsTheWrongKindIsRefused() {
        #expect(throws: (any Error).self) { try ConfigDocument(sample).addingEntry(to: "preset", fields: [("id", .string("fix")), ("title", .string("Fix"))]) }
        #expect(throws: ConfigDocument.EditError.wrongKind(path: "preset.1.title", expected: "text")) {
            try ConfigDocument(sample).addingEntry(to: "preset", fields: [("id", .string("fix")), ("title", .boolean(true)), ("prompt", .string("x"))])
        }
        #expect(throws: ConfigDocument.EditError.unknownKey("preset.1.colour")) {
            try ConfigDocument(sample).addingEntry(to: "preset", fields: [("colour", .string("red"))])
        }
        #expect(throws: ConfigDocument.EditError.wrongKind(path: "general", expected: "a list of entries, which is made with the entries of [[general]]")) {
            try ConfigDocument(sample).addingEntry(to: "general", fields: [])
        }
        #expect(throws: ConfigDocument.EditError.outOfRange(path: "preset", position: 9, count: 3)) { try ConfigDocument(sample).movingEntry(from: 9, to: 1, in: "preset") }
    }

    @Test func appsAndTheVariantsOfAnAgentAreEntriesToo() throws {
        let app = try ConfigDocument("[general]\nagents = [\"claude\"]\n").addingEntry(
            to: "app", fields: [("id", .string("tower")), ("name", .string("Tower")), ("bundle_id", .string("com.fournova.Tower3")), ("role", .string("general"))])
        #expect(ConfigParser.parse(app.text).config.apps.map(\.id) == ["tower"])
        let withAgent = try ConfigDocument("[general]\nagents = [\"claude\"]\n\n[agent.claude]\ncommand = \"claude\"\n").addingEntry(
            to: "agent.claude.variant", fields: [("id", .string("opus")), ("title", .string("Use Opus")), ("arguments", .strings(["--model", "opus"]))])
        #expect(ConfigParser.parse(withAgent.text).config.agent(id: "claude")?.variants.map(\.id).contains("opus") == true)
        #expect(withAgent.entryCount(of: "agent.claude.variant") == 1)
        let removed = try withAgent.removingEntry(at: 1, from: "agent.claude.variant")
        #expect(removed.text == "[general]\nagents = [\"claude\"]\n\n[agent.claude]\ncommand = \"claude\"\n")
    }

    // MARK: A value written across lines

    private static let multiline = """
    [[new_file.template]]
    id = "notes"
    title = "Notes"
    extension = "md"
    contents = \"\"\"
    # Title

    ## Notes\"\"\"

    [[new_file.template]]
    id = "txt"
    title = "Text"
    extension = "txt"
    """ + "\n"

    private func contents(of text: String, id: String = "notes") -> String? {
        ConfigParser.parse(text).config.newFile.templates.first { $0.id == id }?.contents
    }

    @Test func aStringThatEndsOnALineStartingWithAHashIsStillAStringWhenAKeyIsSet() throws {
        let document = ConfigDocument(Self.multiline)
        let original = try #require(contents(of: Self.multiline))
        #expect(original.hasSuffix("## Notes"), "\(original.debugDescription)")
        let set = try document.setting("new_file.template.1.open_with", to: .string("typora"))
        #expect(contents(of: set.text) == original, "the key went into the string")
        #expect(ConfigParser.parse(set.text).config.newFile.templates.first { $0.id == "notes" }?.openWith == "typora")
        #expect(set.text.contains("## Notes\"\"\"\nopen_with = \"typora\"\n"), "after the string, in the entry: \(set.text)")
    }

    @Test func anEntryIsAddedRemovedAndMovedAroundAStringThatEndsOnAHashLine() throws {
        let document = ConfigDocument(Self.multiline)
        let original = try #require(contents(of: Self.multiline))
        let fields = [("id", ConfigDocument.Value.string("csv")), ("title", .string("CSV")), ("extension", .string("csv"))]
        let added = try document.addingEntry(to: "new_file.template", fields: fields, at: 2)
        #expect(ConfigParser.parse(added.text).config.newFile.templates.map(\.id) == ["notes", "csv", "txt"] && contents(of: added.text) == original, "\(added.text)")
        let removed = try document.removingEntry(at: 2, from: "new_file.template")
        #expect(ConfigParser.parse(removed.text).config.newFile.templates.map(\.id) == ["notes"])
        let moved = try document.movingEntry(from: 2, to: 1, in: "new_file.template")
        #expect(ConfigParser.parse(moved.text).config.newFile.templates.map(\.id) == ["txt", "notes"] && contents(of: moved.text) == original)
        let gone = try document.removingEntry(at: 1, from: "new_file.template")
        #expect(ConfigParser.parse(gone.text).config.newFile.templates.map(\.id) == ["txt"], "the string went with its entry: \(gone.text)")
    }

    // MARK: A comment block that stands apart

    private static let apartBetween = """
    [[preset]]
    id = "a"
    title = "A"
    prompt = "A {files}"

    # Below: the presets my dotfiles script writes.

    [[preset]]
    id = "b"
    title = "B"
    prompt = "B {files}"

    # end of presets
    """ + "\n"

    @Test func aCommentBlockThatStandsApartBetweenEntriesStaysWhereItIsWhenAnEntryGoes() throws {
        let document = ConfigDocument(Self.apartBetween)
        let removedFirst = try document.removingEntry(at: 1, from: "preset")
        #expect(removedFirst.text == "# Below: the presets my dotfiles script writes.\n\n[[preset]]\nid = \"b\"\ntitle = \"B\"\nprompt = \"B {files}\"\n\n# end of presets\n", "\(removedFirst.text.debugDescription)")
        let removedLast = try document.removingEntry(at: 2, from: "preset")
        #expect(removedLast.text.contains("# Below: the presets my dotfiles script writes.") && removedLast.text.contains("# end of presets") && !removedLast.text.contains("id = \"b\""), "\(removedLast.text)")
    }

    @Test func aCommentBlockThatStandsApartStaysBetweenTheSamePlacesWhenEntriesAreMoved() throws {
        let moved = try ConfigDocument(Self.apartBetween).movingEntry(from: 2, to: 1, in: "preset")
        let first = try #require(moved.text.range(of: "id = \"b\"")), note = try #require(moved.text.range(of: "# Below:")), second = try #require(moved.text.range(of: "id = \"a\""))
        #expect(first.lowerBound < note.lowerBound && note.lowerBound < second.lowerBound, "the note is still between the two places: \(moved.text)")
        #expect(moved.text.hasSuffix("# end of presets\n"), "and the note at the end is still at the end")
    }

    @Test func anEntryAddedAfterTheLastOneGoesBeforeANoteThatStandsApartAtTheEnd() throws {
        let fields = [("id", ConfigDocument.Value.string("c")), ("title", .string("C")), ("prompt", .string("C {files}"))]
        let added = try ConfigDocument(Self.apartBetween).addingEntry(to: "preset", fields: fields)
        #expect(added.text.hasSuffix("id = \"c\"\ntitle = \"C\"\nprompt = \"C {files}\"\n\n# end of presets\n"), "\(added.text)")
    }

    @Test func theClosingLineOfAStringRightAboveTheNextHeaderIsNotACommentOfThatEntry() throws {
        // The string ends on a line that starts with a hash, and the next entry's header follows it at once.
        let text = """
        [[new_file.template]]
        id = "notes"
        title = "Notes"
        extension = "md"
        contents = \"\"\"
        # Title
        ## Notes\"\"\"
        [[new_file.template]]
        id = "txt"
        title = "Text"
        extension = "txt"
        """ + "\n"
        let document = ConfigDocument(text)
        let original = try #require(ConfigParser.parse(text).config.newFile.templates.first { $0.id == "notes" }?.contents)
        let fields = [("id", ConfigDocument.Value.string("csv")), ("title", .string("CSV")), ("extension", .string("csv"))]
        let added = try document.addingEntry(to: "new_file.template", fields: fields, at: 2)
        let templates = ConfigParser.parse(added.text).config.newFile.templates
        #expect(templates.map(\.id) == ["notes", "csv", "txt"] && templates.first?.contents == original, "\(added.text)")
        let moved = try document.movingEntry(from: 2, to: 1, in: "new_file.template")
        #expect(ConfigParser.parse(moved.text).config.newFile.templates.map(\.id) == ["txt", "notes"], "\(moved.text)")
        let removed = try document.removingEntry(at: 2, from: "new_file.template")
        #expect(ConfigParser.parse(removed.text).config.newFile.templates.map(\.id) == ["notes"] && ConfigParser.parse(removed.text).config.newFile.templates.first?.contents == original)
    }

    // MARK: A table per id, made at once

    @Test func anAgentThatIsNotBuiltInIsMadeWithItsNameAndItsCommandAtOnce() throws {
        let document = ConfigDocument("[general]\nterminal = \"ghostty\"\n")
        // Either key alone is a config that does not read, so there is no way to make it one key after the other.
        #expect(throws: ConfigDocument.EditError.self) { try document.setting("agent.lazygit.command", to: .string("lazygit")) }
        let made = try document.addingTable("agent.lazygit", fields: [("name", .string("lazygit")), ("command", .string("lazygit"))])
        #expect(made.text == "[general]\nterminal = \"ghostty\"\n\n[agent.lazygit]\nname = \"lazygit\"\ncommand = \"lazygit\"\n", "\(made.text.debugDescription)")
        let config = ConfigParser.parse(made.text).config
        #expect(config.agent(id: "lazygit")?.command == "lazygit" && config.agent(id: "lazygit")?.name == "lazygit")
        #expect(throws: ConfigDocument.EditError.exists("agent.lazygit")) { try made.addingTable("agent.lazygit", fields: [("name", .string("x")), ("command", .string("y"))]) }
    }

    @Test func aTableIsMadeOnlyForATablePerIdAndWithFieldsThatBelongToIt() throws {
        let document = ConfigDocument("")
        #expect(throws: ConfigDocument.EditError.self) { try document.addingTable("general", fields: [("terminal", .string("ghostty"))]) }
        #expect(throws: ConfigDocument.EditError.self) { try document.addingTable("agent.x.y", fields: []) }
        #expect(throws: ConfigDocument.EditError.self) { try document.addingTable("agent.lazygit", fields: [("nope", .string("x"))]) }
        #expect(throws: ConfigDocument.EditError.self) { try document.addingTable("agent.lazygit", fields: [("name", .boolean(true))]) }
        #expect(throws: ConfigDocument.EditError.self) { try document.addingTable("agent.Not An Id", fields: [("name", .string("x")), ("command", .string("y"))]) }
        let made = try document.addingTable("agent.mine", fields: [("name", .string("Mine")), ("command", .string("mine --fast"))])
        #expect(made.text == "[agent.mine]\nname = \"Mine\"\ncommand = \"mine --fast\"\n", "\(made.text.debugDescription)")
    }

    // MARK: A table per id, taken out whole

    private let agents = """
    [general]
    agents = ["claude"]

    # My own tool.
    [agent.mine]
    name = "Mine"
    command = "mine --fast"
    args = [
        "--a", # first
        "[not-a-header]",
    ]

    [[agent.mine.variant]]
    id = "slow"
    title = "Slow"
    arguments = ["--slow"]

    # Another one.
    [agent.other]
    name = "Other"
    command = "other"

    [menu]
    items = ["agents"]
    """ + "\n"

    @Test func aTableIsTakenOutWithItsVariantsAndTheCommentAboveItAndNothingElseMoves() throws {
        let document = ConfigDocument(agents)
        let removed = try document.removingTable("agent.mine")
        #expect(removed.text == "[general]\nagents = [\"claude\"]\n\n# Another one.\n[agent.other]\nname = \"Other\"\ncommand = \"other\"\n\n[menu]\nitems = [\"agents\"]\n", "\(removed.text.debugDescription)")
        #expect(ConfigParser.parse(removed.text).config.agents["mine"] == nil)
        // The comment above the next table is that table's, and the table before it is untouched.
        let other = try document.removingTable("agent.other")
        #expect(other.text == agents.replacingOccurrences(of: "# Another one.\n[agent.other]\nname = \"Other\"\ncommand = \"other\"\n\n", with: ""), "\(other.text.debugDescription)")
    }

    @Test func theLastTableOfTheTextTakesTheBlankLinesAboveItWithIt() throws {
        let document = ConfigDocument("[general]\nterminal = \"ghostty\"\n\n# Mine.\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n")
        #expect(try document.removingTable("agent.mine").text == "[general]\nterminal = \"ghostty\"\n")
        #expect(try ConfigDocument("[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n").removingTable("agent.mine").text == "")
    }

    @Test func aTableThatIsWrittenInSeveralPlacesIsTakenOutFromAllOfThem() throws {
        let text = "[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n\n[menu]\nitems = [\"agents\"]\n\n[[agent.mine.variant]]\nid = \"slow\"\ntitle = \"Slow\"\narguments = [\"--slow\"]\n"
        #expect(try ConfigDocument(text).removingTable("agent.mine").text == "[menu]\nitems = [\"agents\"]\n")
    }

    @Test func aCommentThatStandsApartAfterTheTableStays() throws {
        let text = "[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n\n# About the menu below, nothing to do with the agent.\n\n[menu]\nitems = [\"agents\"]\n"
        #expect(try ConfigDocument(text).removingTable("agent.mine").text == "# About the menu below, nothing to do with the agent.\n\n[menu]\nitems = [\"agents\"]\n")
    }

    @Test func aTableThatIsNotThereOrIsWrittenAsKeysIsNotCutOutByLines() throws {
        let document = ConfigDocument(agents)
        #expect(throws: ConfigDocument.EditError.notFound("agent.nothing")) { try document.removingTable("agent.nothing") }
        #expect(throws: ConfigDocument.EditError.inlineTable("agent.mine")) { try ConfigDocument("[agent]\nmine.name = \"Mine\"\nmine.command = \"mine\"\n").removingTable("agent.mine") }
        #expect(throws: ConfigDocument.EditError.inlineTable("agent.mine")) { try ConfigDocument("agent.mine = { name = \"Mine\", command = \"mine\" }\n").removingTable("agent.mine") }
        #expect(throws: ConfigDocument.EditError.self) { try document.removingTable("general") }
        #expect(throws: ConfigDocument.EditError.self) { try document.removingTable("agent") }
        #expect(throws: ConfigDocument.EditError.self) { try document.removingTable("agent.mine.variant") }
        #expect(throws: ConfigDocument.EditError.self) { try ConfigDocument("[agent.mine\nname = 1").removingTable("agent.mine") }
    }

    @Test func aTableAndItsVariantsAtTheEndOfTheTextLeaveNoBlankLineBehind() throws {
        let text = "[general]\nterminal = \"ghostty\"\n\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n\n[[agent.mine.variant]]\nid = \"x\"\ntitle = \"X\"\narguments = [\"-x\"]\n"
        #expect(try ConfigDocument(text).removingTable("agent.mine").text == "[general]\nterminal = \"ghostty\"\n")
    }

    @Test func aSettingThatIsCommentedOutRightAfterTheLastKeyGoesWithTheTable() throws {
        let text = "[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n# args = [\"--fast\"]\n\n# About the menu.\n[menu]\nitems = [\"agents\"]\n"
        #expect(try ConfigDocument(text).removingTable("agent.mine").text == "# About the menu.\n[menu]\nitems = [\"agents\"]\n")
    }

    @Test func anEntryIsNotAppendedToAListThatTheFileWritesAsAValue() throws {
        let inline = "preset = [{ id = \"mine\", title = \"Mine\", prompt = \"Look at {files}.\" }]\n"
        let fields: [(key: String, value: ConfigDocument.Value)] = [("id", .string("other")), ("title", .string("Other")), ("prompt", .string("Read {files}."))]
        #expect(throws: ConfigDocument.EditError.inlineTable("preset")) { try ConfigDocument(inline).addingEntry(to: "preset", fields: fields) }
        #expect(throws: ConfigDocument.EditError.inlineTable("agent.claude.variant")) { try ConfigDocument("[agent.claude]\nvariant = [{ id = \"a\", title = \"A\" }]\n").addingEntry(to: "agent.claude.variant", fields: [("id", .string("b")), ("title", .string("B"))]) }
        let headers = "[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n"
        #expect(try ConfigDocument(headers).addingEntry(to: "preset", fields: fields).text.hasSuffix("[[preset]]\nid = \"other\"\ntitle = \"Other\"\nprompt = \"Read {files}.\"\n"))
    }

    @Test("an id is read as the parser reads it: every way of writing a string", arguments: [
        #""mine""#, #"'mine'"#, "\"\"\"mine\"\"\"", "'''mine'''", #""m\u0069ne""#, #""a\"b""#, #"'a"b'"#, #""x'y""#, #""""#, #""tab\there""#, "\"\"\"\nline\"\"\"", #""\\""#, #"'C:\path'"#, "\"😀\"", #""a # b""#,
        #""mine" # a comment"#, #""é""#, #""\U0001F600""#
    ])
    func anIdIsDecodedAsTheParserDecodesIt(raw: String) {
        let decoded = ConfigParser.readTree("v = " + raw).tree.flatMap { tree -> String? in if case .string(let text)? = tree["v"] { text } else { nil } }
        #expect(ConfigDocument.unquoted(raw) == decoded, "\(raw): \(String(describing: ConfigDocument.unquoted(raw))) against the parser's \(String(describing: decoded))")
        let text = "[[preset]]\nid = \(raw)\ntitle = \"T\"\nprompt = \"P {files}\"\n"
        #expect(ConfigDocument(text).entryIDs(in: "preset") == [decoded], "\(raw)")
        #expect(ConfigDocument(text).parsedEntryIDs(in: "preset") == Set([decoded].compactMap { $0 }), "\(raw)")
    }
}
