import Foundation
import Testing
import RightHereCore
import RightHereKit
@testable import AppModel

// What an independent review of the window's editors found (2026-11-13), each kept as the test that failed on the code it was found in.
// Nothing here touches the real home, Finder, the clipboard or an installed app: a temporary home, made-up facts and a runner that answers every process with success.

/// A Mac of made-up facts with a temporary home, and a window model over it.
@MainActor
struct EditedMac {
    let home: URL
    let paths: RHPaths
    let model: SetupModel

    init() throws {
        home = try makeTemporaryDirectory()
        paths = RHPaths(environment: [:], home: home)
        let facts = FakeSystemFacts(homeDirectory: home, directories: [home.path], applications: [
            "com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"),
            "com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
        ])
        let runner = FakeProcessRunner()
        let helper = "/Applications/Right Here.app/Contents/Helpers/rh"
        let loader = SetupLoader(facts: facts, paths: paths, runner: runner, helperPath: helper, localizer: .english)
        let actions = SetupActions(facts: facts, paths: paths, runner: runner, helperPath: helper, app: nil, trialHome: home)
        model = SetupModel(loader: loader, actions: actions, facts: facts, helper: helper, pollInterval: .milliseconds(10), idleInterval: .milliseconds(10),
                           activationQuietPeriod: .zero, patience: .seconds(30), windowIsVisible: { true })
    }

    /// The model, read from a config.toml of `shared` and, when there is one, a config.local.toml of `local`.
    static func started(shared: String, local: String? = nil) async throws -> EditedMac {
        let mac = try EditedMac()
        try FileManager.default.createDirectory(at: mac.paths.configDirectory, withIntermediateDirectories: true)
        try shared.write(to: mac.paths.configFile, atomically: true, encoding: .utf8)
        if let local { try local.write(to: mac.paths.localConfigFile, atomically: true, encoding: .utf8) }
        await mac.model.refresh()
        return mac
    }

    func cleanUp() { try? FileManager.default.removeItem(at: home) }
    var shared: String { (try? String(contentsOf: paths.configFile, encoding: .utf8)) ?? "" }
    var local: String { (try? String(contentsOf: paths.localConfigFile, encoding: .utf8)) ?? "" }
    var sharedBytes: Data { (try? Data(contentsOf: paths.configFile)) ?? Data() }
    var config: Config { ConfigStore.load(paths: paths).config }
    func writeShared(_ text: String) throws { try text.write(to: paths.configFile, atomically: true, encoding: .utf8) }
}

@Suite("The window's editors, after an independent review")
@MainActor
struct WindowEditorsReviewTests {
    private static let general = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n"

    // MARK: A default chosen on this Mac is the default, and config.toml is not touched

    /// Claude Code starts through its desktop app on this Mac (`config.local.toml`) and through its terminal link on the others (`config.toml`). "In a terminal", its default, took
    /// `launcher` out of this Mac's file, and config.toml's `link` held; choosing it again then took `launcher` out of config.toml, which every other Mac reads. The default is
    /// written in this Mac's file instead (`ConfigOperation.reset`).
    @Test func choosingInATerminalForAnAgentGivesATerminal() async throws {
        let shared = Self.general + "\n[agent.claude]\nlauncher = \"link\"\n"
        let mac = try await EditedMac.started(shared: shared, local: "[agent.claude]\nlauncher = \"desktop\"\n")
        defer { mac.cleanUp() }
        #expect(mac.model.agentOptions("claude")?.launcher == .desktop)
        await mac.model.setAgentLauncher("claude", .terminal)
        #expect(mac.model.agentOptions("claude")?.launcher == .terminal, "config.local.toml: \(mac.local)")
        #expect(mac.local == "[agent.claude]\nlauncher = \"terminal\"\n")
        await mac.model.setAgentLauncher("claude", .terminal)
        #expect(mac.shared == shared, "a choice made on this Mac changed config.toml:\n\(mac.shared)")
    }

    /// The same for "After a file is made": this Mac said `nothing`, config.toml `open`, and "Select it in Finder" gave `open`.
    @Test func choosingSelectItInFinderAfterANewFileGivesThat() async throws {
        let mac = try await EditedMac.started(shared: Self.general + "\n[new_file]\nthen = \"open\"\n", local: "[new_file]\nthen = \"nothing\"\n")
        defer { mac.cleanUp() }
        await mac.model.setNewFileThen(.reveal)
        #expect(mac.model.newFile?.then == .reveal && mac.local == "[new_file]\nthen = \"reveal\"\n", "config.local.toml: \(mac.local)")
    }

