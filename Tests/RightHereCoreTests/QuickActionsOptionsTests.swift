import Foundation
import Testing
@testable import RightHereCore

private func config(_ text: String) -> Config { ConfigParser.parse(text).config }

@Suite("QuickActionsOptions: the Quick Actions as rows to edit")
struct QuickActionsOptionsTests {
    private let facts = FakeSystemFacts(applications: ["com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"), "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app")])

    private func state(_ text: String = "[general]\nterminal = \"ghostty\"\neditor = \"vscode\"\nagents = [\"claude\"]\n", listed: [String]? = nil) -> QuickActionsState {
        QuickActionsOptions.state(config: config(text), facts: facts, localizer: .english, listed: listed)
    }

    private func apply(_ operations: [ConfigOperation], to text: String) throws -> Config {
        var document = ConfigDocument(text)
        for operation in operations { document = try operation.apply(to: document) }
        return config(document.text)
    }

    @Test func theDefaultListIsTheRowsAndWhatCanStillBeAddedIsTheChoices() {
        let shown = state()
        #expect(shown.rows.map(\.id) == ["open.terminal", "open.editor", "agent.claude", "new-file.md", "copy-path.absolute", "copy-path.git-relative"])
        #expect(shown.list.usesDefaults && shown.list.isExact && shown.rows.allSatisfy { $0.title != $0.id })
        #expect(shown.choices.map(\.id).contains("copy-path.name") && !shown.choices.map(\.id).contains("open.terminal") && shown.choices.allSatisfy { !shown.rows.map(\.id).contains($0.id) })
    }

    @Test func theFirstChangeWritesTheDefaultListAndThenChangesIt() throws {
        let shown = state()
        let defaults = shown.rows.map(\.id)
        let added = QuickActionsOptions.operations(adding: "copy-path.name", to: shown)
        #expect(added == [.expect(nil, in: "services.items"), .set("services.items", .strings(defaults)), .insert("copy-path.name", into: "services.items", at: nil)])
        let text = "[general]\nterminal = \"ghostty\"\neditor = \"vscode\"\nagents = [\"claude\"]\n"
        #expect(try apply(added, to: text).serviceItems == defaults + ["copy-path.name"])
        #expect(try apply(QuickActionsOptions.operations(removingAt: 1, from: shown), to: text).serviceItems == Array(defaults.dropFirst()))
        #expect(try apply(QuickActionsOptions.operations(moving: [5], to: 0, in: shown), to: text).serviceItems == ["copy-path.git-relative"] + defaults.dropLast())
        #expect(QuickActionsOptions.operations(adding: "open.terminal", to: shown).isEmpty && QuickActionsOptions.operations(removingAt: 9, from: shown).isEmpty)
    }

    @Test func aWrittenListIsChangedByPlaceAndOneThatTheConfigReadsAnotherWayIsNot() throws {
        let text = "[services]\nitems = [\"open.terminal\", \"agent.claude\", \"copy-path.name\"]\n"
        let shown = state(text, listed: ["open.terminal", "agent.claude", "copy-path.name"])
        #expect(shown.rows.map(\.id) == ["open.terminal", "agent.claude", "copy-path.name"] && !shown.list.usesDefaults && shown.list.isExact)
        let removed = QuickActionsOptions.operations(removingAt: 2, from: shown)
        #expect(removed == [.expect(["open.terminal", "agent.claude", "copy-path.name"], in: "services.items"), .remove(at: 2, from: "services.items")])
        #expect(try apply(removed, to: text).serviceItems == ["open.terminal", "copy-path.name"])
        // The config leaves an id that is no action out of what it reads, so the rows are not the file's list: nothing is changed by place, and the page says so.
        let odd = "[services]\nitems = [\"open.terminal\", \"nonsense\", \"copy-path.name\"]\n"
        let unlike = state(odd, listed: ["open.terminal", "nonsense", "copy-path.name"])
        #expect(unlike.rows.map(\.id) == ["open.terminal", "copy-path.name"] && !unlike.list.isExact && QuickActionsOptions.operations(removingAt: 1, from: unlike).isEmpty)
        let elsewhere = state(text, listed: ["open.terminal"])
        #expect(QuickActionsOptions.operations(removingAt: 1, from: elsewhere).isEmpty)
    }
}
