import Foundation
import Testing
@testable import RightHereCore

// What an independent review of what the Finder menu offers and how it titles it found (2026-11-13), each kept as the test that failed on the
// code it was found in.

private let code = "/Users/tester/code"

private func reviewMachine(installed: [String] = ["com.mitchellh.ghostty", "com.apple.Terminal", "com.microsoft.VSCode", "dev.zed.Zed"],
                          directories: [String] = [], files: [String] = [], packages: Set<String> = []) -> FakeSystemFacts {
    var facts = FakeSystemFacts(
        directories: Set([code] + directories),
        files: Set(files),
        applications: Dictionary(uniqueKeysWithValues: installed.map { ($0, URL(fileURLWithPath: "/Applications/\($0).app")) }),
        bundleVersions: ["com.mitchellh.ghostty": "1.3.1"]
    )
    facts.packages = packages
    return facts
}

private let folderBackground = HereContext.finder(kind: .container, selected: [], targeted: URL(fileURLWithPath: code))

private func everyNode(_ nodes: [MenuNode]) -> [MenuNode] {
    nodes.flatMap { [$0] + everyNode($0.children) }
}

/// The submenu that holds the action `id`, wherever it is.
private func submenu(holding id: String, in nodes: [MenuNode]) -> MenuNode? {
    everyNode(nodes).first { $0.kind == .submenu && $0.children.contains { $0.actionID == id } }
}

private func titlesShownTwice(_ nodes: [MenuNode]) -> [String] {
    let titles = nodes.filter { $0.kind != .separator }.map(\.title)
    return Set(titles.filter { title in titles.filter { $0 == title }.count > 1 }).sorted()
}

@Suite("The Finder menu, after an independent review")
struct MenuReviewTests {
    /// Finder names a target that is no file URL and nothing is selected: a right-click on a server or a share in the sidebar, or in a
    /// window that shows one (`smb://server/share`). `HereContext.finder` leaves such a URL out, rightly (its path would read as a folder
    /// of this Mac), so the context has neither items nor a folder (FinderContext.swift:21-35). The menu is the whole folder menu anyway:
    /// the default terminal and editor, Open With, the agents, New File and Copy Path. `rh run` refuses each of them ("There is no folder
    /// or selection to act on."), and Copy Path, which the extension does itself, copies nothing and says nothing
    /// (FinderSyncExtension.swift:217-218). Only the presets mirror the refusal (ActionRegistry.swift:128-129). The extension adds to it:
    /// a context without items counts as a single folder there and is served the cached folder menu (FinderSyncExtension.swift:114-117).
    /// `rh menu` already refuses to preview a container or sidebar menu without a folder (Actions.swift:90-99). With nothing to act on,
    /// the menu should offer nothing that `rh run` refuses for want of a target.
    @Test func aMenuWithNothingToActOnOffersNothingThatRunRefusesForWantOfATarget() throws {
        let facts = reviewMachine()
        let config = Config(enabledAgents: ["claude"])
        let share = try #require(URL(string: "smb://server/share"))
        for kind in [FinderMenuKind.sidebar, .container, .toolbar] {
            let context = HereContext.finder(kind: kind, selected: [], targeted: share)
            try #require(context.items.isEmpty && context.container == nil)
            let ids = everyNode(MenuBuilder(config: config, facts: facts).build(for: context)).compactMap(\.actionID)
            let refused = ids.filter { id in
                guard let ref = ActionRef(parsing: id) else { return false }
                do {
                    _ = try Planner(config: config, facts: facts).plan(ref, context: context)
                    return false
                } catch {
                    return (error as? PlanError) == .noTarget
                }
            }
            #expect(refused.isEmpty, "\(kind.rawValue) menu with nothing to act on offers \(refused.count) entries that `rh run` refuses with \"There is no folder or selection to act on.\": \(refused)")
        }
    }


    /// The person keeps an app (`Foo.app`) or a package document (`Notes.rtfd`) in the Favorites of Finder's sidebar and right-clicks it
    /// there. Finder names the sidebar item as the menu's target, and `HereContext.finder` makes a sidebar target the container, the
    /// folder being viewed (FinderContext.swift:30-31); `HereContext.workingDirectory` keeps a container that is a package as the folder on
    /// purpose, for one the person opened with Show Package Contents (HereContext.swift:41-46). So the menu offers New File, and the click
    /// makes `untitled.txt` inside the app, which breaks its signature: what ADR 0008 fixed for a selected package
    /// (`NewFileOpeningTests.aSelectedPackageIsOneItemAndAnOpenedOneIsAFolder`), reached through the sidebar. Open in Terminal and the
    /// agents start inside the bundle as well. A package the sidebar names is one item, as a selected one is: if New File is offered, the
    /// file goes next to it.
    @Test func aPackageInTheSidebarIsOneItemAndGetsNoFileInsideIt() throws {
        let app = "/Applications/Foo.app"
        let facts = reviewMachine(directories: ["/Applications", app], packages: [app])
        var config = Config()
        config.newFile.then = .nothing
        let sidebar = HereContext.finder(kind: .sidebar, selected: [], targeted: URL(fileURLWithPath: app))
        let offered = everyNode(MenuBuilder(config: config, facts: facts).build(for: sidebar)).compactMap(\.actionID)
        guard offered.contains("new-file.txt") else { return }
        let plan = try Planner(config: config, facts: facts).plan(.newFile("txt"), context: sidebar)
        guard case .createFile(let made)? = plan.steps.first else {
            Issue.record("New File makes no file: \(plan.steps)")
            return
        }
        #expect(!made.path.hasPrefix(app + "/"), "the menu offers New File on a package in the sidebar, and the click makes \(made.path), inside the package")
        // Every action starts in the folder around it, as for a selected package: a terminal opens /Applications, not the inside of the app.
        #expect(sidebar.workingDirectory(facts: facts)?.path == "/Applications")
    }

