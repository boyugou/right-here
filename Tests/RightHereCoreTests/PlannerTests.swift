import Foundation
import Testing
@testable import RightHereCore

private func machine(
    installed: [String] = ["com.mitchellh.ghostty", "com.apple.Terminal", "com.microsoft.VSCode"],
    files: Set<String> = ["/Users/tester/code/app/a.txt", "/Users/tester/code/app/b b.md"],
    directories: Set<String> = ["/Users/tester/code", "/Users/tester/code/app", "/Users/tester/code/app/src"],
    gitRoots: [String] = ["/Users/tester/code/app"]
) -> FakeSystemFacts {
    FakeSystemFacts(
        directories: directories,
        files: files,
        gitRoots: gitRoots,
        applications: Dictionary(uniqueKeysWithValues: installed.map { ($0, URL(fileURLWithPath: "/Applications/\($0).app")) })
    )
}

private func folder(_ path: String) -> HereContext {
    HereContext(origin: .container, container: URL(fileURLWithPath: path))
}

private func selection(_ paths: String...) -> HereContext {
    HereContext(origin: .items, items: paths.map { URL(fileURLWithPath: $0) })
}

@Suite("Planner")
struct PlannerTests {
    // MARK: Copy path

    @Test func copyPathOfSelection() throws {
        let planner = Planner(facts: machine())
        let plan = try planner.plan(.copyPath(.gitRelative), context: selection("/Users/tester/code/app/a.txt", "/Users/tester/code/app/b b.md"))
        #expect(plan.steps == [.copyToPasteboard("a.txt\nb b.md")])
    }

    @Test func copyPathOfBackgroundIsTheFolder() throws {
        let plan = try Planner(facts: machine()).plan(.copyPath(.tilde), context: folder("/Users/tester/code/app"))
        #expect(plan.steps == [.copyToPasteboard("~/code/app")])
    }

    @Test func copyPathWithNothingFails() {
        #expect(throws: PlanError.noTarget) { try Planner(facts: machine()).plan(.copyPath(.absolute), context: HereContext(origin: .container)) }
    }

    // MARK: Open with apps

    @Test func openTerminalPicksTheFirstInstalledPreferredTerminal() throws {
        let plan = try Planner(facts: machine()).plan(.openTerminal(nil), context: folder("/Users/tester/code/app"))
        #expect(plan.steps == [.open(OpenStep(bundleID: "com.mitchellh.ghostty", targets: ["/Users/tester/code/app"]))])
    }

    @Test func openTerminalFallsBackToTerminalApp() throws {
        let facts = machine(installed: ["com.apple.Terminal"])
        let plan = try Planner(facts: facts).plan(.openTerminal(nil), context: folder("/Users/tester/code/app"))
        #expect(plan.steps == [.open(OpenStep(bundleID: "com.apple.Terminal", targets: ["/Users/tester/code/app"]))])
    }

    @Test func configuredTerminalWins() throws {
        let planner = Planner(config: Config(terminal: "terminal"), facts: machine())
        let plan = try planner.plan(.openTerminal(nil), context: folder("/Users/tester/code/app"))
        #expect(plan.steps == [.open(OpenStep(bundleID: "com.apple.Terminal", targets: ["/Users/tester/code/app"]))])
    }

