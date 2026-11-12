import Foundation
import Testing
@testable import RightHereCore

private let script = "/Users/tester/code/app/run-me.command"
private let folderOfScript = "/Users/tester/code/app"

private func facts(_ installed: [String], shellApps: Set<String> = []) -> FakeSystemFacts {
    var facts = FakeSystemFacts(directories: ["/Users/tester/code", folderOfScript], files: [script],
                                applications: Dictionary(uniqueKeysWithValues: installed.map { ($0, URL(fileURLWithPath: "/Applications/\($0).app")) }))
    facts.shellApps = shellApps
    return facts
}

private func selected(_ path: String) -> HereContext {
    HereContext(origin: .items, items: [URL(fileURLWithPath: path)])
}

private func targets(_ plan: LaunchPlan) -> [String] {
    plan.steps.flatMap { step -> [String] in
        if case .open(let open) = step { return open.targets }
        return []
    }
}

/// A terminal Right Here does not ship, as the window writes one that it pinned to "terminal" when it was added.
private let tabbyAsTerminal = "[[app]]\nid = \"tabby\"\nname = \"Tabby\"\nbundle_id = \"org.tabby\"\nrole = \"terminal\"\n\n"

/// A terminal is only ever handed a folder, since handed a file it runs it (CLAUDE.md rule 3), whichever way the config names it. An independent review
/// (2026-11-12) found the rule held only for the bundle identifiers of the terminals that come with Right Here.
@Suite("Opening items in apps")
struct OpenInAppsTests {
    /// An app that says it runs shell scripts is a terminal whatever the config calls it: Open With and Open in Editor hand it the folder, and New File does not
    /// open a file with it.
    @Test func anAppThatSaysItRunsShellScriptsIsHandedTheFolder() throws {
        let text = "[[app]]\nid = \"tabby\"\nname = \"Tabby\"\nbundle_id = \"org.tabby\"\n[general]\neditor = \"tabby\"\n[new_file]\nthen = \"open\"\n"
            + "[[new_file.template]]\nid = \"cmd\"\ntitle = \"Command\"\nextension = \"command\"\nopen_with = \"tabby\"\n"
        let result = ConfigParser.parse(text)
        #expect(result.config.app(id: "tabby")?.role == .general, "control: written without a role, it is a general app")
        let planner = Planner(config: result.config, facts: facts(["org.tabby"], shellApps: ["org.tabby"]))
        #expect(targets(try planner.plan(.openApp("tabby"), context: selected(script))) == [folderOfScript])
        #expect(targets(try planner.plan(.openEditor, context: selected(script))) == [folderOfScript])
        let made = try planner.plan(.newFile("cmd"), context: HereContext(origin: .container, container: URL(fileURLWithPath: folderOfScript)))
        #expect(!made.steps.contains { step in
            if case .open(let open) = step { return open.bundleID == "org.tabby" }
            return false
        }, "\(made.steps)")
        // An app that says nothing of shells is handed what is selected.
        let plain = Planner(config: result.config, facts: facts(["org.tabby"]))
        #expect(targets(try plain.plan(.openApp("tabby"), context: selected(script))) == [script])
    }

    /// The window pins an app that says it runs shell scripts to "terminal": its page offers no other role. One that says nothing of shells can be made an editor
    /// again (it may have been added as a terminal by mistake).
    @Test func theWindowKeepsAShellAppATerminal() throws {
        let config = ConfigParser.parse(tabbyAsTerminal).config
        let entries = ["tabby": EntryLocation(target: .shared, position: 1)]
        let row = try #require(AppOptions.state(config: config, entries: entries, facts: facts(["org.tabby"], shellApps: ["org.tabby"])).row(id: "tabby"))
        #expect(row.rolePinned)
        #expect(AppOptions.changing(role: .general, of: row) == nil && AppOptions.changing(role: .editor, of: row) == nil)
        let other = try #require(AppOptions.state(config: config, entries: entries, facts: facts(["org.tabby"])).row(id: "tabby"))
        #expect(!other.rolePinned && AppOptions.changing(role: .editor, of: other) != nil)
    }

    /// A second entry with the bundle identifier of a terminal the config adds is refused, as one with a built-in terminal's is, before or after it and in any case.
    @Test(arguments: [true, false])
    func aSecondEntryOfATerminalTheConfigAddsIsRefused(terminalFirst: Bool) {
        let files = "[[app]]\nid = \"tabby-files\"\nname = \"Tabby Files\"\nbundle_id = \"ORG.TABBY\"\nrole = \"editor\"\n\n"
        let result = ConfigParser.parse(terminalFirst ? tabbyAsTerminal + files : files + tabbyAsTerminal)
        #expect(result.config.app(id: "tabby-files") == nil && result.config.app(id: "tabby")?.role == .terminal)
        #expect(result.diagnostics.contains { $0.message.contains("a terminal this config adds") }, "\(result.diagnostics.map(\.message))")
    }

    /// Open With of a terminal starts it as Open in Terminal does: through its adapter, which checks the folder again and knows how the terminal is started.
    @Test("open.app of a terminal starts it the way open.terminal does", arguments: ["alacritty", "kitty", "wezterm", "warp", "ghostty", "terminal"])
    func openWithATerminalGoesThroughItsAdapter(id: String) throws {
        let planner = Planner(facts: facts(KnownApps.terminals.flatMap(\.bundleIDs)))
        let viaOpenWith = try planner.plan(.openApp(id), context: selected(script))
        let viaTerminal = try planner.plan(.openTerminal(id), context: selected(script))
        #expect(viaOpenWith.steps == viaTerminal.steps, "open.app: \(viaOpenWith.steps)\nopen.terminal@: \(viaTerminal.steps)")
    }

    @Test func openWithATemplateTerminalUsesItsTemplate() throws {
        let text = "[[app]]\nid = \"mine\"\nname = \"Mine\"\nbundle_id = \"com.example.term\"\nrole = \"terminal\"\nopen_args = [\"{app}/Contents/MacOS/mine\", \"--cwd\", \"{dir}\"]\n"
        let planner = Planner(config: ConfigParser.parse(text).config, facts: facts(["com.example.term"]))
        let viaOpenWith = try planner.plan(.openApp("mine"), context: selected(script))
        let viaTerminal = try planner.plan(.openTerminal("mine"), context: selected(script))
        #expect(viaOpenWith.steps == viaTerminal.steps, "open.app: \(viaOpenWith.steps)\nopen.terminal@: \(viaTerminal.steps)")
    }

    /// The menu tells apps apart by their names ("Open in <name>"): one called like another app, built in or not, is refused, so no entry can pass for another.
    @Test func anAppCannotTakeTheNameOfAnotherApp() {
        let builtIn = ConfigParser.parse("[[app]]\nid = \"notes\"\nname = \"TextEdit\"\nbundle_id = \"com.example.notes\"\nrole = \"editor\"\n")
        #expect(builtIn.config.app(id: "notes") == nil && builtIn.diagnostics.contains { $0.message.contains("already called") }, "\(builtIn.diagnostics.map(\.message))")
        let twice = ConfigParser.parse("[[app]]\nid = \"a\"\nname = \"Notes\"\nbundle_id = \"com.example.a\"\n[[app]]\nid = \"b\"\nname = \"notes\"\nbundle_id = \"com.example.b\"\n")
        #expect(twice.config.app(id: "a") != nil && twice.config.app(id: "b") == nil)
        // An entry that replaces a built-in app under its id keeps its name.
        #expect(ConfigParser.parse("[[app]]\nid = \"textedit\"\nname = \"TextEdit\"\nbundle_id = \"com.apple.TextEdit\"\nrole = \"editor\"\n").config.app(id: "textedit") != nil)
    }
}
