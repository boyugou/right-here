import Foundation
import RightHereCore

/// What the setup window does besides reading the state: sets Right Here up, opens the config, forgets folders, looks at the
/// terminal and the Finder extension. Each is `async` and not isolated to an actor, so none holds the window's thread, and each
/// says what went wrong as a `SetupNotice`, in the words of the process or the system where there are some.
public struct SetupActions: Sendable {
    /// What setting Right Here up came to: the report of what it did, and the notice when something failed.
    public struct SetupResult: Sendable, Equatable {
        public var report: SetupReport?
        public var notice: SetupNotice?
    }

    private let facts: any SystemFacts
    let paths: RHPaths
    private let runner: any ProcessRunner
    private let helperPath: String
    private let app: URL?
    private let trialHome: URL?
    private let lockTimeout: Duration

    /// - Parameters:
    ///   - helperPath: The `rh` that ships in the app: what the runner script and the Quick Actions run.
    ///   - app: The app that has the Finder extension (the one that is running).
    ///   - lockTimeout: How long setup waits for another one that is running (`SetupRunner`).
    public init(facts: any SystemFacts = LiveSystemFacts(), paths: RHPaths? = nil, runner: any ProcessRunner = LiveProcessRunner(), helperPath: String,
                app: URL? = nil, trialHome: URL? = LiveSystemFacts.homeOverride, lockTimeout: Duration = .seconds(120)) {
        self.facts = facts
        self.paths = paths ?? RHPaths.current(facts: facts)
        self.runner = runner
        self.helperPath = helperPath
        self.app = app
        self.trialHome = trialHome
        self.lockTimeout = lockTimeout
    }

    private var setup: SetupRunner {
        SetupRunner(facts: facts, paths: paths, runner: runner, rhPath: helperPath, app: app, trialHome: trialHome, lockTimeout: lockTimeout)
    }

    /// Sets Right Here up, as `rh setup` does: the config file (made from `choices` and what is installed, only when there is none), the
    /// runner script, the command link, the Quick Actions and the Finder extension's registration, then the checks. The same code as the
    /// command line, called here and not spawned. The notice is `nil` when every step worked.
    /// - Parameter progress: Told of each phase before it starts (`SetupRunner.run`).
    public func setUp(_ choices: SetupChoices = SetupChoices(), progress: @Sendable (SetupPhase) async -> Void = { _ in }) async -> SetupResult {
        await run(.setup(choices: choices), progress: progress)
    }

    private func run(_ request: SetupRequest, lockTimeout: Duration? = nil, progress: @Sendable (SetupPhase) async -> Void) async -> SetupResult {
        var request = request
        request.isForTheWindow = true
        let setup = lockTimeout.map { SetupRunner(facts: facts, paths: paths, runner: runner, rhPath: helperPath, app: app, trialHome: trialHome, lockTimeout: $0) } ?? self.setup
        do {
            let report = try await setup.run(request, progress: progress)
            let failure = report.steps.first { $0.outcome == .failed }?.detail?.english()
            return SetupResult(report: report, notice: report.ok ? nil : .failed(failure ?? "Setup did not finish."))
        } catch {
            // The system's own wording, in the system language; setup did not start.
            return SetupResult(report: nil, notice: .failed(error.localizedDescription))
        }
    }

    /// Install or Repair: the same setup without choices, for a Mac that has a config. It makes what is missing and changes what is out of date,
    /// and never makes the config: a config made from what was found, without the choice the first run asks for, is not what the person would
    /// have chosen, and the window that is not sure yet whether there is one (it has not looked) must not make it.
    public func repair(progress: @Sendable (SetupPhase) async -> Void = { _ in }) async -> SetupResult {
        guard existingConfigFile != nil else { return SetupResult(report: nil, notice: .failed(Self.noConfigYet)) }
        return await run(.repair(), progress: progress)
    }

    /// Writes the Quick Actions again from the config as it is now, and nothing else: what the window does after a change of the person's that makes them differ (an agent
    /// that the default list starts, their own list, the language of their names).
    public func updateQuickActions() async -> SetupResult {
        // Another setup that holds the lock writes them itself; the person's change does not wait for it.
        await run(SetupRequest(pieces: [.services], createsConfig: false), lockTimeout: .zero, progress: { _ in })
    }

