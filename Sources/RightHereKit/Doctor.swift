import Foundation
import RightHereCore

/// Checks that everything Right Here needs is in place. Shared by `rh doctor` and the app.
public struct Doctor: Sendable {
    private let facts: any SystemFacts
    private let paths: RHPaths
    private let loaded: LoadedConfig
    private let runner: any ProcessRunner
    private let rhPath: String?

    /// Paths and config text that a sentence quotes. They are values of the message, not words of its translation: in a
    /// right-to-left sentence the setup window puts a value in an isolate, which is what keeps `~/.local/bin` or a quoted word
    /// in one piece. Their English is what the command line prints.
    private enum Quoted {
        static let localBin = "~/.local/bin"
        static let linkLauncher = "launcher = \"link\""
        static let desktop = "\"desktop\""
        static let agentsExample = "agents = [\"claude\"]"
    }

    public init(
        facts: any SystemFacts = LiveSystemFacts(),
        paths: RHPaths,
        loaded: LoadedConfig,
        runner: any ProcessRunner = LiveProcessRunner(),
        rhPath: String? = Installer.currentExecutablePath()
    ) {
        self.facts = facts
        self.paths = paths
        self.loaded = loaded
        self.runner = runner
        self.rhPath = rhPath
    }

    /// - Parameters:
    ///   - probeExtension: Also ask the Finder extension to try the whole chain a menu click uses,
    ///     including permission to control the terminal. It restarts the extension and can make
    ///     macOS show a permission prompt, so it is opt-in.
    ///   - probeLaunch: Go further and have the extension start a throwaway terminal session that
    ///     runs a typed command, the way an agent launch does. It opens and closes a window.
    public func run(probeExtension: Bool = false, probeLaunch: Bool = false, launchPlacement: TerminalPlacement? = nil) async -> [DoctorCheck] {
        await examine(probeExtension: probeExtension, probeLaunch: probeLaunch, launchPlacement: launchPlacement).checks
    }

    /// The checks, and what the login shell said of the agents' commands on the way.
    /// - Parameter everyAgent: Ask the login shell about every agent the config knows, not only the enabled ones the checks are about: the setup window shows
    ///   for each whether a terminal would find it. The shell is then started even when no agent is enabled.
    /// - Parameter language: The language of what the checks name inside their sentences (an action's title, "5 minutes ago"): the window's, or English for the
    ///   command line and the MCP server, whose sentences are English (the process's own locale made them half German on a German Mac).
    public func examine(probeExtension: Bool = false, probeLaunch: Bool = false, launchPlacement: TerminalPlacement? = nil, everyAgent: Bool = false,
                        language: String = "en") async -> (checks: [DoctorCheck], shell: LoginShellFacts) {
        var checks: [DoctorCheck] = []
        let shell = await loginShellFacts(everyAgent: everyAgent)
        checks.append(configCheck())
        if let pending = pendingCheck() { checks.append(pending) }
        checks += ConfigSync(paths: paths).doctorChecks()
        let names = Localizer(languages: [language])
        checks += menuChecks(names)
        checks += agentChecks(shell, names)
        checks += menuEmptyCheck()
        if claudeLinkIsOffered() { checks.append(claudeLinkCheck()) }
        checks += integrationChecks(shell)
        checks.append(await Self.extensionCheck(runner: runner, crashReports: ExtensionCrashes.reportsFolder(home: facts.homeDirectory)))
        if let copies = copiesCheck() { checks.append(copies) }
        checks.append(Self.activityCheck(logFile: paths.logFile, language: language))
        if probeLaunch {
            checks.append(await launchCheck(placement: launchPlacement))
        } else if probeExtension {
            checks.append(await chainCheck())
        }
        return (checks, shell)
    }

