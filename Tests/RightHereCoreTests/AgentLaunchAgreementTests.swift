import Foundation
import Testing
@testable import RightHereCore

private let appFolder = "/Users/tester/code/app"
private let ghostty = "com.mitchellh.ghostty"
private let terminalApp = "com.apple.Terminal"

private struct Machine {
    let name: String
    let facts: FakeSystemFacts

    init(_ name: String, installed: [String], versions: [String: String] = [:]) {
        self.name = name
        facts = FakeSystemFacts(
            directories: ["/Users/tester/code", appFolder],
            files: ["\(appFolder)/a.txt"],
            applications: Dictionary(uniqueKeysWithValues: installed.map { ($0, URL(fileURLWithPath: "/Applications/\($0).app")) }),
            bundleVersions: versions
        )
    }
}

private let machines = [
    Machine("nothing installed", installed: []),
    Machine("folder-only terminals", installed: ["com.googlecode.iterm2", "net.kovidgoyal.kitty", "dev.warp.Warp-Stable"]),
    Machine("cmux and Terminal", installed: ["com.cmuxterm.app", terminalApp]),
    Machine("an old Ghostty alone", installed: [ghostty], versions: [ghostty: "1.2.3"]),
    Machine("an old Ghostty and Terminal", installed: [ghostty, terminalApp], versions: [ghostty: "1.2.3"]),
    Machine("a new Ghostty", installed: [ghostty, "com.microsoft.VSCode"], versions: [ghostty: "1.3.1"]),
    Machine("a Ghostty of unknown version and Terminal", installed: [ghostty, terminalApp]),
    Machine("Terminal alone", installed: [terminalApp, "com.apple.TextEdit"]),
    Machine("the desktop apps alone", installed: ["com.anthropic.claudefordesktop", "com.openai.codex"]),
    Machine("everything", installed: [
        ghostty, terminalApp, "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.github.wez.wezterm", "com.example.ghost",
        "com.microsoft.VSCode", "dev.zed.Zed", "com.apple.TextEdit", "com.anthropic.claudefordesktop", "com.openai.codex"
    ], versions: [ghostty: "1.3.1"])
]

private func parsed(_ text: String) -> Config { ConfigParser.parse(text).config }

private let weztermOpenArgs = #"open_args = ["{app}/Contents/MacOS/wezterm", "start", "--cwd", "{dir}"]"#
private let weztermRunArgs = #"run_args = ["{app}/Contents/MacOS/wezterm", "start", "--cwd", "{dir}", "--", "{shell}", "-lic", "{command}; exec {shell} -l"]"#

private func app(_ id: String, name: String, bundle: String, role: String, _ extra: String = "") -> String {
    "[[app]]\nid = \"\(id)\"\nname = \"\(name)\"\nbundle_id = \"\(bundle)\"\nrole = \"\(role)\"\n\(extra)\n"
}

private let configs: [(name: String, config: Config)] = [
    ("the default config", .default),
    ("three agents enabled", Config(enabledAgents: ["claude", "codex", "gemini"])),
    ("iTerm is the default terminal", Config(terminal: "iterm", enabledAgents: ["claude"])),
    ("Warp is the default terminal", Config(terminal: "warp", enabledAgents: ["claude"])),
    ("Terminal is the default terminal", Config(terminal: "terminal", enabledAgents: ["claude"])),
    ("claude starts by link", parsed("[general]\nagents = [\"claude\"]\n[agent.claude]\nlauncher = \"link\"\n")),
    ("codex starts in its desktop app", parsed("[general]\nagents = [\"codex\"]\n[agent.codex]\nlauncher = \"desktop\"\n")),
    ("claude has Warp as its own terminal", parsed("[general]\nagents = [\"claude\"]\n[agent.claude]\nterminal = \"warp\"\n")),
    ("ghostty is redefined as an editor and is still the default terminal",
     Config(terminal: "ghostty", enabledAgents: ["claude"], apps: [AppDescriptor(id: "ghostty", name: "Ghostty", bundleIDs: [ghostty], role: .editor)])),
    ("terminal is redefined as an editor", parsed(app("terminal", name: "Terminal", bundle: terminalApp, role: "editor"))),
    ("ghostty is another build", parsed(app("ghostty", name: "Ghostty Fork", bundle: ghostty, role: "terminal"))),
    ("wezterm has open_args and run_args", parsed(app("wezterm", name: "WezTerm", bundle: "com.github.wez.wezterm", role: "terminal", weztermOpenArgs + "\n" + weztermRunArgs))),
    ("wezterm has open_args only", parsed(app("wezterm", name: "WezTerm", bundle: "com.github.wez.wezterm", role: "terminal", weztermOpenArgs))),
    ("a custom terminal has run_args", parsed(app("ghost", name: "Ghost", bundle: "com.example.ghost", role: "terminal", weztermRunArgs))),
    ("a custom agent with a variant", parsed("""
        [general]
        agents = ["lazygit"]
        [agent.lazygit]
        name = "lazygit"
        command = "lazygit"
        [[agent.lazygit.variant]]
        id = "debug"
        title = "Debug"
        arguments = ["--debug"]
        """)),
    ("zed is redefined as a terminal", parsed(app("zed", name: "Zed", bundle: "dev.zed.Zed", role: "terminal")))
]

