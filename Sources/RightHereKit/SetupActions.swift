import Foundation
import RightHereCore

/// What the setup window does besides reading the state: runs `rh install`, opens the config, forgets folders, looks at the
/// terminal and the Finder extension. Each is `async` and not isolated to an actor, so none holds the window's thread, and each
/// says what went wrong as a `SetupNotice`, in the words of the process or the system where there are some.
public struct SetupActions: Sendable {
    private let facts: any SystemFacts
    private let paths: RHPaths
    private let runner: any ProcessRunner
    private let helperPath: String

    /// - Parameter helperPath: The `rh` that ships in the app.
    public init(facts: any SystemFacts = LiveSystemFacts(), paths: RHPaths? = nil, runner: any ProcessRunner = LiveProcessRunner(), helperPath: String) {
        self.facts = facts
        self.paths = paths ?? RHPaths.current(facts: facts)
        self.runner = runner
        self.helperPath = helperPath
    }

    /// Runs `rh install`: the runner script, the command link, the config file and the Finder extension. `nil` when it worked.
    public func installOrRepair() async -> SetupNotice? {
        do {
            return Self.failure(of: try await runner.run(ProcessStep(executable: helperPath, arguments: ["install"]), timeout: .seconds(60)))
        } catch {
            // The system's own wording, in the system language; the install did not run to its end.
            return .failed(error.localizedDescription)
        }
    }

    /// Opens the config file in the default text editor, after `rh init` has made it when there is none. `nil` when it worked.
    public func openConfig() async -> SetupNotice? {
        do {
            if !facts.fileExists(paths.configFile),
               let failure = Self.failure(of: try await runner.run(ProcessStep(executable: helperPath, arguments: ["init"]), timeout: .seconds(30))) {
                return failure
            }
            return Self.failure(of: try await runner.run(ProcessStep(executable: "/usr/bin/open", arguments: ["-t", paths.configFile.path])))
        } catch {
            return .failed(error.localizedDescription)
        }
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
        var state = StateStore.load(paths: paths)
        guard change(&state) else { return nil }
        do {
            try state.save(paths: paths)
            return nil
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
