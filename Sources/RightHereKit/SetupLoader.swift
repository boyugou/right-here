import Foundation
import RightHereCore

/// Everything the setup window shows, read at one moment.
public struct SetupSnapshot: Sendable, Equatable {
    public var checks: [DoctorCheck]
    /// The Finder menu for a folder, built the way the Finder extension builds it; empty when the config has errors.
    public var menu: [MenuNode]
    public var pins: [String]
    public var recents: [String]
    public var configFile: URL
    /// What the config parser says is wrong with the config, errors and warnings, in its own words.
    public var configProblems: [ConfigDiagnostic]

    public init(checks: [DoctorCheck] = [], menu: [MenuNode] = [], pins: [String] = [], recents: [String] = [],
                configFile: URL, configProblems: [ConfigDiagnostic] = []) {
        self.checks = checks
        self.menu = menu
        self.pins = pins
        self.recents = recents
        self.configFile = configFile
        self.configProblems = configProblems
    }

    public var configHasErrors: Bool {
        configProblems.contains { $0.severity == .error }
    }
}

/// Reads the state of the machine for the setup window in one pass: the config once (the doctor and the menu preview
/// are made from the same read), the doctor's checks, the Finder menu and the folders Right Here remembers.
///
/// It is not isolated to an actor, so a caller on the main actor does not wait for it: the doctor starts the login shell
/// for the agents' commands and the file reads can stall. It starts no `git`.
public struct SetupLoader: Sendable {
    private let facts: any SystemFacts
    private let paths: RHPaths
    private let runner: any ProcessRunner
    private let helperPath: String?
    private let localizer: Localizer

    /// - Parameter helperPath: The `rh` that ships in the app, which the runner script of an install should point at.
    public init(facts: any SystemFacts = LiveSystemFacts(), paths: RHPaths? = nil, runner: any ProcessRunner = LiveProcessRunner(),
                helperPath: String?, localizer: Localizer = .system) {
        self.facts = facts
        self.paths = paths ?? RHPaths.current(facts: facts)
        self.runner = runner
        self.helperPath = helperPath
        self.localizer = localizer
    }

    public func load() async -> SetupSnapshot {
        let loaded = ConfigStore.load(paths: paths)
        let checks = await Doctor(facts: facts, paths: paths, loaded: loaded, runner: runner, rhPath: helperPath).run()
        let menu = MenuPreview.folderMenu(loaded.result, facts: facts, folder: facts.homeDirectory, localizer: localizer)
        let state = StateStore.load(paths: paths)
        return SetupSnapshot(checks: checks, menu: menu, pins: state.pins, recents: state.recents,
                             configFile: loaded.file, configProblems: loaded.result.diagnostics)
    }
}
