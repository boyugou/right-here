import Foundation

/// How an agent action starts on this machine, decided in one place. The planner builds the plan from the route and the
/// registry describes the action from the same decision, so what a menu offers is what `rh run` can do. A preset is
/// typed like a variant, so it is resolved here as well.
struct AgentLaunchResolution: Sendable {
    enum Route: Sendable {
        case desktop(AgentDescriptor.Link)
        case terminalLink(AgentDescriptor.Link)
        case terminal(app: AppDescriptor, bundleID: String, adapter: any TerminalAdapter)
    }

    /// Why a launch cannot start, with the English text every surface shows for it.
    enum Unavailable: Error, Sendable, Equatable {
        /// The launcher asked for cannot be combined with a variant (`Config.launcher` words it).
        case launcherConflict(String)
        case noDesktopLink(agent: String)
        case desktopAppNotInstalled(agent: String)
        case noTerminalLink(agent: String)
        case unknownTerminal(String)
        /// No terminal could be chosen as the default; the error says why.
        case noDefaultTerminal(PlanError)
        case terminalNotInstalled(String)
        /// The terminal only opens folders (Warp, cmux): the adapter's refusal, and the app's name for the window's sentence.
        case terminalOnlyOpensFolders(app: String, refusal: String)
        /// The terminal can run commands, but not on this machine (an old version): the adapter says why.
        case terminalCannotRunCommands(String)
        /// An argument of a variant cannot be quoted so that every shell reads it back the same.
        case variantArgument(variant: String, argument: String)
        /// The same for an argument of `[agent.<id>] args`.
        case agentArgument(agent: String, argument: String)

        var text: String {
            switch self {
            case .launcherConflict(let text): return text
            case .noDesktopLink(let agent): return "\(agent) has no desktop app link."
            case .desktopAppNotInstalled(let agent): return "The \(agent) desktop app is not installed."
            case .noTerminalLink(let agent): return "\(agent) has no terminal link. Use a terminal launcher instead."
            case .unknownTerminal(let id): return PlanError.unknownTerminal(id).message
            case .noDefaultTerminal(let error): return error.message
            case .terminalNotInstalled(let name): return PlanError.appNotInstalled(name).message
            case .terminalOnlyOpensFolders(_, let refusal): return refusal
            case .terminalCannotRunCommands(let text): return text
            case .variantArgument(let variant, let argument):
                return "The argument \"\(argument)\" of the variant \"\(variant)\" has a backslash, which shells do not all read the same way inside quotes. Put the whole command in the agent's `command`, which is typed as written."
            case .agentArgument(let agent, let argument):
                return "The argument \"\(argument)\" in args of [agent.\(agent)] has a backslash, which shells do not all read the same way inside quotes. Put the whole command in the agent's `command`, which is typed as written."
            }
        }
    }

    /// The launcher after the rule that a variant is always typed, also when it cannot start: titles follow it.
    let launcher: AgentLauncher
    let route: Result<Route, Unavailable>

    /// - Parameters:
    ///   - hasVariant: A variant or a preset adds typed words, which only a terminal can take.
    ///   - explicit: The launcher the action id names, if it does; otherwise the agent's configured one.
    static func resolve(agent: AgentDescriptor, hasVariant: Bool, explicit: AgentLauncher?, config: Config, facts: any SystemFacts) -> AgentLaunchResolution {
        let chosen = config.launcher(forAgent: agent.id, explicit: explicit, hasVariant: hasVariant)
        func resolution(_ route: Result<Route, Unavailable>) -> AgentLaunchResolution {
            AgentLaunchResolution(launcher: chosen.launcher, route: route)
        }
        if let conflict = chosen.conflict { return resolution(.failure(.launcherConflict(conflict))) }
        switch chosen.launcher {
        case .desktop:
            guard let link = agent.desktopLink else { return resolution(.failure(.noDesktopLink(agent: agent.name))) }
            if let bundleID = agent.iconBundleID, facts.applicationURL(bundleID: bundleID) == nil {
                return resolution(.failure(.desktopAppNotInstalled(agent: agent.name)))
            }
            return resolution(.success(.desktop(link)))
        case .terminalLink:
            guard let link = agent.terminalLink else { return resolution(.failure(.noTerminalLink(agent: agent.name))) }
            return resolution(.success(.terminalLink(link)))
        case .terminal(let id):
            return resolution(terminalRoute(id, config: config, facts: facts))
        }
    }

