import Foundation
import Testing
@testable import RightHereCore

/// How many lines a text has, as a person counts them: a final line break ends the last line.
private func lineCount(_ text: String) -> Int {
    let breaks = text.utf8.filter { $0 == UInt8(ascii: "\n") }.count
    return max(1, text.isEmpty || text.hasSuffix("\n") ? breaks : breaks + 1)
}

private struct Case: CustomTestStringConvertible {
    var name: String
    var text: String
    var line: Int
    var says: String
    var testDescription: String { name }
}

@Suite("TOML syntax errors say what is wrong and where")
struct TOMLSyntaxTests {
    /// Each text is refused by the TOML library; the library's own sentence for it is what the message is mapped from, so a
    /// library that rephrases one fails here. `line` is where the person should look.
    private static let cases: [Case] = [
        Case(name: "an array that is never closed", text: "version = 1\n\n[general]\nterminal = \"ghostty\"\neditor = \"vscode\"\nagents = [\"claude\", \"codex\"\n", line: 6, says: "array not closed: missing `]`"),
        Case(name: "the same without a final line break", text: "version = 1\n[general]\nagents = [\"claude\", \"codex\"", line: 3, says: "array not closed: missing `]`"),
        Case(name: "an array not closed, then a setting", text: "[general]\nagents = [\"claude\", \"codex\"\nterminal = \"ghostty\"\n", line: 2, says: "array not closed: missing `]` (line 3 starts something else)"),
        Case(name: "an array not closed, then a table", text: "[general]\nagents = [\"claude\"\n[menu]\nitems = []\n", line: 2, says: "array not closed: missing `]` (line 3 starts something else)"),
        Case(name: "an array that opens on one line and never closes", text: "a = [\n\"x\",\n\"y\"\nb = 1\n", line: 1, says: "array not closed: missing `]` (line 4 starts something else)"),
        Case(name: "an array of arrays whose outer bracket is missing", text: "x = [[1, 2], [3, 4]\n", line: 1, says: "array not closed: missing `]`"),
        Case(name: "no comma between two items on a line", text: "x = [\"a\" \"b\"]\n", line: 1, says: "missing `,` between the items of this array"),
        Case(name: "no comma between two lines of an array", text: "x = [\n\"a\"\n\"b\"\n]\n", line: 2, says: "missing `,` after this item of the array"),
        Case(name: "an inline table that is never closed", text: "x = { a = 1\n", line: 1, says: "inline table not closed: missing `}`"),
        Case(name: "no comma between inline table entries", text: "x = { a = 1 b = 2 }\n", line: 1, says: "missing `,` between the items of this inline table"),
        Case(name: "a table header without its bracket", text: "[general\nterminal = \"ghostty\"\n", line: 1, says: "table header not closed: missing `]`"),
        Case(name: "the same at the end of the file", text: "[general", line: 1, says: "table header not closed: missing `]`"),
        Case(name: "a [[table]] header without its brackets", text: "[[app]\nid = \"x\"\n", line: 1, says: "table header not closed: missing `]]`"),
        Case(name: "a header with no name", text: "[]\nx = 1\n", line: 1, says: "a table header needs a name"),
        Case(name: "nothing after the equals sign", text: "[general]\nterminal =\n", line: 2, says: "a value is missing or misplaced"),
        Case(name: "a stray comma in an array", text: "x = [,]\n", line: 1, says: "a value is missing or misplaced"),
        Case(name: "no equals sign", text: "[general]\nterminal \"ghostty\"\n", line: 2, says: "missing `=` after the key"),
        Case(name: "a key with a space in it", text: "[general]\nter minal = \"x\"\n", line: 2, says: "missing `=` after the key"),
        Case(name: "text after a value", text: "[general]\nterminal = \"x\" y\n", line: 2, says: "extra text after the value on the same line"),
        Case(name: "text after a header", text: "[general] x\n", line: 1, says: "extra text after the table header"),
        Case(name: "a quote that is never closed", text: "[general]\nterminal = \"ghostty\n", line: 2, says: "text in \"double quotes\" is not closed"),
        Case(name: "a single quote that is never closed", text: "[general]\nterminal = 'ghostty\n", line: 2, says: "text in 'single quotes' is not closed"),
        Case(name: "triple quotes that are never closed", text: "[general]\nterminal = \"\"\"ghostty\n", line: 2, says: "text that starts with `\"\"\"` is never closed"),
        Case(name: "the same table twice", text: "[general]\nterminal = \"a\"\n[general]\neditor = \"b\"\n", line: 3, says: "this key or table is defined twice"),
        Case(name: "the same key twice", text: "[general]\nterminal = \"a\"\nterminal = \"b\"\n", line: 3, says: "this key is already set in this table"),
        Case(name: "a table that is also a value", text: "general = 1\n[general]\nx = 1\n", line: 2, says: "this key or table is defined twice"),
        Case(name: "a table added to an inline table", text: "x = { a = 1 }\n[x]\nb = 2\n", line: 2, says: "this key or table is defined twice"),
        Case(name: "a lone carriage return", text: "x = 1\r y = 2\n", line: 1, says: "a carriage return without a line feed"),
        Case(name: "a control character in a comment", text: "# bad \u{01} comment\nx = 1\n", line: 1, says: "a control character in a comment"),
    ]