    @Test func missingTerminalIsReported() {
        #expect(throws: PlanError.appNotInstalled("iTerm")) {
            try Planner(facts: machine()).plan(.openTerminal("iterm"), context: folder("/Users/tester/code/app"))
        }
    }

    @Test func terminalOpensTheSelectedFolderItselfAndAFilesParent() throws {
        let planner = Planner(facts: machine())
        let onFolder = try planner.plan(.openTerminal("terminal"), context: selection("/Users/tester/code/app/src"))
        #expect(onFolder.steps == [.open(OpenStep(bundleID: "com.apple.Terminal", targets: ["/Users/tester/code/app/src"]))])
        let onFile = try planner.plan(.openTerminal("terminal"), context: selection("/Users/tester/code/app/a.txt"))
        #expect(onFile.steps == [.open(OpenStep(bundleID: "com.apple.Terminal", targets: ["/Users/tester/code/app"]))])
    }

    @Test func editorOpensTheSelectionItself() throws {
        let plan = try Planner(facts: machine()).plan(.openEditor, context: selection("/Users/tester/code/app/a.txt", "/Users/tester/code/app/src"))
        #expect(plan.steps == [.open(OpenStep(bundleID: "com.microsoft.VSCode", targets: ["/Users/tester/code/app/a.txt", "/Users/tester/code/app/src"]))])
    }

    @Test func editorOnBackgroundOpensTheFolder() throws {
        let plan = try Planner(facts: machine()).plan(.openApp("vscode"), context: folder("/Users/tester/code/app"))
        #expect(plan.steps == [.open(OpenStep(bundleID: "com.microsoft.VSCode", targets: ["/Users/tester/code/app"]))])
    }

    @Test func customAppIsOpenable() throws {
        let custom = AppDescriptor(id: "tower", name: "Tower", bundleIDs: ["com.fournova.Tower3"], role: .general)
        let planner = Planner(config: Config(apps: [custom]), facts: machine(installed: ["com.fournova.Tower3"]))
        let plan = try planner.plan(.openApp("tower"), context: folder("/Users/tester/code/app"))
        #expect(plan.steps == [.open(OpenStep(bundleID: "com.fournova.Tower3", targets: ["/Users/tester/code/app"]))])
    }

    @Test func unknownAppIsReported() {
        #expect(throws: PlanError.unknownApp("nope")) {
            try Planner(facts: machine()).plan(.openApp("nope"), context: folder("/Users/tester/code/app"))
        }
    }

    // MARK: Agents

    @Test func claudeTerminalLinkCarriesTheEncodedFolder() throws {
        let facts = machine(directories: ["/Users/tester/my code/app"])
        let plan = try Planner(facts: facts).plan(
            .agent(id: "claude", variant: nil, launcher: .terminalLink),
            context: folder("/Users/tester/my code/app")
        )
        #expect(plan.steps == [.openURL("claude-cli://open?cwd=%2FUsers%2Ftester%2Fmy%20code%2Fapp")])
    }

    @Test func claudeTerminalLinkPrefillsSelectedFilesAsMentions() throws {
        let plan = try Planner(facts: machine()).plan(
            .agent(id: "claude", variant: nil, launcher: .terminalLink),
            context: selection("/Users/tester/code/app/a.txt", "/Users/tester/code/app/b b.md")
        )
        #expect(plan.steps == [.openURL("claude-cli://open?cwd=%2FUsers%2Ftester%2Fcode%2Fapp&q=%40a.txt%20%40%22b%20b.md%22%20")])
    }

    @Test func prefillIgnoresASelectedFolder() throws {
        let plan = try Planner(facts: machine()).plan(
            .agent(id: "claude", variant: nil, launcher: .terminalLink),
            context: selection("/Users/tester/code/app/src")
        )
        #expect(plan.steps == [.openURL("claude-cli://open?cwd=%2FUsers%2Ftester%2Fcode%2Fapp%2Fsrc")])
    }

    @Test func codexDesktopLink() throws {
        let plan = try Planner(facts: machine()).plan(
            .agent(id: "codex", variant: nil, launcher: .desktop), context: folder("/Users/tester/code/app")
        )
        #expect(plan.steps == [.openURL("codex://threads/new?path=%2FUsers%2Ftester%2Fcode%2Fapp")])
    }

    @Test func agentWithoutADesktopLinkSaysSo() {
        #expect(throws: PlanError.self) {
            try Planner(facts: machine()).plan(.agent(id: "aider", variant: nil, launcher: .desktop), context: folder("/Users/tester/code/app"))
        }
    }

    @Test func unknownAgentAndVariant() {
        let planner = Planner(facts: machine())
        #expect(throws: PlanError.unknownAgent("nope")) {
            try planner.plan(.agent(id: "nope", variant: nil, launcher: nil), context: folder("/Users/tester/code/app"))
        }
        #expect(throws: PlanError.unknownVariant(agent: "claude", variant: "nope")) {
            try planner.plan(.agent(id: "claude", variant: "nope", launcher: nil), context: folder("/Users/tester/code/app"))
        }
    }

    @Test func claudeStartsInTheDefaultTerminalByTypingItsCommand() throws {
        let plan = try Planner(facts: machine()).plan(.agent(id: "claude", variant: nil, launcher: nil), context: folder("/Users/tester/code/app"))
        guard case .appleScript(let step)? = plan.steps.first else { Issue.record("expected AppleScript"); return }
        #expect(step.arguments == ["/Users/tester/code/app", "claude", "window"])
        #expect(step.controls == "Ghostty")
    }

    @Test func variantsAppendTheirArguments() throws {
        let plan = try Planner(facts: machine()).plan(.agent(id: "claude", variant: "continue", launcher: nil), context: folder("/Users/tester/code/app"))
        guard case .appleScript(let step)? = plan.steps.first else { Issue.record("expected AppleScript"); return }
        #expect(step.arguments[1] == "claude --continue")
    }

    @Test func aConfiguredCommandReplacesTheBuiltInOne() throws {
        let config = Config(agents: ["claude": .init(command: "claude --model opus")])
        let plan = try Planner(config: config, facts: machine()).plan(.agent(id: "claude", variant: nil, launcher: nil), context: folder("/Users/tester/code/app"))
        guard case .appleScript(let step)? = plan.steps.first else { Issue.record("expected AppleScript"); return }
        #expect(step.arguments[1] == "claude --model opus")
    }

    @Test func aChosenTerminalOverridesTheDefault() throws {
        let plan = try Planner(facts: machine()).plan(.agent(id: "codex", variant: nil, launcher: .terminal("terminal")), context: folder("/Users/tester/code/app"))
        guard case .appleScript(let step)? = plan.steps.first else { Issue.record("expected AppleScript"); return }
        #expect(step.controls == "Terminal")
        #expect(step.arguments == ["/Users/tester/code/app", "codex"])
    }

    @Test func aTerminalWithoutCommandSupportRefusesAgents() {
        let facts = machine(installed: ["dev.warp.Warp-Stable"])
        #expect(throws: PlanError.self) {
            try Planner(facts: facts).plan(.agent(id: "claude", variant: nil, launcher: .terminal("warp")), context: folder("/Users/tester/code/app"))
        }
    }

    @Test func typedLaunchRejectsAPathWithALineBreak() {
        let facts = machine(directories: ["/Users/tester/bad\nname"])
        #expect(throws: PlanError.unsafeText("/Users/tester/bad\nname")) {
            try Planner(facts: facts).plan(.agent(id: "claude", variant: nil, launcher: .terminal("terminal")), context: folder("/Users/tester/bad\nname"))
        }
    }

    @Test func linkLaunchAcceptsAPathWithALineBreakBecauseItIsPercentEncoded() throws {
        let facts = machine(directories: ["/Users/tester/bad\nname"])
        let plan = try Planner(facts: facts).plan(.agent(id: "claude", variant: nil, launcher: .terminalLink), context: folder("/Users/tester/bad\nname"))
        #expect(plan.steps == [.openURL("claude-cli://open?cwd=%2FUsers%2Ftester%2Fbad%0Aname")])
    }

    // MARK: New file

    @Test func newFileGetsTheFirstFreeName() throws {
        let facts = machine(files: ["/Users/tester/code/app/untitled.txt", "/Users/tester/code/app/untitled 2.txt"])
        let plan = try Planner(facts: facts).plan(.newFile("txt"), context: folder("/Users/tester/code/app"))
        #expect(plan.steps == [
            .createFile(CreateFileStep(path: "/Users/tester/code/app/untitled 3.txt")),
            .reveal(["/Users/tester/code/app/untitled 3.txt"])
        ])
    }

    @Test func newFileNextToASelectedFile() throws {
        let plan = try Planner(facts: machine()).plan(.newFile("md"), context: selection("/Users/tester/code/app/a.txt"))
        #expect(plan.steps.first == .createFile(CreateFileStep(path: "/Users/tester/code/app/untitled.md")))
    }

    @Test func newFileCanOpenInTheEditorInstead() throws {
        let planner = Planner(config: Config(newFile: .init(then: .open)), facts: machine())
        let plan = try planner.plan(.newFile("md"), context: folder("/Users/tester/code/app"))
        #expect(plan.steps == [
            .createFile(CreateFileStep(path: "/Users/tester/code/app/untitled.md")),
            .open(OpenStep(bundleID: "com.microsoft.VSCode", targets: ["/Users/tester/code/app/untitled.md"]))
        ])
    }

    @Test func unknownTemplate() {
        #expect(throws: PlanError.unknownTemplate("rtf")) {
            try Planner(facts: machine()).plan(.newFile("rtf"), context: folder("/Users/tester/code/app"))
        }
    }

    // MARK: Reveal

    @Test func reveal() throws {
        let plan = try Planner(facts: machine()).plan(.reveal, context: selection("/Users/tester/code/app/a.txt"))
        #expect(plan.steps == [.reveal(["/Users/tester/code/app/a.txt"])])
    }
}
