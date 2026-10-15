import Foundation
import Testing
@testable import RightHereCore

/// Does what an edit says it does, to the text of a file, and nothing else: so that an instruction the product gives (to a person,
/// or to an AI agent that follows it to the letter) really leads to the config that was asked for.
private func apply(_ edit: ConfigEdit, to text: String) -> String {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let assignment = "\(edit.key.split(separator: ".").last ?? "") = \(edit.value)"
    switch (edit.kind, edit.line) {
    case (.change, let line?):
        let current = lines[line - 1]
        let range = current.range(of: edit.current ?? "")!
        lines[line - 1] = current.replacingCharacters(in: range, with: edit.value)
    case (.add, let line?) where lines[line - 1].trimmingCharacters(in: .whitespaces).hasPrefix("#"):
        lines[line - 1] = assignment
    case (.add, let line?):
        lines.insert(assignment, at: line)
    case (_, nil):
        lines += ["", "[general]", assignment]
    }
    return lines.joined(separator: "\n")
}

private func needed(_ choices: SetupChoices, base: String?, local: String? = nil) -> (edits: [ConfigEdit], config: Config) {
    let config = ConfigLayers.load(base: base.map { .text($0) } ?? .absent, local: local.map { .text($0) } ?? .absent).config
    return (ConfigEdits.needed(for: choices, config: config, base: base, local: local), config)
}

@Suite("The edits that make an existing config say what a person asked for")
struct ConfigEditsTests {
    static let own = """
    # My own notes at the top.
    version = 1

    [general]
    terminal = "ghostty"   # my favourite
    editor = "vscode"
    agents = ["claude"]

    # My menu, which I like.
    [menu]
    items = ["open.terminal", "agents"]

    """

    @Test func aConfigThatAlreadySaysItNeedsNoEdit() {
        let (edits, _) = needed(SetupChoices(terminal: "ghostty", editor: "vscode", agents: ["claude"]), base: Self.own)
        #expect(edits.isEmpty)
        #expect(needed(SetupChoices(), base: Self.own).edits.isEmpty)
    }

    @Test func aSecondAgentIsOneLineWithItsNumberAndBothValues() throws {
        let (edits, _) = needed(SetupChoices(agents: ["claude", "codex"]), base: Self.own)
        let edit = try #require(edits.first)
        #expect(edits.count == 1)
        #expect(edit.kind == .change)
        #expect(edit.file == "config.toml")
        #expect(edit.key == "general.agents")
        #expect(edit.line == 7)
        #expect(edit.current == "[\"claude\"]")
        #expect(edit.value == "[\"claude\", \"codex\"]")
        #expect(edit.instruction == "In config.toml on line 7, change agents = [\"claude\"] to agents = [\"claude\", \"codex\"].")
    }

    @Test func followingTheEditChangesOnlyThatLineAndTheConfigThenSaysWhatWasAsked() {
        let choices = SetupChoices(terminal: "terminal", editor: "zed", agents: ["claude", "codex"])
        let (edits, _) = needed(choices, base: Self.own)
        #expect(edits.count == 3)
        var text = Self.own
        // From the bottom up, so that adding a line does not move the lines still to change.
        for edit in edits.sorted(by: { ($0.line ?? 0) > ($1.line ?? 0) }) { text = apply(edit, to: text) }
        let before = Self.own.split(separator: "\n", omittingEmptySubsequences: false)
        let after = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(before.count == after.count)
        #expect(zip(before, after).filter { $0 != $1 }.count == 3, "only the three lines named may differ")
        #expect(text.contains("# My own notes at the top."))
        #expect(text.contains("# My menu, which I like."))
        #expect(text.contains("   # my favourite"))
        let (again, config) = needed(choices, base: text)
        #expect(again.isEmpty, "\(again.map(\.instruction))")
        #expect(config.terminal == "terminal" && config.editor == "zed" && config.enabledAgents == ["claude", "codex"])
    }