    @Test("a refused text gets the line of the trouble and a message in plain words", arguments: cases)
    private func explained(_ c: Case) throws {
        let result = ConfigParser.parse(c.text)
        let error = try #require(result.diagnostics.first, "the library accepted \(c.text.debugDescription)")
        #expect(result.diagnostics.count == 1 && error.severity == .error && error.path == "")
        #expect(error.line == c.line, "\(error.line.map(String.init) ?? "nil") for \(c.text.debugDescription): \(error.message)")
        #expect(error.message.hasPrefix("TOML syntax error: " + c.says), "\(error.message)")
        #expect(error.message.hasSuffix(". Defaults apply until it is fixed."), "\(error.message)")
        #expect(!error.message.contains("Internal error") && !error.message.contains("Usual causes"), "\(error.message)")
        #expect(result.config == .default)
    }

    @Test func theLineIsNeverPastTheEndOfTheFile() {
        // The library counts the line break it adds, and the end of the text, as lines: 8 for a file of 6.
        for text in ["a = [\"x\"\n", "a = [\"x\"", "a = [\"x\"\n\n\n", "x = {", "x = {\n"] {
            let line = ConfigParser.parse(text).diagnostics.first?.line
            #expect(line.map { $0 >= 1 && $0 <= lineCount(text) } == true, "\(line.map(String.init) ?? "nil") for \(text.debugDescription), which has \(lineCount(text)) lines")
        }
    }

    @Test func twoValuesSideBySideAreTwoItemsWithoutAComma() throws {
        for text in ["x = [1 2]\n", "x = [a b]\n", "x = { a = 1 b }\n", "x = { a = 1 2 }\n"] {
            let error = try #require(ConfigParser.parse(text).diagnostics.first)
            #expect(error.line == 1 && error.message.hasPrefix("TOML syntax error: missing `,` between the items of this"), "\(text.debugDescription): \(error.message)")
        }
        // A date and a time are one value, written with a space.
        #expect(!ConfigParser.parse("x = [1979-05-27 07:32:00]\n").diagnostics.contains { $0.message.hasPrefix("TOML syntax error") })
    }

    @Test func anInternalErrorTheOutlineCannotExplainIsSaidHonestly() throws {
        // Nothing the outline can point at: the message is the general one, on the line the library gave.
        let error = try #require(ConfigParser.parse("x = [\"a\" ,, \"b\" \"c\"\n]\n").diagnostics.first)
        #expect(!error.message.contains("Internal error") && error.line != nil, "\(error)")
    }

