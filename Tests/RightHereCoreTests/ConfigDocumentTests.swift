import Foundation
import Testing
@testable import RightHereCore

/// The edits keep every byte they were not asked to change: comments, order, layout.
@Suite("ConfigDocument: edits that leave the rest of the file alone")
struct ConfigDocumentTests {
    private let sample = """
    # My Right Here config.
    version = 1

    [general]
    terminal = "ghostty" # the one I like
    editor = "vscode"
    agents = ["claude", "codex"]

    # The Finder menu.
    [menu]
    items = [
        "open-terminal",
        # my editor
        "open-editor", # (VS Code)
        "-",
        "agents",
    ]

    [[preset]]
    id = "review"
    title = "Review"
    prompt = "Review {files}"
    """ + "\n"

    private func config(_ text: String) -> Config { ConfigParser.parse(text).config }

    // MARK: A table that dotted keys define

    @Test func aKeyOfATableThatDottedKeysDefineIsWrittenAsOneMoreDottedKeyAndNotInANewHeader() throws {
        let text = "# Mine.\ncopy_path.title = \"Paths\" # mine\n\n[general]\nterminal = \"ghostty\"\n"
        let edited = try ConfigDocument(text).setting("copy_path.styles", to: .strings(["name", "parent"]))
        #expect(edited.text == "# Mine.\ncopy_path.title = \"Paths\" # mine\ncopy_path.styles = [\"name\", \"parent\"]\n\n[general]\nterminal = \"ghostty\"\n", Comment(rawValue: edited.text))
        #expect(!ConfigParser.parse(edited.text).hasErrors && config(edited.text).copyPathStyles == [.name, .parent] && config(edited.text).copyPathTitle == "Paths")
        // Several lines of dotted keys: after the last, and with a value across lines.
        let several = "copy_path.title = \"Paths\"\ncopy_path.extra = [\n  \"x\",\n]\n[general]\nterminal = \"ghostty\"\n"
        let more = try ConfigDocument(several).setting("copy_path.styles", to: .strings(["name"]))
        #expect(more.text.contains("  \"x\",\n]\ncopy_path.styles = [\"name\"]\n[general]"), Comment(rawValue: more.text))
        // A table with a header keeps its keys under the header.
        let header = try ConfigDocument("[copy_path]\ntitle = \"Paths\"\n").setting("copy_path.styles", to: .strings(["name"]))
        #expect(header.text == "[copy_path]\ntitle = \"Paths\"\nstyles = [\"name\"]\n")
    }

    // MARK: A value that is there

    @Test func aValueIsReplacedWhereItIsWrittenAndTheCommentAfterItStays() throws {
        let edited = try ConfigDocument(sample).setting("general.terminal", to: .string("iterm"))
        #expect(edited.text == sample.replacingOccurrences(of: "\"ghostty\"", with: "\"iterm\""))
        #expect(config(edited.text).terminal == "iterm")
    }

    @Test func aTextValueWithQuotesAndBackslashesIsEscapedAndReadBack() throws {
        let tricky = "Review \"these\" in C:\\code and 'those'"
        let edited = try ConfigDocument(sample).setting("preset.1.title", to: .string(tricky))
        #expect(config(edited.text).presets.first?.title == tricky)
    }

    @Test func aBooleanAndANumberAreWrittenAsTOML() throws {
        let edited = try ConfigDocument(sample).setting("general.bypass_permissions", to: .boolean(true)).setting("preset.1.max_files", to: .integer(5))
        #expect(edited.text.contains("bypass_permissions = true") && edited.text.contains("max_files = 5"))
        #expect(config(edited.text).bypassPermissions && config(edited.text).presets.first?.maxFiles == 5)
    }

    // MARK: A key that is not there

