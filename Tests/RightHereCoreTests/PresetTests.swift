import Foundation
import Testing
@testable import RightHereCore

private let appFolder = "/Users/tester/code/app"

private func machine(files: [String] = [], extraDirectories: [String] = [], installed: [String] = ["com.mitchellh.ghostty", "com.apple.Terminal"]) -> FakeSystemFacts {
    FakeSystemFacts(
        directories: Set(["/Users/tester/code", appFolder] + extraDirectories),
        files: Set(files.map { "\(appFolder)/\($0)" }),
        gitRoots: [appFolder],
        applications: Dictionary(uniqueKeysWithValues: installed.map { ($0, URL(fileURLWithPath: "/Applications/\($0).app")) })
    )
}

private func selection(_ names: [String]) -> HereContext {
    HereContext(origin: .items, items: names.map { URL(fileURLWithPath: "\(appFolder)/\($0)") })
}

private let folderContext = HereContext(origin: .container, container: URL(fileURLWithPath: appFolder))

/// A machine that counts how often it is asked whether an item is a folder, so a test can say how much a menu looks at.
private final class CountingFacts: SystemFacts, @unchecked Sendable {
    private let base: FakeSystemFacts
    private let lock = NSLock()
    private var questions = 0

    init(_ base: FakeSystemFacts) { self.base = base }

    var directoryQuestions: Int { lock.withLock { questions } }
    func reset() { lock.withLock { questions = 0 } }

    var homeDirectory: URL { base.homeDirectory }
    var currentDirectory: URL { base.currentDirectory }
    var loginShell: String { base.loginShell }
    func isDirectory(_ url: URL) -> Bool? {
        lock.withLock { questions += 1 }
        return base.isDirectory(url)
    }
    func fileExists(_ url: URL) -> Bool { base.fileExists(url) }
    func itemState(_ url: URL) -> ItemState { base.itemState(url) }
    func gitRoot(containing url: URL) -> URL? { base.gitRoot(containing: url) }
    func applicationURL(bundleID: String) -> URL? { base.applicationURL(bundleID: bundleID) }
    func displayName(bundleID: String) -> String? { base.displayName(bundleID: bundleID) }
    func bundleVersion(bundleID: String) -> String? { base.bundleVersion(bundleID: bundleID) }
    func isRunning(bundleID: String) -> Bool { base.isRunning(bundleID: bundleID) }
    func environment(_ key: String) -> String? { base.environment(key) }
    func onDiskPath(_ url: URL) -> String { base.onDiskPath(url) }
}

/// A config whose `claude` types `printf '%s\0' ...`, so a real shell prints each word it was given, NUL-terminated.
private func printingConfig(presets: [AgentPreset], promptArgument: PromptArgument? = nil) -> Config {
    Config(
        enabledAgents: ["claude"],
        agents: ["claude": .init(command: "printf '%s\\0'", promptArgument: promptArgument)],
        presets: presets
    )
}

private func typedText(_ plan: LaunchPlan) throws -> String {
    guard case .appleScript(let step)? = plan.steps.first else { throw TestFailure("expected a typed launch, got \(plan.steps)") }
    return step.arguments[1]
}

private struct TestFailure: Error { init(_ message: String) { self.message = message }; let message: String }

@Suite("Agent presets: planning")
struct PresetPlannerTests {
    private let review = AgentPreset(id: "review", title: "Review", prompt: "Review {files} in {folder} (first: {name}).")

    @Test func theSelectionBecomesMentionsRelativeToTheFolderAndTheTemplateIsFilledIn() throws {
        let config = Config(enabledAgents: ["claude"], presets: [review])
        let plan = try Planner(config: config, facts: machine(files: ["a.txt", "b b.md"])).plan(.preset(id: "review", terminal: nil), context: selection(["a.txt", "b b.md"]))
        #expect(try typedText(plan) == "claude 'Review @a.txt @\"b b.md\" in app (first: a.txt).'")
        guard case .appleScript(let step)? = plan.steps.first else { return }
        #expect(step.arguments[0] == appFolder)
    }

    @Test func aFileNamedLikeAPlaceholderIsNotExpandedAgain() throws {
        let preset = AgentPreset(id: "p", title: "P", prompt: "{files}|{name}|{folder}")
        let config = Config(enabledAgents: ["claude"], presets: [preset])
        let plan = try Planner(config: config, facts: machine(files: ["{folder}.md", "{files}"])).plan(.preset(id: "p", terminal: nil), context: selection(["{folder}.md", "{files}"]))
        #expect(try typedText(plan) == "claude '@{folder}.md @{files}|{folder}.md|app'")
    }

    @Test func aPresetThatDoesNotNameFilesRunsOnAFolderAndNameIsTheFolder() throws {
        let preset = AgentPreset(id: "p", title: "P", prompt: "Summarize {name}")
        let config = Config(enabledAgents: ["claude"], presets: [preset])
        let plan = try Planner(config: config, facts: machine()).plan(.preset(id: "p", terminal: nil), context: folderContext)
        #expect(try typedText(plan) == "claude 'Summarize app'")
    }

    @Test func aPresetThatNeedsFilesIsRefusedWithoutThem() {
        let config = Config(enabledAgents: ["claude"], presets: [review])
        let planner = Planner(config: config, facts: machine(extraDirectories: ["\(appFolder)/src"]))
        for context in [folderContext, selection(["src"])] {
            do { _ = try planner.plan(.preset(id: "review", terminal: nil), context: context); Issue.record("expected a refusal") } catch let error as PlanError {
                #expect(error.errorDescription?.contains("select one or more files") == true, Comment(rawValue: error.errorDescription ?? ""))
            } catch { Issue.record("\(error)") }
        }
    }

    @Test func moreFilesThanMaxFilesAreRefusedNotCutShort() {
        var preset = review
        preset.maxFiles = 2
        let names = ["a", "b", "c"]
        let config = Config(enabledAgents: ["claude"], presets: [preset])
        do { _ = try Planner(config: config, facts: machine(files: names)).plan(.preset(id: "review", terminal: nil), context: selection(names)); Issue.record("expected a refusal") } catch let error as PlanError {
            #expect(error.errorDescription?.contains("at most 2") == true, Comment(rawValue: error.errorDescription ?? ""))
        } catch { Issue.record("\(error)") }
    }

    @Test func foldersInTheSelectionAreNotMentionedAndSaySo() throws {
        let config = Config(enabledAgents: ["claude"], presets: [review])
        let plan = try Planner(config: config, facts: machine(files: ["a.txt"], extraDirectories: ["\(appFolder)/src"])).plan(.preset(id: "review", terminal: nil), context: selection(["a.txt", "src"]))
        #expect(try typedText(plan).contains("@a.txt in"))
        #expect(!(try typedText(plan).contains("@src")))
        #expect(plan.notices.contains { $0.contains("Folders in the selection") })
    }

    @Test func aFlagAgentGetsItsFlagBeforeThePrompt() throws {
        let config = Config(enabledAgents: ["claude"], agents: ["claude": .init(promptArgument: .flag("--prompt"))], presets: [review])
        let plan = try Planner(config: config, facts: machine(files: ["a.txt"])).plan(.preset(id: "review", terminal: nil), context: selection(["a.txt"]))
        #expect(try typedText(plan).hasPrefix("claude --prompt 'Review @a.txt"))
    }

    @Test func anAgentNotKnownToTakeAPromptIsRefusedAndItsPresetIsNotOffered() {
        let preset = AgentPreset(id: "review", title: "Review", agent: "aider", prompt: "Review {files}")
        let config = Config(enabledAgents: ["aider"], presets: [preset])
        let facts = machine(files: ["a.txt"])
        #expect(throws: PlanError.self) { try Planner(config: config, facts: facts).plan(.preset(id: "review", terminal: nil), context: selection(["a.txt"])) }
        let info = ActionRegistry(config: config, facts: facts).info(.preset(id: "review", terminal: nil))
        #expect(!info.available && info.unavailableReason?.contains("prompt_arg") == true)
    }

