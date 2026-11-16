import Foundation
import RightHereCore

/// What the setup window does besides reading the state: sets Right Here up, opens the config, manages saved folders, looks at the
/// terminal and the Finder extension. Each is `async` and not isolated to an actor, so none holds the window's thread, and each
/// says what went wrong as a `SetupNotice`, in the words of the process or the system where there are some.
public struct SetupActions: Sendable {
    /// What setting Right Here up came to: the report of what it did, and the notice when something failed.
    public struct SetupResult: Sendable, Equatable {
        public var report: SetupReport?
        public var notice: SetupNotice?
    }

    private let facts: any SystemFacts
    private let paths: RHPaths
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
    public func setUp(_ choices: SetupChoices = SetupChoices()) async -> SetupResult {
        await run(.setup(choices: choices))
    }

    private func run(_ request: SetupRequest) async -> SetupResult {
        do {
            let report = try await setup.run(request)
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
    public func repair() async -> SetupResult {
        guard existingConfigFile != nil else { return SetupResult(report: nil, notice: .failed(Self.noConfigYet)) }
        return await run(.repair())
    }

    /// Opens a known layer in the default text editor. Without an explicit choice, the config check's file takes precedence.
    /// A missing selection is reported, never created or replaced with a different layer. `nil` when it worked.
    public func openConfig(_ requested: SetupConfigFile? = nil) async -> SetupNotice? {
        let loaded = ConfigStore.load(paths: paths)
        let available = loaded.setupFiles
        guard let selected = requested ?? loaded.setupErrorFile ?? available.first else { return .failed(Self.noConfigYet) }
        let file = selected.url(relativeTo: paths.configFile)
        guard available.contains(selected) else {
            return .failed(CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: file.path]).localizedDescription)
        }
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

    public func pin(_ folder: String) async -> SetupNotice? {
        guard let url = existingFolder(folder) else { return unavailableFolder(folder) }
        return edit { $0.pin(url.path) }
    }

    /// Reveal only: the saved path is never handed to its default application.
    public func revealFolder(_ folder: String) async -> SetupNotice? {
        guard let url = existingFolder(folder) else { return unavailableFolder(folder) }
        return await reveal(url)
    }

    public func revealSavedFolders() async -> SetupNotice? {
        await reveal(paths.stateFile)
    }

    private func reveal(_ url: URL) async -> SetupNotice? {
        do {
            return Self.failure(of: try await runner.run(ProcessStep(executable: "/usr/bin/open", arguments: ["-R", url.path])))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func existingFolder(_ path: String) -> URL? {
        guard let context = try? ContextInput(paths: [], container: path, resolution: .absoluteOnly).makeContext(),
              let url = context.container?.lexicallyNormalized else { return nil }
        return facts.isDirectory(url) == true ? url : nil
    }

    private func unavailableFolder(_ path: String) -> SetupNotice {
        .folderUnavailable(PathDisplay.abbreviatingHome(path.withControlCharactersEscaped, home: facts.homeDirectory.path))
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
        } catch let error as StateStoreError {
            return .savedFoldersProblem(error.message(home: facts.homeDirectory.path))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
