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

    @Test func placementNamesRoundTrip() {
        #expect(TerminalPlacement(configName: "tab") == .newTab)
        #expect(TerminalPlacement(configName: "window") == .newWindow)
        #expect(TerminalPlacement(configName: "split") == nil)
        for placement in TerminalPlacement.allCases { #expect(TerminalPlacement(configName: placement.configName) == placement) }
    }

    // MARK: Ghostty versions

    private func ghosttyMachine(version: String?) -> FakeSystemFacts {
        FakeSystemFacts(
            directories: ["/Users/tester/my code"],
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

    @Test("a hostile folder name is quoted for the shell that will read it", arguments: [
        ("/bin/zsh", #"cd '/tmp/q\'\''; touch x; #' && claude"#),
        ("/opt/homebrew/bin/fish", #"cd '/tmp/q\\\'; touch x; #' && claude"#)
    ])
    func hostileFolderQuotedPerShell(shell: String, expected: String) throws {
        let name = #"/tmp/q\'; touch x; #"#
        let machine = FakeSystemFacts(loginShell: shell, directories: [name])
        let session = TerminalSession(directory: URL(fileURLWithPath: name), typedInput: "claude")
        guard case .appleScript(let step)? = try AppleTerminalAdapter().steps(for: session, bundleID: "x", facts: machine).first else {
            Issue.record("expected AppleScript"); return
        }
        #expect(step.arguments == [expected])
    }

    // MARK: Folders only

    @Test("a plain open refuses anything that is not a known folder", arguments: ["/Users/tester/run-me.command", "/Users/tester/missing"])
    func plainOpenRequiresAFolder(path: String) {
        let session = TerminalSession(directory: URL(fileURLWithPath: path))
        #expect(throws: PlanError.self) { try GhosttyAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.self) { try AppleTerminalAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.self) { try TerminalAdapters.adapter(for: KnownApps.terminal(id: "warp")!).steps(for: session, bundleID: "x", facts: facts) }
    }

    @Test("a typed launch refuses anything that is not a known folder", arguments: ["/Users/tester/run-me.command", "/Users/tester/missing"])
    func typedLaunchRequiresAFolder(path: String) {
        let session = TerminalSession(directory: URL(fileURLWithPath: path), typedInput: "claude")
        #expect(throws: PlanError.self) { try GhosttyAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.self) { try AppleTerminalAdapter().steps(for: session, bundleID: "x", facts: facts) }
    }

    @Test("a typed launch refuses text that would press Return or other keys", arguments: ["claude\nrm -rf ~", "claude\r", "claude\u{1b}[A", "claude\u{2028}"])
    func typedLaunchRefusesControlCharacters(text: String) {
        let session = TerminalSession(directory: directory, typedInput: text)
        #expect(throws: PlanError.unsafeText(text)) { try GhosttyAdapter().steps(for: session, bundleID: "x", facts: facts) }
        #expect(throws: PlanError.unsafeText(text)) { try AppleTerminalAdapter().steps(for: session, bundleID: "x", facts: facts) }
    }

    @Test func terminalRefusesAFolderItWouldHaveToTypeWithALineBreak() {
        let name = "/Users/tester/two\nlines"
        let session = TerminalSession(directory: URL(fileURLWithPath: name), typedInput: "claude")
        #expect(throws: PlanError.unsafeText(name)) {
            try AppleTerminalAdapter().steps(for: session, bundleID: "x", facts: FakeSystemFacts(directories: [name]))
        }
    }

    // MARK: Registry

    @Test func registryReturnsDedicatedAdaptersAndAFallback() {
        #expect(TerminalAdapters.adapter(for: KnownApps.terminal(id: "ghostty")!).supportsCommands)
        #expect(TerminalAdapters.adapter(for: KnownApps.terminal(id: "terminal")!).supportsCommands)
        #expect(!TerminalAdapters.adapter(for: KnownApps.terminal(id: "warp")!).supportsCommands)
    }

    @Test func fallbackRefusesToRunCommands() {
        let adapter = TerminalAdapters.adapter(for: KnownApps.terminal(id: "warp")!)
        #expect(throws: PlanError.self) {
            try adapter.steps(for: TerminalSession(directory: directory, typedInput: "claude"), bundleID: "x", facts: facts)
        }
    }
}
