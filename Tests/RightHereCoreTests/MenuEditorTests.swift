import Foundation
import Testing
@testable import RightHereCore

private func machine() -> FakeSystemFacts {
    FakeSystemFacts(
        directories: ["/Users/tester/code"],
        applications: ["com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"), "com.apple.Terminal": URL(fileURLWithPath: "/Applications/Terminal.app"),
                       "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app"), "dev.zed.Zed": URL(fileURLWithPath: "/Applications/Zed.app")]
    )
}

private let folder = URL(fileURLWithPath: "/Users/tester/code")
private let background = HereContext(origin: .container, container: folder)

private func config(_ text: String) -> Config { ConfigParser.parse(text).config }

@Suite("MenuBuilder.entries: what each item of the list comes to")
struct MenuBuilderEntriesTests {
    @Test(arguments: [
        "",
        "[menu]\nitems = [\"open-terminal\", \"-\", \"-\", \"copy-path\", \"-\"]\n",
        "[menu]\nitems = [\"-\", \"open-editor\", \"nonsense\", \"copy-path.tilde\", \"open-with\"]\n",
        "[menu]\nitems = []\n",
        "[general]\nagents = [\"claude\", \"codex\"]\n[menu]\nitems = [\"agents\", \"agents-more\", \"-\", \"presets\", \"new-file\"]\n"
    ])
    func theMenuIsTheEntriesJoinedAndTidied(text: String) {
        let builder = MenuBuilder(config: config(text), facts: machine())
        let joined = MenuBuilder.tidy(builder.entries(for: background).flatMap(\.nodes))
        #expect(joined == builder.build(for: background), "\(text)")
    }

    @Test func eachItemKeepsItsPlaceAndMakesWhatItMakes() {
        let builder = MenuBuilder(config: config("[menu]\nitems = [\"open-terminal\", \"-\", \"copy-path.tilde\", \"nonsense\", \"open-editor\", \"-\"]\n"), facts: machine())
        let entries = builder.entries(for: background)
        #expect(entries.map(\.entry) == ["open-terminal", "-", "copy-path.tilde", "nonsense", "open-editor", "-"])
        #expect(entries.map { $0.nodes.map { $0.kind == .separator ? "-" : $0.title } } == [["Open in Ghostty"], ["-"], ["Copy Path: Path from Home (~)"], [], ["Open in Visual Studio Code"], ["-"]])
    }

    @Test func theItemsOfAnotherListAreWhatTheyWouldMake() {
        let builder = MenuBuilder(config: config(""), facts: machine())
        let entries = builder.entries(for: background, items: ["open-with", "copy-path"])
        #expect(entries.map(\.entry) == ["open-with", "copy-path"])
        #expect(entries[1].nodes.first?.title == "Copy Path" && entries[1].nodes.first?.kind == .submenu)
    }
}

@Suite("MenuEditor: the menu as something to edit")
struct MenuEditorTests {
    /// The state of a config file that is read on its own: what the file writes for the list is what the config says.
    private func state(_ text: String = "") -> MenuEditorState {
        MenuEditor.state(config: config(text), facts: machine(), localizer: .english, folder: folder, inFile: try? ConfigDocument(text).elements(of: MenuEditorState.key) ?? nil)
    }

    private let listed = "[menu]\nitems = [\"open-terminal\", \"open-editor\", \"-\", \"copy-path\", \"open-with\", \"nonsense\"]\n"

    @Test func aRowIsAnItemAndWhatItMakes() {
        let state = state(listed)
        #expect(!state.usesDefaults)
        #expect(state.rows.map(\.position) == [1, 2, 3, 4, 5, 6])
        #expect(state.rows.map(\.entry) == ["open-terminal", "open-editor", "-", "copy-path", "open-with", "nonsense"])
        #expect(state.rows.map(\.nodes.count) == [1, 1, 1, 1, 1, 0])
        #expect(state.rows.map(\.isSeparator) == [false, false, true, false, false, false])
        #expect(state.rows.map(\.fallbackTitle) == ["open-terminal", "open-editor", "", "Copy Path", "Open With", "nonsense"])
        #expect(Set(state.rows.map(\.id)).count == 6)
    }

    @Test func twoSeparatorsAreTwoRowsWithTheirOwnIdentity() {
        let state = state("[menu]\nitems = [\"open-terminal\", \"-\", \"copy-path\", \"-\"]\n")
        #expect(state.rows.map(\.id) == ["1:open-terminal", "2:-", "3:copy-path", "4:-"])
    }

