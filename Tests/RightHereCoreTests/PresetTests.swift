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
        let preset = AgentPreset(id: "review", title: "Review", agent: "gemini", prompt: "Review {files}")
        let config = Config(enabledAgents: ["gemini"], presets: [preset])
        let facts = machine(files: ["a.txt"])
        #expect(throws: PlanError.self) { try Planner(config: config, facts: facts).plan(.preset(id: "review", terminal: nil), context: selection(["a.txt"])) }
        let info = ActionRegistry(config: config, facts: facts).info(.preset(id: "review", terminal: nil))
        #expect(!info.available && info.unavailableReason?.contains("prompt_arg") == true)
    }

    @Test func claudeAndCodexTakeTheirPromptAsAnArgument() {
        #expect(KnownAgents.claude.promptArgument == .positional && KnownAgents.codex.promptArgument == .positional)
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

    @Test("a prompt that cannot be typed as one safe word is refused with the preset error", arguments: [
        "new\nline.txt", "carriage\rreturn.txt", "tab\there.txt", "bell\u{7}.txt", "escape\u{1B}[2J.txt", "line\u{2028}separator.txt",
        "back\\slash.txt", "quote \"and space.txt"
    ])
    func hostileFileNamesAreRefused(name: String) {
        let config = Config(enabledAgents: ["claude"], presets: [review])
        let facts = machine(files: [name])
        do { _ = try Planner(config: config, facts: facts).plan(.preset(id: "review", terminal: nil), context: selection([name])); Issue.record("expected a refusal") } catch let error as PlanError {
            guard case .unsafePrompt(let preset, _) = error else { Issue.record("expected .unsafePrompt, got \(error)"); return }
            #expect(preset == "review")
            #expect(error.errorDescription?.contains("cannot be typed into a terminal") == true)
            // Whatever the name held, the message shows it escaped, never as a raw line break.
            #expect(!(error.errorDescription ?? "").unicodeScalars.contains(where: { $0.value < 0x20 }))
        } catch { Issue.record("\(error)") }
    }

    @Test func aNameThatWouldMakeThePromptStartWithADashIsRefused() {
        let preset = AgentPreset(id: "p", title: "P", prompt: "{name} explained")
        let config = Config(enabledAgents: ["claude"], presets: [preset])
        let facts = machine(files: ["--version"])
        do { _ = try Planner(config: config, facts: facts).plan(.preset(id: "p", terminal: nil), context: selection(["--version"])); Issue.record("expected a refusal") } catch let error as PlanError {
            guard case .unsafePrompt = error else { Issue.record("expected .unsafePrompt, got \(error)"); return }
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
        let result = parse("[general]\nagents = [\"claude\"]\n[[preset]]\nid = \"x\"\ntitle = \"X\"\nagent = \"gemini\"\nprompt = \"Hi\"\n")
        let messages = result.diagnostics.filter { $0.severity == .warning }.map(\.message)
        #expect(messages.contains { $0.contains("not in general.agents") } && messages.contains { $0.contains("prompt_arg") })
        #expect(result.config.preset(id: "x") != nil)
    }

    @Test func promptArgMakesAnAgentUsable() throws {
        let result = parse("[general]\nagents = [\"gemini\"]\n[agent.gemini]\nprompt_arg = \"-i\"\n[[preset]]\nid = \"x\"\ntitle = \"X\"\nagent = \"gemini\"\nprompt = \"Hi\"\n")
        #expect(result.diagnostics == [])
        #expect(result.config.agent(id: "gemini")?.promptArgument == .flag("-i"))
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

    @Test func aPresetOnTheDefaultTerminalIsTheSamePresetAsOneWithoutASuffix() {
        #expect(ActionRef(parsing: "preset.review@default") == .preset(id: "review", terminal: nil))
        #expect(ActionRef(parsing: "preset.review@default")?.id == "preset.review")
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
