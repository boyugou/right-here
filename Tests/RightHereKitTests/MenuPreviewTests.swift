import Foundation
import Testing
@testable import RightHereCore
@testable import RightHereKit

private func action(_ title: String, icon: Icon? = nil) -> MenuNode {
    MenuNode(kind: .action, title: title, icon: icon, actionID: "test." + title, children: [])
}

private func submenu(_ title: String, icon: Icon? = nil, _ children: [MenuNode]) -> MenuNode {
    MenuNode(kind: .submenu, title: title, icon: icon, actionID: nil, children: children)
}

/// What a person reads in the preview: the title of a line, `-` for a separator.
private func titles(_ rows: [MenuPreviewRow]) -> [String] {
    rows.map { $0.kind == .separator ? "-" : $0.title }
}

/// Run, Open With (a terminal, a separator, an editor), a separator, Copy Path.
private let sample: [MenuNode] = [
    action("Run"),
    submenu("Open With", icon: .symbol("arrow.up.forward.app"), [action("Terminal"), .separator, action("Zed")]),
    .separator,
    submenu("Copy Path", [action("Full Path"), action("File Name")]),
]

@Suite("MenuPreview rows")
struct MenuPreviewRowTests {
    @Test func aMenuWithoutSubmenusIsOneLevelOfPlainRows() {
        let rows = MenuPreview.rows([action("Run"), .separator, action("Copy Path")])
        #expect(titles(rows) == ["Run", "-", "Copy Path"])
        #expect(rows.map(\.kind) == [.action, .separator, .action])
        #expect(rows.map(\.level) == [0, 0, 0])
        #expect(rows.map(\.hasChildren) == [false, false, false])
        #expect(rows.map(\.isExpanded) == [false, false, false])
    }

    @Test func anEmptyMenuHasNoRows() {
        #expect(MenuPreview.rows([]).isEmpty)
        #expect(MenuPreview.rows([], expanded: ["0"]).isEmpty)
    }

    @Test func aShutSubmenuShowsOnlyItselfAndSaysItHasEntries() {
        let rows = MenuPreview.rows(sample)
        #expect(titles(rows) == ["Run", "Open With", "-", "Copy Path"])
        let openWith = rows[1]
        #expect(openWith.kind == .submenu)
        #expect(openWith.hasChildren)
        #expect(!openWith.isExpanded)
    }

    @Test func anOpenSubmenuShowsItsEntriesRightAfterItOneLevelDeeper() {
        let rows = MenuPreview.rows(sample, expanded: ["1"])
        #expect(titles(rows) == ["Run", "Open With", "Terminal", "-", "Zed", "-", "Copy Path"])
        #expect(rows.map(\.level) == [0, 0, 1, 1, 1, 0, 0])
        #expect(rows.map(\.isExpanded) == [false, true, false, false, false, false, false])
    }

    @Test func aSeparatorInsideASubmenuIsARowOfThatLevel() {
        let rows = MenuPreview.rows(sample, expanded: ["1"])
        let separator = rows[3]
        #expect(separator.kind == .separator)
        #expect(separator.level == 1)
        #expect(separator.title.isEmpty)
        #expect(!separator.hasChildren)
    }

    @Test func severalSubmenusOpenIndependently() {
        let both = MenuPreview.rows(sample, expanded: ["1", "3"])
        #expect(titles(both) == ["Run", "Open With", "Terminal", "-", "Zed", "-", "Copy Path", "Full Path", "File Name"])
        let second = MenuPreview.rows(sample, expanded: ["3"])
        #expect(titles(second) == ["Run", "Open With", "-", "Copy Path", "Full Path", "File Name"])
    }

    @Test func aSubmenuInsideAShutSubmenuStaysHiddenWhateverTheSetSays() {
        let nested = [submenu("More", [action("Continue"), submenu("Presets", [action("Review")])])]
        #expect(titles(MenuPreview.rows(nested, expanded: ["0.1"])) == ["More"])
        #expect(titles(MenuPreview.rows(nested, expanded: ["0"])) == ["More", "Continue", "Presets"])
        let rows = MenuPreview.rows(nested, expanded: ["0", "0.1"])
        #expect(titles(rows) == ["More", "Continue", "Presets", "Review"])
        #expect(rows.map(\.level) == [0, 1, 1, 2])
    }

    @Test func aSubmenuWithNothingInItCannotBeOpened() {
        let rows = MenuPreview.rows([submenu("Empty", [])], expanded: ["0"])
        #expect(titles(rows) == ["Empty"])
        #expect(!rows[0].hasChildren)
        #expect(!rows[0].isExpanded)
    }

    @Test func aLineKeepsTheTitleAndTheIconOfItsEntry() {
        let rows = MenuPreview.rows(sample, expanded: ["1"])
        #expect(rows[1].icon == .symbol("arrow.up.forward.app"))
        #expect(rows[0].icon == nil)
        #expect(rows[2].title == "Terminal")
    }

    @Test func idsAreThePositionsInTheMenuAndUniqueEvenForEqualTitles() {
        let menu = [action("Same"), action("Same"), submenu("Same", [action("Same"), .separator, action("Same")])]
        let rows = MenuPreview.rows(menu, expanded: ["2"])
        #expect(rows.map(\.id) == ["0", "1", "2", "2.0", "2.1", "2.2"])
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test func openingASubmenuLeavesTheIdsOfTheLinesAfterItAlone() {
        let shut = MenuPreview.rows(sample).map(\.id)
        let open = MenuPreview.rows(sample, expanded: ["1"]).map(\.id)
        #expect(shut == ["0", "1", "2", "3"])
        #expect(open.filter { !$0.contains(".") } == shut)
    }
}

private let home = URL(fileURLWithPath: "/Users/tester")

private func machine() -> FakeSystemFacts {
    FakeSystemFacts(
        homeDirectory: home,
        directories: [home.path],
        applications: [
            "com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"),
            "com.apple.Terminal": URL(fileURLWithPath: "/Applications/Terminal.app"),
            "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
            "dev.zed.Zed": URL(fileURLWithPath: "/Applications/Zed.app"),
        ]
    )
}

