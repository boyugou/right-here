import Foundation
import Testing
@testable import RightHereCore

private func facts(installed: [String], versions: [String: String] = [:]) -> FakeSystemFacts {
    FakeSystemFacts(
        directories: ["/Users/tester/code"],
        applications: Dictionary(uniqueKeysWithValues: installed.map { ($0, URL(fileURLWithPath: "/Applications/\($0).app")) }),
        bundleVersions: versions
    )
}

private let folder = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/code"))

@Suite("DefaultApps")
struct DefaultAppsTests {
    @Test func theConfiguredDefaultIsUsedAsItIsAndAnUnconfiguredOneIsTheFirstInstalledInTheOrder() throws {
        let machine = facts(installed: ["com.apple.Terminal", "com.googlecode.iterm2", "com.apple.TextEdit", "dev.zed.Zed"])
        #expect(try DefaultApps(config: .default, facts: machine).resolve(role: .terminal, configured: nil).id == "iterm")
        #expect(try DefaultApps(config: .default, facts: machine).resolve(role: .editor, configured: nil).id == "zed")
        #expect(try DefaultApps(config: Config(terminal: "terminal"), facts: machine).resolve(role: .terminal, configured: "terminal").id == "terminal")
        // A configured default that is not installed counts as none: the first installed one in the order is used.
        #expect(try DefaultApps(config: .default, facts: machine).resolve(role: .terminal, configured: "warp").id == "iterm")
        #expect(try DefaultApps(config: .default, facts: machine).resolve(role: .editor, configured: "vscode").id == "zed")
    }

    @Test func aConfiguredDefaultThatIsNotInstalledIsReturnedAsItIsWhenNothingElseOfTheRoleIs() throws {
        // Nothing of the role is installed: the app the person chose is the answer, and the action says it is missing.
        let defaults = DefaultApps(config: Config(terminal: "ghostty", editor: "vscode"), facts: facts(installed: []))
        #expect(try defaults.resolve(role: .terminal, configured: "ghostty").id == "ghostty")
        #expect(try defaults.resolve(role: .editor, configured: "vscode").id == "vscode")
        #expect(try defaults.commandTerminal().id == "ghostty")
        #expect(defaults.substitution(role: .terminal) == nil, "nothing stands in for it")
        #expect(throws: PlanError.noDefaultApp(.terminal)) { try DefaultApps(config: .default, facts: facts(installed: [])).resolve(role: .terminal, configured: nil) }
    }

    @Test func aConfiguredDefaultThatIsAnUnknownAppOrTheWrongRoleIsStillRefused() {
        let machine = facts(installed: ["com.apple.Terminal", "com.microsoft.VSCode"])
        #expect(throws: PlanError.unknownApp("nope")) { try DefaultApps(config: .default, facts: machine).resolve(role: .terminal, configured: "nope") }
        #expect(throws: PlanError.self) { try DefaultApps(config: .default, facts: machine).resolve(role: .terminal, configured: "vscode") }
        #expect(throws: PlanError.self) { try DefaultApps(config: .default, facts: machine).resolve(role: .editor, configured: "terminal") }
    }

    @Test func aDefaultThatIsNotInstalledIsReplacedByTheFirstInstalledAppAndSaysSo() throws {
        // A config shared between Macs: this one has Ghostty, the other had iTerm and Zed.
        let machine = facts(installed: ["com.mitchellh.ghostty", "com.microsoft.VSCode"], versions: ["com.mitchellh.ghostty": "1.3.1"])
        let defaults = DefaultApps(config: Config(terminal: "iterm", editor: "zed"), facts: machine)
        let terminal = try #require(defaults.substitution(role: .terminal))
        #expect(terminal.wanted.id == "iterm" && terminal.used.id == "ghostty")
        #expect(terminal.sentence == "iTerm is not installed; Ghostty is used instead.")
        let editor = try #require(defaults.substitution(role: .editor))
        #expect(editor.wanted.id == "zed" && editor.used.id == "vscode")
        #expect(editor.sentence == "Zed is not installed; Visual Studio Code is used instead.")
        // An installed default, and no default at all, replace nothing.
        #expect(DefaultApps(config: Config(terminal: "ghostty"), facts: machine).substitution(role: .terminal) == nil)
        #expect(DefaultApps(config: .default, facts: machine).substitution(role: .terminal) == nil)
    }

    @Test func theFallbackForTypingACommandSkipsTerminalsThatCannotRunOne() throws {
        // Warp opens a folder but cannot be told to run a command here; Terminal can. The two answers differ.
        let machine = facts(installed: ["dev.warp.Warp-Stable", "com.apple.Terminal"])
        let defaults = DefaultApps(config: Config(terminal: "iterm"), facts: machine)
        #expect(try defaults.resolve(role: .terminal, configured: "iterm").id == "warp")
        #expect(try defaults.commandTerminal().id == "terminal")
        #expect(defaults.substitution(role: .terminal)?.used.id == "warp")
        #expect(defaults.substitution(role: .terminal, typing: true)?.used.id == "terminal")
    }