    /// The line typed to start the agent. `command` is a typed command line, so it goes in as written and may carry arguments of
    /// its own (`claude --model opus`). Each element of a variant's `arguments` is one argument, one word of the line: it is
    /// quoted when it needs it, so `"be brief; echo $HOME"` reaches the agent as that one argument and not as shell syntax,
    /// and a word that needs no quoting (`--continue`, `resume`) is typed bare, as it always was. An argument with a backslash
    /// is refused: fish reads one inside single quotes differently from the other shells (the reason presets refuse it too),
    /// and the terminal's shell is not necessarily the login shell.
    static func typedLine(agent: AgentDescriptor, variant: AgentDescriptor.Variant?, options: Config.AgentLaunchOptions) -> Result<String, Unavailable> {
        var words = [agent.command]
        // The words of the flag, each quoted when it needs it: the config only lets a flag be words of plain characters, and a flag that came another way is not typed as shell syntax either.
        if let flag = options.bypassFlag {
            words += flag.split(separator: " ").map { word in
                String(word).range(of: ConfigSchema.bypassFlagPattern, options: .regularExpression) != nil ? String(word) : ShellQuoting.quote(String(word), for: .posix)
            }
        }
        switch argumentWords(options.arguments, of: agent) {
        case .success(let quoted): words += quoted
        case .failure(let why): return .failure(why)
        }
        for argument in variant?.arguments ?? [] {
            if argument.unicodeScalars.contains("\\") { return .failure(.variantArgument(variant: variant?.id ?? "", argument: argument)) }
            words.append(ShellQuoting.quote(argument, for: .posix))
        }
        return .success(words.joined(separator: " "))
    }

    /// The person's `args` of an agent as words of the typed line, each quoted when it needs it and refused with a backslash, like a variant's.
    static func argumentWords(_ arguments: [String], of agent: AgentDescriptor) -> Result<[String], Unavailable> {
        var words: [String] = []
        for argument in arguments {
            if argument.unicodeScalars.contains("\\") { return .failure(.agentArgument(agent: agent.id, argument: argument)) }
            words.append(ShellQuoting.quote(argument, for: .posix))
        }
        return .success(words)
    }

    /// The terminal a command is typed into: the named one, or the default for commands.
    private static func terminalRoute(_ id: String?, config: Config, facts: any SystemFacts) -> Result<Route, Unavailable> {
        let app: AppDescriptor
        if let id {
            guard let found = config.terminalApp(id: id) else { return .failure(.unknownTerminal(id)) }
            app = found
        } else {
            do throws(PlanError) { app = try DefaultApps(config: config, facts: facts).commandTerminal() } catch { return .failure(.noDefaultTerminal(error)) }
        }
        guard let bundleID = app.installedBundleID(facts: facts) else { return .failure(.terminalNotInstalled(app.name)) }
        let adapter = TerminalAdapters.adapter(for: app)
        if let refusal = adapter.commandRefusal { return .failure(.terminalOnlyOpensFolders(app: app.name, refusal: refusal)) }
        if let blocker = adapter.commandBlocker(bundleID: bundleID, facts: facts) { return .failure(.terminalCannotRunCommands(blocker)) }
        return .success(.terminal(app: app, bundleID: bundleID, adapter: adapter))
    }
}

extension PlanError {
    init(_ unavailable: AgentLaunchResolution.Unavailable) {
        self = .unsupported(unavailable.text)
    }
}

extension AgentLaunchResolution.Unavailable {
    /// The reasons a person meets as sentences of the catalog, which the window writes in their language; the others are their English.
    var message: LocalizedMessage {
        switch self {
        case .terminalOnlyOpensFolders(let app, _): return .appTerminalNoAgents(app)
        case .terminalNotInstalled(let name): return .doctorAppNotInstalled(name)
        case .noDefaultTerminal(.noDefaultApp(.terminal)): return .doctorTerminalNone
        default: return .doctorVerbatim(text)
        }
    }
}
