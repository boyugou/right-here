import Foundation
import Testing
@testable import RightHereCore

private let facts = FakeSystemFacts(directories: ["/Users/tester/my code"], files: ["/Users/tester/run-me.command"])
private let directory = URL(fileURLWithPath: "/Users/tester/my code")

@Suite("Terminal adapters")
struct TerminalAdapterTests {
    // MARK: Ghostty

    @Test func ghosttyOpensAFolderWithoutAppleScript() throws {
        let steps = try GhosttyAdapter().steps(for: TerminalSession(directory: directory), bundleID: "com.mitchellh.ghostty", facts: facts)
        #expect(steps == [.open(OpenStep(bundleID: "com.mitchellh.ghostty", targets: ["/Users/tester/my code"]))])
    }

    @Test func ghosttyRunsACommandThroughAppleScriptWithValuesAsArguments() throws {
        let session = TerminalSession(directory: directory, typedInput: "claude --continue")
        let steps = try GhosttyAdapter().steps(for: session, bundleID: "com.mitchellh.ghostty", facts: facts)
        let script = try #require(steps.first)
        guard case .appleScript(let step) = script else { Issue.record("expected AppleScript"); return }
        #expect(step.arguments == ["/Users/tester/my code", "claude --continue", "window"])
        #expect(step.controls == "Ghostty")
        #expect(step.source == GhosttyAdapter.script)
    }

    @Test func ghosttyTabPlacement() throws {
        let session = TerminalSession(directory: directory, typedInput: "claude", placement: .newTab)
        guard case .appleScript(let step)? = try GhosttyAdapter().steps(for: session, bundleID: "x", facts: facts).first else {
            Issue.record("expected AppleScript"); return
        }
        #expect(step.arguments.last == "tab")
    }

    @Test func ghosttyScriptNeverEmbedsUserText() throws {
        let values = ["/tmp/a\"; do shell script \"rm -rf ~\"; \"", "/tmp/x' & (do shell script \"id\") & '"]
        let awkward = FakeSystemFacts(directories: Set(values))
        for value in values {
            let session = TerminalSession(directory: URL(fileURLWithPath: value), typedInput: "claude")
            guard case .appleScript(let step)? = try GhosttyAdapter().steps(for: session, bundleID: "x", facts: awkward).first else {
                Issue.record("expected AppleScript"); return
            }
            #expect(!step.source.contains(value))
            #expect(step.arguments.first == value)
        }
    }

    @Test func ghosttyScriptUsesTheDocumentedCommands() {
        let source = GhosttyAdapter.script
        for fragment in ["new surface configuration", "initial working directory", "initial input", "linefeed",
                         "new window with configuration", "new tab in front window with configuration"] {
            #expect(source.contains(fragment), "missing \(fragment)")
        }
    }

    // MARK: Tabs

    @Test func ghosttyOpensAFolderInATabWithAnEmptyCommand() throws {
        let session = TerminalSession(directory: directory, placement: .newTab)
        guard case .appleScript(let step)? = try GhosttyAdapter().steps(for: session, bundleID: "com.mitchellh.ghostty", facts: facts).first else {
            Issue.record("expected AppleScript, a plain open always makes a window"); return
        }
        #expect(step.arguments == ["/Users/tester/my code", "", "tab"])
        #expect(step.controls == "Ghostty")
    }

    @Test func aPlainOpenInAWindowStillNeedsNoAppleScript() throws {
        let steps = try GhosttyAdapter().steps(for: TerminalSession(directory: directory, placement: .newWindow), bundleID: "com.mitchellh.ghostty", facts: facts)
        #expect(steps == [.open(OpenStep(bundleID: "com.mitchellh.ghostty", targets: ["/Users/tester/my code"]))])
    }