    /// What starts an interactive session with a first prompt, from each tool's own documentation (ADR 0024); `agy` was also read from its `--help`.
    /// The tools that have only a flag that runs once and exits (Kimi Code's `-p`), no documented way (Goose, Amp, aider) or no confirmation
    /// (Muse Code; opencode's `--prompt`, whose documentation does not say whether it submits, and whose positional argument is the project)
    /// have none here: a preset then says so, and the config can set `prompt_arg`.
    @Test func theBuiltInPromptArgumentsStartAnInteractiveSession() {
        #expect(KnownAgents.claude.promptArgument == .positional && KnownAgents.codex.promptArgument == .positional)
        #expect(KnownAgents.agy.promptArgument == .flag("-i"), "agy -p and --prompt are aliases of --print, which runs once")
        #expect(KnownAgents.gemini.promptArgument == .flag("-i"), "gemini -p runs once")
        #expect(KnownAgents.copilot.promptArgument == .flag("-i"), "copilot -p runs once")
        #expect(KnownAgents.cursor.promptArgument == .positional, "agent \"…\" under its documentation's Interactive mode; -p runs once")
        #expect(KnownAgents.qwen.promptArgument == .flag("-i"), "qwen -i is --prompt-interactive; -p runs once")
        #expect(KnownAgents.droid.promptArgument == .positional, "droid \"query\" starts the REPL with it; droid exec runs once")
        #expect(KnownAgents.kiro.promptArgument == .positional, "kiro-cli chat [INPUT] is the first question; --no-interactive runs once")
        for id in ["opencode", "kimi", "muse", "goose", "aider", "amp"] {
            #expect(KnownAgents.agent(id: id)?.promptArgument == nil, "\(id)")
        }
    }

    @Test func aCommandThatCarriesAnArgumentIsLookedUpByItsFirstWord() {
        // `goose` alone prints its help; the session is `goose session`.
        #expect(KnownAgents.goose.command == "goose session")
        #expect(KnownAgents.goose.executable == "goose")
        #expect(KnownAgents.kiro.executable == "kiro-cli", "`kiro` alone starts the Kiro IDE")
        #expect(KnownAgents.all.allSatisfy { $0.executable == $0.command || ["goose", "kiro"].contains($0.id) })
    }

    @Test func aPresetUsesTheFirstEnabledAgentUnlessItNamesOne() throws {
        let config = Config(enabledAgents: ["codex", "claude"], presets: [review])
        let plan = try Planner(config: config, facts: machine(files: ["a.txt"])).plan(.preset(id: "review", terminal: nil), context: selection(["a.txt"]))
        #expect(try typedText(plan).hasPrefix("codex 'Review"))
        let named = AgentPreset(id: "review", title: "Review", agent: "claude", prompt: "Review {files}")
        let other = try Planner(config: Config(enabledAgents: ["codex", "claude"], presets: [named]), facts: machine(files: ["a.txt"])).plan(.preset(id: "review", terminal: nil), context: selection(["a.txt"]))
        #expect(try typedText(other).hasPrefix("claude 'Review"))
    }

    @Test func noEnabledAgentIsAnErrorThatSaysWhatToDo() {
        do { _ = try Planner(config: Config(presets: [review]), facts: machine(files: ["a.txt"])).plan(.preset(id: "review", terminal: nil), context: selection(["a.txt"])); Issue.record("expected a refusal") } catch let error as PlanError {
            #expect(error.errorDescription?.contains("general.agents") == true)
        } catch { Issue.record("\(error)") }
    }

    @Test func anUnknownPresetNamesTheOnesThatExist() {
        do { _ = try Planner(config: Config(enabledAgents: ["claude"]), facts: machine()).plan(.preset(id: "reveiw", terminal: nil), context: folderContext); Issue.record("expected an error") } catch let error as PlanError {
            #expect(error.errorDescription?.contains("Did you mean \"review\"?") == true, Comment(rawValue: error.errorDescription ?? ""))
        } catch { Issue.record("\(error)") }
    }

    @Test func aPresetNeverUsesTheLinkOrDesktopLauncherOfItsAgent() throws {
        let config = Config(enabledAgents: ["claude"], agents: ["claude": .init(launcher: .terminalLink)], presets: [review])
        let plan = try Planner(config: config, facts: machine(files: ["a.txt"])).plan(.preset(id: "review", terminal: nil), context: selection(["a.txt"]))
        guard case .appleScript? = plan.steps.first else { Issue.record("expected a typed launch, got \(plan.steps)"); return }
    }

    @Test func aNamedTerminalIsUsed() throws {
        let plan = try Planner(config: Config(enabledAgents: ["claude"], presets: [review]), facts: machine(files: ["a.txt"]))
            .plan(.preset(id: "review", terminal: "terminal"), context: selection(["a.txt"]))
        guard case .appleScript(let step)? = plan.steps.first else { Issue.record("expected AppleScript"); return }
        #expect(step.controls == "Terminal")
    }

    // MARK: Refusals

    @Test("a file whose name cannot be typed in the prompt is named, and the prompt is not blamed", arguments: [
        "new\nline.txt", "carriage\rreturn.txt", "tab\there.txt", "bell\u{7}.txt", "escape\u{1B}[2J.txt", "line\u{2028}separator.txt",
        "back\\slash.txt", "quote \"and space.txt"
    ])
    func hostileFileNamesAreRefused(name: String) {
        let config = Config(enabledAgents: ["claude"], presets: [review])
        let facts = machine(files: [name])
        do { _ = try Planner(config: config, facts: facts).plan(.preset(id: "review", terminal: nil), context: selection([name])); Issue.record("expected a refusal") } catch let error as PlanError {
            guard case .unsafePresetName(let preset, let subject, _) = error else { Issue.record("expected .unsafePresetName, got \(error)"); return }
            #expect(preset == "review")
            // The file is the one named, by its own name, quoted once.
            #expect(subject == "the file " + name.jsonQuoted)
            let message = error.errorDescription ?? ""
            #expect(message.hasPrefix("the file " + name.jsonQuoted + " cannot be named in the prompt of preset \"review\": "), Comment(rawValue: message))
            #expect(!message.hasPrefix("The prompt of preset"))
            #expect(!message.contains("\"\""))
            // Whatever the name held, the message shows it escaped, never as a raw line break.
            #expect(!message.unicodeScalars.contains(where: { $0.value < 0x20 }))
        } catch { Issue.record("\(error)") }
    }

    @Test("a file whose name shows nothing or reads as something else is named, and the prompt is not blamed", arguments: [
        "report\u{202E}gnp.exe.txt", "zero\u{200B}width.txt", "tag\u{E0073}\u{E0074}.md", "soft\u{00AD}hyphen.txt", "bom\u{FEFF}.txt", "word\u{2060}joiner.txt", "isolate\u{2066}x.txt",
        "notes😀\u{E0100}\u{E0101}\u{E0102}.txt", "plan\u{2062}\u{2063}\u{2064}\u{2061}.txt", "join\u{200D}ed.txt", "arabic\u{0600}number.txt".replacingOccurrences(of: "\u{0600}", with: "\u{2066}")
    ])
    func misleadingFileNamesAreRefused(name: String) {
        let config = Config(enabledAgents: ["claude"], presets: [review])
        do { _ = try Planner(config: config, facts: machine(files: [name])).plan(.preset(id: "review", terminal: nil), context: selection([name])); Issue.record("expected a refusal") } catch let error as PlanError {
            guard case .unsafePresetName(_, let subject, let reason) = error else { Issue.record("expected .unsafePresetName, got \(error)"); return }
            #expect(subject == "the file " + name.jsonQuoted)
            #expect(reason.hasPrefix("its name has a character that shows nothing or changes how it reads"), Comment(rawValue: reason))
            let message = error.errorDescription ?? ""
            #expect(!message.unicodeScalars.contains(where: ConfigBuilder.changesHowTextReads), "the message shows the character escaped, as the person could not see it otherwise: \(message)")
        } catch { Issue.record("\(error)") }
    }

