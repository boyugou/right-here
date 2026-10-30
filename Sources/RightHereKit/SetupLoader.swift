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
    /// What the login shell said of the agents' commands when the checks ran; `nil` before a read of them.
    public var agentCommands: LoginShellFacts?
    /// The language the config names (`general.language`); `nil` follows the system.
    public var language: String?
    /// The copies of the app in the Applications folders, newest first (`AppCopies.installed`); `nil` when they were not looked at.
    public var installedCopies: [AppCopy]?
    /// The Finder menu for a folder, built the way the Finder extension builds it; empty when the config has errors.
    public var menu: [MenuNode]
    /// The same menu as rows to edit, and what can be added to it; `nil` when the config has errors or there is none (an edit needs a text that reads).
    public var menuEditor: MenuEditorState?
    /// The file an edit of the menu goes to: the machine's own when it lists the menu, else the shared one.
    public var menuTarget: ConfigTarget
    /// The terminal, the editor, the agents and the permission prompts as settings to edit; `nil` when the config has errors or there is none.
    public var general: GeneralSettingsState?
    /// The file an edit of the agents goes to: the machine's own when it lists them, else the shared one.
    public var agentsTarget: ConfigTarget
    /// Each agent's own options (`general.agents` in the same order), to edit; empty when `general` is `nil`.
    public var agentOptions: [AgentOptionsState]
    /// The prompt presets as lines to edit; `nil` when the config has errors or there is none.
    public var presets: PresetsState?
    /// The "New File" templates as lines to edit; `nil` when the config has errors or there is none.
    public var newFile: NewFileState?
    /// The forms of Copy Path and the Quick Actions as lists to edit; `nil` when the config has errors or there is none.
    public var copyPath: CopyPathState?
    public var quickActions: QuickActionsState?
    /// The apps the config adds as lines to edit; `nil` when the config has errors or there is none.
    public var apps: AppsState?
    /// The changes an AI assistant proposed that wait for the person (`ConfigService.submit`).
    public var proposals: [ConfigProposal]
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
    /// When the config was read. A read of the whole state takes seconds (the doctor starts the login shell), and a change of the config made meanwhile is newer than
    /// what this says of it.
    public var readAt: ContinuousClock.Instant

    public init(checks: [DoctorCheck] = [], menu: [MenuNode] = [], menuEditor: MenuEditorState? = nil, menuTarget: ConfigTarget = .shared, general: GeneralSettingsState? = nil, agentsTarget: ConfigTarget = .shared,
                agentOptions: [AgentOptionsState] = [], presets: PresetsState? = nil, newFile: NewFileState? = nil, copyPath: CopyPathState? = nil, quickActions: QuickActionsState? = nil, apps: AppsState? = nil, proposals: [ConfigProposal] = [], folders: FolderSnapshot = FolderSnapshot(),
                configFile: URL, configExists: Bool = true, offer: SetupOffer? = nil, configProblems: [ConfigDiagnostic] = [], mcpCommand: String = AppIdentity.cliName, home: URL, readAt: ContinuousClock.Instant = .now,
                agentCommands: LoginShellFacts? = nil, language: String? = nil, installedCopies: [AppCopy]? = nil) {
        self.checks = checks
        self.agentCommands = agentCommands
        self.language = language
        self.installedCopies = installedCopies
        self.menu = menu
        self.menuEditor = menuEditor
        self.menuTarget = menuTarget
        self.general = general
        self.agentsTarget = agentsTarget
        self.agentOptions = agentOptions
        self.presets = presets
        self.newFile = newFile
        self.copyPath = copyPath
        self.quickActions = quickActions
        self.apps = apps
        self.proposals = proposals
        self.folders = folders
        self.configFile = configFile
        self.configExists = configExists
        self.offer = offer
        self.configProblems = configProblems
        self.mcpCommand = mcpCommand
        self.home = home
        self.readAt = readAt
    }

    public var configHasErrors: Bool {
        configProblems.contains { $0.severity == .error }
    }
}

/// The parts of the state that come from the config alone: what the editors redraw after a change, without asking the doctor (which starts the login shell).
public struct MenuSnapshot: Sendable, Equatable {
    public var menu: [MenuNode]
    public var editor: MenuEditorState?
    public var target: ConfigTarget
    public var general: GeneralSettingsState?
    public var agentsTarget: ConfigTarget
    public var agentOptions: [AgentOptionsState]
    public var presets: PresetsState?
    public var newFile: NewFileState?
    public var copyPath: CopyPathState?
    public var quickActions: QuickActionsState?
    public var apps: AppsState?
    public var problems: [ConfigDiagnostic]
    public var language: String?
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
    /// The language of what the window shows of the menu; `nil`: the config's (`Config.localizer`).
    private let localizer: Localizer?
    private let separators: Bool

    /// - Parameters:
    ///   - helperPath: The `rh` that ships in the app, which the runner script of an install should point at.
    ///   - finderShowsSeparators: Whether Finder draws the separators of the menu (`FinderMenuPresentation`); the preview shows what Finder shows.
    public init(facts: any SystemFacts = LiveSystemFacts(), paths: RHPaths? = nil, runner: any ProcessRunner = LiveProcessRunner(),
                helperPath: String?, localizer: Localizer? = nil, finderShowsSeparators: Bool = FinderMenuPresentation.showsSeparators()) {
        self.separators = finderShowsSeparators
        self.facts = facts
        self.paths = paths ?? RHPaths.current(facts: facts)
        self.runner = runner
        self.helperPath = helperPath
        self.localizer = localizer
    }