    /// Typing an agent's built-in command (`claude`) took `command` out of this Mac's file, and config.toml's `claude --model sonnet` held; typing it again took it out of config.toml.
    @Test func typingTheBuiltInCommandGivesTheBuiltInCommand() async throws {
        let shared = Self.general + "\n[agent.claude]\ncommand = \"claude --model sonnet\"\n"
        let mac = try await EditedMac.started(shared: shared, local: "[agent.claude]\ncommand = \"claude --model opus\"\n")
        defer { mac.cleanUp() }
        await mac.model.setAgentCommand("claude", "claude")
        #expect(mac.model.agentOptions("claude")?.command == "claude", "config.local.toml: \(mac.local)")
        await mac.model.setAgentCommand("claude", "claude")
        #expect(mac.shared == shared, "typing it again on this Mac changed config.toml:\n\(mac.shared)")
    }

    /// The way an agent takes a first prompt, typed back to its built-in way: the same, for a setting that no probe of the review covered.
    @Test func thePromptWayTypedBackToTheBuiltInOneIsTheBuiltInOne() async throws {
        let shared = Self.general + "\n[agent.claude]\nprompt_arg = \"--prompt\"\n"
        let mac = try await EditedMac.started(shared: shared, local: "[agent.claude]\nprompt_arg = \"-p\"\n")
        defer { mac.cleanUp() }
        await mac.model.setAgentPromptArgument("claude", "")
        #expect(mac.config.agent(id: "claude")?.promptArgument == .positional && mac.shared == shared, "config.local.toml: \(mac.local)")
    }

    /// This Mac titled Copy Path `Pfad`, config.toml `Path`: emptying the field, which means the default title, gave `Path`. An empty title is the default (`title = ""`).
    @Test func emptyingTheTitleOfCopyPathGivesTheDefaultTitle() async throws {
        let mac = try await EditedMac.started(shared: Self.general + "\n[copy_path]\ntitle = \"Path\"\n", local: "[copy_path]\ntitle = \"Pfad\"\n")
        defer { mac.cleanUp() }
        await mac.model.setCopyPathTitle("")
        #expect(mac.model.copyPath?.title == nil && mac.local == "[copy_path]\ntitle = \"\"\n", "config.local.toml: \(mac.local)")
    }

    // MARK: A read that began before a change keeps the default rows the change showed

    /// When this Mac's file and config.toml both set the terminal, its default row says "As in config.toml (Terminal)" (`underneath`). The person chooses it: this Mac's file no longer
    /// sets the key, and the row is "Automatic (Ghostty)" again. A read of the whole state that began before the change (the doctor takes seconds) then ends: `apply` keeps the editors
    /// the change showed (menu, general, agents, presets, …) but not `underneath`, so the row says "As in config.toml (Terminal)" again, and choosing it now would take the terminal out of
    /// config.toml and give Ghostty: the very mismatch the default rows were made to end. `SetupSnapshot.take` now lists every part that comes from the config, once.
    @Test func aReadThatBeganBeforeAChangeDoesNotPutTheOldDefaultRowsBack() async throws {
        let mac = try await EditedMac.started(shared: "[general]\nterminal = \"terminal\"\nagents = [\"claude\"]\n", local: "[general]\nterminal = \"ghostty\"\n")
        defer { mac.cleanUp() }
        #expect(mac.model.snapshot?.underneath["general.terminal"] == "terminal")
        var stale = try #require(mac.model.snapshot)
        stale.readAt = .now
        try await Task.sleep(for: .milliseconds(5))
        await mac.model.setTerminal(nil)
        #expect(mac.model.snapshot?.underneath["general.terminal"] == nil && !mac.local.contains("terminal"))
        mac.model.apply(stale)
        let row = mac.model.defaultChoiceTitle(for: "general.terminal", automatic: "Automatic (Ghostty)") { $0 }
        #expect(row == "Automatic (Ghostty)", "the default row says \"\(row)\" again after the stale read, though this Mac's file no longer sets the terminal")
    }
}