    /// Opens the config file in the default text editor. A Mac with no config is told to choose first and press Set Up, which makes the file
    /// from the choices; this does not. `nil` when it worked.
    public func openConfig() async -> SetupNotice? {
        guard let file = existingConfigFile else { return .failed(Self.noConfigYet) }
        do {
            return Self.failure(of: try await runner.run(ProcessStep(executable: "/usr/bin/open", arguments: ["-t", file.path])))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// The config file, or when only the per-machine overlay is there, that: what a config that exists is, for the window (`LoadedConfig.hasConfig`).
    private var existingConfigFile: URL? {
        let loaded = ConfigStore.load(paths: paths)
        guard loaded.hasConfig else { return nil }
        return loaded.localFileExists && !loaded.fileExists ? paths.localConfigFile : paths.configFile
    }

    static let noConfigYet = "There is no config file yet. Choose what you use and press Set Up: the file is made from your choices."

    /// What a change of the config made in the window came to: what it did, so that it can be said and taken back, or why it was refused.
    public struct ConfigEditResult: Sendable, Equatable {
        public var change: ConfigChange?
        public var notice: SetupNotice?
    }

    /// Changes the config as the person asks in the window (`ConfigService`, as `rh config` does): in the file that decides `key` on this Mac, in the smallest way, with the
    /// text before it kept for undo. A change the config would refuse (a text that does not read, a setting it does not have) is said, and the file is left as it was.
    /// - Parameter anchor: What the file that decides `key` is also the one that holds, for a key of a table that another key makes (`ConfigService.owner(of:anchor:)`).
    /// - Parameter target: The file to change, when it is not the one a setting decides: an entry of a list (a preset) is in the file that holds it, and the same place in the other file is another entry.
    public func editConfig(_ operations: [ConfigOperation], deciding key: String, anchor: String? = nil, target: ConfigTarget? = nil) async -> ConfigEditResult {
        let service = ConfigService(paths: paths)
        do {
            return ConfigEditResult(change: try service.apply(operations, target: target ?? service.owner(of: key, anchor: anchor), actor: .window), notice: nil)
        } catch ConfigDocument.EditError.changedMeanwhile {
            return ConfigEditResult(change: nil, notice: .listChanged)
        } catch {
            return ConfigEditResult(change: nil, notice: .failed(Self.describe(error)))
        }
    }

    /// The agents that the change would make start without their permission prompts, and did not.
    public func looseningEffects(of operations: [ConfigOperation], deciding key: String, anchor: String? = nil, target: ConfigTarget? = nil) async -> [PromptEffects.Entry] {
        let service = ConfigService(paths: paths)
        return service.looseningEffects(of: operations, target: target ?? service.owner(of: key, anchor: anchor))
    }

    /// The agents that making a stored proposal would start without their permission prompts, and did not.
    public func looseningEffects(ofProposal id: String) async -> [PromptEffects.Entry] {
        ConfigService(paths: paths).looseningEffects(ofProposal: id)
    }

    /// The ids that the files have for the entries of a list of tables (`ConfigService.entryIDsInUse`): a new entry takes none of them.
    public func entryIDsInUse(of table: String) async -> Set<String> {
        ConfigService(paths: paths).entryIDsInUse(of: table)
    }

    public func presetIDsInUse() async -> Set<String> {
        ConfigService(paths: paths).presetIDsInUse()
    }

    /// The file that decides `key` on this Mac (`ConfigService.owner(of:anchor:)`).
    public func owner(of key: String, anchor: String? = nil) async -> ConfigTarget {
        ConfigService(paths: paths).owner(of: key, anchor: anchor)
    }

    /// The ids of the agents that a file of the config mentions, which a new agent does not take (`ConfigService.agentIDsInUse`).
    public func agentIDsInUse() async -> Set<String> {
        ConfigService(paths: paths).agentIDsInUse()
    }

    /// The ids of the three kinds that `disabled` names, which a new app, template or agent takes none of (`ConfigService.disableableIDsInUse`).
    public func disableableIDsInUse() async -> Set<String> {
        ConfigService(paths: paths).disableableIDsInUse()
    }

    /// The apps the files offer by bundle identifier (`ConfigService.appsAvailable`), as they are now.
    public func appsAvailable() async -> [String: String] {
        ConfigService(paths: paths).appsAvailable()
    }

    /// What an error says, as a line a person reads: it may quote a value somebody else wrote.
    static func describe(_ error: Error) -> String {
        ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription).withControlCharactersEscaped
    }

    /// Pins a folder. `nil` when it was saved, or when it was pinned already.
    public func pin(_ folder: String) async -> SetupNotice? {
        edit { $0.pin(folder) }
    }

    /// Takes a folder out of the pinned ones. `nil` when it was saved, or when there was nothing to take out.
    public func unpin(_ folder: String) async -> SetupNotice? {
        edit { $0.unpin(folder) }
    }

    /// Empties the list of recent folders. `nil` when it was saved.
    public func clearRecents() async -> SetupNotice? {
        edit { $0.clearRecents(); return true }
    }

    /// The git repository a folder is in, as the setup window looks it up (`nil` when there is none).
    public func repository(containing folder: URL) async -> URL? {
        facts.gitRoot(containing: folder)?.standardizedFileURL
    }

    /// The launch probe alone: the Finder extension starts a throwaway terminal session that runs a typed command, the way a menu
    /// click starts an agent. A window opens and closes; the first time, macOS asks whether Right Here may control the terminal.
    public func launchCheck() async -> DoctorCheck {
        await Doctor(facts: facts, paths: paths, loaded: ConfigStore.load(paths: paths), runner: runner, rhPath: helperPath).launchCheck()
    }

    /// The Finder extension's check alone, one `pluginkit` call: what the window looks at while it waits for the person to switch
    /// the extension on.
    public func extensionCheck() async -> DoctorCheck {
        await Doctor.extensionCheck(runner: runner)
    }

    /// What a finished process says about itself: nothing when it worked, else why in its own words, else its exit status.
    static func failure(of result: ProcessResult) -> SetupNotice? {
        guard result.status != 0 else { return nil }
        let text = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? .stopped(status: result.status) : .failed(text)
    }

    private func edit(_ change: (inout StateStore) -> Bool) -> SetupNotice? {
        do {
            try StateStore.update(paths: paths) { _ = change(&$0) }
            return nil
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