    /// A config adds a preset of its own, under another id, with the title of a built-in one: "Review", or on a German Mac "Überprüfen",
    /// which is what the built-in Review is called there. The parser accepts it (ConfigBuilder+Presets.swift:26-75 holds the id to be
    /// unique, not the title), and the Agent Presets submenu has two lines "Review" that type two different prompts into the agent, with
    /// nothing to tell them apart. Two templates of one title do the same in New File. Apps, agents and an agent's start options are each
    /// held to a title of their own ("the menu tells them apart by their titles"), a start option even against every translation of a
    /// built-in title (ConfigBuilder+Agents.swift:98-112, 165-171); presets and templates are not.
    @Test func twoPresetsOrTwoTemplatesNeverShareATitleInOneSubmenu() throws {
        let file = "\(code)/a.swift"
        let facts = reviewMachine(files: [file])
        let oneFile = HereContext(origin: .items, items: [URL(fileURLWithPath: file)])
        for (language, title) in [("en", "Review"), ("de", "Überprüfen")] {
            let toml = "[general]\nagents = [\"claude\"]\n[[preset]]\nid = \"fix\"\ntitle = \"\(title)\"\nprompt = \"Fix the bugs in {files}.\"\n"
            let config = ConfigParser.parse(toml).config
            let menu = MenuBuilder(config: config, facts: facts, localizer: Localizer(languages: [language])).build(for: oneFile)
            let presets = try #require(submenu(holding: "preset.review", in: menu))
            #expect(titlesShownTwice(presets.children).isEmpty,
                    "\(language): the presets submenu shows \(presets.children.map { "\($0.title) (\($0.actionID ?? ""))" })")
        }
        let templates = "[[new_file.template]]\nid = \"note\"\ntitle = \"Note\"\nextension = \"md\"\n[[new_file.template]]\nid = \"plain\"\ntitle = \"Note\"\nextension = \"txt\"\n"
        let newFile = everyNode(MenuBuilder(config: ConfigParser.parse(templates).config, facts: facts).build(for: folderBackground))
            .filter { $0.actionID?.hasPrefix("new-file.") == true }
        #expect(titlesShownTwice(newFile).isEmpty, "New File shows \(newFile.map { "\($0.title) (\($0.actionID ?? ""))" })")
    }

    /// The setup window's menu editor offers under Add every action that can run and that `menu.items` does not list in those very words
    /// (MenuEditor.swift:81). Several of them are in the menu already through a group: "Open in Ghostty" (`open.terminal`,
    /// `open.terminal@ghostty`) through `open-terminal`, "Open in Visual Studio Code" (`open.editor`, `open.app.vscode`) through
    /// `open-editor`, "Claude Code Here" (`agent.claude`) through `agents`, and "Copy Path: Full Path" (`copy-path.absolute`), which the
    /// menu then titles "Copy Path" (MenuBuilder.swift:139-140) next to the "Copy Path" submenu. The person who adds one gets two lines
    /// that read the same; the parser's "listed twice" warning only sees two equal strings (ConfigBuilder+Menu.swift:20-24). An app added
    /// as a line of its own ("Open in Zed") also stays in Open With, which says it leaves out what the menu offers on a line of its own
    /// (MenuBuilder.swift:110-113), and a start option added so ("Claude Code: Continue") stays in More Agent Options, which "offers the
    /// other ways and never the same one twice" (DESIGN.md section 7; MenuBuilder.swift:124 knows only `agents` and `agent.<id>`).
    @Test func whatTheMenuEditorOffersToAddNeverMakesTwoLinesThatReadTheSame() {
        let facts = reviewMachine()
        let config = Config(enabledAgents: ["claude"])
        let state = MenuEditor.state(config: config, facts: facts, localizer: .english, folder: URL(fileURLWithPath: code), inFile: nil)
        var sameTitle: [String] = []
        var submenuRepeats: [String] = []
        for choice in state.choices where choice.section != .group {
            var added = config
            added.menuItems = MenuBuilder.defaultItems + [choice.entry]
            let menu = MenuBuilder(config: added, facts: facts).build(for: folderBackground)
            let twice = titlesShownTwice(menu)
            if !twice.isEmpty { sameTitle.append("Add \"\(choice.title)\" (\(choice.entry)) -> \(twice)") }
            let ownLines = Set(menu.compactMap(\.actionID))
            for group in ["Open With", "More Agent Options"] {
                let inside = menu.first { $0.kind == .submenu && $0.title == group }.map { everyNode($0.children).compactMap(\.actionID) } ?? []
                if let repeated = inside.first(where: ownLines.contains) { submenuRepeats.append("\(group): \(repeated)") }
            }
        }
        #expect(sameTitle.isEmpty, "adding these from the menu editor gives the menu two lines of one title: \(sameTitle)")
        #expect(submenuRepeats.isEmpty, "a submenu repeats what the menu offers on a line of its own: \(submenuRepeats)")
    }
}
