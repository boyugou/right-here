import Foundation
import Testing
@testable import RightHereCore

private let ghostty = "com.mitchellh.ghostty"
private let terminalApp = "com.apple.Terminal"

private func facts(_ installed: [String] = [], versions: [String: String] = [:]) -> FakeSystemFacts {
    FakeSystemFacts(
        directories: ["/Users/tester/code"],
        applications: Dictionary(uniqueKeysWithValues: installed.map { ($0, URL(fileURLWithPath: "/Applications/\($0).app")) }),
        bundleVersions: versions
    )
}

private func resolve(
    _ agentID: String = "claude", variant: Bool = false, launcher: AgentLauncher? = nil,
    config: Config = .default, installed: [String] = [], versions: [String: String] = [:]
) throws -> AgentLaunchResolution {
    let agent = try #require(config.agent(id: agentID))
    return AgentLaunchResolution.resolve(agent: agent, hasVariant: variant, explicit: launcher, config: config, facts: facts(installed, versions: versions))
}

private func unavailable(_ resolution: AgentLaunchResolution) -> AgentLaunchResolution.Unavailable? {
    if case .failure(let why) = resolution.route { return why }
    return nil
}

private func parsed(_ text: String) -> Config { ConfigParser.parse(text).config }

@Suite("AgentLaunchResolution")
struct AgentLaunchResolutionTests {
    @Test func aTerminalThatCanRunCommandsIsTheRouteWithItsAdapter() throws {
        let resolution = try resolve(installed: [ghostty, terminalApp], versions: [ghostty: "1.3.1"])
        guard case .success(.terminal(let app, let bundleID, let adapter)) = resolution.route else { Issue.record("\(resolution.route)"); return }
        #expect(app.id == "ghostty" && bundleID == ghostty && adapter is GhosttyAdapter)
        #expect(resolution.launcher == .terminal(nil))
        let named = try resolve(launcher: .terminal("terminal"), installed: [ghostty, terminalApp])
        guard case .success(.terminal(let other, _, let otherAdapter)) = named.route else { Issue.record("\(named.route)"); return }
        #expect(other.id == "terminal" && otherAdapter is AppleTerminalAdapter)
    }

    @Test func theDefaultTerminalForACommandSkipsOnesThatCannotRunOne() throws {
        for installed in [["com.cmuxterm.app", terminalApp], ["dev.warp.Warp-Stable", terminalApp]] {
            guard case .success(.terminal(let app, _, _)) = try resolve(installed: installed).route else { Issue.record("no route for \(installed)"); return }
            #expect(app.id == "terminal")
        }
        guard case .success(.terminal(let itermApp, _, _)) = try resolve(installed: ["com.googlecode.iterm2", terminalApp]).route else { Issue.record("no route for iterm"); return }
        #expect(itermApp.id == "iterm")
        guard case .success(.terminal(let weztermApp, _, let wezAdapter)) = try resolve(installed: ["com.github.wez.wezterm", terminalApp]).route else { Issue.record("no route for wezterm"); return }
        #expect(weztermApp.id == "wezterm" && wezAdapter is WezTermAdapter)
        guard case .success(.terminal(let kittyApp, _, let kittyAdapter)) = try resolve(installed: ["net.kovidgoyal.kitty", terminalApp]).route else { Issue.record("no route for kitty"); return }
        #expect(kittyApp.id == "kitty" && kittyAdapter is KittyAdapter)
    }

    @Test func aTerminalIdThatIsNoTerminalIsUnknown() throws {
        #expect(unavailable(try resolve(launcher: .terminal("nowhere"), installed: [terminalApp])) == .unknownTerminal("nowhere"))
        #expect(unavailable(try resolve(launcher: .terminal("zed"), installed: ["dev.zed.Zed"])) == .unknownTerminal("zed"), "an editor is not a terminal")
        let text = try #require(unavailable(try resolve(launcher: .terminal("nowhere")))).text
        #expect(text.hasPrefix("Unknown terminal \"nowhere\"."), Comment(rawValue: text))
    }

    @Test func noTerminalInstalledMeansThereIsNoDefault() throws {
        let why = try #require(unavailable(try resolve()))
        #expect(why == .noDefaultTerminal(.noDefaultApp(.terminal)))
        #expect(why.text == "No terminal is installed.")
    }

    @Test func aDefaultTheConfigMadeUnusableSaysWhy() throws {
        let config = Config(terminal: "ghostty", apps: [AppDescriptor(id: "ghostty", name: "Ghostty", bundleIDs: [ghostty], role: .editor)])
        let why = try #require(unavailable(try resolve(config: config, installed: [ghostty])))
        #expect(why.text == "Ghostty is not a terminal. Use open.app.ghostty to open files with it.")
    }

    @Test func aTerminalThatIsNotInstalledIsNamed() throws {
        let why = try #require(unavailable(try resolve(launcher: .terminal("iterm"), installed: [terminalApp])))
        #expect(why == .terminalNotInstalled("iTerm"))
        #expect(why.text == "iTerm is not installed.")
    }

    @Test func aConfiguredDefaultThatIsNotInstalledGivesWayToTheFirstTerminalThatCanRunACommand() throws {
        // A config shared between Macs names iTerm; this one has Terminal. The default counts as none (the doctor, `rh menu --explain`
        // and the plan say that another terminal is used); naming iTerm for the agent, as above, does not fall back.
        let configured = try resolve(config: Config(terminal: "iterm"), installed: [terminalApp])
        #expect(unavailable(configured) == nil)
        guard case .success(.terminal(let app, _, _)) = configured.route else { Issue.record("no terminal route: \(configured.route)"); return }
        #expect(app.id == "terminal")
    }