    @Test func namesInAnyScriptAreCarriedInThePrompt() throws {
        let names = ["日本語.txt", "عربي\u{200F}.txt", "naïve café.md", "👨\u{200D}👩.txt", "שלום\u{200E}.txt", "جواب\u{061C}.txt", "emoji❤\u{FE0F}.txt", "ཀ\u{0F71}.txt", "می\u{200C}خواهم.txt"]
        let config = Config(enabledAgents: ["claude"], presets: [review])
        for name in names {
            let plan = try Planner(config: config, facts: machine(files: [name])).plan(.preset(id: "review", terminal: nil), context: selection([name]))
            #expect(!plan.steps.isEmpty, "\(name.debugDescription)")
        }
    }

    @Test("a preset keeps the permission prompts on: an agent whose command or arguments already carry the flag is refused", arguments: [
        ("claude --dangerously-skip-permissions", [String]()), ("claude", ["--dangerously-skip-permissions"]), ("claude --model opus --dangerously-skip-permissions --verbose", [String]())
    ])
    func aFlagThatSwitchesThePromptsOffIsNotTypedForAPreset(command: String, args: [String]) {
        let config = Config(enabledAgents: ["claude"], agents: ["claude": .init(command: command, args: args)], presets: [review])
        do { _ = try Planner(config: config, facts: machine(files: ["a.txt"])).plan(.preset(id: "review", terminal: nil), context: selection(["a.txt"])); Issue.record("expected a refusal") } catch let error as PlanError {
            #expect(error.errorDescription?.contains("--dangerously-skip-permissions, which switches its permission prompts off") == true, Comment(rawValue: error.errorDescription ?? ""))
        } catch { Issue.record("\(error)") }
    }

    @Test("the guard of a preset reads the line as a shell does, and does not depend on a setting that can be blanked", arguments: [
        // (agent, its settings): the flag blanked, the other spelling of a flag, quotes, a path to the program, the program of a built-in agent under another name
        ("claude", Config.AgentSettings(command: "claude --dangerously-skip-permissions", bypassPermissionArgument: "")),
        ("claude", Config.AgentSettings(command: "claude \"--dangerously-skip-permissions\"")),
        ("claude", Config.AgentSettings(command: "claude '--dangerously-skip-permissions'")),
        ("claude", Config.AgentSettings(command: "/usr/local/bin/claude --dangerously-skip-permissions")),
        ("claude", Config.AgentSettings(command: "claude", promptArgument: .flag("--dangerously-skip-permissions"), args: [])),
        ("gemini", Config.AgentSettings(args: ["--approval-mode", "yolo"])),
        ("gemini", Config.AgentSettings(command: "gemini --approval-mode yolo")),
        ("gemini", Config.AgentSettings(command: "gemini --approval-mode=yolo")),
        ("claude", Config.AgentSettings(bypassPermissionArgument: "--permission-mode bypassPermissions", args: ["--permission-mode", "bypassPermissions"]))
    ])
    func aFlagThatSwitchesThePromptsOffIsRecognisedWhateverTheSpellingOrTheSettings(agent: String, settings: Config.AgentSettings) {
        let config = Config(enabledAgents: [agent], agents: [agent: settings], presets: [AgentPreset(id: "p", title: "P", agent: agent, prompt: "Review {files}")])
        do { _ = try Planner(config: config, facts: machine(files: ["a.txt"])).plan(.preset(id: "p", terminal: nil), context: selection(["a.txt"])); Issue.record("expected a refusal for \(settings)") } catch let error as PlanError {
            #expect(error.errorDescription?.contains("which switches its permission prompts off") == true, Comment(rawValue: error.errorDescription ?? ""))
        } catch { Issue.record("\(error)") }
    }

    @Test func anAgentOfOnesOwnThatRunsABuiltInAgentWithItsFlagIsRefusedAndOneThatRunsAToolOfItsOwnIsNot() throws {
        let mine = AgentDescriptor(id: "cc", name: "Claude (fast)", command: "claude --dangerously-skip-permissions", promptArgument: .positional)
        let refused = Config(enabledAgents: ["cc"], customAgents: [mine], presets: [AgentPreset(id: "p", title: "P", agent: "cc", prompt: "Review {files}")])
        #expect(throws: PlanError.self) { try Planner(config: refused, facts: machine(files: ["a.txt"])).plan(.preset(id: "p", terminal: nil), context: selection(["a.txt"])) }
        for command in ["mytool --auto", "mytool --yolo --allow-all", "tool --approval mode yolo"] {
            let own = AgentDescriptor(id: "mine", name: "Mine", command: command, promptArgument: .positional)
            let allowed = Config(enabledAgents: ["mine"], customAgents: [own], presets: [AgentPreset(id: "p", title: "P", agent: "mine", prompt: "Review {files}")])
            #expect(throws: Never.self, "\(command)") { try Planner(config: allowed, facts: machine(files: ["a.txt"])).plan(.preset(id: "p", terminal: nil), context: selection(["a.txt"])) }
        }
    }

    @Test func aFlagOfSeveralWordsIsMatchedNextToEachOtherAndInOrder() {
        let typed = ["--permission-mode", "plan", "--append-system-prompt", "bypassPermissions"]
        #expect(!ShellWords.carries(typed, flag: "--permission-mode bypassPermissions"), "the words are there, but not next to each other")
        #expect(ShellWords.carries(["x", "--permission-mode", "bypassPermissions"], flag: "--permission-mode bypassPermissions"))
        #expect(!ShellWords.carries(["bypassPermissions", "--permission-mode"], flag: "--permission-mode bypassPermissions"))
        #expect(ShellWords.split(#"claude "a b" 'c d' e\ f --x=y"#) == ["claude", "a b", "c d", "e f", "--x=y"])
        #expect(ShellWords.carries(ShellWords.split("tool --approval-mode=yolo"), flag: "--approval-mode yolo") && ShellWords.carries(["--approval-mode", "yolo"], flag: "--approval-mode=yolo"))
    }

    @Test("the guard of a preset sees the flag behind what the shell makes of the line: an assignment or a wrapper before the program, another case, $'…', a redirection", arguments: [
        "FOO=1 claude --dangerously-skip-permissions",
        "CLAUDE_CONFIG_DIR=/tmp/work claude --dangerously-skip-permissions",
        "env claude --dangerously-skip-permissions",
        "exec claude --dangerously-skip-permissions",
        "Claude --dangerously-skip-permissions",
        "/usr/local/bin/CLAUDE --dangerously-skip-permissions",
        "claude $'--dangerously-skip-permissions'",
        "claude $'\\x2d\\x2ddangerously-skip-permissions'",
        "claude --dangerously-skip-permissions>&1",
        "claude --dangerously-skip-permissions 2>/dev/null",
        "claude;--dangerously-skip-permissions",
        // An octal escape is a byte to the shells: \455 is 0x2D, a minus.
        "claude $'\\455\\455dangerously-skip-permissions'",
        // The line of another command, inside one word.
        "sh -c 'claude --dangerously-skip-permissions \"$@\"' sh",
        "eval 'claude --dangerously-skip-permissions'",
        "env -S 'claude --dangerously-skip-permissions'",
        "bash -lc \"sh -c 'claude --dangerously-skip-permissions'\"",
        // zsh's =claude is the path of the program.
        "=claude --dangerously-skip-permissions"
    ])
    func theGuardOfAPresetSeesTheFlagBehindWhatTheShellMakesOfTheLine(command: String) {
        let own = AgentDescriptor(id: "work", name: "Work", command: command, promptArgument: .positional)
        let config = Config(enabledAgents: ["work"], customAgents: [own], presets: [AgentPreset(id: "p", title: "P", agent: "work", prompt: "Review {files}")])
        do { _ = try Planner(config: config, facts: machine(files: ["a.txt"])).plan(.preset(id: "p", terminal: nil), context: selection(["a.txt"])); Issue.record("expected a refusal for \(command)") } catch let error as PlanError {
            #expect(error.errorDescription?.contains("which switches its permission prompts off") == true, Comment(rawValue: error.errorDescription ?? ""))
        } catch { Issue.record("\(error)") }
    }