    /// More than one copy of the app in the Applications folders: Spotlight and Launchpad open any of them, and an old one has none of what the new one has (a person
    /// opened 0.3.2 from `~/Applications` and looked for what 0.3.7 in `/Applications` added). No row with one copy or none.
    func copiesCheck() -> DoctorCheck? {
        let installed = AppCopies.installed(facts.applicationCopies(bundleID: AppIdentity.hostBundleID), home: facts.homeDirectory.path)
        guard installed.count > 1, let newest = installed.first else { return nil }
        let home = facts.homeDirectory.path
        let listed = installed.map { "\($0.version ?? "?") (\(PathDisplay.abbreviatingHome(($0.path as NSString).deletingLastPathComponent, home: home)))" }
        return DoctorCheck(.appCopies, status: .warn, detail: .doctorAppCopies(String(installed.count), listed.joined(separator: ", ")),
                           fix: .doctorFixAppCopies(PathDisplay.abbreviatingHome(newest.path, home: home)))
    }

    /// The changes that an AI assistant proposed and that wait for the person: what only they can do, so the row says so. No row when none waits.
    func pendingCheck(now: Date = Date()) -> DoctorCheck? {
        let count = ConfigProposals(directory: paths.proposalsDirectory).waitingCount(now: now)
        guard count > 0 else { return nil }
        return DoctorCheck(.pending, status: .needsUser, detail: .doctorPendingWaiting(String(count)), fix: .doctorFixPending)
    }

    /// What the login shell says, in one start of it, and only when there is something to ask: the commands of the enabled agents (with `everyAgent`, of every
    /// agent the config knows), and
    /// the `PATH` of a new terminal window when the command link exists and this process's own `PATH` does not have its folder (a
    /// graphical app and a program an AI assistant starts have the `PATH` launchd gives them, which says nothing about a terminal).
    private func loginShellFacts(everyAgent: Bool) async -> LoginShellFacts {
        let config = loaded.config
        var seen = Set<String>()
        let commands = (config.enabledAgents.compactMap { config.agent(id: $0) } + (everyAgent ? config.allAgents : [])).map(\.executable).filter { seen.insert($0).inserted }
        let installer = Installer(home: facts.homeDirectory)
        let linked = (try? FileManager.default.destinationOfSymbolicLink(atPath: installer.cliLink.path)) != nil
        let wantPath = linked && !processPath(contains: installer.locations.localBin)
        return await Detector(facts: facts, runner: runner).probe(commands: commands, wantPath: wantPath)
    }

    private func processPath(contains folder: URL) -> Bool {
        Self.pathListsFolder((facts.environment("PATH") ?? "").split(separator: ":").map(String.init), folder)
    }

    /// Whether the folders of a `PATH` include `folder`, however they are spelled: a trailing slash, a doubled slash, a `.` part and a
    /// symbolic link on the way all name the same folder, and a text compare would call the person's own `PATH` wrong.
    static func pathListsFolder(_ entries: [String], _ folder: URL) -> Bool {
        let wanted = Set([folder.standardizedFileURL.path, folder.resolvingSymlinksInPath().path])
        return entries.contains { entry in
            guard entry.hasPrefix("/") else { return false }
            let url = URL(fileURLWithPath: entry)
            return wanted.contains(url.standardizedFileURL.path) || wanted.contains(url.resolvingSymlinksInPath().path)
        }
    }

    /// The launch probe alone, as a check: what `run(probeLaunch:)` adds as its last row. The setup window runs this and
    /// puts the row in the list it has, instead of running the whole doctor again (which asks the login shell for the
    /// agents' commands once more) for a row that is only about the terminal.
    public func launchCheck(placement: TerminalPlacement? = nil) async -> DoctorCheck {
        Self.launchCheck(for: await ExtensionProbe(paths: paths, facts: facts, runner: runner).runLaunch(placement: placement))
    }