    @Test func aKeyIsAddedAtTheEndOfItsTableAndNotAfterTheBlankLinesAndCommentsThatFollow() throws {
        let edited = try ConfigDocument(sample).setting("general.terminal_placement", to: .string("tab"))
        let expected = sample.replacingOccurrences(of: "agents = [\"claude\", \"codex\"]\n", with: "agents = [\"claude\", \"codex\"]\nterminal_placement = \"tab\"\n")
        #expect(edited.text == expected)
        #expect(config(edited.text).terminalPlacement == .newTab)
    }

    @Test func aTableThatIsNotThereIsMadeAtTheEndWithABlankLineBeforeIt() throws {
        let edited = try ConfigDocument("[general]\nterminal = \"ghostty\"\n").setting("copy_path.title", to: .string("Copy"))
        #expect(edited.text == "[general]\nterminal = \"ghostty\"\n\n[copy_path]\ntitle = \"Copy\"\n")
        let noNewline = try ConfigDocument("[general]\nterminal = \"ghostty\"").setting("copy_path.title", to: .string("Copy"))
        #expect(noNewline.text == "[general]\nterminal = \"ghostty\"\n\n[copy_path]\ntitle = \"Copy\"\n")
    }

    @Test func aKeyOfATablePerIdMakesItsTable() throws {
        let edited = try ConfigDocument(sample).setting("agent.claude.args", to: .strings(["--verbose"]))
        #expect(edited.text.hasSuffix("\n[agent.claude]\nargs = [\"--verbose\"]\n"))
        #expect(config(edited.text).agent(id: "claude")?.promptArgument != nil)
    }

    @Test func aTopLevelKeyGoesAboveTheFirstTable() throws {
        let edited = try ConfigDocument("[general]\nterminal = \"ghostty\"\n").setting("disabled", to: .strings(["zed"]))
        #expect(edited.text == "disabled = [\"zed\"]\n\n[general]\nterminal = \"ghostty\"\n")
    }

    @Test func aKeyIsAddedToAnEntryOfAnArrayOfTables() throws {
        let edited = try ConfigDocument(sample).setting("preset.1.agent", to: .string("codex"))
        #expect(edited.text.hasSuffix("prompt = \"Review {files}\"\nagent = \"codex\"\n"))
        #expect(config(edited.text).presets.first?.agent == "codex")
    }

    // MARK: Removing a key

    @Test func aKeyIsRemovedWithItsLinesAndTheCommentsAboveItStay() throws {
        let edited = try ConfigDocument(sample).removing("general.editor")
        #expect(edited.text == sample.replacingOccurrences(of: "editor = \"vscode\"\n", with: ""))
        let multiLine = try ConfigDocument(sample).removing("menu.items")
        #expect(!multiLine.text.contains("open-terminal") && multiLine.text.contains("# The Finder menu.\n[menu]\n\n[[preset]]"))
    }

    // MARK: Elements of an array

    @Test func anElementIsAddedToASingleLineArrayInTheSameLayout() throws {
        let edited = try ConfigDocument(sample).insertingElement("gemini", into: "general.agents")
        #expect(edited.text.contains("agents = [\"claude\", \"codex\", \"gemini\"]"))
        let first = try ConfigDocument(sample).insertingElement("gemini", into: "general.agents", at: 1)
        #expect(config(first.text).enabledAgents == ["gemini", "claude", "codex"])
        // Each place keeps what it had: a new first element is not squeezed against the one after it ("gemini","claude").
        #expect(first.text.contains("agents = [\"gemini\", \"claude\", \"codex\"]\n"), "\(first.text)")
        let middle = try ConfigDocument(sample).insertingElement("gemini", into: "general.agents", at: 2)
        #expect(middle.text.contains("agents = [\"claude\", \"gemini\", \"codex\"]\n"), "\(middle.text)")
    }