    @Test("a command whose result depends on something that is not in it is refused for a preset: the flag may be behind it", arguments: [
        "claude $(printf %s --dangerously-skip-permissions)",
        "claude `printf %s --dangerously-skip-permissions`",
        "claude ${PWD+--dangerously-skip-permissions}",
        "claude {--dangerously-skip-permissions,--verbose}",
        "claude --model \"$MODEL\"",
        "claude 'not closed",
        // Braces that hold a space (quoted, escaped, or one that is not a space to the shells), a glob, a qualifier of zsh's that runs code, the history of the shell.
        "claude {--dangerously-skip-permissions,' '}",
        "claude {--dangerously-skip-permissions,a\\ b}",
        "claude {--dangerously-skip-permissions,a\u{A0}b}",
        "claude {--dangerously-skip-permissions,a\u{3000}b}",
        "claude {--dangerously-skip-permissions,\"a b\"}",
        "claude --dangerously-skip-permission?",
        "claude --dangerously-skip-permis[s]ions",
        "claude *",
        "claude *([1]e:'reply=(--dangerously-skip-permissions)':)",
        "claude --verbose !#:1:s/verbose/dangerously-skip-permissions/",
        "claude \"!#:0:s/claude/--dangerously-skip-permissions/\""
    ])
    func aCommandWithAnExpansionIsRefusedForAPreset(command: String) {
        let config = Config(enabledAgents: ["claude"], agents: ["claude": .init(command: command)], presets: [review])
        do { _ = try Planner(config: config, facts: machine(files: ["a.txt"])).plan(.preset(id: "review", terminal: nil), context: selection(["a.txt"])); Issue.record("expected a refusal for \(command)") } catch let error as PlanError {
            // A flag that is there to be read is refused for being there; one that is not is refused for what might hide it.
            let said = error.errorDescription ?? ""
            #expect(said.contains("shell syntax whose result Right Here cannot read") || said.contains("which switches its permission prompts off"), Comment(rawValue: said))
        } catch { Issue.record("\(error)") }
    }

    @Test("a command of plain words, quotes and assignments is still started by a preset", arguments: [
        "claude --model opus", "FOO=1 claude --model opus", "env FOO=1 claude", "claude --append-system-prompt '{a,b} $HOME `x`'", "claude --append-system-prompt \"it's\"", "Claude"
    ])
    func aPlainCommandIsStillStartedByAPreset(command: String) throws {
        let config = Config(enabledAgents: ["claude"], agents: ["claude": .init(command: command)], presets: [review])
        let typed = try typedText(Planner(config: config, facts: machine(files: ["a.txt"])).plan(.preset(id: "review", terminal: nil), context: selection(["a.txt"])))
        #expect(typed.hasPrefix(command + " "), "\(typed)")
    }

    @Test func aShellReaderReadsQuotesEscapesRedirectionsAndSaysWhatItCannotRead() {
        func words(_ line: String) -> [String] { ShellWords.split(line) }
        #expect(words("a  b\tc") == ["a", "b", "c"])
        #expect(words("claude $'--x\\ty' $'\\u2d\\u2dz' $'\\101'") == ["claude", "--x\ty", "--z", "A"], "ANSI-C quotes are decoded")
        #expect(words("a>&1 b 2>f c<g") == ["a", "1", "b", "f", "c", "g"], "a redirection is not part of the word before it, nor is the descriptor")
        #expect(words("a;b|c&&d (e)") == ["a", "b", "c", "d", "e"])
        #expect(words("a\\\nb") == ["ab"], "a backslash and a line break join the line")
        #expect(words("\"a\\\"b\" 'c\\d' \"e\\f\"") == ["a\"b", "c\\d", "e\\f"], "inside double quotes a backslash stays before an ordinary character")
        #expect(words("'' \"\"") == ["", ""], "an empty word is a word")
        for line in ["a $x", "a ${x}", "a $(x)", "a `x`", "a {b,c}", "a \"$x\"", "a \"`x`\"", "a 'b", "a \"b", "a b\\"] {
            #expect(ShellWords.hasExpansion(line), "\(line)")
        }
        for line in ["a b", "a '$x' '{b,c}' '`x`'", "a \\$x", "a {b", "a b}", "a {b c}", "a $'x'", "a 'it''s'"] {
            #expect(!ShellWords.hasExpansion(line), "\(line)")
        }
        #expect(ShellWords.programNames(in: ["FOO=1", "/usr/local/bin/Claude", "env", ""]) == ["foo=1", "claude", "env"])
    }

    /// Measured with /bin/zsh 5.9 (the login shell macOS gives a person) and /bin/bash 3.2: zsh gives a program the word up to its first NUL (`$'A\0B'x` is `A`) and bash cuts only the `$'…'` string
    /// that holds it (`Ax`), and some escapes of `$'…'` are read differently: `$'--\d'` is `--\d` to bash and `--d` to zsh, so a flag could be spelled in a way that only one of them reads as the flag.
    @Test func aWordIsCutAtItsNulAndAnEscapeThatTheTwoShellsReadDifferentlyIsNotReadAtAll() {
        #expect(ShellWords.split("claude --flag$'\\0'") == ["claude", "--flag"])
        #expect(ShellWords.split("a$'b\\x00c' d$'\\08'e") == ["ab", "d"])
        #expect(ShellWords.carries(ShellWords.split("claude --dangerously-skip-permissions$'\\0'junk"), flag: "--dangerously-skip-permissions"), "zsh starts the program with the flag")
        for line in ["claude --flag$'\\0'", "a$'\\x00'", "a $'\\0'b", "a $'\\c@'"] {
            #expect(ShellWords.hasExpansion(line), "a NUL ends the word differently in the two shells: \(line)")
        }
        for line in ["a $'--\\dangerously'", "a $'\\q'", "a $'\\cA'", "a $'\\xg'", "a $'\\x'", "a $'\\u'", "a $'\\Uzz'", "a $'--flag\\z'"] {
            #expect(ShellWords.hasExpansion(line), "\(line)")
        }
        for line in ["a $'\\n'", "a $'\\x41'", "a $'\\101'", "a $'\\u00e9'", "a $'\\''", "a $'\\\"'", "a $'\\?'", "a $'\\e'", "a $'\\\\'", "a $'\\a\\b\\f\\r\\t\\v'"] {
            #expect(!ShellWords.hasExpansion(line), "\(line)")
        }
    }