    @Test func aTerminalThatCannotRunCommandsSaysSoInTheAdaptersWords() throws {
        let folderOnly = try #require(unavailable(try resolve(launcher: .terminal("warp"), installed: ["dev.warp.Warp-Stable"])))
        #expect(folderOnly.text == "Warp cannot run commands yet. Choose another terminal for this agent.")
        let template = parsed("""
            [[app]]
            id = "wezterm"
            name = "WezTerm"
            bundle_id = "com.github.wez.wezterm"
            role = "terminal"
            open_args = ["{app}/Contents/MacOS/wezterm", "start", "--cwd", "{dir}"]
            """)
        let noRun = try #require(unavailable(try resolve(launcher: .terminal("wezterm"), config: template, installed: ["com.github.wez.wezterm"])))
        #expect(noRun.text.contains("run_args"), Comment(rawValue: noRun.text))
    }

    @Test func aGhosttyThatCannotBeScriptedIsBlockedOnThisMachine() throws {
        let why = try #require(unavailable(try resolve(launcher: .terminal("ghostty"), installed: [ghostty], versions: [ghostty: "1.2.3"])))
        #expect(why.text.contains("1.2.3") && why.text.contains("1.3"), Comment(rawValue: why.text))
        #expect(unavailable(try resolve(launcher: .terminal("ghostty"), installed: [ghostty], versions: [ghostty: "1.3"])) == nil)
    }

    @Test func linksNeedTheAgentToHaveOne() throws {
        guard case .success(.terminalLink(let link)) = try resolve(launcher: .terminalLink).route else { Issue.record("no link route"); return }
        #expect(link.template.hasPrefix("claude-cli://"))
        let why = try #require(unavailable(try resolve("codex", launcher: .terminalLink)))
        #expect(why == .noTerminalLink(agent: "Codex"))
        #expect(why.text == "Codex has no terminal link. Use a terminal launcher instead.")
        #expect(unavailable(try resolve("aider", launcher: .desktop)) == .noDesktopLink(agent: "aider"))
    }

    @Test func aDesktopLaunchNeedsItsAppInstalled() throws {
        let why = try #require(unavailable(try resolve(launcher: .desktop)))
        #expect(why == .desktopAppNotInstalled(agent: "Claude Code"))
        #expect(why.text == "The Claude Code desktop app is not installed.")
        guard case .success(.desktop(let link)) = try resolve(launcher: .desktop, installed: ["com.anthropic.claudefordesktop"]).route else { Issue.record("no desktop route"); return }
        #expect(link.template.hasPrefix("claude://"))
    }

    @Test func aVariantIsTypedAndAnExplicitLinkOrDesktopWithOneIsAConflict() throws {
        let linked = parsed("[agent.claude]\nlauncher = \"link\"\n")
        let typed = try resolve(variant: true, config: linked, installed: [terminalApp])
        #expect(typed.launcher == .terminal(nil))
        guard case .success(.terminal) = typed.route else { Issue.record("a variant did not go to a terminal: \(typed.route)"); return }
        let conflict = try resolve(variant: true, launcher: .desktop, installed: [terminalApp, "com.anthropic.claudefordesktop"])
        #expect(conflict.launcher == .terminal(nil))
        guard case .launcherConflict(let text)? = unavailable(conflict) else { Issue.record("no conflict: \(conflict.route)"); return }
        #expect(text.contains("variant"))
    }

    @Test func aPresetIsTypedLikeAVariantWhateverTheAgentsLauncherIs() throws {
        let desktop = parsed("[agent.codex]\nlauncher = \"desktop\"\n")
        let resolution = try resolve("codex", variant: true, config: desktop, installed: [terminalApp, "com.openai.codex"])
        guard case .success(.terminal(let app, _, _)) = resolution.route else { Issue.record("\(resolution.route)"); return }
        #expect(app.id == "terminal")
    }

    @Test func thePlannerRefusesWithTheSameSentenceAsTheRegistry() throws {
        let machine = facts([terminalApp])
        let context = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/code"))
        for ref in [ActionRef.agent(id: "claude", variant: nil, launcher: .desktop), .agent(id: "codex", variant: nil, launcher: .terminalLink),
                    .agent(id: "claude", variant: nil, launcher: .terminal("warp")), .agent(id: "claude", variant: "continue", launcher: .desktop)] {
            let reason = try #require(ActionRegistry(config: .default, facts: machine).info(ref).unavailableReason)
            #expect(throws: PlanError.unsupported(reason), "\(ref.id)") { try Planner(facts: machine).plan(ref, context: context) }
        }
    }

    @Test func theWordsOfAFlagAreTypedEachQuotedWhenItNeedsItSoThatNothingIsShellSyntax() throws {
        let claude = try #require(KnownAgents.agent(id: "claude"))
        // The config only lets a flag be plain words; a flag that came another way is not typed as shell syntax either.
        let plain = try AgentLaunchResolution.typedLine(agent: claude, variant: nil, options: .init(bypassFlag: "--permission-mode bypassPermissions", arguments: [])).get()
        #expect(plain == "claude --permission-mode bypassPermissions")
        let hostile = try AgentLaunchResolution.typedLine(agent: claude, variant: nil, options: .init(bypassFlag: "--yes; touch /tmp/x $(id)", arguments: [])).get()
        #expect(hostile == "claude --yes';' touch /tmp/x '$(id)'" || hostile == "claude '--yes;' touch /tmp/x '$(id)'", "\(hostile)")
        #expect(!hostile.contains("; touch"))
    }
}
