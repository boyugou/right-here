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
        // Not installed does not matter here: the default is what the person set, and the action says it is missing.
        #expect(try DefaultApps(config: .default, facts: machine).resolve(role: .terminal, configured: "warp").id == "warp")
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
        for id in ["xcode", "typora", "obsidian", "android-studio"] { #expect(KnownApps.app(id: id)?.defaultRank == nil, "\(id) is never a default") }
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
        // iTerm and cmux open folders only, and a Ghostty older than 1.3 cannot be scripted; Terminal can.
        for machine in [facts(installed: ["com.googlecode.iterm2", "com.apple.Terminal"]),
                        facts(installed: ["com.cmuxterm.app", "com.apple.Terminal"]),
                        facts(installed: ["com.mitchellh.ghostty", "com.apple.Terminal"], versions: ["com.mitchellh.ghostty": "1.2.3"])] {
            let defaults = DefaultApps(config: .default, facts: machine)
            #expect(try defaults.commandTerminal().id == "terminal")
        }
        let scriptable = facts(installed: ["com.mitchellh.ghostty", "com.apple.Terminal"], versions: ["com.mitchellh.ghostty": "1.3.1"])
        #expect(try DefaultApps(config: .default, facts: scriptable).commandTerminal().id == "ghostty")
        // With nothing that can run a command, the first installed terminal is still the answer, and starting an agent in it says why not.
        let foldersOnly = facts(installed: ["com.googlecode.iterm2", "dev.warp.Warp-Stable"])
        #expect(try DefaultApps(config: .default, facts: foldersOnly).commandTerminal().id == "iterm")
        // A configured default is used as it is, even when it cannot run a command.
        #expect(try DefaultApps(config: Config(terminal: "iterm"), facts: facts(installed: ["com.googlecode.iterm2", "com.apple.Terminal"])).commandTerminal().id == "iterm")
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