    @Test func theShellsSplitWordsAtASpaceATabAndALineBreakOnlyAndAQuotedBraceIsStillABrace() {
        // A no-break space is a character of a word to bash and zsh, not the end of it.
        #expect(ShellWords.split("a\u{A0}b c\u{3000}d") == ["a\u{A0}b", "c\u{3000}d"])
        #expect(!ShellWords.hasExpansion("a\u{A0}{b"), "a lone brace is a plain character")
        #expect(ShellWords.hasExpansion("claude {x,\"a b\"}") && ShellWords.hasExpansion("claude {x,a\\ b}") && ShellWords.hasExpansion("claude {x,$'a b'}"))
        #expect(!ShellWords.hasExpansion("claude {x,'}'") && !ShellWords.hasExpansion("claude '{x,y}'") && !ShellWords.hasExpansion("claude {x y}"), "a quoted brace does not make one, and a space ends the word")
        // A byte, whatever the digits say, and a byte that is not ASCII is the shells' to join into a character.
        #expect(ShellWords.split("$'\\455'") == ["-"] && !ShellWords.hasExpansion("$'\\455'"))
        #expect(ShellWords.hasExpansion("$'\\377'") && ShellWords.hasExpansion("$'\\xe9'"))
        #expect(!ShellWords.hasExpansion("$'\\101\\x41'"))
        // History is expanded outside single quotes, and a glob is its matches.
        #expect(ShellWords.hasExpansion("a !b") && ShellWords.hasExpansion("a \"!b\"") && ShellWords.hasExpansion("a $'!b'") && !ShellWords.hasExpansion("a '!b'"))
        #expect(ShellWords.hasExpansion("a *") && ShellWords.hasExpansion("a b?") && ShellWords.hasExpansion("a [b]") && !ShellWords.hasExpansion("a '*' \"?\" \\[ \\*"))
        // The program of =claude is claude.
        #expect(ShellWords.programNames(in: ["=claude", "--x"]).contains("claude"))
        // A word that is a line of its own carries the flag of its inner words; a flag inside a prompt text does too, which is the cost of not parsing what a program does with its words.
        #expect(ShellWords.carries(ShellWords.split("sh -c 'exec claude --dangerously-skip-permissions'"), flag: "--dangerously-skip-permissions"))
        #expect(!ShellWords.carries(ShellWords.split("claude --model opus"), flag: "--dangerously-skip-permissions"))
    }

    @Test func aPresetIsStillStartedWithOtherFlagsAndWithAFlagOfAnotherAgentThatIsNotTheBypassFlag() throws {
        let plain = Config(enabledAgents: ["claude"], agents: ["claude": .init(command: "claude --model opus", args: ["--verbose"])], presets: [review])
        let typed = try typedText(Planner(config: plain, facts: machine(files: ["a.txt"])).plan(.preset(id: "review", terminal: nil), context: selection(["a.txt"])))
        #expect(typed.hasPrefix("claude --model opus --verbose "), "\(typed)")
        // Words that only look like the flag do not count, and a flag the agent has none of is nothing to refuse.
        let near = Config(enabledAgents: ["claude"], agents: ["claude": .init(command: "claude --dangerously-skip-permissions-not")], presets: [review])
        #expect(throws: Never.self) { try Planner(config: near, facts: machine(files: ["a.txt"])).plan(.preset(id: "review", terminal: nil), context: selection(["a.txt"])) }
        let lazygit = Config(enabledAgents: ["lazygit"], customAgents: [AgentDescriptor(id: "lazygit", name: "lazygit", command: "lazygit --yolo", promptArgument: .positional)], presets: [AgentPreset(id: "p", title: "P", agent: "lazygit", prompt: "Look at {files}")])
        #expect(throws: Never.self) { try Planner(config: lazygit, facts: machine(files: ["a.txt"])).plan(.preset(id: "p", terminal: nil), context: selection(["a.txt"])) }
    }

    @Test func theFileThatIsAtFaultIsTheOneNamedAmongSeveral() {
        let config = Config(enabledAgents: ["claude"], presets: [review])
        let facts = machine(files: ["fine.txt", "two\nlines.txt", "also fine.txt"])
        do { _ = try Planner(config: config, facts: facts).plan(.preset(id: "review", terminal: nil), context: selection(["fine.txt", "two\nlines.txt", "also fine.txt"])); Issue.record("expected a refusal") } catch let error as PlanError {
            #expect(error == .unsafePresetName(preset: "review", subject: "the file \"two\\nlines.txt\"", reason: "its name has a line break or another control character"))
        } catch { Issue.record("\(error)") }
    }

    @Test func aFolderNameThePromptCarriesIsNamedAsTheFolder() {
        let preset = AgentPreset(id: "p", title: "P", prompt: "Explain {files} in {folder}")
        let config = Config(enabledAgents: ["claude"], presets: [preset])
        let facts = FakeSystemFacts(directories: ["/Users/tester/code", "/Users/tester/code/odd\nfolder"], files: ["/Users/tester/code/odd\nfolder/a.txt"],
                                    applications: ["com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app")])
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/odd\nfolder/a.txt")])
        do { _ = try Planner(config: config, facts: facts).plan(.preset(id: "p", terminal: nil), context: context); Issue.record("expected a refusal") } catch let error as PlanError {
            #expect(error == .unsafePresetName(preset: "p", subject: "the folder \"odd\\nfolder\"", reason: "its name has a line break or another control character"))
        } catch { Issue.record("\(error)") }
    }

    @Test func aNameThePromptDoesNotCarryIsNeverBlamed() throws {
        // `{files}` is not in this prompt, so a file with a line break in its name does not reach the terminal.
        let preset = AgentPreset(id: "p", title: "P", prompt: "Say hello")
        let config = Config(enabledAgents: ["claude"], presets: [preset])
        let plan = try Planner(config: config, facts: machine(files: ["two\nlines.txt"])).plan(.preset(id: "p", terminal: nil), context: selection(["two\nlines.txt"]))
        #expect(!plan.steps.isEmpty)
    }

    @Test func aNameThatWouldMakeThePromptStartWithADashIsRefused() {
        let preset = AgentPreset(id: "p", title: "P", prompt: "{name} explained")
        let config = Config(enabledAgents: ["claude"], presets: [preset])
        let facts = machine(files: ["--version"])
        do { _ = try Planner(config: config, facts: facts).plan(.preset(id: "p", terminal: nil), context: selection(["--version"])); Issue.record("expected a refusal") } catch let error as PlanError {
            #expect(error == .unsafePresetName(preset: "p", subject: "the selected item \"--version\"", reason: "its name would start the prompt with a dash, which the agent would read as an option"))
        } catch { Issue.record("\(error)") }
    }

    @Test func aPromptThatIsTheProblemItselfIsStillSaidToBeThePrompt() {
        // A template with a line break in it (the config refuses one, a Config built by hand does not) has no name to blame.
        let preset = AgentPreset(id: "p", title: "P", prompt: "line one\nline two {files}")
        let config = Config(enabledAgents: ["claude"], presets: [preset])
        do { _ = try Planner(config: config, facts: machine(files: ["a.txt"])).plan(.preset(id: "p", terminal: nil), context: selection(["a.txt"])); Issue.record("expected a refusal") } catch let error as PlanError {
            #expect(error == .unsafePrompt(preset: "p", reason: "it has a line break or another control character"))
        } catch { Issue.record("\(error)") }
    }

    @Test func aFileNameThatLooksLikeAFlagIsHarmlessInsideTheMention() throws {
        let config = Config(enabledAgents: ["claude"], presets: [review])
        let plan = try Planner(config: config, facts: machine(files: ["--help"])).plan(.preset(id: "review", terminal: nil), context: selection(["--help"]))
        #expect(try typedText(plan).contains("'Review @--help in"))
    }

    // MARK: A real shell reads back exactly the prompt

    private static let hostileNames = [
        "plain.txt", "it's.txt", "a'b'c.txt", "$(touch CANARY).txt", "`touch CANARY`.txt", "$HOME and ${PATH}.txt", "semi;colon && pipe | redirect > CANARY.txt",
        "--help", "-rf", "~tilde", "star*?[glob].txt", "bang!history.txt", "#hash.txt", "{folder}.md", "{files}", "%s%n.txt", "日本語 パス.txt", "emoji 🚀.txt",
        "a b.txt", "''", "'; touch CANARY; '"
    ]

    @Test("the typed text round-trips through a real shell", arguments: ["/bin/sh", "/bin/bash", "/bin/zsh"])
    func roundTrip(shell: String) throws {
        let directory = try makeScratchDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let names = Self.hostileNames
        for name in names {
            let preset = AgentPreset(id: "p", title: "P", prompt: "Look at {files} and then at {name} ({folder}) 'quoted' $x `y` !z")
            let config = printingConfig(presets: [preset])
            let plan = try Planner(config: config, facts: machine(files: [name])).plan(.preset(id: "p", terminal: nil), context: selection([name]))
            let typed = try typedText(plan)
            let words = try Shell.run(shell, typed, in: directory).split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            let expectedMention = name.contains(where: \.isWhitespace) ? "@\"\(name)\"" : "@\(name)"
            #expect(words == ["Look at \(expectedMention) and then at \(name) (app) 'quoted' $x `y` !z", ""], "\(shell) read \(typed.debugDescription) as \(words)")
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("CANARY").path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("CANARY.txt").path))
    }

    @Test("a flag and a prompt arrive as two separate words", arguments: ["/bin/sh", "/bin/zsh"])
    func flagRoundTrip(shell: String) throws {
        let directory = try makeScratchDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let config = printingConfig(presets: [AgentPreset(id: "p", title: "P", prompt: "Look at {files}")], promptArgument: .flag("--prompt"))
        let plan = try Planner(config: config, facts: machine(files: ["it's.txt"])).plan(.preset(id: "p", terminal: nil), context: selection(["it's.txt"]))
        let words = try Shell.run(shell, try typedText(plan), in: directory).split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        #expect(words == ["--prompt", "Look at @it's.txt", ""])
    }
}