    @Test func aConfigThatDoesNotListTheMenuHasTheDefaultOne() {
        let state = state()
        #expect(state.usesDefaults)
        #expect(state.rows.map(\.entry) == MenuBuilder.defaultItems)
        #expect(self.state("[menu]\nitems = [\"copy-path\"]\n").usesDefaults == false)
        #expect(self.state("[menu]\nitems = []\n").usesDefaults == false, "an empty list is a list")
    }

    @Test func whatCanBeAddedIsWhatTheMenuLacks() {
        let state = state(listed)
        let groups = state.choices.filter { $0.section == .group }.map(\.entry)
        #expect(groups == ["agents", "agents-more", "presets", "new-file"], "in the order the editor offers them, without the ones that are in the menu")
        let entries = Set(state.choices.map(\.entry))
        #expect(entries.contains("copy-path.tilde") && entries.contains("copy-path.name") && entries.contains("reveal"))
        #expect(!entries.contains("copy-path") && !entries.contains("open-terminal") && !entries.contains("-"))
        #expect(state.choices.first { $0.entry == "copy-path.tilde" }?.section == .copyPath)
        #expect(state.choices.first { $0.entry == "reveal" }?.section == .reveal)
        // Lines of their own, listed where one check adds them (Not in the Menu), not inside a submenu of Add to Menu.
        #expect(state.choices.first { $0.entry == "repository.copy-link" }?.section == .reveal)
        #expect(state.choices.first { $0.entry == "repository.open-page" }?.section == .reveal)
        #expect(state.choices.first { $0.entry == "new-file.md" }?.section == .newFile)
        #expect(state.choices.first { $0.entry == "open.app.zed" }?.section == .openApp)
        #expect(state.choices.first { $0.entry == "copy-path.tilde" }?.title == "Copy Path: Path from Home (~)")
        // The presets act on selected files and make nothing for a folder; the group still has the symbol its submenu has in the menu.
        #expect(state.choices.first { $0.entry == "presets" }?.icon == .symbol("text.bubble"))
        #expect(state.choices.filter { $0.section == .group }.allSatisfy { $0.icon != nil })
    }

    @Test func whatIsAlreadyInTheMenuIsNotOfferedAgainAndWhatCannotRunIsNotOffered() {
        let state = state("[menu]\nitems = [\"copy-path.tilde\", \"open.app.zed\"]\n")
        let entries = Set(state.choices.map(\.entry))
        #expect(!entries.contains("copy-path.tilde") && !entries.contains("open.app.zed") && entries.contains("copy-path.name"))
        // An action that cannot run on this Mac (its app is not installed) is not offered.
        let cannotRun = ActionRegistry(config: config("[menu]\nitems = [\"copy-path.tilde\", \"open.app.zed\"]\n"), facts: machine(), localizer: .english).catalog().filter { !$0.available }
        #expect(!cannotRun.isEmpty, "the machine of this test has an app that is not installed")
        for action in cannotRun { #expect(!entries.contains(action.id), "\(action.id) cannot run here and is offered") }
        #expect(state.choices.allSatisfy { !$0.title.isEmpty })
    }

    @Test func aGroupIsNamedByWhatItMakesInTheMenu() {
        let state = state("[menu]\nitems = [\"copy-path\"]\n")
        #expect(state.choices.first { $0.entry == "open-terminal" }?.title == "Open in Ghostty")
        #expect(state.choices.first { $0.entry == "open-editor" }?.title == "Open in Visual Studio Code")
        #expect(state.choices.first { $0.entry == "open-with" }?.title == "Open With")
        #expect(state.choices.first { $0.entry == "new-file" }?.title == "New File")
    }

    // MARK: The changes

    /// The list after the changes, read back from the file text the way the config reads it.
    private func apply(_ operations: [ConfigOperation], to text: String) throws -> [String] {
        var document = ConfigDocument(text)
        for operation in operations { document = try operation.apply(to: document) }
        return ConfigParser.parse(document.text).config.menuItems ?? []
    }

    /// What SwiftUI's `onMove` does to an array: the rows at `source` go before the row at `destination`.
    private func moved(_ items: [String], from source: IndexSet, to destination: Int) -> [String] {
        let moving = source.sorted().map { items[$0] }
        var rest = items.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: moving, at: destination - source.filter { $0 < destination }.count)
        return rest
    }