    @Test func anElementIsAddedToAnArrayOfOneWithASpaceAfterTheComma() throws {
        let one = ConfigDocument("[general]\nagents = [\"claude\"]\n")
        #expect(try one.insertingElement("codex", into: "general.agents").text == "[general]\nagents = [\"claude\", \"codex\"]\n")
        #expect(try one.insertingElement("codex", into: "general.agents", at: 1).text == "[general]\nagents = [\"codex\", \"claude\"]\n")
        // Setting the whole list is laid out the same way.
        #expect(try one.setting("general.agents", to: .strings(["claude", "codex", "gemini"])).text == "[general]\nagents = [\"claude\", \"codex\", \"gemini\"]\n")
        #expect(try one.setting("general.agents", to: .strings([])).text == "[general]\nagents = []\n")
        // An array that was empty gets one element and then another.
        let empty = try ConfigDocument("[general]\nagents = []\n").insertingElement("claude", into: "general.agents").insertingElement("codex", into: "general.agents")
        #expect(empty.text == "[general]\nagents = [\"claude\", \"codex\"]\n")
        // Removing down to one and adding again keeps the spaces.
        let down = try ConfigDocument("[general]\nagents = [\"claude\", \"codex\"]\n").removingElement(at: 1, from: "general.agents")
        #expect(down.text == "[general]\nagents = [\"codex\"]\n")
        #expect(try down.insertingElement("claude", into: "general.agents").text == "[general]\nagents = [\"codex\", \"claude\"]\n")
    }

    @Test func anElementIsAddedInTheLayoutOfAnArrayThatHasSpacesInsideItsBrackets() throws {
        let document = ConfigDocument("[general]\nagents = [ \"claude\",  \"codex\" ]\n")
        #expect(try document.insertingElement("gemini", into: "general.agents", at: 1).text == "[general]\nagents = [ \"gemini\",  \"claude\",  \"codex\" ]\n")
        #expect(try document.insertingElement("gemini", into: "general.agents", at: 2).text == "[general]\nagents = [ \"claude\",  \"gemini\",  \"codex\" ]\n")
        #expect(try document.insertingElement("gemini", into: "general.agents").text == "[general]\nagents = [ \"claude\",  \"codex\",  \"gemini\" ]\n")
    }

    @Test func anElementIsAddedToAnArrayWhoseFirstElementIsOnTheLineOfTheBracket() throws {
        let document = ConfigDocument("[menu]\nitems = [\"open-terminal\",\n         \"open-editor\"]\n")
        #expect(try document.insertingElement("agents", into: "menu.items", at: 1).text == "[menu]\nitems = [\"agents\",\n         \"open-terminal\",\n         \"open-editor\"]\n")
    }

    @Test func anElementIsAddedToAMultiLineArrayOnALineOfItsOwn() throws {
        let edited = try ConfigDocument(sample).insertingElement("copy-path", into: "menu.items")
        #expect(edited.text.contains("    \"agents\",\n    \"copy-path\",\n]"))
        #expect(config(edited.text).menuItems?.last == "copy-path")
    }