    @Test func aFileOfHundredsOfPrefixesNeverSaysInternalErrorOrPointsPastTheEnd() {
        let template = ConfigTemplate.render(DetectedEnvironment(terminal: "ghostty", editor: "vscode", agents: ["claude", "codex"]))
        let full = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\",\n  \"codex\"]\n[[app]]\nid = \"x\"\nname = \"X\"\nbundle_id = \"a.b\"\n[agent.mine]\nname = \"M\"\ncommand = \"m\"\n[[agent.mine.variant]]\nid = \"v\"\ntitle = \"V\"\narguments = [\"--a\", \"--b\"]\n"
        var checked = 0
        for text in [template, full] {
            let bytes = Array(text.utf8)
            for length in 0...bytes.count {
                guard let prefix = String(bytes: bytes[0..<length], encoding: .utf8) else { continue }
                for error in ConfigParser.parse(prefix).diagnostics where error.path == "" && error.message.hasPrefix("TOML syntax error") {
                    checked += 1
                    #expect(!error.message.contains("Internal error"), "\(prefix.debugDescription): \(error.message)")
                    #expect(error.line.map { $0 >= 1 && $0 <= lineCount(prefix) } == true, "\(prefix.debugDescription): line \(error.line.map(String.init) ?? "nil") of \(lineCount(prefix))")
                }
            }
        }
        #expect(checked > 50, "only \(checked) prefixes were refused; the corpus tests nothing")
    }

    @Test func aProblemInTheOverlayIsAtTheOverlaysLineAndLeavesTheFileOut() throws {
        let base = "[general]\nterminal = \"ghostty\"\n"
        let overlay = "# per machine\n[general]\nagents = [\"claude\"\n"
        let result = ConfigLayers.load(base: .text(base), local: .text(overlay))
        let error = try #require(result.diagnostics.first)
        #expect(error.file == "config.local.toml" && error.line == 3, "\(error)")
        #expect(error.message == "TOML syntax error: array not closed: missing `]`. This file is left out until it is fixed.", "\(error.message)")
        #expect(result.config.terminal == "ghostty")
        // The same mistake in the shared file, with an overlay beside it: the defaults and the overlay apply.
        let broken = ConfigLayers.load(base: .text(overlay), local: .text("[general]\nterminal = \"terminal\"\n"))
        let first = try #require(broken.diagnostics.first)
        #expect(first.file == nil && first.line == 3 && first.message.hasSuffix(". Defaults apply until it is fixed."), "\(first)")
        #expect(broken.config.terminal == "terminal")
    }
}

@Suite("TOMLOutline")
struct TOMLOutlineTests {
    private let text = """
    version = 1

    [general]
    terminal = "ghostty"   # the default
    agents = ["claude",
              "codex"]

    [[app]]
    id = "one"
    name = "One"

    [[app]]
    id = "two"
    notes = '''
    [fake]
    text = [
    '''

    [agent.claude]
    command = "claude"
    [[agent.claude.variant]]
    id = "fast"
    [[agent.claude.variant]]
    id = "slow"

    [agent.codex]
    [[agent.codex.variant]]
    id = "last"

    "quoted key"."with\\tescape" = 1
    dotted.key.here = 2
    """

    @Test func everyKeyAndTableIsAtItsLine() {
        let outline = TOMLOutline(text)
        func line(_ path: String) -> Int? { outline.lines[path] }
        #expect(line("version") == 1)
        #expect(line("general") == 3 && line("general.terminal") == 4 && line("general.agents") == 5)
        #expect(line("app.1") == 8 && line("app.1.id") == 9 && line("app.1.name") == 10)
        #expect(line("app.2") == 12 && line("app.2.id") == 13 && line("app.2.notes") == 14)
        #expect(line("agent.claude") == 19 && line("agent.claude.command") == 20)
        #expect(line("agent.claude.variant.1") == 21 && line("agent.claude.variant.1.id") == 22)
        #expect(line("agent.claude.variant.2") == 23 && line("agent.claude.variant.2.id") == 24)
        // Another agent's variants are counted afresh: its first is the first.
        #expect(line("agent.codex.variant.1") == 27 && line("agent.codex.variant.1.id") == 28)
        // Keys after a header belong to its table, quoted or dotted ones too, and a key's escapes are read.
        #expect(line("agent.codex.variant.1.quoted key.with\\tescape") == 30)
        #expect(line("agent.codex.variant.1.dotted.key.here") == 31)
        // Nothing in a multi-line string or a multi-line array is taken for a statement.
        #expect(line("fake") == nil && line("app.2.text") == nil)
    }