    /// - Parameter examined: The doctor's checks and what its login shell said, when the caller has them, made after everything this read could see changed (the
    ///   ones a repair ran at its end): the doctor, which starts the login shell and takes seconds, is not run again.
    public func load(reusing examined: (checks: [DoctorCheck], shell: LoginShellFacts)? = nil) async -> SetupSnapshot {
        let readAt = ContinuousClock.now
        let loaded = ConfigStore.load(paths: paths, withOrigins: true)
        // Without a config the window is on its first run and offers what is installed; the login shell is asked once, for that.
        let configExists = loaded.hasConfig
        let offer = configExists ? nil : await SetupOffer.make(facts: facts, runner: runner)
        let doctor: (checks: [DoctorCheck], shell: LoginShellFacts)
        if let examined { doctor = examined } else { doctor = await Doctor(facts: facts, paths: paths, loaded: loaded, runner: runner, rhPath: helperPath)
            .examine(everyAgent: configExists, language: (localizer ?? loaded.config.localizer).resolvedLanguage) }
        let checks = doctor.checks
        let shown = menuSnapshot(loaded)
        return SetupSnapshot(
            checks: checks, menu: shown.menu, menuEditor: shown.editor, menuTarget: shown.target, general: shown.general, agentsTarget: shown.agentsTarget, agentOptions: shown.agentOptions, presets: shown.presets, newFile: shown.newFile,
            copyPath: shown.copyPath, quickActions: shown.quickActions, apps: shown.apps, proposals: ConfigService(paths: paths).pending(), folders: await folders(),
            configFile: loaded.file, configExists: configExists, offer: offer,
            configProblems: loaded.result.diagnostics,
            mcpCommand: SetupSnippets.mcpCommand(home: facts.homeDirectory, helperPath: helperPath), home: facts.homeDirectory, readAt: readAt,
            agentCommands: doctor.shell, language: loaded.config.language,
            installedCopies: AppCopies.installed(facts.applicationCopies(bundleID: AppIdentity.hostBundleID), home: facts.homeDirectory.path))
    }

    /// The Quick Actions check as the config says it now, without the rest of the doctor (which starts the login shell).
    public func servicesCheck() async -> DoctorCheck {
        Doctor(facts: facts, paths: paths, loaded: ConfigStore.load(paths: paths), runner: runner, rhPath: helperPath).servicesCheck()
    }

    /// The menu, the editors and the config's problems as the config says them now, read without the doctor.
    public func menu() async -> MenuSnapshot {
        menuSnapshot(ConfigStore.load(paths: paths, withOrigins: true))
    }

    private func menuSnapshot(_ loaded: LoadedConfig) -> MenuSnapshot {
        let localizer = self.localizer ?? loaded.config.localizer
        let menu = MenuPreview.folderMenu(loaded.result, facts: facts, folder: facts.homeDirectory, localizer: localizer, separators: separators)
        // A text that does not read cannot be edited, and a config that is not there is made by the setup, not by an edit.
        let editable = !loaded.result.hasErrors && loaded.fileExists
        let service = ConfigService(paths: paths)
        let editor = editable ? MenuEditor.state(config: loaded.config, facts: facts, localizer: localizer, folder: facts.homeDirectory, inFile: service.listed(MenuEditorState.key)) : nil
        let general = editable ? GeneralSettings.state(config: loaded.config, facts: facts, listedAgents: service.listed(GeneralSettingsState.agentsKey)) : nil
        let options = general?.agents.compactMap { agent -> AgentOptionsState? in
            let entries = service.entryLocations(of: AgentVariants.table(of: agent.id), in: loaded.result)
            return AgentOptions.state(id: agent.id, config: loaded.config, facts: facts, listedArgs: service.listed(AgentOptions.argumentsKey(of: agent.id)), variantEntries: entries,
                                      listedVariantArguments: service.variantArguments(of: agent.id, entries: entries))
        } ?? []
        let presets = editable ? PresetOptions.state(config: loaded.config, entries: service.presetEntries(in: loaded.result), written: Set((loaded.result.entryOrigins["preset"] ?? []).compactMap(\.id)),
                                                        hiddenInShared: service.hiddenEntryIDs(of: "preset", in: .shared, loaded: loaded.result), localizer: localizer) : nil
        let newFile = editable ? NewFileOptions.state(config: loaded.config, entries: service.entryLocations(of: "new_file.template", in: loaded.result), facts: facts, localizer: localizer,
                                                                        sharedDefinesTemplates: ConfigStore.sharedConfig(paths: paths).newFile.definesTemplates) : nil
        let copyPath = editable ? CopyPathOptions.state(config: loaded.config, localizer: localizer, listed: service.listed(CopyPathOptions.stylesKey)) : nil
        let quickActions = editable ? QuickActionsOptions.state(config: loaded.config, facts: facts, localizer: localizer, listed: service.listed(QuickActionsOptions.key),
                                                                sharedDefaults: ActionRegistry.defaultServiceItems(enabledAgents: ConfigStore.sharedConfig(paths: paths).enabledAgents)) : nil
        let apps = editable ? AppOptions.state(config: loaded.config, entries: service.entryLocations(of: "app", in: loaded.result), facts: facts) : nil
        return MenuSnapshot(menu: menu, editor: editor, target: service.owner(of: MenuEditorState.key), general: general,
                            agentsTarget: service.owner(of: GeneralSettingsState.agentsKey), agentOptions: options, presets: presets, newFile: newFile, copyPath: copyPath, quickActions: quickActions, apps: apps, problems: loaded.result.diagnostics,
                            language: loaded.config.language)
    }

    /// The folders Right Here remembers, as they are on disk now.
    public func folders() async -> FolderSnapshot {
        let state = StateStore.load(paths: paths)
        return FolderSnapshot(pins: state.pins, recents: state.recents, repositories: WorktreeRepositories.among(state.pins + state.recents, facts: facts))
    }
}
