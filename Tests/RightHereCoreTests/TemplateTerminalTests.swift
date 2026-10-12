import Foundation
import Testing
@testable import RightHereCore

@Suite("Config-defined terminals (open_args, run_args)")
struct TemplateTerminalTests {
    private let config = """
    [[app]]
    id = "wezterm"
    name = "WezTerm"
    bundle_id = "com.github.wez.wezterm"
    role = "terminal"
    open_args = ["{app}/Contents/MacOS/wezterm", "start", "--cwd", "{dir}"]
    run_args = ["{app}/Contents/MacOS/wezterm", "start", "--cwd", "{dir}", "--", "{shell}", "-lic", "{command}; exec {shell} -l"]
    """

    private func facts(directories: Set<String> = ["/Users/tester/code", "/Users/tester/code/{command} dir"]) -> FakeSystemFacts {
        FakeSystemFacts(directories: directories, applications: ["com.github.wez.wezterm": URL(fileURLWithPath: "/Applications/WezTerm.app")])
    }

    private func plan(_ ref: ActionRef, in directory: String = "/Users/tester/code", config text: String? = nil) throws -> LaunchPlan {
        let result = ConfigParser.parse(text ?? config)
        #expect(!result.hasErrors, Comment(rawValue: "\(result.diagnostics)"))
        return try Planner(config: result.config, facts: facts()).plan(ref, context: HereContext(origin: .container, container: URL(fileURLWithPath: directory)))
    }

    @Test func aTypedLaunchIsAnArgumentVectorWithTheFolderAsItsOwnArgument() throws {
        let plan = try plan(.agent(id: "claude", variant: nil, launcher: .terminal("wezterm")))
        guard case .run(let step)? = plan.steps.first else { Issue.record("expected a run step"); return }
        #expect(step.executable == "/Applications/WezTerm.app/Contents/MacOS/wezterm")
        #expect(step.arguments == ["start", "--cwd", "/Users/tester/code", "--", "/bin/zsh", "-lic", "claude; exec /bin/zsh -l"])
    }

    @Test func aPlainOpenUsesOpenArgs() throws {
        let plan = try plan(.openTerminal("wezterm"))
        guard case .run(let step)? = plan.steps.first else { Issue.record("expected a run step"); return }
        #expect(step.arguments == ["start", "--cwd", "/Users/tester/code"])
    }

    @Test func aFolderNamedLikeAPlaceholderStaysAFolderName() throws {
        let plan = try plan(.agent(id: "claude", variant: nil, launcher: .terminal("wezterm")), in: "/Users/tester/code/{command} dir")
        guard case .run(let step)? = plan.steps.first else { Issue.record("expected a run step"); return }
        #expect(step.arguments[2] == "/Users/tester/code/{command} dir", "text that arrived with a replacement was expanded again")
    }

    @Test func aTerminalWithoutRunArgsCannotStartAnAgentButStillOpensAFolder() throws {
        let text = """
        [[app]]
        id = "wezterm"
        name = "WezTerm"
        bundle_id = "com.github.wez.wezterm"
        role = "terminal"
        open_args = ["{app}/Contents/MacOS/wezterm", "start", "--cwd", "{dir}"]
        """
        #expect(throws: PlanError.self) { try plan(.agent(id: "claude", variant: nil, launcher: .terminal("wezterm")), config: text) }
        #expect(throws: Never.self) { try plan(.openTerminal("wezterm"), config: text) }
        let result = ConfigParser.parse(text)
        let info = ActionRegistry(config: result.config, facts: facts()).info(.agent(id: "claude", variant: nil, launcher: .terminal("wezterm")))
        #expect(!info.available)
    }

    @Test func aTypedCommandWithAControlCharacterIsStillRefused() {
        let adapter = TemplateTerminalAdapter(terminalID: "w", displayName: "W", launch: TerminalLaunch(run: ["/bin/x", "{dir}", "{command}"]))
        #expect(throws: PlanError.self) {
            try adapter.steps(for: TerminalSession(directory: URL(fileURLWithPath: "/Users/tester/code"), typedInput: "claude\nrm -rf ~"), bundleID: "x", facts: facts())
        }
    }

    @Test func aFileIsNeverHandedOver() {
        let adapter = TemplateTerminalAdapter(terminalID: "w", displayName: "W", launch: TerminalLaunch(open: ["/bin/x", "{dir}"]))
        var machine = facts()
        machine.files.insert("/Users/tester/run-me.command")
        #expect(throws: PlanError.self) {
            try adapter.steps(for: TerminalSession(directory: URL(fileURLWithPath: "/Users/tester/run-me.command")), bundleID: "x", facts: machine)
        }
    }

    @Test("the config refuses launch arguments that cannot work", arguments: [
        ("role = \"editor\"\nrun_args = [\"/bin/x\", \"{dir}\", \"{command}\"]", "role"),
        ("role = \"terminal\"\nrun_args = [\"wezterm\", \"{dir}\", \"{command}\"]", "absolute path"),
        ("role = \"terminal\"\nrun_args = [\"/bin/x\", \"{dir}\"]", "{command}"),
        ("role = \"terminal\"\nopen_args = [\"relative/x\", \"{dir}\"]", "absolute path")
    ])
    func badTemplates(extra: String, mention: String) throws {
        let result = ConfigParser.parse("[[app]]\nid = \"w\"\nname = \"W\"\nbundle_id = \"a.b\"\n" + extra + "\n")
        let error = try #require(result.diagnostics.first { $0.severity == .error })
        #expect(error.message.contains(mention), Comment(rawValue: error.message))
    }

    @Test func aRunTemplateThatIgnoresTheFolderIsWarnedAbout() throws {
        let result = ConfigParser.parse("[[app]]\nid = \"w\"\nname = \"W\"\nbundle_id = \"a.b\"\nrole = \"terminal\"\nrun_args = [\"/bin/x\", \"{command}\"]\n")
        #expect(result.diagnostics.contains { $0.severity == .warning && $0.message.contains("{dir}") })
    }

    @Test("a folder placeholder inside a string a shell reads is warned about, one of its own is not", arguments: [
        ("run_args = [\"/bin/sh\", \"-c\", \"cd {dir} && {command}\"]", true),
        ("run_args = [\"/bin/x\", \"-lc\", \"cd {dir}; {command}\"]", true),
        ("run_args = [\"/bin/x\", \"--cwd\", \"{dir}\", \"--\", \"{shell}\", \"-lic\", \"{command}\"]", false),
        ("run_args = [\"/bin/x\", \"--working-directory={dir}\", \"{command}\"]", false)
    ])
    func folderInsideAShellString(args: String, warns: Bool) {
        let result = ConfigParser.parse("[[app]]\nid = \"w\"\nname = \"W\"\nbundle_id = \"a.b\"\nrole = \"terminal\"\n" + args + "\n")
        #expect(result.diagnostics.contains { $0.message.contains("shell will read") } == warns, Comment(rawValue: "\(result.diagnostics)"))
    }
}
