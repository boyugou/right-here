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

    // MARK: One Undo of an agent taken out of two files

    /// The agents are listed in this Mac's own file and the agent of one's own is defined in config.toml. "Remove Agent" makes two changes (the list's entry, then the table), and the note
    /// "Removed Mine" offers one Undo. It takes back the table only: the agent is defined again but not in the menu, and config.local.toml stays without it. One Undo should give both files back.
    @Test func undoAfterRemovingAnAgentWhoseListAndTableAreInTwoFilesGivesBothBack() async throws {
        let shared = "[general]\nterminal = \"ghostty\"\n\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n"
        let local = "[general]\nagents = [\"claude\", \"mine\"]\n"
        let mac = try await EditedMac.started(shared: shared, local: local)
        defer { mac.cleanUp() }
        #expect(mac.model.agentOptions("mine") != nil && mac.model.general?.enabledAgents.map(\.id) == ["claude", "mine"])
        await mac.model.removeAgent("mine")
        #expect(mac.model.agentOptions("mine") == nil && !mac.shared.contains("agent.mine") && !mac.local.contains("mine"))
        #expect(mac.model.configEdit != nil, "the note of the removal, with its Undo")
        await mac.model.undoEdit()
        #expect(mac.shared == shared && mac.local == local,
                "one Undo of \"Removed Mine\" should give back both files; config.toml:\n\(mac.shared)\nconfig.local.toml:\n\(mac.local)")
        #expect(mac.model.general?.enabledAgents.map(\.id) == ["claude", "mine"], "and Mine back in the menu: \(mac.model.general?.enabledAgents.map(\.id) ?? [])")
    }

    // MARK: An Undo of one file is held to what the other file says

    /// The person adds an app (Tower, an editor: config.toml) and makes it this Mac's editor (config.local.toml, which sets the editor). On the Config page, config.toml's Recent Changes
    /// offers Undo on "add the app entry". Undo writes config.toml's earlier text without the check every edit has, that the two files together read without an error they did not have:
    /// config.local.toml's editor now names an app that is not there, and the config has an error the Undo brought. It should be refused, or say what it breaks, as an edit is.
    @Test func anUndoOfOneFileDoesNotLeaveTheOtherNamingWhatItTookOut() async throws {
        let mac = try await EditedMac.started(shared: Self.general, local: "[general]\neditor = \"vscode\"\n")
        defer { mac.cleanUp() }
        let made = await mac.model.createApp(name: "Probe Editor", bundleID: "org.example.probe-editor", role: .editor)
        #expect(made == "probe-editor", "\(String(describing: mac.model.notice))\n\(mac.shared)")
        await mac.model.setEditor("probe-editor")
        #expect(mac.local.contains("editor = \"probe-editor\""), "\(mac.local)")
        let errorsBefore = ConfigStore.load(paths: mac.paths).result.diagnostics.filter { $0.severity == .error }
        #expect(errorsBefore.isEmpty)
        await mac.model.openConfigPage()
        #expect(mac.model.configTarget == .shared && mac.model.configPage?.history.first?.summary.contains("app") == true)
        await mac.model.undoConfigChange()
        let errorsAfter = ConfigStore.load(paths: mac.paths).result.diagnostics.filter { $0.severity == .error }
        #expect(errorsAfter.isEmpty, "the Undo left the config with an error: \(errorsAfter.map(\.message)); notice: \(String(describing: mac.model.notice))\nconfig.toml:\n\(mac.shared)\nconfig.local.toml:\n\(mac.local)")
    }

    // MARK: Undo of a file whose line endings are mixed

    /// A config that came from Windows (CRLF) with a line appended by `echo … >>` (LF). Choosing "Automatic" for the editor takes that line out, and the file is all CRLF afterwards. The
    /// note's Undo then says the file "was changed after the last edit", which nobody did: the history holds the digest of the text as written, and Undo reads it back with its CRLF made LF.
    @Test func undoOfAChangeThatLeftAMixedFileAllCRLFIsMade() async throws {
        let shared = "[general]\r\nterminal = \"ghostty\"\r\nagents = [\"claude\"]\r\neditor = \"vscode\"\n"
        let mac = try await EditedMac.started(shared: shared)
        defer { mac.cleanUp() }
        #expect(mac.model.general?.editor == "vscode")
        await mac.model.setEditor(nil)
        #expect(mac.model.general?.editor == nil && mac.model.configEdit != nil, "the change was made: \(String(describing: mac.model.notice))")
        await mac.model.undoEdit()
        #expect(mac.sharedBytes == Data(shared.utf8), "Undo was refused: \(String(describing: mac.model.notice)); the file:\n\(mac.shared.debugDescription)")
    }

    // MARK: The first change of the built-in templates is held to the file that was read

    /// The window read a config that defines no template, so it shows the built-in ones. Something else (an assistant, `rh config`, the person in an editor) then gives the config a template of its
    /// own, which replaces the built-in ones. Customize Templates writes the five built-in templates next to it without a check: they come back, against the change that was made. Every other first
    /// change of a list the window shows is held to the file being as it was read (`expect(nil)`) and refused with "something else changed this list".
    @Test func customizingTheBuiltInTemplatesIsRefusedWhenTheFileDefinesTemplatesNow() async throws {
        let mac = try await EditedMac.started(shared: Self.general)
        defer { mac.cleanUp() }
        #expect(mac.model.newFile?.isBuiltIn == true)
        let theirs = Self.general + "\n[[new_file.template]]\nid = \"notes\"\ntitle = \"Notes\"\nextension = \"txt\"\n"
        try mac.writeShared(theirs)
        await mac.model.customizeTemplates()
        #expect(mac.shared == theirs, "the built-in templates were written out next to the template the file defines now:\n\(mac.shared)")
    }

    /// The same for the first New Template… of a window that still shows the built-in templates.
    @Test func aNewTemplateDoesNotBringTheBuiltInOnesBackWhenTheFileDefinesTemplatesNow() async throws {
        let mac = try await EditedMac.started(shared: Self.general)
        defer { mac.cleanUp() }
        let theirs = Self.general + "\n[[new_file.template]]\nid = \"notes\"\ntitle = \"Notes\"\nextension = \"txt\"\n"
        try mac.writeShared(theirs)
        _ = await mac.model.createTemplate(title: "Python Script", fileExtension: "py")
        let ids = mac.config.newFile.templates.map(\.id)
        #expect(!ids.contains("md"), "the built-in templates came back with the new one: \(ids)\n\(mac.shared)")
    }

    // MARK: A table written inline is not extended with a header

    /// `[agent]` with `claude = { command = "…" }` writes Claude Code's table inline, and TOML closes an inline table: nothing may be added to it below, a `[[agent.claude.variant]]` included
    /// (Python's `tomllib`: "Cannot mutate immutable namespace ('agent', 'claude', 'variant')"). New Start Option… appends one all the same, and Right Here's own parser reads the
    /// result, so nothing stops it: the file is no longer TOML for an editor's TOML support or any other tool. The window should refuse it with the sentence that sends the person to
    /// the text (`EditError.inlineTable`), as it does for a key of that table and for an inline array of entries (ADR 0026, review of stages 5 to 8).
    @Test func aStartOptionOfAnAgentWrittenInlineIsNotAppendedAsAHeader() async throws {
        let shared = Self.general + "\n[agent]\nclaude = { command = \"claude --model opus\" }\n"
        let mac = try await EditedMac.started(shared: shared)
        defer { mac.cleanUp() }
        #expect(mac.model.agentOptions("claude")?.command == "claude --model opus", "the config reads")
        _ = await mac.model.createVariant(agent: "claude", title: "Fast")
        let written = mac.shared
        #expect(written == shared, "the file now extends an inline table with a header (Right Here reads it: \(ConfigParser.canBeRead(written))):\n\(written)")
    }

    /// The same root cause for New Template… below `new_file = { then = "open" }`: the built-in templates and the new one are appended as `[[new_file.template]]` headers.
    @Test func aTemplateIsNotAppendedBelowAnInlineNewFileTable() async throws {
        let shared = "new_file = { then = \"open\" }\n\n" + Self.general
        let mac = try await EditedMac.started(shared: shared)
        defer { mac.cleanUp() }
        #expect(mac.model.newFile?.then == .open, "the config reads")
        _ = await mac.model.createTemplate(title: "Python Script", fileExtension: "py")
        let written = mac.shared
        #expect(written == shared, "the file now extends an inline table with headers (Right Here reads it: \(ConfigParser.canBeRead(written))):\n\(written)")
    }

    // MARK: A table that dotted keys define inside another table gets no header of its own

    /// `[agent]` with `claude.command = "…"` defines `agent.claude` with dotted keys. Choosing a terminal for Claude Code appends a `[agent.claude]` header, which defines that table a
    /// second time; the parser refuses that text, and the window says "TOML syntax error: this key or table is defined twice; each can be written once, so merge the two. Defaults apply
    /// until it is fixed": a sentence about the person's file, which is fine, of a line it does not have. The key should be written as `claude.terminal` under `[agent]` (what the
    /// document already does for dotted keys at the top of the file), or the change refused with the sentence that sends the person to the text. Every first setting of such an agent
    /// (terminal, how it starts, arguments, its prompts) meets this.
    @Test func aKeyOfATableThatDottedKeysDefineInsideATableIsWrittenAsADottedKey() async throws {
        let shared = Self.general + "\n[agent]\nclaude.command = \"claude --model opus\"\n"
        let mac = try await EditedMac.started(shared: shared)
        defer { mac.cleanUp() }
        #expect(mac.model.agentOptions("claude")?.command == "claude --model opus", "the config reads")
        await mac.model.setAgentTerminal("claude", "terminal")
        let said = mac.model.notice?.text(in: .english, isolatingValues: false) ?? ""
        let written = mac.config.agents["claude"]?.launcher == .terminal("terminal") && mac.shared.contains("claude.terminal = \"terminal\"")
        #expect(written || said.contains("dotted keys"), "neither written as a dotted key nor refused for what it is; the window said: \(said)\n\(mac.shared)")
    }

    // MARK: An entry's commented-out setting goes with it

    /// A preset of one's own whose last line is a setting the person commented out (`# max_files = 3`). Remove Preset takes the entry and leaves that line in the file, where it now reads
    /// as a note of whatever is above it. Taking out an agent's table takes such a line with it (`removingTable`: "the comment lines right after that (a setting that is commented
    /// out, `# args = ["--fast"]`)"); an entry of a list of tables does not (`slots(of:)` ends at the last key).
    @Test func removingAPresetTakesItsCommentedOutSettingWithIt() async throws {
        let before = Self.general + "\n[menu]\nitems = [\"open-terminal\", \"agents-more\"]\n"
        let shared = before + "\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n# max_files = 3\n"
        let mac = try await EditedMac.started(shared: shared)
        defer { mac.cleanUp() }
        #expect(mac.model.preset("mine")?.origin == .own)
        await mac.model.removePreset("mine")
        #expect(mac.model.preset("mine") == nil)
        #expect(!mac.shared.contains("max_files"), "the preset is gone and its commented-out setting is left behind:\n\(mac.shared)")
    }

    /// The same cause seen from New Preset…: the new entry goes right after the last key of the last preset, above that preset's `# max_files = 3`, which then reads as the new
    /// preset's setting.
    @Test func aNewPresetDoesNotTakeTheCommentedOutSettingOfThePresetAboveIt() async throws {
        let shared = Self.general + "\n[[preset]]\nid = \"mine\"\ntitle = \"Mine\"\nprompt = \"Look at {files}.\"\n# max_files = 3\n\n[menu]\nitems = [\"open-terminal\", \"agents-more\"]\n"
        let mac = try await EditedMac.started(shared: shared)
        defer { mac.cleanUp() }
        #expect(await mac.model.createPreset(title: "Second", prompt: "Read {files}."))
        let text = mac.shared
        let comment = try #require(text.range(of: "# max_files = 3"))
        let second = try #require(text.range(of: "id = \"second\""))
        #expect(comment.lowerBound < second.lowerBound, "the commented-out setting of \"mine\" now stands under the new preset:\n\(text)")
    }
}