    @Test func aPathWithoutALineGetsTheNearestOneAbove() {
        let outline = TOMLOutline(text)
        #expect(outline.line(of: "general.agents") == 5)
        #expect(outline.line(of: "general.nothing") == 3)
        #expect(outline.line(of: "app.2.id") == 13)
        // An entry that is not there falls back to the array's first one: `[[app]]` as a whole is at line 8.
        #expect(outline.line(of: "app") == 8 && outline.line(of: "app.3.id") == 8)
        #expect(outline.line(of: "nothing") == nil)
    }

    @Test func aValueIsKeptAsWritten() {
        let outline = TOMLOutline(text)
        #expect(outline.rawValue(of: "general.terminal") == "\"ghostty\"")
        #expect(outline.rawValue(of: "general.agents") == "[\"claude\",\n          \"codex\"]")
        #expect(outline.rawValue(of: "version") == "1")
        #expect(outline.rawValue(of: "general") == nil)
    }

    @Test func theKeysOfAnInlineTableAreKnownAsTheKeysOfATable() throws {
        let inline = """
        general = { terminal = "ghostty", agents = ["claude",
                    "codex"], nested = { deep = 1 }, "quoted" = 'x' }
        menu = { items = [{ id = "a" }] }
        """
        let outline = TOMLOutline(inline)
        #expect(outline.lines["general"] == 1 && outline.lines["general.terminal"] == 1 && outline.lines["general.agents"] == 1)
        #expect(outline.lines["general.nested"] == 2 && outline.lines["general.nested.deep"] == 2 && outline.lines["general.quoted"] == 2)
        #expect(outline.rawValue(of: "general.terminal") == "\"ghostty\"")
        #expect(outline.rawValue(of: "general.agents") == "[\"claude\",\n            \"codex\"]")
        #expect(outline.rawValue(of: "general.nested.deep") == "1" && outline.rawValue(of: "general.quoted") == "'x'")
        #expect(outline.rawValue(of: "general")?.hasPrefix("{ terminal") == true, "the table as a whole is still a value of its key")
        // A table inside an array has no path of its own.
        #expect(outline.lines["menu.items.1.id"] == nil && outline.lines["menu.items.id"] == nil && outline.rawValue(of: "menu.items") != nil)
        // Every key the library reads is in the outline, the keys of an inline table included.
        let tree = try #require(ConfigParser.readTree(inline).tree)
        func check(_ value: TOMLValue, path: [String]) {
            switch value {
            case .table(let nested): for (key, child) in nested { check(child, path: path + [key]) }
            case .array: break
            default: #expect(outline.lines[path.joined(separator: ".")] != nil, "no line for \(path.joined(separator: "."))")
            }
        }
        check(.table(tree), path: [])
    }

    @Test func aTextThatIsFineHasNoProblem() {
        #expect(TOMLOutline(text).problem == nil)
        #expect(TOMLOutline("").problem == nil)
        #expect(TOMLOutline("").lineCount == 1)
        #expect(TOMLOutline("a = 1").lineCount == 1 && TOMLOutline("a = 1\n").lineCount == 1 && TOMLOutline("a = 1\n\n").lineCount == 2)
    }

    @Test("a text the library reads has no problem, whatever it holds", arguments: [
        "x = [\n  1, 2,\n  3,\n]\n", "x = { a = 1, b = { c = [1, 2] } }\n", "x = [ { a = 1 }, { a = 2 } ]\n", "x = \"\"\"\na [ b\n\"\"\"\n", "x = ''' [ '''\n",
        "x = 1979-05-27 07:32:00\n", "x = 'a # b' # c\n", "[a.b]\n[a.c]\n", "[[a]]\n[a.b]\n[[a]]\n[a.b]\n", "x = [ ]\n", "x = { }\n", "# [ not a table\n"
    ])
    func noFalseProblems(text: String) {
        #expect(TOMLOutline(text).problem == nil, "\(TOMLOutline(text).problem.map(\.message) ?? "")")
        #expect(!ConfigParser.parse(text).diagnostics.contains { $0.message.hasPrefix("TOML syntax error") }, "the library refuses what the outline was said to accept")
    }