    @Test func aTabInAnOldGhosttyIsRefusedWithTheVersionReason() {
        let old = FakeSystemFacts(directories: ["/Users/tester/my code"], bundleVersions: ["com.mitchellh.ghostty": "1.2.3"])
        #expect(throws: PlanError.self) {
            try GhosttyAdapter().steps(for: TerminalSession(directory: directory, placement: .newTab), bundleID: "com.mitchellh.ghostty", facts: old)
        }
    }

    @Test func terminalAppIgnoresThePlacementAndAlwaysOpensAWindow() throws {
        let plain = try AppleTerminalAdapter().steps(for: TerminalSession(directory: directory, placement: .newTab), bundleID: "com.apple.Terminal", facts: facts)
        #expect(plain == [.open(OpenStep(bundleID: "com.apple.Terminal", targets: ["/Users/tester/my code"]))])
        let typed = try AppleTerminalAdapter().steps(for: TerminalSession(directory: directory, typedInput: "claude", placement: .newTab), bundleID: "x", facts: facts)
        let window = try AppleTerminalAdapter().steps(for: TerminalSession(directory: directory, typedInput: "claude", placement: .newWindow), bundleID: "x", facts: facts)
        #expect(typed == window)
    }

    @Test func ghosttyOpensAFolderInASplit() throws {
        let session = TerminalSession(directory: directory, placement: .splitRight)
        guard case .appleScript(let step)? = try GhosttyAdapter().steps(for: session, bundleID: "com.mitchellh.ghostty", facts: facts).first else {
            Issue.record("expected AppleScript"); return
        }
        #expect(step.arguments == ["/Users/tester/my code", "", "split-right"])
        #expect(step.controls == "Ghostty")
    }

    @Test func ghosttyOpensAFolderInASplitDown() throws {
        let session = TerminalSession(directory: directory, typedInput: "claude", placement: .splitDown)
        guard case .appleScript(let step)? = try GhosttyAdapter().steps(for: session, bundleID: "com.mitchellh.ghostty", facts: facts).first else {
            Issue.record("expected AppleScript"); return
        }
        #expect(step.arguments == ["/Users/tester/my code", "claude", "split-down"])
    }

    @Test func placementNamesRoundTrip() {
        #expect(TerminalPlacement(configName: "tab") == .newTab)
        #expect(TerminalPlacement(configName: "window") == .newWindow)
        #expect(TerminalPlacement(configName: "split") == nil)
        #expect(TerminalPlacement(configName: "split-right") == .splitRight)
        #expect(TerminalPlacement(configName: "split-down") == .splitDown)
        #expect(TerminalPlacement(configName: "floating") == nil)
        for placement in TerminalPlacement.allCases { #expect(TerminalPlacement(configName: placement.configName) == placement) }
    }

    // MARK: iTerm

    @Test func itermOpensAFolderInAWindowWithoutAppleScript() throws {
        let steps = try ITermAdapter().steps(for: TerminalSession(directory: directory), bundleID: "com.googlecode.iterm2", facts: facts)
        #expect(steps == [.open(OpenStep(bundleID: "com.googlecode.iterm2", targets: ["/Users/tester/my code"]))])
    }

    @Test func itermRunsACommandThroughAppleScriptWithLineAndPlacementArguments() throws {
        let session = TerminalSession(directory: directory, typedInput: "claude --continue")
        let steps = try ITermAdapter().steps(for: session, bundleID: "com.googlecode.iterm2", facts: facts)
        let script = try #require(steps.first)
        guard case .appleScript(let step) = script else { Issue.record("expected AppleScript"); return }
        #expect(step.arguments == ["cd '/Users/tester/my code' && claude --continue", "window"])
        #expect(step.controls == "iTerm")
        #expect(step.source == ITermAdapter.script)
    }

    @Test func itermTabPlacement() throws {
        let session = TerminalSession(directory: directory, typedInput: "claude", placement: .newTab)
        guard case .appleScript(let step)? = try ITermAdapter().steps(for: session, bundleID: "com.googlecode.iterm2", facts: facts).first else {
            Issue.record("expected AppleScript"); return
        }
        #expect(step.arguments == ["cd '/Users/tester/my code' && claude", "tab"])
    }

    @Test func itermOpensAFolderInATab() throws {
        let session = TerminalSession(directory: directory, placement: .newTab)
        guard case .appleScript(let step)? = try ITermAdapter().steps(for: session, bundleID: "com.googlecode.iterm2", facts: facts).first else {
            Issue.record("expected AppleScript"); return
        }
        #expect(step.arguments == ["cd '/Users/tester/my code'", "tab"])
        #expect(step.controls == "iTerm")
    }

    @Test func itermSplitPlacement() throws {
        let session = TerminalSession(directory: directory, typedInput: "claude", placement: .splitRight)
        guard case .appleScript(let step)? = try ITermAdapter().steps(for: session, bundleID: "com.googlecode.iterm2", facts: facts).first else {
            Issue.record("expected AppleScript"); return
        }
        #expect(step.arguments == ["cd '/Users/tester/my code' && claude", "split-right"])
    }

    @Test func itermSplitDownPlacement() throws {
        let session = TerminalSession(directory: directory, placement: .splitDown)
        guard case .appleScript(let step)? = try ITermAdapter().steps(for: session, bundleID: "com.googlecode.iterm2", facts: facts).first else {
            Issue.record("expected AppleScript"); return
        }
        #expect(step.arguments == ["cd '/Users/tester/my code'", "split-down"])
    }

    @Test func itermScriptNeverEmbedsUserText() throws {
        let values = ["/tmp/a\"; do shell script \"rm -rf ~\"; \"", "/tmp/x' & (do shell script \"id\") & '"]
        let awkward = FakeSystemFacts(directories: Set(values))
        for value in values {
            let session = TerminalSession(directory: URL(fileURLWithPath: value), typedInput: "claude")
            guard case .appleScript(let step)? = try ITermAdapter().steps(for: session, bundleID: "com.googlecode.iterm2", facts: awkward).first else {
                Issue.record("expected AppleScript"); return
            }
            #expect(!step.source.contains(value))
            #expect(step.arguments.count == 2)
            #expect(step.arguments[1] == "window")
        }
    }

    @Test func itermScriptUsesTheDocumentedCommands() {
        let source = ITermAdapter.script
        for fragment in ["com.googlecode.iterm2", "create tab with default profile", "create window with default profile", "current session", "write text"] {
            #expect(source.contains(fragment), "missing \(fragment)")
        }
    }

    @Test func itermVersionChecks() {
        let old = FakeSystemFacts(directories: ["/Users/tester/my code"], bundleVersions: ["com.googlecode.iterm2": "2.9.3"])
        #expect(throws: PlanError.self) {
            try ITermAdapter().steps(for: TerminalSession(directory: directory, placement: .newTab), bundleID: "com.googlecode.iterm2", facts: old)
        }
        #expect(throws: PlanError.self) {
            try ITermAdapter().steps(for: TerminalSession(directory: directory, typedInput: "claude"), bundleID: "com.googlecode.iterm2", facts: old)
        }
        let valid = FakeSystemFacts(directories: ["/Users/tester/my code"], bundleVersions: ["com.googlecode.iterm2": "3.5.0"])
        #expect(ITermAdapter().commandBlocker(bundleID: "com.googlecode.iterm2", facts: valid) == nil)
    }

    @Test func itermRefusesBackslashInDirectory() {
        let folderWithBackslash = "/Users/tester/my\\code"
        let backslashFacts = FakeSystemFacts(directories: [folderWithBackslash])
        let session = TerminalSession(directory: URL(fileURLWithPath: folderWithBackslash), typedInput: "claude")
        #expect(throws: PlanError.self) {
            try ITermAdapter().steps(for: session, bundleID: "com.googlecode.iterm2", facts: backslashFacts)
        }
    }

    @Test func itermTypesTheFolder() {
        #expect(ITermAdapter().typesTheFolder)
    }

    // MARK: Ghostty versions

    private func ghosttyMachine(version: String?, directories: Set<String> = []) -> FakeSystemFacts {
        FakeSystemFacts(
            directories: Set(["/Users/tester/my code"]).union(directories),
            applications: ["com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app")],
            bundleVersions: version.map { ["com.mitchellh.ghostty": $0] } ?? [:]
        )
    }

    @Test func aGhosttyWithoutAppleScriptRefusesCommandsButStillOpensFolders() throws {
        let old = ghosttyMachine(version: "1.2.3")
        #expect(throws: PlanError.self) {
            try GhosttyAdapter().steps(for: TerminalSession(directory: directory, typedInput: "claude"), bundleID: "com.mitchellh.ghostty", facts: old)
        }
        let steps = try GhosttyAdapter().steps(for: TerminalSession(directory: directory), bundleID: "com.mitchellh.ghostty", facts: old)
        #expect(steps == [.open(OpenStep(bundleID: "com.mitchellh.ghostty", targets: ["/Users/tester/my code"]))])
    }

    @Test func theReasonNamesBothVersions() {
        let reason = GhosttyAdapter().commandBlocker(bundleID: "com.mitchellh.ghostty", facts: ghosttyMachine(version: "1.2.3"))
        #expect(reason?.contains("1.2.3") == true)
        #expect(reason?.contains("1.3") == true)
    }

    @Test("Ghostty versions that can run commands, or are not known", arguments: ["1.3", "1.3.1", "1.4.0-dev+abc123", "2.0", nil as String?])
    func newEnoughGhosttyIsNotBlocked(version: String?) throws {
        let machine = ghosttyMachine(version: version)
        #expect(GhosttyAdapter().commandBlocker(bundleID: "com.mitchellh.ghostty", facts: machine) == nil)
        let session = TerminalSession(directory: directory, typedInput: "claude")
        guard case .appleScript? = try GhosttyAdapter().steps(for: session, bundleID: "com.mitchellh.ghostty", facts: machine).first else {
            Issue.record("expected AppleScript"); return
        }
    }

    @Test func theRegistryExplainsWhyAnAgentCannotStartInAnOldGhostty() {
        let registry = ActionRegistry(config: Config(enabledAgents: ["claude"]), facts: ghosttyMachine(version: "1.2.3"))
        let info = registry.info(.agent(id: "claude", variant: nil, launcher: nil))
        #expect(!info.available)
        #expect(info.unavailableReason?.contains("1.3") == true)
    }

    // MARK: Terminal.app

    @Test func terminalOpensAFolderWithoutAppleScript() throws {
        let steps = try AppleTerminalAdapter().steps(for: TerminalSession(directory: directory), bundleID: "com.apple.Terminal", facts: facts)
        #expect(steps == [.open(OpenStep(bundleID: "com.apple.Terminal", targets: ["/Users/tester/my code"]))])
    }

    @Test func terminalRunsACommandWithTheFolderQuotedForTheLoginShell() throws {
        let session = TerminalSession(directory: directory, typedInput: "claude")
        guard case .appleScript(let step)? = try AppleTerminalAdapter().steps(for: session, bundleID: "x", facts: facts).first else {
            Issue.record("expected AppleScript"); return
        }
        #expect(step.arguments == ["cd '/Users/tester/my code' && claude"])
        #expect(step.controls == "Terminal")
        #expect(!step.source.contains("quoted form of"), "quoting is done in Swift, for the login shell")
    }

    @Test("the cd line is quoted the one way every shell reads alike, whatever the login shell is",
          arguments: ["/bin/zsh", "/opt/homebrew/bin/fish", "/bin/bash"])
    func theQuotingDoesNotDependOnTheLoginShell(shell: String) throws {
        // Terminal.app starts whatever shell its profile names, which need not be the account's login shell.
        let name = #"/tmp/q'; touch x; #"#
        let machine = FakeSystemFacts(loginShell: shell, directories: [name])
        let session = TerminalSession(directory: URL(fileURLWithPath: name), typedInput: "claude")
        guard case .appleScript(let step)? = try AppleTerminalAdapter().steps(for: session, bundleID: "x", facts: machine).first else {
            Issue.record("expected AppleScript"); return
        }
        #expect(step.arguments == [#"cd '/tmp/q'\''; touch x; #' && claude"#])
    }

    @Test("a folder with a backslash is refused, because fish and the other shells read it differently",
          arguments: [#"/tmp/q\'; touch x; #"#, #"/tmp/back\slash"#, #"/tmp/a\"#])
    func aBackslashInTheFolderIsRefused(name: String) {
        for shell in ["/bin/zsh", "/opt/homebrew/bin/fish"] {
            let machine = FakeSystemFacts(loginShell: shell, directories: [name])
            let session = TerminalSession(directory: URL(fileURLWithPath: name), typedInput: "claude")
            #expect(throws: PlanError.self) { try AppleTerminalAdapter().steps(for: session, bundleID: "x", facts: machine) }
        }
        // A plain open hands the folder over untyped, so it is fine.
        let machine = FakeSystemFacts(directories: [name])
        #expect(throws: Never.self) { try AppleTerminalAdapter().steps(for: TerminalSession(directory: URL(fileURLWithPath: name)), bundleID: "x", facts: machine) }
    }

    @Test func ghosttyIsNotAffectedByABackslashBecauseItNeverTypesTheFolder() throws {
        let name = #"/tmp/back\slash"#
        let machine = ghosttyMachine(version: "1.3.1", directories: [name])
        let steps = try GhosttyAdapter().steps(for: TerminalSession(directory: URL(fileURLWithPath: name), typedInput: "claude"), bundleID: "com.mitchellh.ghostty", facts: machine)
        guard case .appleScript(let step)? = steps.first else { Issue.record("expected AppleScript"); return }
        #expect(step.arguments.contains(name))
        #expect(!GhosttyAdapter().typesTheFolder)
        #expect(AppleTerminalAdapter().typesTheFolder)
    }

    @Test("the line Terminal types reaches the folder in every shell that is installed (fish only where it is)",
          arguments: ["/bin/sh", "/bin/bash", "/bin/zsh", "/bin/dash", "/bin/ksh"] + (fishPath.map { [$0] } ?? []))
    func theLineReachesTheFolderInARealShell(shell: String) throws {
        let root = try makeScratchDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        for name in ["plain", "with space", "it's", "a'b'c", "dollar $HOME `x`", "semi;colon&pipe|x", "quote\"d", "tilde ~", "-dash", "ünï\u{301}code", "emoji 🚀", "a'\u{301}b"] {
            let folder = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let machine = FakeSystemFacts(directories: [folder.path])
            let session = TerminalSession(directory: folder, typedInput: "pwd -P")
            guard case .appleScript(let step)? = try AppleTerminalAdapter().steps(for: session, bundleID: "x", facts: machine).first else {
                Issue.record("expected AppleScript"); return
            }
            let line = try #require(step.arguments.first)
            let reported = try Shell.run(shell, line, in: root).trimmingCharacters(in: .newlines)
            #expect(URL(fileURLWithPath: reported).resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path,
                    "\(shell) read \(line.debugDescription) as \(reported.debugDescription)")
        }
    }

    @Test("csh and tcsh also expand ! inside single quotes, which can only make the cd fail: nothing else ever runs",
          arguments: ["/bin/csh", "/bin/tcsh"])
    func cshAndTcshFailSafe(shell: String) throws {
        try #require(FileManager.default.isExecutableFile(atPath: shell), "\(shell) is not installed here")
        let root = try makeScratchDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        for name in ["plain", "with space", "it's", "a'b'c", "bang!here", "a!!b", "x!$", "dollar $HOME", "semi;colon", "evil';touch CANARY;'x"] {
            let folder = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let machine = FakeSystemFacts(directories: [folder.path])
            guard case .appleScript(let step)? = try AppleTerminalAdapter().steps(for: TerminalSession(directory: folder, typedInput: "pwd -P"), bundleID: "x", facts: machine).first else {
                Issue.record("expected AppleScript"); return
            }
            let reported = try Shell.run(shell, try #require(step.arguments.first), in: root).trimmingCharacters(in: .newlines)
            let landed = URL(fileURLWithPath: reported).resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path
            #expect(landed || reported.isEmpty, "\(shell) printed \(reported.debugDescription) for \(name.debugDescription)")
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("CANARY").path), "\(shell) ran the injected command")
            if !name.contains("!") { #expect(landed, "\(shell) did not reach \(name.debugDescription)") }
        }
    }

    // MARK: Folders only

    @Test("a plain open refuses anything that is not a known folder", arguments: ["/Users/tester/run-me.command", "/Users/tester/missing"])
    func plainOpenRequiresAFolder(path: String) {
        let session = TerminalSession(directory: URL(fileURLWithPath: path))
        #expect(throws: PlanError.self) { try GhosttyAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.self) { try AppleTerminalAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.self) { try ITermAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.self) { try WezTermAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.self) { try KittyAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.self) { try TerminalAdapters.adapter(for: KnownApps.terminal(id: "warp")!).steps(for: session, bundleID: "x", facts: facts) }
    }

    @Test("a typed launch refuses anything that is not a known folder", arguments: ["/Users/tester/run-me.command", "/Users/tester/missing"])
    func typedLaunchRequiresAFolder(path: String) {
        let session = TerminalSession(directory: URL(fileURLWithPath: path), typedInput: "claude")
        #expect(throws: PlanError.self) { try GhosttyAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.self) { try AppleTerminalAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.self) { try ITermAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.self) { try WezTermAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.self) { try KittyAdapter().steps(for: session, bundleID: "x", facts: facts) }
    }

    @Test("a typed launch refuses text that would press Return or other keys", arguments: ["claude\nrm -rf ~", "claude\r", "claude\u{1b}[A", "claude\u{2028}"])
    func typedLaunchRefusesControlCharacters(text: String) {
        let session = TerminalSession(directory: directory, typedInput: text)
        #expect(throws: PlanError.unsafeText(text)) { try GhosttyAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.unsafeText(text)) { try AppleTerminalAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.unsafeText(text)) { try ITermAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.unsafeText(text)) { try WezTermAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.unsafeText(text)) { try KittyAdapter().steps(for: session, bundleID: "x", facts: facts) }
    }

    @Test func terminalRefusesAFolderItWouldHaveToTypeWithALineBreak() {
        let name = "/Users/tester/two\nlines"
        let session = TerminalSession(directory: URL(fileURLWithPath: name), typedInput: "claude")
        #expect(throws: PlanError.unsafeFolder(name)) {
            try AppleTerminalAdapter().steps(for: session, bundleID: "x", facts: FakeSystemFacts(directories: [name]))
        }
        #expect(throws: PlanError.unsafeFolder(name)) {
            try ITermAdapter().steps(for: session, bundleID: "x", facts: FakeSystemFacts(directories: [name]))
        }
    }

    @Test func aTerminalThatIsHandedTheFolderTakesAnyNameBecauseNothingTypesIt() throws {
        let name = "/Users/tester/two\nlines \u{1b}[2J"
        let machine = FakeSystemFacts(directories: [name], applications: ["x": URL(fileURLWithPath: "/Applications/X.app")])
        let session = TerminalSession(directory: URL(fileURLWithPath: name), typedInput: "claude")
        guard case .appleScript(let ghostty)? = try GhosttyAdapter().steps(for: session, bundleID: "x", facts: machine).first else { Issue.record("expected AppleScript"); return }
        #expect(ghostty.arguments.first == name)
        guard case .run(let wezterm)? = try WezTermAdapter().steps(for: session, bundleID: "x", facts: machine).first else { Issue.record("expected a run step"); return }
        #expect(wezterm.arguments[2] == name)
        guard case .run(let kitty)? = try KittyAdapter().steps(for: session, bundleID: "x", facts: machine).first else { Issue.record("expected a run step"); return }
        #expect(kitty.arguments[1] == name)
        // The command is still typed, and still held to the rule.
        let hostile = TerminalSession(directory: URL(fileURLWithPath: name), typedInput: "claude\nrm -rf ~")
        #expect(throws: PlanError.unsafeText("claude\nrm -rf ~")) { try GhosttyAdapter().steps(for: hostile, bundleID: "x", facts: machine) }
    }

    @Test func onlyTheTerminalsThatHandOverTheFolderSayTheyTypeNothingOfIt() {
        #expect(!GhosttyAdapter().typesTheFolder && !WezTermAdapter().typesTheFolder && !KittyAdapter().typesTheFolder)
        #expect(!OpenFolderTerminalAdapter(terminalID: "warp", displayName: "Warp").typesTheFolder)
        #expect(AppleTerminalAdapter().typesTheFolder && ITermAdapter().typesTheFolder)
        // A terminal the config defines says nothing, and the default is the strict answer: its template may type `{dir}`.
        #expect(TemplateTerminalAdapter(terminalID: "t", displayName: "T", launch: TerminalLaunch(run: ["/bin/sh", "-c", "cd {dir} && {command}"])).typesTheFolder)
    }

    // MARK: Registry

    @Test func registryReturnsDedicatedAdaptersAndAFallback() {
        #expect(TerminalAdapters.adapter(for: KnownApps.terminal(id: "ghostty")!).supportsCommands)
        #expect(TerminalAdapters.adapter(for: KnownApps.terminal(id: "terminal")!).supportsCommands)
        #expect(TerminalAdapters.adapter(for: KnownApps.terminal(id: "iterm")!).supportsCommands)
        #expect(!TerminalAdapters.adapter(for: KnownApps.terminal(id: "warp")!).supportsCommands)
    }

    @Test func fallbackRefusesToRunCommands() {
        let adapter = TerminalAdapters.adapter(for: KnownApps.terminal(id: "warp")!)
        #expect(throws: PlanError.self) {
            try adapter.steps(for: TerminalSession(directory: directory, typedInput: "claude"), bundleID: "x", facts: facts)
        }
    }

    @Test func theAdapterFollowsTheDriverAndNotTheId() {
        func adapter(_ id: String, _ driver: AppDescriptor.Driver) -> any TerminalAdapter {
            TerminalAdapters.adapter(for: AppDescriptor(id: id, name: id, bundleIDs: ["x"], role: .terminal, driver: driver))
        }
        #expect(adapter("anything", .ghostty) is GhosttyAdapter)
        #expect(adapter("anything", .appleScriptTerminal) is AppleTerminalAdapter)
        #expect(adapter("anything", .iterm) is ITermAdapter)
        #expect(adapter("anything", .wezterm) is WezTermAdapter)
        #expect(adapter("anything", .kitty) is KittyAdapter)
        #expect(adapter("ghostty", .openFolder) is OpenFolderTerminalAdapter)
        #expect(adapter("terminal", .template(TerminalLaunch(run: ["/bin/x", "{command}"]))) is TemplateTerminalAdapter)
    }

    @Test func theAdviceNamesTheBuiltInTerminalsThatCanRunCommands() {
        // `rh doctor` says which terminals to choose; a built-in terminal that gains a way to run commands joins the phrase.
        #expect(KnownApps.commandTerminalPhrase == "Ghostty, Terminal, iTerm, WezTerm or kitty")
        #expect(KnownApps.terminals.filter { TerminalAdapters.adapter(for: $0).supportsCommands }.map(\.name) == ["Ghostty", "Terminal", "iTerm", "WezTerm", "kitty"])
    }

    @Test func theBuiltInDriversAreGhosttyTerminalAppITermWezTermKittyAndTheRestAreHandedTheFolder() {
        let drivers = Dictionary(uniqueKeysWithValues: KnownApps.terminals.map { ($0.id, $0.driver) })
        #expect(drivers["ghostty"] == .ghostty)
        #expect(drivers["terminal"] == .appleScriptTerminal)
        #expect(drivers["iterm"] == .iterm)
        #expect(drivers["wezterm"] == .wezterm)
        #expect(drivers["kitty"] == .kitty)
        for id in ["alacritty", "warp", "cmux"] { #expect(drivers[id] == .openFolder, "\(id)") }
    }

    @Test func wezTermIsStartedThroughOpenWithItsOwnArguments() throws {
        let wezFacts = FakeSystemFacts(directories: ["/Users/tester/code"], applications: ["com.github.wez.wezterm": URL(fileURLWithPath: "/Applications/WezTerm.app")])
        let plainSession = TerminalSession(directory: URL(fileURLWithPath: "/Users/tester/code"))
        let plainSteps = try WezTermAdapter().steps(for: plainSession, bundleID: "com.github.wez.wezterm", facts: wezFacts)
        guard case .run(let step1)? = plainSteps.first else { Issue.record("expected run step"); return }
        #expect(step1.executable == "/usr/bin/open")
        #expect(step1.arguments == ["-n", "-b", "com.github.wez.wezterm", "--args", "start", "--cwd", "/Users/tester/code"])

        let typedSession = TerminalSession(directory: URL(fileURLWithPath: "/Users/tester/code"), typedInput: "claude")
        let typedSteps = try WezTermAdapter().steps(for: typedSession, bundleID: "com.github.wez.wezterm", facts: wezFacts)
        guard case .run(let step2)? = typedSteps.first else { Issue.record("expected run step"); return }
        #expect(step2.executable == "/usr/bin/open")
        #expect(step2.arguments == ["-n", "-b", "com.github.wez.wezterm", "--args", "start", "--cwd", "/Users/tester/code", "--", "/bin/zsh", "-lic", "claude; exec /bin/zsh -l"])
    }

    @Test func kittyIsStartedThroughOpenWithItsOwnArguments() throws {
        let kittyFacts = FakeSystemFacts(directories: ["/Users/tester/code"], applications: ["net.kovidgoyal.kitty": URL(fileURLWithPath: "/Applications/kitty.app")])
        let plainSession = TerminalSession(directory: URL(fileURLWithPath: "/Users/tester/code"))
        let plainSteps = try KittyAdapter().steps(for: plainSession, bundleID: "net.kovidgoyal.kitty", facts: kittyFacts)
        guard case .run(let step1)? = plainSteps.first else { Issue.record("expected run step"); return }
        #expect(step1.executable == "/usr/bin/open")
        #expect(step1.arguments == ["-n", "-b", "net.kovidgoyal.kitty", "--args", "--directory", "/Users/tester/code"])

        let typedSession = TerminalSession(directory: URL(fileURLWithPath: "/Users/tester/code"), typedInput: "claude")
        let typedSteps = try KittyAdapter().steps(for: typedSession, bundleID: "net.kovidgoyal.kitty", facts: kittyFacts)
        guard case .run(let step2)? = typedSteps.first else { Issue.record("expected run step"); return }
        #expect(step2.executable == "/usr/bin/open")
        #expect(step2.arguments == ["-n", "-b", "net.kovidgoyal.kitty", "--args", "--directory", "/Users/tester/code", "/bin/zsh", "-lic", "claude; exec /bin/zsh -l"])
    }
}