    @Test func onlyTheDefaultFallsBackAnAppAnActionNamesDoesNot() throws {
        let machine = facts(installed: ["com.mitchellh.ghostty", "com.apple.Terminal"], versions: ["com.mitchellh.ghostty": "1.3.1"])
        let config = ConfigParser.parse("[general]\nterminal = \"iterm\"\nagents = [\"claude\", \"codex\"]\n[agent.codex]\nterminal = \"iterm\"\n").config
        let planner = Planner(config: config, facts: machine)
        let registry = ActionRegistry(config: config, facts: machine)
        // The default falls back, and every default entry is offered with the app that is used.
        #expect(registry.info(.openTerminal(nil)).title == "Open in Ghostty")
        #expect(registry.info(.agent(id: "claude", variant: nil, launcher: nil)).available)
        // Naming the terminal, directly or as an agent's own, is a statement about that terminal.
        for ref in [ActionRef.openTerminal("iterm"), .agent(id: "claude", variant: nil, launcher: .terminal("iterm")), .agent(id: "codex", variant: nil, launcher: nil)] {
            #expect(throws: PlanError.self, "\(ref.id)") { try planner.plan(ref, context: folder) }
            let info = registry.info(ref)
            #expect(!info.available && info.unavailableReason == "iTerm is not installed.", "\(ref.id): \(info.unavailableReason ?? "")")
        }
    }

    @Test func thePlansOfTheDefaultsSaySoWhenTheDefaultWasReplaced() throws {
        let machine = facts(installed: ["com.mitchellh.ghostty", "com.apple.Terminal", "com.microsoft.VSCode"], versions: ["com.mitchellh.ghostty": "1.3.1"])
        let config = Config(terminal: "iterm", editor: "zed", enabledAgents: ["claude"])
        let planner = Planner(config: config, facts: machine)
        let note = ["iTerm is not installed; Ghostty is used instead."]
        #expect(try planner.plan(.openTerminal(nil), context: folder).notices == note)
        #expect(try planner.plan(.agent(id: "claude", variant: nil, launcher: nil), context: folder).notices == note)
        #expect(try planner.plan(.openEditor, context: folder).notices == ["Zed is not installed; Visual Studio Code is used instead."])
        // A terminal the action names is the person's choice and needs no note; an installed default none either.
        #expect(try planner.plan(.openTerminal("terminal"), context: folder).notices.isEmpty)
        #expect(try Planner(config: Config(terminal: "ghostty"), facts: machine).plan(.openTerminal(nil), context: folder).notices.isEmpty)
    }

    /// Changing the default order is a visible change, so it is a change to this test as well.
    @Test func theDefaultsArePickedInThisOrder() {
        #expect(DefaultApps.ranked(KnownApps.all, role: .terminal).map(\.id) == ["ghostty", "cmux", "iterm", "wezterm", "kitty", "alacritty", "warp", "terminal"])
        #expect(DefaultApps.ranked(KnownApps.all, role: .editor).map(\.id) == ["vscode", "cursor", "zed", "windsurf", "sublime", "nova", "bbedit", "intellij", "pycharm", "webstorm", "textedit"])
    }

    @Test func ranksAreUniqueWithinARoleAndOnlyAppsThatMeanToBePickedHaveOne() {
        for role in AppDescriptor.Role.allCases {
            let ranks = KnownApps.all.filter { $0.role == role }.compactMap(\.defaultRank)
            #expect(Set(ranks).count == ranks.count, "two \(role.rawValue)s share a rank")
        }
        for id in ["xcode", "typora", "obsidian", "android-studio", "trae", "positron", "rustrover", "clion", "goland"] {
            #expect(KnownApps.app(id: id)?.defaultRank == nil, "\(id) is never a default")
        }
        #expect(KnownApps.terminals.max { ($0.defaultRank ?? -1) < ($1.defaultRank ?? -1) }?.id == "terminal", "Terminal.app is always there, so it is the last resort")
    }