@Suite("Agent presets: templates")
struct PresetTemplateTests {
    @Test func placeholdersAreFoundInOnePass() {
        #expect(PresetTemplate.segments(of: "a {files} b {folder}{name} {nope} {") == [.text("a "), .files, .text(" b "), .folder, .name, .text(" {nope} {")])
        #expect(PresetTemplate.expand("{name}{name}", files: "", folder: "", name: "{files}") == "{files}{files}")
    }

    @Test func wordsInBracesThatAreNotPlaceholdersAreFound() {
        #expect(PresetTemplate.unknownPlaceholders(in: "Review {file} and {path}, {files} {file} { a } {\"json\": 1}") == ["file", "path"])
    }

    @Test("what cannot be typed is named", arguments: ["", "  ", "a\nb", "a\u{0}b", "a\\b", "-x", String(repeating: "a", count: AgentPreset.maxPromptBytes + 1)])
    func refusals(prompt: String) {
        #expect(PresetTemplate.typingRefusal(prompt) != nil)
    }

    @Test func theLengthLimitCountsBytesNotCharacters() {
        let limit = AgentPreset.maxPromptBytes
        #expect(PresetTemplate.typingRefusal(String(repeating: "a", count: limit)) == nil)
        #expect(PresetTemplate.typingRefusal(String(repeating: "a", count: limit + 1))?.contains("bytes") == true)
        // Two bytes each: half as many characters reach the limit.
        #expect(PresetTemplate.typingRefusal(String(repeating: "é", count: limit / 2)) == nil)
        #expect(PresetTemplate.typingRefusal(String(repeating: "é", count: limit / 2 + 1)) != nil)
        // One Character, a quarter of a million bytes: it used to pass a limit of 4000 "characters".
        let oneCharacter = "a" + String(repeating: "\u{301}", count: 125_000)
        #expect(oneCharacter.count == 1 && oneCharacter.utf8.count > 200_000)
        #expect(PresetTemplate.typingRefusal("Review {files} " + oneCharacter) != nil)
    }

    @Test func aConfigWhosePromptIsTooManyBytesIsAnError() {
        let long = "a" + String(repeating: "\u{301}", count: 5000)
        let result = ConfigParser.parse("[[preset]]\nid = \"p\"\ntitle = \"P\"\nprompt = \"Look at {files} \(long)\"\n")
        #expect(result.diagnostics.contains { $0.severity == .error && $0.path == "preset.1.prompt" && $0.message.contains("bytes") }, "\(result.diagnostics.map(\.message))")
        #expect(result.config.preset(id: "p") == nil)
    }

    @Test func anOrdinarySentenceIsFine() {
        #expect(PresetTemplate.typingRefusal("Review @src/a.swift: it's \"fine\" $HOME `x` — 日本語") == nil)
    }

    @Test func builtInPresetsOnlyAskForReading() {
        #expect(AgentPreset.builtIn.map(\.id) == ["review", "explain", "tests"])
        for preset in AgentPreset.builtIn {
            #expect(preset.needsFiles)
            #expect(PresetTemplate.typingRefusal(preset.prompt) == nil, Comment(rawValue: preset.id))
            #expect(PresetTemplate.unknownPlaceholders(in: preset.prompt).isEmpty)
            #expect(preset.prompt.contains("not") && preset.prompt.lowercased().contains("modify") , "the wording must say the agent should not change files")
        }
    }
}

@Suite("Agent presets: action ids")
struct PresetActionRefTests {
    @Test func parseAndWriteBack() {
        #expect(ActionRef(parsing: "preset.review") == .preset(id: "review", terminal: nil))
        #expect(ActionRef(parsing: "preset.review@ghostty") == .preset(id: "review", terminal: "ghostty"))
        #expect(ActionRef.preset(id: "my-prompt-2", terminal: "terminal").id == "preset.my-prompt-2@terminal")
    }

    @Test("malformed ids are not presets", arguments: ["preset", "preset.", "preset.a.b", "preset.Review", "preset.a b", "preset.a@", "preset.a@B", "preset.review@a@b", "presets.review"])
    func malformed(id: String) {
        #expect(ActionRef(parsing: id) == nil)
    }
}

@Suite("Agent presets: config")
struct PresetConfigTests {
    private func parse(_ text: String) -> ConfigLoadResult { ConfigParser.parse(text) }

    @Test func builtInPresetsExistWithoutAnyConfig() {
        #expect(parse("").config.presets.map(\.id) == ["review", "explain", "tests"])
    }

    @Test func aPresetIsReadAndAnOverrideReplacesTheBuiltInInPlace() throws {
        let result = parse("""
        [general]
        agents = ["claude", "codex"]

        [[preset]]
        id = "explain"
        title = "Explain simply"
        agent = "codex"
        prompt = "Explain {files} to a beginner."
        max_files = 5

        [[preset]]
        id = "lint"
        title = "Lint"
        prompt = "Check {name} for style problems."
        """)
        #expect(result.diagnostics == [])
        #expect(result.config.presets.map(\.id) == ["review", "explain", "tests", "lint"])
        let explain = try #require(result.config.preset(id: "explain"))
        #expect(explain.title == "Explain simply" && explain.agent == "codex" && explain.maxFiles == 5 && explain.titleKey == nil)
        #expect(result.config.preset(id: "lint")?.maxFiles == AgentPreset.defaultMaxFiles)
    }

    private func firstProblem(_ text: String, severity: ConfigDiagnostic.Severity = .error) -> ConfigDiagnostic? {
        parse("[general]\nagents = [\"claude\"]\n" + text).diagnostics.first { $0.severity == severity }
    }

    @Test func aLineBreakInThePromptIsAnErrorAndThePresetIsLeftOut() throws {
        let result = parse("[general]\nagents = [\"claude\"]\n[[preset]]\nid = \"x\"\ntitle = \"X\"\nprompt = \"\"\"\nline one\nline two\"\"\"\n")
        let error = try #require(result.diagnostics.first)
        #expect(error.path == "preset.1.prompt" && error.message.contains("line break"))
        #expect(result.config.preset(id: "x") == nil)
    }

    @Test func aMistypedPlaceholderIsAnErrorWithTheLikelyFix() throws {
        let error = try #require(firstProblem("[[preset]]\nid = \"x\"\ntitle = \"X\"\nprompt = \"Review {file}\"\n"))
        #expect(error.message.contains("unknown placeholder {file}"))
        #expect(error.replacement == "{files}")
    }