@Suite("WezTerm and kitty start through LaunchServices")
struct ArgumentTerminalTests {
    private func facts() -> FakeSystemFacts {
        FakeSystemFacts(directories: ["/Users/tester/my code"], applications: ["com.github.wez.wezterm": URL(fileURLWithPath: "/Applications/WezTerm.app"),
                                                                              "net.kovidgoyal.kitty": URL(fileURLWithPath: "/Applications/kitty.app")])
    }

    private func process(_ steps: [Step]) throws -> ProcessStep {
        guard steps.count == 1, case .run(let step) = steps[0] else { throw PlanError.unsupported("expected one process step, got \(steps)") }
        return step
    }

    @Test func weztermIsStartedThroughOpenSoThatNothingWaitsForTheWindow() throws {
        let session = TerminalSession(directory: URL(fileURLWithPath: "/Users/tester/my code"), typedInput: "claude")
        let step = try process(WezTermAdapter().steps(for: session, bundleID: "com.github.wez.wezterm", facts: facts()))
        #expect(step.executable == "/usr/bin/open")
        #expect(Array(step.arguments.prefix(5)) == ["-n", "-b", "com.github.wez.wezterm", "--args", "start"])
        #expect(step.arguments.contains("/Users/tester/my code"))
        #expect(step.arguments.last?.hasPrefix("claude; exec ") == true)
    }

    @Test func kittyIsStartedThroughOpenSoThatNothingWaitsForTheWindow() throws {
        let session = TerminalSession(directory: URL(fileURLWithPath: "/Users/tester/my code"), typedInput: nil)
        let step = try process(KittyAdapter().steps(for: session, bundleID: "net.kovidgoyal.kitty", facts: facts()))
        #expect(step.executable == "/usr/bin/open")
        #expect(step.arguments == ["-n", "-b", "net.kovidgoyal.kitty", "--args", "--directory", "/Users/tester/my code"])
    }

    @Test func noTerminalBinaryIsRunDirectly() throws {
        // A step that runs the terminal's own binary lasts as long as its window does.
        for (adapter, bundle) in [(WezTermAdapter() as any TerminalAdapter, "com.github.wez.wezterm"), (KittyAdapter(), "net.kovidgoyal.kitty")] {
            let step = try process(adapter.steps(for: TerminalSession(directory: URL(fileURLWithPath: "/Users/tester/my code"), typedInput: "claude"), bundleID: bundle, facts: facts()))
            #expect(!step.executable.contains("/Contents/MacOS/"))
        }
    }
}