    /// What the launch probe reported, as a check. `nil` means the extension never reported back. A probe says what the
    /// Finder extension and the terminal reported, in English in every language (`doctor.verbatim`).
    static func launchCheck(for result: LaunchProbe.Result?) -> DoctorCheck {
        func check(_ status: DoctorCheck.Status, _ detail: String?, fix: String? = nil) -> DoctorCheck {
            DoctorCheck(.finderLaunch, status: status, detail: detail.map(LocalizedMessage.doctorVerbatim), fix: fix.map(LocalizedMessage.doctorVerbatim))
        }
        guard let result else {
            return check(.fail, "the Finder extension did not report back",
                         fix: "Run `rh setup`, then try again. See ~/Library/Logs/right-here/rh.log.")
        }
        let name = result.application
        switch result.outcome {
        case .ran:
            var took = result.seconds.map { String(format: " in %.1f s", $0) } ?? ""
            if let accepted = result.accepted { took += String(format: " (request accepted after %.1f s)", accepted) }
            let shell = result.shell.map { "; login shell \($0)" } ?? ""
            return check(.ok, "\(name) ran a typed command in a new session\(took)\(shell)")
        case .timedOut:
            return check(.needsUser, result.detail, fix: "macOS is waiting for you to allow Right Here to control \(name). Click Allow, then run this again.")
        case .denied:
            return check(.fail, "macOS refused to let Right Here control \(name)", fix: "Allow Right Here in System Settings › Privacy & Security › Automation.")
        case .noReply:
            return check(.fail, result.detail,
                         fix: "Check that \(name) starts your shell normally (a slow or interactive startup file can stall it), or choose another terminal with general.terminal.")
        case .wrongFolder:
            return check(.fail, result.detail, fix: "Choose another terminal with general.terminal and report this, with the terminal's name and version.")
        case .notInstalled, .unsupported:
            return check(.warn, result.detail, fix: "Choose a terminal that can run commands with general.terminal (\(KnownApps.commandTerminalPhrase)).")
        case .failed:
            return check(.fail, result.detail, fix: "Run `rh probe launch` in a terminal for details.")
        }
    }

    private func chainCheck() async -> DoctorCheck {
        Self.chainCheck(for: await ExtensionProbe(paths: paths, facts: facts, runner: runner).runAutomation())
    }

    /// What the automation probe reported, as a check. `nil` means the extension never reported back.
    static func chainCheck(for results: [AutomationProbe.Result]?) -> DoctorCheck {
        func check(_ status: DoctorCheck.Status, _ detail: String, fix: String? = nil) -> DoctorCheck {
            DoctorCheck(.finderChain, status: status, detail: .doctorVerbatim(detail), fix: fix.map(LocalizedMessage.doctorVerbatim))
        }
        guard let results else {
            return check(.fail, "the Finder extension did not report back", fix: "Run `rh setup`, then try again. See ~/Library/Logs/right-here/rh.log.")
        }
        let worst = results.first { $0.outcome != .granted && $0.outcome != .notRunning } ?? results.first
        let summary = results.map { "\($0.application): \($0.outcome.rawValue)" }.joined(separator: ", ")
        switch worst?.outcome {
        case .granted?, .notRunning?:
            return check(.ok, summary)
        case .timedOut?:
            return check(.needsUser, summary, fix: "macOS is waiting for you to allow Right Here to control the terminal. Click Allow, then run this again.")
        default:
            return check(.fail, summary, fix: "Allow Right Here in System Settings › Privacy & Security › Automation.")
        }
    }

    // MARK: Config

