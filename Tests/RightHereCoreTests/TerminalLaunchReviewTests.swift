import Foundation
import Testing
@testable import RightHereCore

/// From an independent review of the terminal launches (2026-11-12). Each test failed against the code it was written against (bd70b3a).
@Suite("Terminal launches: what a second review found")
struct TerminalLaunchReviewTests {
    static let folder = "/Users/tester/code/app"
    static let installed: [String: URL] = [
        "com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
        "com.googlecode.iterm2": URL(fileURLWithPath: "/Applications/iTerm.app"),
        "com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"),
        "com.github.wez.wezterm": URL(fileURLWithPath: "/Applications/WezTerm.app"),
        "net.kovidgoyal.kitty": URL(fileURLWithPath: "/Applications/kitty.app"),
        "org.alacritty": URL(fileURLWithPath: "/Applications/Alacritty.app")
    ]

    // MARK: 1. The `'\''` splice in a shell whose single quotes take no escape

    /// nushell (read from its source at 7bff3d1, not run: it is not installed here) reads `'…'` with no escape at all, takes `\` outside quotes as an
    /// ordinary byte, ends a statement at `;` and starts a comment at `#` after a space (`crates/nu-parser/src/lex.rs`). So POSIX's `'it'\''s'` is, to
    /// nushell, a quoted `it`, a `\`, an empty quoted string, and then everything up to the next `'` is outside the quotes. With this name the typed line
    /// was `claude 'Review a'\''; touch CANARY #.txt for bugs.'`: nushell runs `claude`, then `touch CANARY`, and the rest is a comment. elvish and
    /// PowerShell write a quote inside single quotes as `''` and have no backslash escape there either.
    static let nushell = "/opt/homebrew/bin/nu"
    static let apostropheName = "a'; touch CANARY #.txt"
    /// A preset that types the selected item's plain name: `{files}` refuses a name with a `#`, which an agent reads as line numbers in a mention.
    static let byName = AgentPreset(id: "review", title: "Review", prompt: "Review {name} for bugs.")

    static func presetPlan(terminal: String, loginShell: String, file: String, command: String = "claude") throws -> LaunchPlan {
        let facts = FakeSystemFacts(loginShell: loginShell, directories: [URL(fileURLWithPath: file).deletingLastPathComponent().path], files: [file], applications: installed)
        let config = Config(terminal: terminal, enabledAgents: ["claude"], agents: ["claude": .init(command: command)], presets: [byName])
        return try Planner(config: config, facts: facts).plan(.preset(id: "review", terminal: nil), context: HereContext(origin: .items, items: [URL(fileURLWithPath: file)]))
    }

    /// WezTerm, kitty and Alacritty start the login shell themselves (`[shell, "-lic", line]`), and nushell takes `-lic` (its CLI lets the last flag of a
    /// group take the value, `src/command.rs`), so here the shell that reads the line is known exactly.
    @Test("a preset does not hand nushell a name whose apostrophe ends the quoting (the adapter starts the login shell itself)",
          arguments: ["wezterm", "kitty", "alacritty"])
    func apostropheThroughTheLoginShell(terminal: String) throws {
        let plan = try Self.presetPlan(terminal: terminal, loginShell: Self.nushell, file: "\(Self.folder)/\(Self.apostropheName)")
        guard case .run(let step)? = plan.steps.first, let flag = step.arguments.firstIndex(where: { $0 == "-lic" || $0 == "-ic" }) else {
            Issue.record("expected a start through the login shell, got \(plan.steps)"); return
        }
        // What nushell runs is what it reads outside its quotes: Right Here's own words, and nothing of the name.
        #expect(outsideRawQuotes(step.arguments[flag + 1]) == "claude ; exec \(Self.nushell) -l", "\(terminal) would start \(Self.nushell) -lic with: \(step.arguments[flag + 1])")
    }

    /// Ghostty, Terminal and iTerm run whatever shell their own configuration names (Ghostty's `command = nu`, a Terminal profile's command), which is
    /// not necessarily the login shell: the reason a backslash is refused whatever the login shell is (DESIGN 9.1, ADR 0012).
    @Test("the same through Ghostty, whatever the login shell is", arguments: ["/bin/zsh", nushell])
    func apostropheThroughGhostty(loginShell: String) throws {
        let plan = try Self.presetPlan(terminal: "ghostty", loginShell: loginShell, file: "\(Self.folder)/\(Self.apostropheName)")
        guard case .appleScript(let step)? = plan.steps.first, step.arguments.count == 3 else { Issue.record("expected a Ghostty launch, got \(plan.steps)"); return }
        #expect(outsideRawQuotes(step.arguments[1]) == "claude ", "Ghostty would type: \(step.arguments[1])")
    }

    static let nuPath: String? = ["/opt/homebrew/bin/nu", "/usr/local/bin/nu"].first(where: FileManager.default.isExecutableFile)

    /// The real shell, where it is installed (CI can add it, as it adds fish). Skipped here.
    @Test("what Ghostty would type for that name runs nothing in a real nushell", .enabled(if: nuPath != nil))
    func realNushellRunsNothingANameCarried() throws {
        let nu = try #require(Self.nuPath)
        let root = try makeScratchDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appendingPathComponent(Self.apostropheName)
        try Data().write(to: file)
        let plan: LaunchPlan
        do {
            // An absolute path is an external command to nushell (`true` alone is its boolean).
            plan = try Self.presetPlan(terminal: "ghostty", loginShell: nu, file: file.path, command: "/usr/bin/true")
        } catch is PlanError {
            return
        }
        guard case .appleScript(let step)? = plan.steps.first, step.arguments.count == 3 else { Issue.record("expected a Ghostty launch, got \(plan.steps)"); return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: nu)
        process.arguments = ["--no-config-file", "-c", step.arguments[1]]
        process.currentDirectoryURL = project
        process.environment = emptyHomeEnvironment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate() }
        #expect(LaunchSafetyTests.canaries(under: root).isEmpty, "nushell ran a command that a file name carried. Ghostty typed: \(step.arguments[1])")
    }

    // MARK: 2. A typed line longer than a new terminal's tty keeps

    /// Ghostty sends `initial input` as soon as the shell is started (`src/termio/Termio.zig`, `threadEnter`), while the shell still reads its startup
    /// files and the tty is in canonical mode; macOS keeps 1024 bytes of such a line and drops the rest, Return included, while `write` says it took it all
    /// (measured in `CanonicalLineLimitTests`). Terminal's `do script` and iTerm's `write text` type into a new session the same way (their timing is not measured).
    static let manyFiles = (1...20).map { String(format: "component_%02d_with_a_rather_descriptive_name_for_tests.swift", $0) }

    @Test("a preset's line typed into a new terminal fits in the 1024 bytes its tty keeps of a line, or is refused", arguments: ["ghostty", "terminal", "iterm"])
    func aTypedPresetLineFitsTheTTY(terminal: String) throws {
        let files = Self.manyFiles.map { "\(Self.folder)/\($0)" }
        let facts = FakeSystemFacts(directories: [Self.folder], files: Set(files), applications: Self.installed)
        let config = Config(terminal: terminal, enabledAgents: ["claude"])
        do {
            let plan = try Planner(config: config, facts: facts).plan(.preset(id: "review", terminal: nil), context: HereContext(origin: .items, items: files.map { URL(fileURLWithPath: $0) }))
            guard case .appleScript(let step)? = plan.steps.first else { Issue.record("expected a typed launch, got \(plan.steps)"); return }
            let typed = terminal == "ghostty" ? step.arguments[1] : step.arguments[0]
            #expect(typed.utf8.count <= 1023, "\(terminal) would type \(typed.utf8.count) bytes and Return; the tty keeps 1024 of them, so Return never arrives")
        } catch is PlanError {}
    }

    @Test("so does the `cd` line Terminal and iTerm type for a deep folder", arguments: ["terminal", "iterm"])
    func aTypedCdLineFitsTheTTY(terminal: String) throws {
        let deep = "/Users/tester/" + (1...4).map { String(repeating: Character(String($0)), count: 250) }.joined(separator: "/")
        let facts = FakeSystemFacts(directories: [deep], applications: Self.installed)
        do {
            let plan = try Planner(config: Config(terminal: terminal, enabledAgents: ["claude"]), facts: facts)
                .plan(.agent(id: "claude", variant: nil, launcher: nil), context: HereContext(origin: .container, container: URL(fileURLWithPath: deep)))
            guard case .appleScript(let step)? = plan.steps.first else { Issue.record("expected a typed launch, got \(plan.steps)"); return }
            #expect(step.arguments[0].utf8.count <= 1023, "\(terminal) would type \(step.arguments[0].utf8.count) bytes and Return")
        } catch is PlanError {}
    }

    /// Control: a terminal that is handed the command as an argument has no such limit, and must not be refused.
    @Test("a terminal handed the command as an argument takes the long line", arguments: ["wezterm", "kitty", "alacritty"])
    func anArgumentTerminalTakesTheLongLine(terminal: String) throws {
        let files = Self.manyFiles.map { "\(Self.folder)/\($0)" }
        let facts = FakeSystemFacts(directories: [Self.folder], files: Set(files), applications: Self.installed)
        let plan = try Planner(config: Config(terminal: terminal, enabledAgents: ["claude"]), facts: facts)
            .plan(.preset(id: "review", terminal: nil), context: HereContext(origin: .items, items: files.map { URL(fileURLWithPath: $0) }))
        guard case .run? = plan.steps.first else { Issue.record("expected a start with arguments, got \(plan.steps)"); return }
    }

    // MARK: 3. iTerm's tab: the line goes to the current session, not to the tab just made

    /// iTerm2's scripting documentation (iterm2.com/documentation-scripting.html): `create tab` "Returns a reference to the new tab", and `current tab`
    /// is "the tab that is selected in the window"; it does not say that a new tab is selected. The window and split branches type into what their
    /// command returned; the tab branch types into `current session` of `current window`, which ADR 0025 lists as unconfirmed. If that is still the
    /// person's own session (an ssh session, an editor, a running agent), the `cd … && agent …` line is typed there.
    @Test func itermTypesIntoTheTabItCreated() throws {
        let lines = ITermAdapter.script.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let start = try #require(lines.firstIndex { $0.hasPrefix("else if placement is \"tab\"") })
        let end = try #require(lines[(start + 1)...].firstIndex { $0.hasPrefix("else") })
        let branch = Array(lines[(start + 1)..<end])
        let create = try #require(branch.first { $0.contains("create tab with default profile") })
        #expect(create.hasPrefix("set "), "the tab that `create tab` returns is not kept: \(create)")
        #expect(!branch.contains("tell current session"), "the line is typed into whichever session is current: \(branch)")
    }

    // MARK: 4. `{dir}` inside a script that is not a shell's `-c`

    /// Hard rule 2 names AppleScript source as well as a shell. The parser warns about `{dir}` inside `sh -c "…"`; AppleScript's `-e` and `env -S` are
    /// scripts too, and `x" & (do shell script "…") & "` in a folder name is then AppleScript.
    @Test("a folder placeholder inside AppleScript source or an `env -S` line is warned about, as one inside `sh -c` is", arguments: [
        #"open_args = ["/usr/bin/osascript", "-e", "tell application \"Terminal\" to do script \"cd {dir}\""]"#,
        #"run_args = ["/usr/bin/env", "-S", "zsh -lic 'cd {dir}; {command}'"]"#
    ])
    func folderInsideAScript(args: String) {
        let result = ConfigParser.parse("[[app]]\nid = \"w\"\nname = \"W\"\nbundle_id = \"a.b\"\nrole = \"terminal\"\n" + args + "\n")
        #expect(result.diagnostics.contains { $0.severity == .warning && $0.message.contains("{dir} sits inside") }, Comment(rawValue: "\(result.diagnostics)"))
    }

    // MARK: 5. A terminal whose way with a folder no documentation gives

    /// Warp is held to the rule for typed text because its documentation does not say what it does with the folder (ADR 0025); cmux and an `[[app]]`
    /// terminal without templates are handed it through `open` with no documentation either, and take any name. Not shown to matter on a real cmux.
    @Test func anUndocumentedTerminalIsHeldToTheRuleWarpIsHeldTo() {
        let name = "/Users/tester/two\nlines"
        let machine = FakeSystemFacts(directories: [name])
        let session = TerminalSession(directory: URL(fileURLWithPath: name))
        #expect(throws: PlanError.self) { try WarpAdapter().steps(for: session, bundleID: "dev.warp.Warp-Stable", facts: machine) }
        #expect(throws: PlanError.self) { try OpenFolderTerminalAdapter(terminalID: "cmux", displayName: "cmux").steps(for: session, bundleID: "com.cmuxterm.app", facts: machine) }
    }

    /// A terminal the config defines with `run_args` only is handed the folder with `open` for a plain open, the same way.
    @Test func aTemplateTerminalsPlainOpenIsHeldToTheSameRule() {
        let machine = FakeSystemFacts(directories: ["/Users/tester/two\nlines"])
        let adapter = TemplateTerminalAdapter(terminalID: "t", displayName: "T", launch: TerminalLaunch(run: ["/bin/x", "{dir}", "{command}"]))
        #expect(throws: PlanError.self) { try adapter.steps(for: TerminalSession(directory: URL(fileURLWithPath: "/Users/tester/two\nlines")), bundleID: "a.b", facts: machine) }
    }
}