    @Test func aLeadingDashAndABackslashAreErrors() {
        #expect(firstProblem("[[preset]]\nid = \"x\"\ntitle = \"X\"\nprompt = \"-p {files}\"\n")?.message.contains("dash") == true)
        #expect(firstProblem("[[preset]]\nid = \"x\"\ntitle = \"X\"\nprompt = \"a\\\\b\"\n")?.message.contains("backslash") == true)
    }

    @Test func anUnknownAgentIsAnErrorWithASuggestion() throws {
        let error = try #require(firstProblem("[[preset]]\nid = \"x\"\ntitle = \"X\"\nagent = \"cluade\"\nprompt = \"Hi\"\n"))
        #expect(error.path == "preset.1.agent" && error.replacement == "claude")
    }

    @Test func anAgentThatIsNotEnabledOrCannotTakeAPromptIsAWarning() throws {
        let result = parse("[general]\nagents = [\"claude\"]\n[[preset]]\nid = \"x\"\ntitle = \"X\"\nagent = \"aider\"\nprompt = \"Hi\"\n")
        let messages = result.diagnostics.filter { $0.severity == .warning }.map(\.message)
        #expect(messages.contains { $0.contains("not in general.agents") } && messages.contains { $0.contains("prompt_arg") })
        #expect(result.config.preset(id: "x") != nil)
    }

    @Test func promptArgMakesAnAgentUsable() throws {
        let result = parse("[general]\nagents = [\"amp\"]\n[agent.amp]\nprompt_arg = \"--prompt\"\n[[preset]]\nid = \"x\"\ntitle = \"X\"\nagent = \"amp\"\nprompt = \"Hi\"\n")
        #expect(result.diagnostics == [])
        #expect(result.config.agent(id: "amp")?.promptArgument == .flag("--prompt"))
        #expect(firstProblem("[agent.claude]\nprompt_arg = \"not a flag\"\n")?.path == "agent.claude.prompt_arg")
    }

    @Test func maxFilesOutOfRangeIsAnErrorAndTheDefaultApplies() throws {
        for value in ["0", "51", "-1"] {
            let result = parse("[[preset]]\nid = \"x\"\ntitle = \"X\"\nprompt = \"Hi\"\nmax_files = \(value)\n")
            #expect(result.diagnostics.first?.path == "preset.1.max_files")
            #expect(result.config.preset(id: "x")?.maxFiles == AgentPreset.defaultMaxFiles)
        }
    }

    @Test func aSubmitKeyIsUnknownBecausePresetsAreAlwaysSent() throws {
        let warning = try #require(firstProblem("[[preset]]\nid = \"x\"\ntitle = \"X\"\nprompt = \"Hi\"\nsubmit = false\n", severity: .warning))
        #expect(warning.path == "preset.1.submit" && warning.message == "unknown key")
    }

    @Test func missingKeysAndDuplicatesAreErrors() {
        #expect(firstProblem("[[preset]]\nid = \"x\"\ntitle = \"X\"\n")?.message.contains("needs id, title and prompt") == true)
        let duplicate = parse("[[preset]]\nid = \"x\"\ntitle = \"A\"\nprompt = \"a\"\n[[preset]]\nid = \"x\"\ntitle = \"B\"\nprompt = \"b\"\n")
        #expect(duplicate.diagnostics.first?.message.contains("duplicate preset id") == true)
        #expect(duplicate.config.preset(id: "x")?.title == "A")
    }

    @Test func menuAndServicesMayNamePresetsAndATypoIsReported() throws {
        let good = parse("[general]\nagents = [\"claude\"]\n[menu]\nitems = [\"preset.review\", \"presets\", \"preset.review@ghostty\"]\n[services]\nitems = [\"preset.tests\"]\n")
        #expect(good.diagnostics == [])
        let typo = try #require(parse("[menu]\nitems = [\"preset.reveiw\"]\n").diagnostics.first)
        #expect(typo.message.contains("no preset \"reveiw\"") && typo.replacement == "preset.review")
    }

    @Test func theSchemaDocumentsPresetsAndTheAgentKey() throws {
        let markdown = ConfigSchema.markdown()
        #expect(markdown.contains("`[[preset]]` (array of tables)") && markdown.contains("`agent.<id>.prompt_arg`"))
        let schema = ConfigSchema.jsonSchema()
        let properties = try #require(schema["properties"] as? [String: Any])
        let preset = try #require(properties["preset"] as? [String: Any])
        #expect((preset["items"] as? [String: Any])?["required"] as? [String] == ["id", "title", "prompt"])
    }
}

@Suite("Agent presets: menu and catalog")
struct PresetMenuTests {
    private func titles(_ nodes: [MenuNode]) -> [String] { nodes.map { $0.kind == .separator ? "-" : $0.title } }

    private func menu(_ config: Config, _ context: HereContext, files: [String] = []) -> [MenuNode] {
        MenuBuilder(config: config, facts: machine(files: files)).build(for: context)
    }

    @Test func anExplicitPresetEntryFollowsTheSameSelectionRulesAsThePresetsGroup() {
        var config = Config(enabledAgents: ["claude"])
        config.menuItems = ["preset.review", "presets"]
        // No file selected: neither the entry nor the group is offered.
        #expect(menu(config, folderContext).isEmpty)
        // A file selected: both are.
        #expect(menu(config, selection(["a.txt"]), files: ["a.txt"]).map(\.title).contains("Review") || menu(config, selection(["a.txt"]), files: ["a.txt"]).flatMap(\.actionIDs).contains("preset.review"))
        // More files than max_files: not offered, as in the group.
        var many = config
        many.presets = [AgentPreset(id: "review", title: "Review", prompt: "Review {files}.", maxFiles: 2)]
        let names = ["a", "b", "c"].map { "\($0).txt" }
        #expect(menu(many, selection(names), files: names).flatMap(\.actionIDs).isEmpty)
    }

    @Test func aPresetHasOneSpellingForTheDefaultTerminal() {
        #expect(ActionRef(parsing: "preset.review") == .preset(id: "review", terminal: nil))
        #expect(ActionRef(parsing: "preset.review@default") == nil)
    }

    @Test(arguments: ["link", "desktop"])
    func aPresetCannotUseAnAgentOnlyLauncherAndSaysWhy(word: String) throws {
        let config = Config(enabledAgents: ["claude"], presets: [AgentPreset(id: "review", title: "Review", prompt: "Review {files}.")])
        let facts = machine(files: ["a.txt"])
        let ref = try #require(ActionRef(parsing: "preset.review@\(word)"))
        let error = #expect(throws: PlanError.self) { try Planner(config: config, facts: facts).plan(ref, context: selection(["a.txt"])) }
        #expect(error?.message.contains("typed into a terminal") == true, Comment(rawValue: "\(String(describing: error?.message))"))
        let info = ActionRegistry(config: config, facts: facts).info(ref)
        #expect(!info.available && info.unavailableReason?.contains("typed into a terminal") == true)
    }

    private func presetsSubmenu(in nodes: [MenuNode]) -> MenuNode? {
        for node in nodes {
            if node.kind == .submenu, node.title == "Agent Presets" { return node }
            if let found = presetsSubmenu(in: node.children) { return found }
        }
        return nil
    }

    @Test func theDefaultMenuNestsPresetsInsideMoreAgentOptionsOnlyForFiles() throws {
        let config = Config(enabledAgents: ["claude"])
        let withFiles = menu(config, selection(["a.txt"]), files: ["a.txt"])
        #expect(titles(withFiles).contains("Agent Presets") == false, "not at the top level")
        let more = try #require(withFiles.first { $0.title == "More Agent Options" })
        let presets = try #require(more.children.first { $0.title == "Agent Presets" })
        #expect(titles(presets.children) == ["Review", "Explain", "Write Tests"])
        #expect(presets.children.map(\.actionID) == ["preset.review", "preset.explain", "preset.tests"])

        // Every built-in prompt names files, so a folder's menu has no such submenu.
        #expect(presetsSubmenu(in: menu(config, folderContext)) == nil)
    }