    @Test func aRowDraggedAnywhereEndsWhereSwiftUIWouldPutIt() throws {
        let text = "[menu]\nitems = [\"a1\", \"a2\", \"a3\", \"a4\", \"a5\"]\n".replacingOccurrences(of: "a1", with: "open-terminal").replacingOccurrences(of: "a2", with: "open-editor")
            .replacingOccurrences(of: "a3", with: "open-with").replacingOccurrences(of: "a4", with: "copy-path").replacingOccurrences(of: "a5", with: "new-file")
        let state = state(text)
        let items = state.rows.map(\.entry)
        for from in 0..<items.count {
            for destination in 0...items.count {
                let operations = MenuEditor.operations(moving: IndexSet(integer: from), to: destination, in: state)
                let expected = moved(items, from: IndexSet(integer: from), to: destination)
                #expect(try apply(operations, to: text) == expected, "row \(from) to \(destination)")
                if expected == items { #expect(operations.isEmpty, "a drag that leaves the row where it is writes nothing: \(from) to \(destination)") }
            }
        }
    }

    @Test func severalRowsDraggedTogetherEndWhereSwiftUIWouldPutThem() throws {
        let text = "[menu]\nitems = [\"open-terminal\", \"open-editor\", \"open-with\", \"copy-path\", \"new-file\", \"-\"]\n"
        let state = state(text)
        let items = state.rows.map(\.entry)
        let selections: [IndexSet] = [[0, 1], [1, 3], [0, 2, 4], [2, 3, 4], [0, 5], [1, 2, 3, 4]]
        for source in selections {
            for destination in 0...items.count {
                let expected = moved(items, from: source, to: destination)
                #expect(try apply(MenuEditor.operations(moving: source, to: destination, in: state), to: text) == expected, "\(Array(source)) to \(destination)")
            }
        }
    }

    @Test func aMoveKeepsTheCommentsOfWhatItMoves() throws {
        let text = "[menu]\nitems = [\n    \"open-terminal\", # first\n    # about this\n    \"open-editor\",\n    \"copy-path\",\n]\n"
        let state = state(text)
        var document = ConfigDocument(text)
        for operation in MenuEditor.operations(moving: IndexSet(integer: 2), to: 0, in: state) { document = try operation.apply(to: document) }
        #expect(document.text == "[menu]\nitems = [\n    \"copy-path\",\n    \"open-terminal\", # first\n    # about this\n    \"open-editor\",\n]\n")
    }

    @Test func aDragOutsideTheListIsNothing() {
        let state = state(listed)
        #expect(MenuEditor.operations(moving: [], to: 1, in: state).isEmpty)
        #expect(MenuEditor.operations(moving: [9], to: 1, in: state).isEmpty)
        #expect(MenuEditor.operations(moving: [-1], to: 1, in: state).isEmpty)
        #expect(MenuEditor.operations(moving: [0], to: 99, in: state).isEmpty)
        #expect(MenuEditor.operations(moving: [0], to: -1, in: state).isEmpty)
    }

    @Test func removingARowTakesItsItemOutOfTheList() throws {
        let state = state(listed)
        #expect(MenuEditor.operations(removing: 3, in: state) == [.expect(state.rows.map(\.entry), in: "menu.items"), .remove(at: 3, from: "menu.items")])
        #expect(try apply(MenuEditor.operations(removing: 3, in: state), to: listed) == ["open-terminal", "open-editor", "copy-path", "open-with", "nonsense"])
        for position in [0, 7, -1] { #expect(MenuEditor.operations(removing: position, in: state).isEmpty, "\(position)") }
    }

    @Test func addingPutsTheItemWhereSaidAndAtTheEndWithoutAPlace() throws {
        let state = state(listed)
        #expect(try apply(MenuEditor.operations(adding: "agents", in: state), to: listed).last == "agents")
        #expect(try apply(MenuEditor.operations(adding: "-", at: 2, in: state), to: listed) == ["open-terminal", "-", "open-editor", "-", "copy-path", "open-with", "nonsense"])
        #expect(try apply(MenuEditor.operations(adding: "presets", at: 1, in: state), to: listed).first == "presets")
        #expect(try apply(MenuEditor.operations(adding: "presets", at: 7, in: state), to: listed).last == "presets")
        #expect(MenuEditor.operations(adding: "presets", at: 0, in: state).isEmpty)
        #expect(MenuEditor.operations(adding: "presets", at: 8, in: state).isEmpty)
    }

    @Test func theFirstChangeOfADefaultMenuWritesTheWholeListFirst() throws {
        let state = state()
        #expect(state.usesDefaults)
        let removal = MenuEditor.operations(removing: 2, in: state)
        #expect(removal == [.expect(nil, in: "menu.items"), .set("menu.items", .strings(MenuBuilder.defaultItems)), .remove(at: 2, from: "menu.items")])
        var expected = MenuBuilder.defaultItems
        expected.remove(at: 1)
        #expect(try apply(removal, to: "") == expected)
        #expect(try apply(MenuEditor.operations(adding: "presets", in: state), to: "") == MenuBuilder.defaultItems + ["presets"])
        var dragged = MenuBuilder.defaultItems
        dragged.insert(dragged.remove(at: 3), at: 0)
        #expect(try apply(MenuEditor.operations(moving: [3], to: 0, in: state), to: "") == dragged)
        #expect(MenuEditor.operations(moving: [3], to: 3, in: state).isEmpty, "and a drag that does nothing does not write the list")
    }

    @Test func aListThatIsWrittenIsNotWrittenAgain() {
        let state = state(listed)
        #expect(!MenuEditor.operations(removing: 1, in: state).contains { if case .set = $0 { return true } else { return false } })
    }

    @Test func theEditedMenuReadsBackAsRowsInTheNewOrder() throws {
        let text = listed
        let state = state(text)
        var document = ConfigDocument(text)
        for operation in MenuEditor.operations(moving: IndexSet(integer: 3), to: 1, in: state) { document = try operation.apply(to: document) }
        let again = self.state(document.text)
        #expect(again.rows.map(\.entry) == ["open-terminal", "copy-path", "open-editor", "-", "open-with", "nonsense"])
        #expect(again.rows.map(\.position) == [1, 2, 3, 4, 5, 6])
        #expect(again.listed == again.rows.map(\.entry) && again.isExact)
    }

    // MARK: A list the window did not read as it is

    /// The state the window has on a Mac whose own config turns something off: the config is the two files laid over each other, and the list is the shared file's.
    private func machineState(shared: String, overlay: String) -> MenuEditorState {
        let merged = ConfigLayers.load(base: .text(shared), local: .text(overlay)).config
        return MenuEditor.state(config: merged, facts: machine(), localizer: .english, folder: folder, inFile: try? ConfigDocument(shared).elements(of: MenuEditorState.key) ?? nil)
    }

    @Test func aListThatThisMacCutsShortIsNotEditedByPlace() throws {
        let shared = "[menu]\nitems = [\"open-terminal\", \"open.app.zed\", \"-\", \"copy-path\"]\n"
        let overlay = "disabled = [\"zed\"]\n"
        let state = machineState(shared: shared, overlay: overlay)
        #expect(state.rows.map(\.entry) == ["open-terminal", "-", "copy-path"], "the Finder menu does not have the item this Mac turns off")
        #expect(state.listed == ["open-terminal", "open.app.zed", "-", "copy-path"])
        #expect(!state.isExact)
        // The third row of the window is the fourth item of the file: a change by place would land on the wrong item.
        #expect(MenuEditor.operations(removing: 3, in: state).isEmpty)
        #expect(MenuEditor.operations(moving: [2], to: 0, in: state).isEmpty)
        #expect(MenuEditor.operations(adding: "presets", in: state).isEmpty)
    }

    @Test func aListThatIsWhatTheFileSaysIsExactWithOrWithoutTheOverlay() {
        let shared = "[menu]\nitems = [\"open-terminal\", \"-\", \"copy-path\"]\n"
        #expect(machineState(shared: shared, overlay: "disabled = [\"zed\"]\n").isExact, "turning off what the list does not name changes nothing")
        #expect(state(shared).isExact && state().isExact)
        #expect(!MenuEditorState(rows: [], usesDefaults: true, choices: [], listed: ["a"]).isExact, "a list is written that the config does not have")
        #expect(!MenuEditorState(rows: [], usesDefaults: false, choices: [], listed: nil).isExact)
    }

    @Test func everyChangeIsHeldToTheListThatWasShown() throws {
        let state = state(listed)
        let shown = ["open-terminal", "open-editor", "-", "copy-path", "open-with", "nonsense"]
        for operations in [MenuEditor.operations(removing: 2, in: state), MenuEditor.operations(adding: "presets", at: 2, in: state), MenuEditor.operations(moving: [1], to: 4, in: state)] {
            #expect(operations.first == .expect(shown, in: "menu.items"))
            // Something else put an item first after the window read the file: the change is refused, and nothing is applied to another item.
            let meanwhile = try ConfigDocument(listed).insertingElement("agents", into: "menu.items", at: 1)
            #expect(throws: ConfigDocument.EditError.changedMeanwhile("menu.items")) {
                var document = meanwhile
                for operation in operations { document = try operation.apply(to: document) }
            }
        }
    }

    @Test func aMenuThatIsNotWrittenIsHeldToNotBeingWrittenWhenItsFirstChangeWritesIt() throws {
        let state = state()
        let operations = MenuEditor.operations(removing: 1, in: state)
        let meanwhile = try ConfigDocument("").setting("menu.items", to: .strings(["copy-path"]))
        #expect(throws: ConfigDocument.EditError.changedMeanwhile("menu.items"), "somebody wrote a menu meanwhile: the default one is not written over it") {
            var document = meanwhile
            for operation in operations { document = try operation.apply(to: document) }
        }
    }
}
