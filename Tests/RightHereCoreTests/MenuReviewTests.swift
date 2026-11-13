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
}