    @Test func aPresetWithoutFilesIsOfferedForAFolder() throws {
        var config = Config(enabledAgents: ["claude"])
        config.presets.append(AgentPreset(id: "summary", title: "Summarize", prompt: "Summarize {folder}"))
        let presets = try #require(presetsSubmenu(in: menu(config, folderContext)))
        #expect(titles(presets.children) == ["Summarize"])
    }

    @Test func listingThePresetsGroupPutsItAtTheTopLevelAndNowhereElse() throws {
        var config = Config(enabledAgents: ["claude"])
        config.menuItems = ["agents", "agents-more", "presets"]
        let nodes = menu(config, selection(["a.txt"]), files: ["a.txt"])
        #expect(titles(nodes).contains("Agent Presets"))
        let more = nodes.first { $0.title == "More Agent Options" }
        #expect(more?.children.contains { $0.title == "Agent Presets" } != true)
    }

    @Test func tooManyFilesHideAPreset() {
        var config = Config(enabledAgents: ["claude"])
        config.presets = [AgentPreset(id: "p", title: "P", prompt: "{files}", maxFiles: 1)]
        #expect(presetsSubmenu(in: menu(config, selection(["a", "b"]), files: ["a", "b"])) == nil)
        #expect(presetsSubmenu(in: menu(config, selection(["a"]), files: ["a"])) != nil)
    }

    @Test func anItemThatCannotBeToldDoesNotHideThePresets() {
        // None of these paths exists for the fake file system, so `isDirectory` knows nothing about them (as for a path the
        // system will not let the extension look at). The menu is hidden only for what it knows to be a folder; `rh` says why
        // when it cannot run.
        let config = Config(enabledAgents: ["claude"])
        #expect(presetsSubmenu(in: menu(config, selection(["ghost.txt"]))) != nil)
        #expect(presetsSubmenu(in: menu(config, selection(["ghost.txt", "src"]))) != nil)
    }

    @Test func aMenuLooksAtNoItemWhenThereAreMoreItemsThanMaxFiles() {
        let counting = CountingFacts(machine())
        let config = Config(enabledAgents: ["claude"])
        let many = (0...AgentPreset.defaultMaxFiles).map { "ghost\($0).txt" }
        #expect(presetsSubmenu(in: MenuBuilder(config: config, facts: counting).build(for: selection(many))) == nil, "more items than max_files")
        #expect(counting.directoryQuestions == 0, "the count alone decides: no file system work for a big selection")
    }

    @Test func aMenuStopsLookingAtTheFirstItemThatIsNotAFolder() {
        let counting = CountingFacts(machine(files: ["a.txt", "b.txt", "c.txt"], extraDirectories: ["\(appFolder)/src"]))
        let registry = ActionRegistry(config: Config(enabledAgents: ["claude"]), facts: counting)
        let review = ActionRef.preset(id: "review", terminal: nil)
        #expect(registry.info(review, context: selection(["a.txt", "b.txt", "c.txt"])).available)
        #expect(counting.directoryQuestions == 1)
        counting.reset()
        #expect(registry.info(review, context: selection(["src", "src", "b.txt", "c.txt"])).available)
        #expect(counting.directoryQuestions == 3, "the folders, then the first file")
    }

    // MARK: A selected folder

    @Test func aSelectedFolderHasNoPresetsThatNeedFilesAndTheMenuSaysTheSameAsRun() {
        let facts = machine(extraDirectories: ["\(appFolder)/src", "\(appFolder)/lib"])
        let config = Config(enabledAgents: ["claude"])
        for names in [["src"], ["src", "lib"]] {
            #expect(presetsSubmenu(in: MenuBuilder(config: config, facts: facts).build(for: selection(names))) == nil, "\(names)")
            let ref = ActionRef.preset(id: "review", terminal: nil)
            let info = ActionRegistry(config: config, facts: facts).info(ref, context: selection(names))
            #expect(!info.available)
            // What `rh run` refuses with, in the same words.
            #expect(throws: PlanError.unsupported(info.unavailableReason ?? "")) { try Planner(config: config, facts: facts).plan(ref, context: selection(names)) }
        }
    }

    @Test func aMixedSelectionKeepsThePresetsAndAPresetThatNamesNoFilesIsOfferedForAFolder() throws {
        let facts = machine(files: ["a.txt"], extraDirectories: ["\(appFolder)/src"])
        let config = Config(enabledAgents: ["claude"])
        let mixed = try #require(presetsSubmenu(in: MenuBuilder(config: config, facts: facts).build(for: selection(["src", "a.txt"]))))
        #expect(titles(mixed.children) == ["Review", "Explain", "Write Tests"])
        var summary = config
        summary.presets = [AgentPreset(id: "summary", title: "Summarize", prompt: "Summarize {folder}")]
        let folder = try #require(presetsSubmenu(in: MenuBuilder(config: summary, facts: facts).build(for: selection(["src"]))))
        #expect(titles(folder.children) == ["Summarize"])
    }

    @Test func anExplicitPresetEntryIsHiddenForAFolderToo() {
        var config = Config(enabledAgents: ["claude"])
        config.menuItems = ["preset.review", "presets"]
        let nodes = MenuBuilder(config: config, facts: machine(extraDirectories: ["\(appFolder)/src"])).build(for: selection(["src"]))
        #expect(nodes.isEmpty, "\(nodes.flatMap(\.actionIDs))")
    }

    @Test func aPresetOfAnAgentThatIsNotEnabledIsNotOffered() {
        var config = Config(enabledAgents: ["claude"])
        config.presets = [AgentPreset(id: "p", title: "P", agent: "codex", prompt: "{files}")]
        #expect(presetsSubmenu(in: menu(config, selection(["a"]), files: ["a"])) == nil)
    }

    @Test func severalAgentsShowTheirNames() throws {
        var config = Config(enabledAgents: ["claude", "codex"])
        config.presets = [AgentPreset(id: "a", title: "A", agent: "claude", prompt: "{files}"), AgentPreset(id: "b", title: "B", agent: "codex", prompt: "{files}")]
        let presets = try #require(presetsSubmenu(in: menu(config, selection(["a"]), files: ["a"])))
        #expect(titles(presets.children) == ["Claude Code: A", "Codex: B"])
    }

    @Test func theMenuIsLocalized() throws {
        let nodes = MenuBuilder(config: Config(enabledAgents: ["claude"]), facts: machine(files: ["a.txt"]), localizer: Localizer(languages: ["de"])).build(for: selection(["a.txt"]))
        let presets = try #require(presetsSubmenu(in: nodes) ?? nodes.flatMap(\.children).first { $0.children.contains { $0.actionID == "preset.review" } })
        #expect(presets.title == "Agent-Voreinstellungen")
        #expect(titles(presets.children) == ["Überprüfen", "Erklären", "Tests schreiben"])
    }

    @Test func infoSaysWhyAPresetIsUnavailableHere() {
        let registry = ActionRegistry(config: Config(enabledAgents: ["claude"]), facts: machine())
        let info = registry.info(.preset(id: "review", terminal: nil), context: folderContext)
        #expect(!info.available && info.unavailableReason?.contains("select one or more files") == true)
        #expect(registry.info(.preset(id: "review", terminal: nil)).available, "without a selection the action itself is fine")
    }

    @Test func theCatalogListsEveryPreset() {
        let ids = ActionRegistry(config: Config(enabledAgents: ["claude"]), facts: machine()).catalog().map(\.id)
        #expect(ids.contains("preset.review") && ids.contains("preset.explain") && ids.contains("preset.tests"))
    }
}