    @Test func anElementMovesWithItsCommentsAndNothingElseChanges() throws {
        let edited = try ConfigDocument(sample).movingElement(from: 2, to: 1, in: "menu.items")
        #expect(edited.text.contains("""
        items = [
            # my editor
            "open-editor", # (VS Code)
            "open-terminal",
            "-",
            "agents",
        ]
        """))
        #expect(config(edited.text).menuItems == ["open-editor", "open-terminal", "-", "agents"])
        // Everything outside the array is as it was.
        let around = { (text: String) in text.components(separatedBy: "items = [").first! + "|" + text.components(separatedBy: "]\n").last! }
        #expect(around(edited.text) == around(sample))
    }

    @Test func anElementIsRemovedWithTheCommentLinesAboveItAndTheCommentAtTheEndOfItsLine() throws {
        let edited = try ConfigDocument(sample).removingElement(at: 2, from: "menu.items")
        #expect(!edited.text.contains("my editor") && !edited.text.contains("VS Code"))
        #expect(config(edited.text).menuItems == ["open-terminal", "-", "agents"])
    }

    @Test func movingTheLastElementToTheFrontKeepsTheTrailingCommaOfTheLayout() throws {
        let edited = try ConfigDocument(sample).movingElement(from: 4, to: 1, in: "menu.items")
        #expect(edited.text.contains("    \"agents\",\n    \"open-terminal\",\n"))
        #expect(edited.text.contains("    \"-\",\n]"))
    }

    @Test func aTakenApartArrayIsPutBackTogetherUnchanged() {
        for raw in ["[]", "[\"a\"]", "[ \"a\", \"b\" ]", "[\n]", "[\n    \"a\", # one\n    \"b\"\n]", "[\n    # first\n\n    \"a\",\n    \"b\",\n    # last\n]", "['x', \"y\"]", "[1, 2]"] {
            #expect(TOMLArrayText(raw)?.rendered() == raw, "\(raw.debugDescription)")
        }
        #expect(TOMLArrayText("[[1], [2]]") == nil, "nested arrays are not read")
        #expect(TOMLArrayText("[\"a\" \"b\"]") == nil, "two elements without a comma are not an array")
    }

    @Test func aWholeArrayIsSetInTheLayoutOfTheOneItReplaces() throws {
        let one = try ConfigDocument(sample).setting("general.agents", to: .strings(["gemini"]))
        #expect(one.text.contains("agents = [\"gemini\"]\n"))
        let many = try ConfigDocument(sample).setting("menu.items", to: .strings(["agents", "-", "open-terminal"]))
        #expect(many.text.contains("items = [\n    \"agents\",\n    \"-\",\n    \"open-terminal\",\n]"))
        let emptied = try ConfigDocument(sample).setting("general.agents", to: .strings([]))
        #expect(emptied.text.contains("agents = []\n") && config(emptied.text).enabledAgents.isEmpty)
    }

    // MARK: What is refused

    @Test func anEditIsRefusedWhenItWouldNotBeAnEditOfTheSettingsItNames() {
        #expect(throws: ConfigDocument.EditError.unknownKey("general.terminl")) { try ConfigDocument(sample).setting("general.terminl", to: .string("x")) }
        #expect(throws: ConfigDocument.EditError.invalidPath("general..terminal")) { try ConfigDocument(sample).setting("general..terminal", to: .string("x")) }
        #expect(throws: ConfigDocument.EditError.unknownKey("preset.title")) { try ConfigDocument(sample).setting("preset.title", to: .string("x")) }
        #expect(throws: ConfigDocument.EditError.wrongKind(path: "general.terminal", expected: "text")) { try ConfigDocument(sample).setting("general.terminal", to: .boolean(true)) }
        #expect(throws: ConfigDocument.EditError.wrongKind(path: "general", expected: "a table, which is not a value")) { try ConfigDocument(sample).setting("general", to: .string("x")) }
        #expect(throws: ConfigDocument.EditError.invalidValue(path: "general.terminal_placement", reason: "it is one of window, tab, split-right, split-down")) {
            try ConfigDocument(sample).setting("general.terminal_placement", to: .string("floating"))
        }
    }

    @Test func anEditPastTheEndOrOfSomethingThatIsNotThereIsRefused() {
        #expect(throws: ConfigDocument.EditError.outOfRange(path: "menu.items", position: 9, count: 4)) { try ConfigDocument(sample).removingElement(at: 9, from: "menu.items") }
        #expect(throws: ConfigDocument.EditError.outOfRange(path: "menu.items", position: 6, count: 4)) { try ConfigDocument(sample).insertingElement("x", into: "menu.items", at: 6) }
        #expect(throws: ConfigDocument.EditError.outOfRange(path: "menu.items", position: 0, count: 4)) { try ConfigDocument(sample).movingElement(from: 0, to: 1, in: "menu.items") }
        #expect(throws: ConfigDocument.EditError.notFound("general.editor")) { try ConfigDocument("[general]\nterminal = \"ghostty\"\n").removing("general.editor") }
        #expect(throws: ConfigDocument.EditError.notFound("preset.2")) { try ConfigDocument(sample).setting("preset.2.agent", to: .string("codex")) }
        #expect(throws: ConfigDocument.EditError.wrongKind(path: "general.terminal", expected: "text")) { try ConfigDocument(sample).insertingElement("x", into: "general.terminal") }
    }

    @Test func aConfigThatAlreadyHasAnErrorIsNotEdited() {
        let broken = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"\n"
        #expect(throws: (any Error).self) { try ConfigDocument(broken).setting("general.editor", to: .string("zed")) }
        let semantic = "[general]\nterminal_placement = \"floating\"\n"
        #expect(throws: (any Error).self) { try ConfigDocument(semantic).setting("general.editor", to: .string("zed")) }
    }

    @Test func aKeyInsideAnInlineTableIsChangedWhereItIsWrittenButNeverAddedTo() throws {
        let inline = "general = { terminal = \"ghostty\" }\n"
        #expect(try ConfigDocument(inline).setting("general.terminal", to: .string("iterm")).text == "general = { terminal = \"iterm\" }\n")
        #expect(throws: ConfigDocument.EditError.inlineTable("general")) { try ConfigDocument(inline).setting("general.editor", to: .string("zed")) }
        #expect(throws: ConfigDocument.EditError.inlineTable("general.terminal")) { try ConfigDocument(inline).removing("general.terminal") }
    }

    @Test func aChangeThatMakesTheConfigInvalidIsRefusedBeforeAnythingIsWritten() {
        // An id has to be lowercase letters, digits and dashes.
        #expect(throws: (any Error).self) { try ConfigDocument(sample).setting("preset.1.id", to: .string("Review Me")) }
        #expect(throws: (any Error).self) { try ConfigDocument(sample).setting("preset.1.max_files", to: .integer(500)) }
    }

    @Test func aWholeTextReplacesTheOldOneWhenItReads() throws {
        let text = "# New.\n[general]\nterminal = \"iterm\" # mine\n"
        let replaced = try ConfigDocument(sample).replacingText(text)
        #expect(replaced.text == text)
        #expect(try ConfigDocument(sample).replacingText("").text == "", "an empty config is a config")
        // A key the schema does not know is a warning, which the person reads, and not a reason to refuse the text.
        #expect(try ConfigDocument(sample).replacingText("[general]\nunknown_key = 1\n").text.contains("unknown_key"))
    }

    @Test func aTextThatDoesNotReadIsRefusedWithTheFirstError() {
        #expect(throws: ConfigDocument.EditError.self) { try ConfigDocument(sample).replacingText("[general\n") }
        do {
            _ = try ConfigDocument(sample).replacingText("[general]\nterminal = \"nonsense\"\n")
            Issue.record("accepted")
        } catch ConfigDocument.EditError.wouldBeInvalid(let message) {
            #expect(message.hasPrefix("line 2: [general.terminal] unknown terminal \"nonsense\""), "\(message)")
        } catch {
            Issue.record("\(error)")
        }
    }

    @Test func aTextThatDoesNotReadCanBeReplacedByOneThatDoes() throws {
        // The other edits will not touch a text with an error; this is how it is put right.
        let broken = ConfigDocument("[general\nterminal = \"ghostty\"\n")
        #expect(throws: ConfigDocument.EditError.self) { try broken.setting("general.terminal", to: .string("iterm")) }
        #expect(try broken.replacingText("[general]\nterminal = \"ghostty\"\n").text == "[general]\nterminal = \"ghostty\"\n")
    }

    @Test func positionsOfEntriesAreFoundByID() {
        let two = sample + "\n[[preset]]\nid = \"explain\"\ntitle = \"Explain\"\nprompt = \"Explain {files}\"\n"
        #expect(ConfigDocument(two).position(ofEntryWithID: "explain", in: "preset") == 2)
        #expect(ConfigDocument(two).position(ofEntryWithID: "nope", in: "preset") == nil)
        #expect(ConfigDocument(two).entryCount(of: "preset") == 2)
    }
}