private func loaded(_ config: Config, diagnostics: [ConfigDiagnostic] = []) -> ConfigLoadResult {
    ConfigLoadResult(config: config, diagnostics: diagnostics)
}

private let anError = ConfigDiagnostic(severity: .error, path: "", message: "expected ] to close the table", line: 1)
private let aWarning = ConfigDiagnostic(severity: .warning, path: "general.terminl", message: "unknown key")

@Suite("MenuPreview folder menu")
struct MenuPreviewFolderMenuTests {
    private let config = Config(enabledAgents: ["claude", "codex"])

    @Test func thePreviewIsWhatMenuBuilderBuildsForAFolder() {
        let preview = MenuPreview.folderMenu(loaded(config), facts: machine(), folder: home, localizer: .english)
        let built = MenuBuilder(config: config, facts: machine(), localizer: .english).build(for: HereContext(origin: .container, container: home))
        #expect(preview == built)
        // Not only equal to itself: the menu a person with this config and these apps sees on a folder.
        #expect(preview.map { $0.kind == .separator ? "-" : $0.title } == [
            "Open in Ghostty", "Open in Visual Studio Code", "Open With", "Claude Code Here", "Codex Here", "More Agent Options", "-", "New File", "Copy Path",
        ])
    }

    @Test func everyEntryOfTheBuiltMenuIsOnSomeLineOfItsRows() {
        let preview = MenuPreview.folderMenu(loaded(config), facts: machine(), folder: home, localizer: .english)
        var expanded: Set<String> = []
        while let next = MenuPreview.rows(preview, expanded: expanded).first(where: { $0.hasChildren && !$0.isExpanded }) { expanded.insert(next.id) }
        let all = MenuPreview.rows(preview, expanded: expanded)
        func titles(_ nodes: [MenuNode]) -> [String] { nodes.flatMap { [$0.kind == .separator ? "" : $0.title] + titles($0.children) } }
        #expect(all.map(\.title) == titles(preview))
        #expect(all.count > preview.count)
    }

    @Test func itIsTheMenuForAFolderAndNotTheOneForSelectedFiles() {
        // The agent presets name files and New File needs at most one item, so two files get the first and no second:
        // the opposite of a folder.
        let config = Config(enabledAgents: ["claude"], menuItems: ["presets", "new-file"])
        let files = HereContext(origin: .items, items: [home.appendingPathComponent("a.txt"), home.appendingPathComponent("b.txt")])
        #expect(MenuBuilder(config: config, facts: machine()).build(for: files).map(\.title) == ["Agent Presets"])
        let preview = MenuPreview.folderMenu(loaded(config), facts: machine(), folder: home, localizer: .english)
        #expect(preview.map(\.title) == ["New File"])
    }

    @Test func itFollowsTheLanguageItIsGiven() {
        let german = MenuPreview.folderMenu(loaded(config), facts: machine(), folder: home, localizer: Localizer(languages: ["de"]))
        #expect(german.first?.title == "In Ghostty öffnen")
        #expect(german.contains { $0.title == "Neue Datei" })
    }

    @Test func aConfigWithAnErrorShowsNothing() {
        #expect(MenuPreview.folderMenu(loaded(config, diagnostics: [anError]), facts: machine(), folder: home, localizer: .english).isEmpty)
        // Whatever else is wrong with the file does not matter; one error is enough.
        #expect(MenuPreview.folderMenu(loaded(config, diagnostics: [aWarning, anError]), facts: machine(), folder: home, localizer: .english).isEmpty)
    }

    @Test func aWarningAloneStillShowsTheMenu() {
        let menu = MenuPreview.folderMenu(loaded(config, diagnostics: [aWarning]), facts: machine(), folder: home, localizer: .english)
        #expect(!menu.isEmpty)
    }

    @Test func aMenuWithNothingInItShowsNothing() {
        let empty = Config(menuItems: [])
        #expect(MenuPreview.folderMenu(loaded(empty), facts: machine(), folder: home, localizer: .english).isEmpty)
    }

    private func paths(in directory: URL) -> RHPaths {
        RHPaths(environment: ["RH_CONFIG_DIR": directory.path], home: home)
    }

    @Test func aConfigFileThatDoesNotParseShowsNothing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try "[general\nterminal = \"ghostty\"\n".write(to: paths(in: directory).configFile, atomically: true, encoding: .utf8)
        let result = ConfigStore.load(paths: paths(in: directory)).result
        #expect(result.hasErrors)
        #expect(MenuPreview.folderMenu(result, facts: machine(), folder: home, localizer: .english).isEmpty)
    }

    @Test func noConfigFileMeansTheDefaultMenu() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = ConfigStore.load(paths: paths(in: directory)).result
        let menu = MenuPreview.folderMenu(result, facts: machine(), folder: home, localizer: .english)
        #expect(menu.map(\.title).contains("Copy Path"))
        #expect(menu == MenuBuilder(config: .default, facts: machine()).build(for: HereContext(origin: .container, container: home)))
    }
}