    @Test func theOutlineAndTheLibraryAgreeOnWhatIsWhere() throws {
        // Every path the library reads is in the outline (except tables that exist only as the parents of others).
        let tree = try #require(ConfigParser.readTree(text).tree)
        let outline = TOMLOutline(text)
        func check(_ value: TOMLValue, path: [String]) {
            switch value {
            case .table(let nested):
                for (key, child) in nested { check(child, path: path + [key]) }
            case .array(let items) where value.isTableArray:
                for (index, item) in items.enumerated() { check(item, path: path + [String(index + 1)]) }
            default:
                let spelled = path.map(\.withControlCharactersEscaped).joined(separator: ".")
                #expect(outline.lines[spelled] != nil, "no line for \(spelled)")
            }
        }
        check(.table(tree), path: [])
    }
}

@Suite("TOMLOutline: random text")
struct TOMLOutlineFuzzTests {
    /// Deterministic, so a failing text can be replayed from its seed.
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @Test func noTextOfTheCharactersThatMatterMakesTheOutlineTrapOrPointOutsideTheFile() {
        let pieces = ["[", "]", "[[", "]]", "{", "}", "=", ",", ".", "\"", "'", "\"\"\"", "'''", "#", "\n", "\r\n", " ", "\t", "a", "b-c", "1", "\\", "\\\"", "é", "💥", "=\n", "a = ", "[a]\n", "[[a]]\n", "x = [", "y = {", "\"k\" = ", "'''\n"]
        var random = SplitMix64(state: 7)
        for _ in 0..<20_000 {
            let text = (0..<Int(random.next() % 40)).map { _ in pieces[Int(random.next() % UInt64(pieces.count))] }.joined()
            let outline = TOMLOutline(text)
            for line in outline.lines.values { #expect(line >= 1 && line <= max(1, outline.lineCount + 1), "\(text.debugDescription)") }
            if let problem = outline.problem { #expect(problem.line >= 1 && problem.line <= outline.lineCount, "\(text.debugDescription): \(problem)") }
            _ = outline.line(of: "a.b")
            _ = outline.rawValue(of: "a")
            _ = outline.clamped(0)
        }
    }

    @Test func aRandomConfigTheLibraryReadsHasNoProblemAndEveryKeyHasALine() throws {
        var checked = 0
        for text in randomConfigTexts(seed: 31, count: 600) {
            guard ConfigParser.canBeRead(text), let tree = ConfigParser.readTree(text).tree else { continue }
            let outline = TOMLOutline(text)
            #expect(outline.problem == nil, "\(text.debugDescription): \(outline.problem.map(\.message) ?? "")")
            func check(_ value: TOMLValue, path: [String]) {
                switch value {
                case .table(let nested): for (key, child) in nested { check(child, path: path + [key]) }
                case .array(let items) where value.isTableArray: for (index, item) in items.enumerated() { check(item, path: path + [String(index + 1)]) }
                default:
                    let spelled = path.map(\.withControlCharactersEscaped).joined(separator: ".")
                    #expect(outline.line(of: spelled) != nil, "no line for \(spelled) in \(text.debugDescription)")
                }
            }
            check(.table(tree), path: [])
            checked += 1
        }
        #expect(checked > 100, "only \(checked) of the random configs could be read; the corpus tests nothing")
    }

    @Test func theDiagnosticsOfARandomConfigAreInsideTheFileAndInOrder() {
        for text in randomConfigTexts(seed: 77, count: 600) {
            let lines = max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
            let result = ConfigParser.parse(text)
            var previous = 0
            for diagnostic in result.diagnostics {
                if let line = diagnostic.line {
                    #expect(line >= 1 && line <= lines, "line \(line) of \(lines) for \(diagnostic.message) in \(text.debugDescription)")
                    #expect(line >= previous, "\(diagnostic.message) is out of order in \(text.debugDescription)")
                    previous = line
                }
            }
        }
    }
}