private let launchers: [AgentLauncher?] = [
    nil, .terminal(nil), .terminal("ghostty"), .terminal("terminal"), .terminal("iterm"), .terminal("warp"), .terminal("wezterm"),
    .terminal("ghost"), .terminal("cmux"), .terminal("zed"), .terminal("vscode"), .terminal("nowhere"), .terminalLink, .desktop
]

private func agentRefs(_ config: Config) -> [ActionRef] {
    var refs: [ActionRef] = [.agent(id: "nobody", variant: nil, launcher: nil)]
    for agent in config.allAgents {
        let variants: [String?] = [nil] + agent.variants.map { $0.id } + ["bogus"]
        for variant in variants {
            for launcher in launchers { refs.append(.agent(id: agent.id, variant: variant, launcher: launcher)) }
        }
    }
    return refs
}

private func appRefs(_ config: Config) -> [ActionRef] {
    [.openTerminal(nil), .openEditor, .openTerminal("nowhere"), .openApp("nowhere")]
        + config.allApps.map { $0.role == .terminal ? ActionRef.openTerminal($0.id) : .openApp($0.id) }
        + config.allApps.map { ActionRef.openTerminal($0.id) }
}

private func presetRefs(_ config: Config) -> [ActionRef] {
    let terminals: [String?] = [nil, "terminal", "ghostty", "warp", "wezterm", "nowhere"]
    return config.presets.flatMap { preset in terminals.map { ActionRef.preset(id: preset.id, terminal: $0) } } + [.preset(id: "nobody", terminal: nil)]
}

@Suite("The registry and the planner agree")
struct AgentLaunchAgreementTests {
    private let folder = HereContext(origin: .container, container: URL(fileURLWithPath: appFolder))
    private let files = HereContext(origin: .items, items: [URL(fileURLWithPath: "\(appFolder)/a.txt")])

    @Test("an action is offered exactly when it can be planned, for every agent, variant, launcher and terminal")
    func offeredExactlyWhenPlannable() {
        var disagreements: [String] = []
        var offered = 0
        var refused = 0
        for machine in machines {
            for (configName, config) in configs {
                let registry = ActionRegistry(config: config, facts: machine.facts)
                let planner = Planner(config: config, facts: machine.facts)
                for ref in agentRefs(config) + appRefs(config) + presetRefs(config) {
                    let context: HereContext
                    if case .preset = ref { context = files } else { context = folder }
                    let info: ActionInfo
                    if case .preset = ref { info = registry.info(ref, context: context) } else { info = registry.info(ref) }
                    var refusal: PlanError?
                    do { _ = try planner.plan(ref, context: context) } catch { refusal = error as? PlanError }
                    let planned = refusal == nil
                    if info.available { offered += 1 } else { refused += 1 }
                    if info.available != planned || (info.available == (info.unavailableReason != nil)) {
                        disagreements.append("\(machine.name) / \(configName) / \(ref.id): offered \(info.available) (\(info.unavailableReason ?? "no reason")), planned \(planned)")
                    }
                    // What cannot start is explained in the same words by `rh actions` and by `rh run`.
                    switch ref {
                    case .agent, .preset:
                        if case .unsupported(let text)? = refusal, text != info.unavailableReason {
                            disagreements.append("\(machine.name) / \(configName) / \(ref.id): the planner says \"\(text)\", the registry \"\(info.unavailableReason ?? "nothing")\"")
                        }
                    case .openTerminal, .openEditor, .openApp:
                        // The terminal named by `open.terminal@editor`, an app that is not there, a default that cannot be chosen:
                        // each is decided in one place and worded once.
                        if let refusal, refusal.message != info.unavailableReason {
                            disagreements.append("\(machine.name) / \(configName) / \(ref.id): the planner says \"\(refusal.message)\", the registry \"\(info.unavailableReason ?? "nothing")\"")
                        }
                    default: break
                    }
                }
            }
        }
        #expect(disagreements.isEmpty, Comment(rawValue: "\(disagreements.count) disagreements, for example:\n" + disagreements.prefix(12).joined(separator: "\n")))
        #expect(offered > 500 && refused > 500, "the table has to exercise both answers (\(offered) offered, \(refused) refused)")
    }
}
