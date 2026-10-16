import Foundation
import RightHereCore

/// The folders Right Here remembers, and the git repositories they are in.
public struct FolderSnapshot: Sendable, Equatable {
    /// Pinned with `rh pin`, in the order they were pinned.
    public var pins: [String]
    /// The folders of the actions run most recently, the newest first.
    public var recents: [String]
    /// The repositories the pinned and the recent folders are in, the first the most likely one to be asked about.
    public var repositories: [URL]

    public init(pins: [String] = [], recents: [String] = [], repositories: [URL] = []) {
        self.pins = pins
        self.recents = recents
        self.repositories = repositories
    }
}

/// Everything the setup window shows, read at one moment.
public struct SetupSnapshot: Sendable, Equatable {
    public var checks: [DoctorCheck]
    /// The Finder menu for a folder, built the way the Finder extension builds it; empty when the config has errors.
    public var menu: [MenuNode]
    public var folders: FolderSnapshot
    public var configFile: URL
    /// Whether there is a config at all, `config.toml` or the per-machine overlay. Without one the window is on its first run.
    public var configExists: Bool
    /// What a person without a config can choose from; `nil` when there is a config.
    public var offer: SetupOffer?
    /// What the config parser says is wrong with the config, errors and warnings, in its own words.
    public var configProblems: [ConfigDiagnostic]
    /// The program an MCP client starts (`SetupSnippets.mcpCommand`).
    public var mcpCommand: String
    /// The home folder, which paths are written from `~` against.
    public var home: URL

    public init(checks: [DoctorCheck] = [], menu: [MenuNode] = [], folders: FolderSnapshot = FolderSnapshot(), configFile: URL,
                configExists: Bool = true, offer: SetupOffer? = nil, configProblems: [ConfigDiagnostic] = [], mcpCommand: String = AppIdentity.cliName, home: URL) {
        self.checks = checks
        self.menu = menu
        self.folders = folders
        self.configFile = configFile
        self.configExists = configExists
        self.offer = offer
        self.configProblems = configProblems
        self.mcpCommand = mcpCommand
        self.home = home
    }

    public var configHasErrors: Bool {
        configProblems.contains { $0.severity == .error }
    }
}

/// Reads the state of the machine for the setup window in one pass: the config once (the doctor and the menu preview are made
/// from the same read), the doctor's checks, the Finder menu, the folders Right Here remembers and the repositories they are in.
///
/// It is not isolated to an actor, so a caller on the main actor does not wait for it: the doctor starts the login shell for the
/// agents' commands and the file reads can stall. It starts no `git`; the worktrees are listed only when the person asks for them.
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
        // Without a config the window is on its first run and offers what is installed; the login shell is asked once, for that.
        let configExists = loaded.hasConfig
        let offer = configExists ? nil : await SetupOffer.make(facts: facts, runner: runner)
        let checks = await Doctor(facts: facts, paths: paths, loaded: loaded, runner: runner, rhPath: helperPath).run()
        let menu = MenuPreview.folderMenu(loaded.result, facts: facts, folder: facts.homeDirectory, localizer: localizer)
        return SetupSnapshot(
            checks: checks, menu: menu, folders: await folders(), configFile: loaded.file, configExists: configExists, offer: offer,
            configProblems: loaded.result.diagnostics,
            mcpCommand: SetupSnippets.mcpCommand(home: facts.homeDirectory, helperPath: helperPath), home: facts.homeDirectory)
    }

    /// The folders Right Here remembers, as they are on disk now.
    public func folders() async -> FolderSnapshot {
        let state = StateStore.load(paths: paths)
        return FolderSnapshot(pins: state.pins, recents: state.recents, repositories: WorktreeRepositories.among(state.pins + state.recents, facts: facts))
    }
}
