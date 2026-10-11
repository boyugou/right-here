import Foundation
import Testing
@testable import RightHereCore

private let facts = FakeSystemFacts()
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
        for value in ["/tmp/a\"; do shell script \"rm -rf ~\"; \"", "/tmp/x' & (do shell script \"id\") & '"] {
            let session = TerminalSession(directory: URL(fileURLWithPath: value), typedInput: "claude")
            guard case .appleScript(let step)? = try GhosttyAdapter().steps(for: session, bundleID: "x", facts: facts).first else {
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

    // MARK: Terminal.app

    @Test func terminalOpensAFolderWithoutAppleScript() throws {
        let steps = try AppleTerminalAdapter().steps(for: TerminalSession(directory: directory), bundleID: "com.apple.Terminal", facts: facts)
        #expect(steps == [.open(OpenStep(bundleID: "com.apple.Terminal", targets: ["/Users/tester/my code"]))])
    }

    @Test func terminalRunsACommandWithTheFolderQuotedByAppleScript() throws {
        let session = TerminalSession(directory: directory, typedInput: "claude")
        guard case .appleScript(let step)? = try AppleTerminalAdapter().steps(for: session, bundleID: "x", facts: facts).first else {
            Issue.record("expected AppleScript"); return
        }
        #expect(step.arguments == ["/Users/tester/my code", "claude"])
        #expect(step.source.contains("quoted form of cwd"))
        #expect(step.controls == "Terminal")
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