    @Test func aSettingThatIsOnlyACommentedExampleIsReplacedWhereTheExampleIs() throws {
        let fresh = ConfigTemplate.render(DetectedEnvironment())
        let (edits, _) = needed(SetupChoices(terminal: "ghostty", editor: "zed", agents: ["claude", "codex"]), base: fresh)
        #expect(edits.count == 3)
        for edit in edits { #expect(edit.kind == .add && edit.line != nil, "\(edit)") }
        let agents = try #require(edits.first { $0.key == "general.agents" })
        #expect(agents.instruction.contains("is a commented example of this setting"))
        let lines = fresh.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[(agents.line ?? 1) - 1].hasPrefix("# agents = "))
        var text = fresh
        for edit in edits.sorted(by: { ($0.line ?? 0) > ($1.line ?? 0) }) { text = apply(edit, to: text) }
        let result = ConfigParser.parse(text)
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics)")
        #expect(result.config.terminal == "ghostty" && result.config.editor == "zed" && result.config.enabledAgents == ["claude", "codex"])
    }

    @Test func aSettingMissingFromTheGeneralTableIsAddedUnderItsHeader() throws {
        let base = "version = 1\n\n[general]\neditor = \"vscode\"\n\n[menu]\nitems = [\"agents\"]\n"
        let (edits, _) = needed(SetupChoices(terminal: "ghostty"), base: base)
        let edit = try #require(edits.first)
        #expect(edits.count == 1 && edit.kind == .add && edit.line == 3)
        #expect(edit.instruction == "In config.toml, add the line terminal = \"ghostty\" under [general] (line 3).")
        let result = ConfigParser.parse(apply(edit, to: base))
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics)")
        #expect(result.config.terminal == "ghostty")
    }

    @Test func aFileWithoutAGeneralTableGetsOneAtTheEnd() throws {
        let base = "version = 1\n\n[menu]\nitems = [\"agents\"]\n"
        let (edits, _) = needed(SetupChoices(agents: ["claude"]), base: base)
        let edit = try #require(edits.first)
        #expect(edit.line == nil && edit.kind == .add)
        #expect(edit.instruction == "In config.toml, add a [general] table at the end of the file with the line agents = [\"claude\"].")
        let result = ConfigParser.parse(apply(edit, to: base))
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics)")
        #expect(result.config.enabledAgents == ["claude"])
    }

    @Test func theOverlayDecidesOnThisMacWhenItSetsTheKey() throws {
        let local = "[general]\nagents = [\"codex\"]\n"
        let (edits, config) = needed(SetupChoices(agents: ["claude", "codex"]), base: Self.own, local: local)
        #expect(config.enabledAgents == ["codex"])
        let edit = try #require(edits.first)
        #expect(edits.count == 1)
        #expect(edit.file == "config.local.toml" && edit.line == 2 && edit.current == "[\"codex\"]")
        let (done, merged) = needed(SetupChoices(agents: ["claude", "codex"]), base: Self.own, local: apply(edit, to: local))
        #expect(done.isEmpty)
        #expect(merged.enabledAgents == ["claude", "codex"])
    }

    @Test func aKeyOnlyTheSharedFileSetsIsEditedThere() throws {
        let (edits, _) = needed(SetupChoices(editor: "zed"), base: Self.own, local: "[general]\nterminal = \"terminal\"\n")
        let edit = try #require(edits.first)
        #expect(edit.file == "config.toml" && edit.line == 6 && edit.current == "\"vscode\"")
    }

    @Test func aListThatRunsOverSeveralLinesIsNamedByWhereItStarts() throws {
        let base = "[general]\nagents = [\n  \"claude\",\n  \"codex\",\n]\n"
        let (edits, _) = needed(SetupChoices(agents: ["claude"]), base: base)
        let edit = try #require(edits.first)
        #expect(edit.line == 2 && edit.current?.contains("\n") == true)
        #expect(edit.instruction.contains("the list that starts there (it runs over several lines)"), "\(edit.instruction)")
    }

    @Test func aGeneralTableWrittenInlineIsSaidSo() throws {
        let base = "general = { terminal = \"ghostty\" }\n"
        let (edits, _) = needed(SetupChoices(editor: "zed"), base: base)
        let edit = try #require(edits.first)
        #expect(edit.line == 1)
        #expect(edit.instruction.contains("written inline on line 1"), "\(edit.instruction)")
    }

    @Test func noAgentsAsksForAnEmptyList() throws {
        let (edits, _) = needed(SetupChoices(agents: []), base: Self.own)
        let edit = try #require(edits.first)
        #expect(edit.value == "[]")
        #expect(needed(SetupChoices(agents: []), base: apply(edit, to: Self.own)).edits.isEmpty)
    }

    @Test func theEditsAreJSONForAProgram() throws {
        let (edits, _) = needed(SetupChoices(agents: ["claude", "codex"]), base: Self.own)
        let data = try JSONEncoder().encode(edits)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(object.first?["key"] as? String == "general.agents")
        #expect(object.first?["kind"] as? String == "change")
        #expect(object.first?["line"] as? Int == 7)
    }
}