    func configCheck() -> DoctorCheck {
        // A link to a file that is not there (a dotfiles manager, before its repository is cloned) reads as no config, and "run `rh setup`" would
        // say to run what has just refused to go on: the link is named, and what to do about it.
        for file in [loaded.file, loaded.localFile] {
            if let target = ConfigProblem.danglingTarget(of: file) {
                return DoctorCheck(.config, status: .fail, detail: .doctorVerbatim("\(file.path) is a link to \(target.withControlCharactersEscaped), which does not exist. Defaults apply until it does."),
                                   fix: .doctorVerbatim("Create the file the link points to, or remove the link and run `rh setup`."))
            }
        }
        if !loaded.fileExists && !loaded.localFileExists {
            return DoctorCheck(.config, status: .warn, detail: .doctorConfigMissing(loaded.file.path), fix: .doctorFixRunSetup)
        }
        if loaded.result.hasErrors {
            let first = loaded.result.diagnostics.first { $0.severity == .error }
            return DoctorCheck(.config, status: .fail, detail: first.map { .doctorVerbatim($0.summary(file: loaded.file)) }, fix: .doctorFixConfigErrors)
        }
        let warnings = loaded.result.diagnostics.count
        var status: DoctorCheck.Status = warnings == 0 ? .ok : .warn
        var notes: [LocalizedMessage] = []
        if loaded.localFileExists { notes.append(.doctorConfigOverlay(loaded.localFile.path)) }
        for file in [loaded.file, loaded.localFile] where (try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)) != nil {
            notes.append(.doctorConfigSymlink(file.lastPathComponent))
            status = .warn
        }
        let detail: LocalizedMessage
        if warnings > 0 {
            detail = .doctorConfigWarnings(String(warnings))
        } else {
            detail = loaded.fileExists ? .doctorVerbatim(loaded.file.path) : .doctorConfigMissing(loaded.file.path)
        }
        return DoctorCheck(.config, status: status, detail: detail, notes: notes, fix: warnings == 0 ? nil : .doctorFixConfigWarnings)
    }

    // MARK: Apps and agents

    private func menuChecks(_ names: Localizer) -> [DoctorCheck] {
        let registry = ActionRegistry(config: loaded.config, facts: facts, localizer: names)
        let defaults = DefaultApps(config: loaded.config, facts: facts)
        // A default the config chose that is not installed is a warning when another app takes its place, and a problem when
        // none does (`missing` says how serious that is for the role).
        func check(_ id: CheckID, _ action: ActionInfo, role: AppDescriptor.Role, configured: String?, missing: DoctorCheck.Status,
                   fix: LocalizedMessage, fallbackFix: LocalizedMessage) -> DoctorCheck {
            if action.available, let found = defaults.substitution(role: role) {
                return DoctorCheck(id, status: .warn, detail: .doctorAppFallback(found.wanted.name, found.used.name), fix: fallbackFix)
            }
            return DoctorCheck(id, status: action.available ? .ok : missing, detail: appDetail(action, role: role, configured: configured), fix: action.available ? nil : fix)
        }
        return [
            check(.terminalDefault, registry.info(.openTerminal(nil)), role: .terminal, configured: loaded.config.terminal, missing: .fail,
                  fix: .doctorFixTerminal, fallbackFix: .doctorFixTerminalFallback),
            check(.editorDefault, registry.info(.openEditor), role: .editor, configured: loaded.config.editor, missing: .warn,
                  fix: .doctorFixEditor, fallbackFix: .doctorFixEditorFallback)
        ]
    }

    /// A row only when the config leaves the menu empty for a folder, with the reasons: nothing in the files of such a config is
    /// wrong, and the menu does not appear. A healthy setup stays quiet.
    private func menuEmptyCheck() -> [DoctorCheck] {
        let folder = HereContext(origin: .container, container: facts.homeDirectory)
        let explained = MenuBuilder(config: loaded.config, facts: facts).explain(for: folder)
        guard explained.menu.isEmpty else { return [] }
        return [DoctorCheck(.finderMenu, status: .warn, detail: .doctorMenuEmpty, notes: explained.leftOut.map { .doctorVerbatim($0.line.withControlCharactersEscaped) }, fix: .doctorFixMenuEmpty)]
    }

    /// What a default app check says: the app a click opens, or why there is none. The two reasons a person can meet
    /// (nothing of the role is installed, the configured app is not) are catalog messages, found by asking `DefaultApps`
    /// again, which is what the registry asked; their English is the planner's sentence word for word, which a test holds.
    /// A config that names an unknown app, or a terminal as an editor, is refused when it is read and the default is used
    /// instead, so no other reason arises; if one ever does, it is the registry's English, shown as it is.
    private func appDetail(_ app: ActionInfo, role: AppDescriptor.Role, configured: String?) -> LocalizedMessage? {
        if app.available { return .menuOpenIn(app.shortTitle) }
        guard let reason = app.unavailableReason else { return nil }
        do throws(PlanError) {
            let found = try DefaultApps(config: loaded.config, facts: facts).resolve(role: role, configured: configured)
            if found.installedBundleID(facts: facts) == nil { return .doctorAppNotInstalled(found.name) }
        } catch {
            switch error {
            case .noDefaultApp(.terminal): return .doctorTerminalNone
            case .noDefaultApp(.editor): return .doctorEditorNone
            default: break
            }
        }
        return .doctorVerbatim(reason)
    }

    private func agentChecks(_ shell: LoginShellFacts, _ names: Localizer) -> [DoctorCheck] {
        let config = loaded.config
        guard !config.enabledAgents.isEmpty else {
            return [DoctorCheck(.agents, status: .warn, detail: .doctorAgentsNone, fix: .doctorFixAgentsAdd(Quoted.agentsExample))]
        }
        let registry = ActionRegistry(config: config, facts: facts, localizer: names)
        let found = shell.found
        var checks: [DoctorCheck] = []
        for id in config.enabledAgents {
            guard let agent = config.agent(id: id) else { continue }
            let command = agent.executable
            let action = registry.info(.agent(id: id, variant: nil, launcher: nil))
            if !found.contains(command), !shell.answered {
                // The shell was started and did not get to the end (a startup file that exits or waits, an `exec tmux`), so nobody knows.
                checks.append(DoctorCheck(.agent(id), title: agent.name, status: .warn, detail: .doctorAgentUnknown(command)))
            } else if !found.contains(command) {
                checks.append(DoctorCheck(.agent(id), title: agent.name, status: .warn, detail: .doctorAgentNotFound(command), fix: .doctorFixAgentRemove(id)))
            } else if !action.available {
                checks.append(DoctorCheck(.agent(id), title: agent.name, status: .warn, detail: action.unavailableMessage ?? action.unavailableReason.map(LocalizedMessage.doctorVerbatim),
                                          fix: .doctorFixAgentLauncher(Quoted.linkLauncher, Quoted.desktop)))
            } else {
                // A choice the person made, so not a warning; but never silent: the row says the agent's own permission prompts are off.
                if let flag = config.flagThatSkipsPrompts(for: agent) {
                    checks.append(DoctorCheck(.agent(id), title: agent.name, status: .ok, detail: .doctorAgentBypass(command, action.title, flag)))
                } else {
                    checks.append(DoctorCheck(.agent(id), title: agent.name, status: .ok, detail: .doctorAgentOk(command, action.title)))
                }
            }
        }
        return checks
    }

    /// The terminal link is Claude Code's own way in, and a handler that is not there matters only where something starts Claude Code
    /// through it: the agent's `launcher = "link"` (which the plain Claude Code entries then follow), the menu's entry for it (under
    /// More Agent Options), or a Quick Action for it. A warning for a person who has no such entry (no Claude Code at all, or a menu
    /// of their own without it), with a fix that starts a tool they may not use, is noise that an AI agent then repeats to them.
    private func claudeLinkIsOffered() -> Bool {
        let config = loaded.config
        guard config.enabledAgents.contains("claude") else { return false }
        if config.agents["claude"]?.launcher == .terminalLink { return true }
        let link = "agent.claude@\(AgentLauncher.linkWord)"
        let folder = HereContext(origin: .container, container: facts.homeDirectory)
        return MenuBuilder(config: config, facts: facts).build(for: folder).contains { $0.actionIDs.contains(link) }
            || (config.serviceItems ?? []).contains(link)
    }

    private func claudeLinkCheck() -> DoctorCheck {
        let handler = facts.homeDirectory.appendingPathComponent("Applications/Claude Code URL Handler.app")
        guard facts.fileExists(handler) else {
            return DoctorCheck(.claudeLink, status: .warn, detail: .doctorClaudeLinkMissing(Quoted.linkLauncher), fix: .doctorFixClaudeLink)
        }
        return DoctorCheck(.claudeLink, status: .ok, detail: .doctorClaudeLinkOk)
    }

    // MARK: Finder integration

    private func integrationChecks(_ shell: LoginShellFacts) -> [DoctorCheck] {
        let installer = Installer(home: facts.homeDirectory)
        var checks: [DoctorCheck] = []

        if let target = installer.installedRunnerTarget() {
            let exists = FileManager.default.isExecutableFile(atPath: target)
            let stale = rhPath.map { $0 != target } ?? false
            if !exists {
                checks.append(DoctorCheck(.finderRunner, status: .fail, detail: .doctorRunnerTargetMissing(target), fix: .doctorFixRunSetup))
            } else if stale {
                checks.append(DoctorCheck(.finderRunner, status: .warn, detail: .doctorRunnerStale(target), fix: .doctorFixRunSetup))
            } else {
                checks.append(DoctorCheck(.finderRunner, status: .ok, detail: .doctorRunnerOk(target)))
            }
        } else {
            checks.append(DoctorCheck(.finderRunner, status: .fail, detail: .doctorRunnerMissing, fix: .doctorFixRunSetup))
        }

        checks.append(servicesCheck())

        let linked = (try? FileManager.default.destinationOfSymbolicLink(atPath: installer.cliLink.path)) != nil
        let onPath = processPath(contains: installer.locations.localBin) || Self.pathListsFolder(shell.path ?? [], installer.locations.localBin)
        if !linked {
            checks.append(DoctorCheck(.cliLink, status: .warn, detail: .doctorCliMissing(installer.cliLink.path), fix: .doctorFixRunSetup))
        } else if onPath {
            checks.append(DoctorCheck(.cliLink, status: .ok, detail: .doctorVerbatim(installer.cliLink.path)))
        } else if shell.path == nil {
            // The shell was asked (the link exists and this process's PATH lacks the folder) and said nothing: a startup file that exits, or
            // takes longer than the probe waits. Nothing is known, so nothing is claimed and the person is not told to edit a profile.
            checks.append(DoctorCheck(.cliLink, status: .ok, detail: .doctorCliPathUnknown(installer.cliLink.path)))
        } else {
            checks.append(DoctorCheck(.cliLink, status: .warn, detail: .doctorCliNotOnPath(installer.cliLink.path), fix: .doctorFixCliPath(Quoted.localBin)))
        }
        return checks
    }

    /// Evidence that a click in Finder has reached `rh`: the newest successful action in the run log that
    /// did not come from the command line. Informational; nothing here is wrong when there is none yet.
    static func activityCheck(logFile: URL, now: Date = Date(), language: String = "en") -> DoctorCheck {
        let text = [logFile, logFile.appendingPathExtension("1")]
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        for line in text.split(separator: "\n").reversed() {
            guard let entry = RunLog.Entry(parsing: line), entry.origin != .cli else { continue }
            let relative = RelativeDateTimeFormatter()
            relative.locale = Locale(identifier: language)
            relative.unitsStyle = .full
            return DoctorCheck(.finderActivity, status: .ok,
                               detail: .doctorActivityRecent(entry.actionID, entry.origin.rawValue, relative.localizedString(for: entry.date, relativeTo: now)))
        }
        return DoctorCheck(.finderActivity, status: .ok, detail: .doctorActivityNone)
    }

    /// The Quick Actions check alone: the Services on disk against the ones the config asks for. It reads the folder of the Services and starts nothing, so the setup window asks it again after a
    /// change of the Quick Actions, which only an Install or Repair carries out.
    public func servicesCheck() -> DoctorCheck {
        let installer = Installer(home: facts.homeDirectory)
        return Self.servicesCheck(
            installed: Set(installer.installedServices().map(\.lastPathComponent)),
            expected: Set(ServiceWorkflow.distinct(ActionRegistry(config: loaded.config, facts: facts, localizer: loaded.config.localizer)
                .serviceSpecs(rhPath: rhPath ?? "rh")).map(ServiceWorkflow.bundleName(for:))))
    }

    /// Compares the Services on disk with the ones the config asks for: they are files written by
    /// `rh setup`, so editing the config does not change them by itself.
    static func servicesCheck(installed: Set<String>, expected: Set<String>) -> DoctorCheck {
        if installed.isEmpty {
            return DoctorCheck(.services, status: .warn, detail: .doctorServicesNone, fix: .doctorFixRunSetup)
        }
        if installed == expected {
            return DoctorCheck(.services, status: .ok, detail: .doctorServicesOk(String(installed.count)))
        }
        let missing = expected.subtracting(installed).count
        let stale = installed.subtracting(expected).count
        return DoctorCheck(.services, status: .warn, detail: .doctorServicesDiffer(String(installed.count), String(missing), String(stale)), fix: .doctorFixRunSetup)
    }

    /// What the Finder extension's check says, and nothing else: one `pluginkit` call. The setup window looks again
    /// every two seconds while its first-run card waits for the extension to be switched on, and the whole doctor
    /// would read the config and ask a login shell for the agents' commands each time.
    /// - Parameter crashReports: where macOS writes crash reports. Given, a switched-on extension that crashed since it was installed is a warning:
    ///   it is registered and enabled, and still shows no menu (ADR 0019). Left out, as the setup window's look every two seconds does while its first-run card waits, only `pluginkit` is asked.
    public static func extensionCheck(runner: any ProcessRunner = LiveProcessRunner(), crashReports: URL? = nil, now: Date = Date()) async -> DoctorCheck {
        let status = await FinderExtensionManager(runner: runner).status()
        switch status.state {
        case .unanswered:
            // A warning and not a failure: nobody knows, so the window does not offer a first run for it, and nothing says the extension is gone.
            return DoctorCheck(.finderExtension, status: .warn,
                               detail: .doctorVerbatim("macOS's plug-in daemon (pluginkit) did not answer within \(Int(FinderExtensionManager.lookTimeout.components.seconds)) seconds, so it is not known whether the extension is registered"),
                               fix: .doctorVerbatim("Try again in a minute; if it keeps happening, restart the Mac."))
        case .notRegistered:
            return DoctorCheck(.finderExtension, status: .fail, detail: .doctorExtensionNotRegistered, fix: .doctorFixExtensionInstall)
        case .disabled:
            return DoctorCheck(.finderExtension, status: .needsUser, detail: .doctorExtensionDisabled, fix: .doctorFixExtensionEnable)
        case .enabled:
            if status.paths.count > 1 {
                return DoctorCheck(.finderExtension, status: .warn, detail: .doctorExtensionMultiple(String(status.paths.count), status.paths.joined(separator: "; ")),
                                   fix: .doctorFixExtensionClean)
            }
            if let crashReports,
               let crashes = ExtensionCrashes.scan(in: crashReports, installedAfter: status.paths.first.flatMap(ExtensionCrashes.installDate(ofExtensionAt:)),
                                                   buildIDs: status.paths.first.flatMap(ExtensionCrashes.buildIDs(ofExtensionAt:)), now: now) {
                return DoctorCheck(.finderExtension, status: .warn, detail: .doctorVerbatim(crashes.detail(now: now)), fix: .doctorVerbatim(ExtensionCrashes.fix))
            }
            return DoctorCheck(.finderExtension, status: .ok, detail: status.paths.first.map(LocalizedMessage.doctorExtensionEnabled))
        }
    }
}