    @Test func anEditorIsNeverTheDefaultTerminalAndAnAppWithoutARankIsOnlyUsedWhenTheConfigDefinesIt() throws {
        let editorsOnly = facts(installed: ["com.microsoft.VSCode", "com.apple.TextEdit", "com.apple.dt.Xcode"])
        #expect(throws: PlanError.noDefaultApp(.terminal)) { try DefaultApps(config: .default, facts: editorsOnly).resolve(role: .terminal, configured: nil) }
        // Xcode has no rank, so it is not a default editor either; an editor the config defines is, after the ranked ones.
        #expect(try DefaultApps(config: .default, facts: editorsOnly).resolve(role: .editor, configured: nil).id == "vscode")
        let onlyXcode = facts(installed: ["com.apple.dt.Xcode"])
        #expect(throws: PlanError.noDefaultApp(.editor)) { try DefaultApps(config: .default, facts: onlyXcode).resolve(role: .editor, configured: nil) }
        let own = AppDescriptor(id: "tower", name: "Tower", bundleIDs: ["com.fournova.Tower3"], role: .editor)
        let both = facts(installed: ["com.apple.dt.Xcode", "com.fournova.Tower3", "com.apple.TextEdit"])
        #expect(try DefaultApps(config: Config(apps: [own]), facts: both).resolve(role: .editor, configured: nil).id == "textedit")
        #expect(try DefaultApps(config: Config(apps: [own]), facts: facts(installed: ["com.fournova.Tower3"])).resolve(role: .editor, configured: nil).id == "tower")
    }

    @Test func theTerminalForACommandSkipsOnesThatCannotRunOne() throws {
        // cmux and warp open folders only, and older Ghostty / iTerm cannot be scripted; Terminal can.
        for machine in [facts(installed: ["com.cmuxterm.app", "com.apple.Terminal"]),
                        facts(installed: ["dev.warp.Warp-Stable", "com.apple.Terminal"]),
                        facts(installed: ["com.googlecode.iterm2", "com.apple.Terminal"], versions: ["com.googlecode.iterm2": "2.9.0"]),
                        facts(installed: ["com.mitchellh.ghostty", "com.apple.Terminal"], versions: ["com.mitchellh.ghostty": "1.2.3"])] {
            let defaults = DefaultApps(config: .default, facts: machine)
            #expect(try defaults.commandTerminal().id == "terminal")
        }
        let ghosttyScriptable = facts(installed: ["com.mitchellh.ghostty", "com.apple.Terminal"], versions: ["com.mitchellh.ghostty": "1.3.1"])
        #expect(try DefaultApps(config: .default, facts: ghosttyScriptable).commandTerminal().id == "ghostty")
        let itermScriptable = facts(installed: ["com.googlecode.iterm2", "com.apple.Terminal"], versions: ["com.googlecode.iterm2": "3.5.0"])
        #expect(try DefaultApps(config: .default, facts: itermScriptable).commandTerminal().id == "iterm")
        let weztermScriptable = facts(installed: ["com.github.wez.wezterm", "com.apple.Terminal"])
        #expect(try DefaultApps(config: .default, facts: weztermScriptable).commandTerminal().id == "wezterm")
        let kittyScriptable = facts(installed: ["net.kovidgoyal.kitty", "com.apple.Terminal"])
        #expect(try DefaultApps(config: .default, facts: kittyScriptable).commandTerminal().id == "kitty")
        // With nothing that can run a command, the first installed terminal is still the answer, and starting an agent in it says why not.
        let foldersOnly = facts(installed: ["com.cmuxterm.app", "dev.warp.Warp-Stable"])
        #expect(try DefaultApps(config: .default, facts: foldersOnly).commandTerminal().id == "cmux")
        // A configured default that is installed is used as it is, even when it cannot run a command.
        #expect(try DefaultApps(config: Config(terminal: "cmux"), facts: facts(installed: ["com.cmuxterm.app", "com.apple.Terminal"])).commandTerminal().id == "cmux")
    }

    @Test func noTerminalOrEditorInstalledIsSaidInTheSameWordsByTheRegistryAndThePlanner() {
        let machine = facts(installed: [])
        let registry = ActionRegistry(config: .default, facts: machine)
        let planner = Planner(facts: machine)
        for (ref, role, text) in [(ActionRef.openTerminal(nil), AppDescriptor.Role.terminal, "No terminal is installed."), (.openEditor, .editor, "No editor is installed.")] {
            #expect(registry.info(ref).unavailableReason == text)
            #expect(throws: PlanError.noDefaultApp(role)) { try planner.plan(ref, context: folder) }
            #expect(PlanError.noDefaultApp(role).localizedDescription == text)
        }
    }

    @Test func aDefaultTheConfigMadeUnusableIsRefusedForItsRealReasonEverywhere() {
        let ghostty = AppDescriptor(id: "ghostty", name: "Ghostty", bundleIDs: ["com.mitchellh.ghostty"], role: .editor)
        let config = Config(terminal: "ghostty", apps: [ghostty])
        let machine = facts(installed: ["com.mitchellh.ghostty", "com.apple.Terminal"])
        let reason = ActionRegistry(config: config, facts: machine).info(.openTerminal(nil)).unavailableReason
        #expect(reason == "Ghostty is not a terminal. Use open.app.ghostty to open files with it.")
        #expect(throws: PlanError.unsupported(reason ?? "")) { try Planner(config: config, facts: machine).plan(.openTerminal(nil), context: folder) }
    }
}
