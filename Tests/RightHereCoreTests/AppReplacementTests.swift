import Foundation
import Testing
@testable import RightHereCore

private let appFolder = "/Users/tester/code/app"

private func facts(installed: [String]) -> FakeSystemFacts {
    FakeSystemFacts(
        directories: ["/Users/tester/code", appFolder],
        applications: Dictionary(uniqueKeysWithValues: installed.map { ($0, URL(fileURLWithPath: "/Applications/\($0).app")) })
    )
}

private func app(_ id: String, name: String, bundle: String, role: String = "terminal", _ extra: String = "") -> String {
    "[[app]]\nid = \"\(id)\"\nname = \"\(name)\"\nbundle_id = \"\(bundle)\"\nrole = \"\(role)\"\n\(extra)\n"
}

private func plan(_ ref: ActionRef, _ toml: String, installed: [String]) throws -> LaunchPlan {
    let result = ConfigParser.parse(toml)
    #expect(!result.hasErrors, Comment(rawValue: "\(result.diagnostics)"))
    let context = HereContext(origin: .container, container: URL(fileURLWithPath: appFolder))
    return try Planner(config: result.config, facts: facts(installed: installed)).plan(ref, context: context)
}

private func openedBundle(_ plan: LaunchPlan) -> String? {
    guard case .open(let step)? = plan.steps.first else { return nil }
    return step.bundleID
}

/// An `[[app]]` that reuses a built-in id replaces that app, but it is still the same kind of terminal: it keeps the
/// built-in's way of starting a session and its place in the order the default terminal is picked in, unless it brings
/// its own `open_args` or `run_args`.
@Suite("A config app under a built-in id")
struct AppReplacementTests {
    private let claudeInGhostty = ActionRef.agent(id: "claude", variant: nil, launcher: .terminal("ghostty"))
    private let claudeInTerminal = ActionRef.agent(id: "claude", variant: nil, launcher: .terminal("terminal"))

    @Test func ghosttyFromAnotherBundleStillTypesThroughGhosttysAppleScript() throws {
        let toml = app("ghostty", name: "Ghostty Fork", bundle: "com.example.fork")
        guard case .appleScript(let step)? = try plan(claudeInGhostty, toml, installed: ["com.example.fork"]).steps.first else {
            Issue.record("expected AppleScript"); return
        }
        #expect(step.controls == "Ghostty")
        #expect(step.arguments == [appFolder, "claude", "window"])
    }

    @Test func terminalFromAnotherBundleStillTypesThroughTerminalAppsAppleScript() throws {
        let toml = app("terminal", name: "My Terminal", bundle: "com.example.term")
        guard case .appleScript(let step)? = try plan(claudeInTerminal, toml, installed: ["com.example.term"]).steps.first else {
            Issue.record("expected AppleScript"); return
        }
        #expect(step.controls == "Terminal")
        #expect(step.arguments == ["cd \(appFolder) && claude"])
    }

    @Test func aReplacedBuiltInKeepsItsPlaceInTheDefaultOrder() throws {
        // Ghostty is first and Terminal last, wherever the config entries stand.
        let fork = app("ghostty", name: "Ghostty Fork", bundle: "com.example.fork")
        let first = try plan(.openTerminal(nil), fork, installed: ["com.apple.Terminal", "com.example.fork", "com.googlecode.iterm2"])
        #expect(openedBundle(first) == "com.example.fork")
        let renamed = app("terminal", name: "My Terminal", bundle: "com.example.term")
        let beforeTerminal = try plan(.openTerminal(nil), renamed, installed: ["com.example.term", "com.googlecode.iterm2"])
        #expect(openedBundle(beforeTerminal) == "com.googlecode.iterm2", "Terminal comes last, even when the config renames it")
    }

    @Test func aReplacedBuiltInWithItsOwnArgumentsIsStartedThatWay() throws {
        let toml = app("ghostty", name: "Ghostty", bundle: "com.mitchellh.ghostty", #"run_args = ["/usr/bin/true", "{dir}", "{command}"]"#)
        guard case .run(let step)? = try plan(claudeInGhostty, toml, installed: ["com.mitchellh.ghostty"]).steps.first else {
            Issue.record("expected a run step"); return
        }
        #expect(step.executable == "/usr/bin/true")
        #expect(step.arguments == [appFolder, "claude"])
    }

    @Test func aBuiltInTerminalTheConfigMakesAnEditorIsRefusedAndTheBuiltInOneStaysTheDefaultTerminal() throws {
        let toml = app("ghostty", name: "Ghostty", bundle: "com.mitchellh.ghostty", role: "editor")
        let result = ConfigParser.parse(toml)
        #expect(result.hasErrors && result.config.apps.isEmpty, "a terminal handed a file runs it, so the entry that would hand it files is left out")
        let context = HereContext(origin: .container, container: URL(fileURLWithPath: appFolder))
        let plan = try Planner(config: result.config, facts: facts(installed: ["com.mitchellh.ghostty", "com.apple.Terminal"])).plan(.openTerminal(nil), context: context)
        #expect(openedBundle(plan) == "com.mitchellh.ghostty", "the built-in Ghostty, which is first in the order")
    }

    @Test func aTerminalWithAnIdOfItsOwnOpensFoldersCannotStartAgentsAndComesAfterTheBuiltIns() throws {
        let toml = app("ghost", name: "Ghost", bundle: "com.example.ghost")
        #expect(openedBundle(try plan(.openTerminal(nil), toml, installed: ["com.example.ghost", "com.apple.Terminal"])) == "com.apple.Terminal")
        #expect(openedBundle(try plan(.openTerminal(nil), toml, installed: ["com.example.ghost"])) == "com.example.ghost")
        #expect(throws: PlanError.self) {
            try plan(.agent(id: "claude", variant: nil, launcher: .terminal("ghost")), toml, installed: ["com.example.ghost"])
        }
    }
}
