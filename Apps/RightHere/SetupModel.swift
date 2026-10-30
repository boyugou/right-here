import AppKit
import FinderSync
import Observation
import RightHereCore
import RightHereKit

/// Why a change made in one of the editors was refused (the list had been changed by something else, the config has an error), said on the page where it was made.
struct EditRefusal: Equatable, Sendable {
    var notice: SetupNotice
    var tab: SetupTab
    /// The setting that was being changed, so that a page with two editors says it where the change was made.
    var key: String
}

/// What the last change made in one of the editors did, so that the window can say it and take it back.
struct ConfigEdit: Equatable, Sendable {
    var message: LocalizedMessage
    /// The setting that decided which file the change went to; taking it back is asked of that file.
    var key: String
    /// The page it was made on, which is where it is said.
    var tab: SetupTab
    /// The digest of the text the change wrote: Undo takes back this change and no other.
    var digest: String?
    /// The digest of the text it replaced: a file that someone else changed and changed back to `digest` is not this change's.
    var beforeDigest: String?
    /// The file the change was made in. Undo goes to that file: the file that decides the setting may be another one by then (a change that took the setting out of this Mac's own file).
    var target: ConfigTarget = .shared
    /// What the config says is wrong now that was not before the change, in the config's own words (an item of the menu that names an agent that was taken out).
    var warnings: [String] = []
}

/// A change that would make agents start without their permission prompts, held until the person says yes (`SetupModel.edit`): the window is the person and nothing stops it, but it does
/// not take the yes for granted, whichever control the change comes from.
struct PendingLoosening: Equatable, Sendable {
    /// The proposal of an assistant whose Apply is held (`operations` are then none); `nil` for a change of the window.
    var proposal: String? = nil
    var operations: [ConfigOperation]
    var key: String
    var anchor: String?
    var target: ConfigTarget?
    var message: LocalizedMessage
    var tab: SetupTab
    /// The agents it would start without asking, with the flag each gets.
    var agents: [PromptEffects.Entry]
}

/// The checks of the text in the Config editor, kept for the text they were made for: the page asks for them twice for each keystroke (the problems and the Save button), and
/// on a large config each asking is a parse of the whole text.
@MainActor
final class DraftChecks {
    private var text: String?
    private var digest: String?
    private var found: [ConfigDiagnostic] = []

    func problems(of draft: String, digest fileDigest: String, with validation: ConfigDocument.Validation) -> [ConfigDiagnostic] {
        if text == draft, digest == fileDigest { return found }
        found = validation.problems(draft)
        text = draft
        digest = fileDigest
        return found
    }
}

/// What the setup window shows and does. The reads, the actions and the git work are asked of RightHereKit, which runs them off
/// the main actor; this class keeps the answers and asks again when it has to. A refresh that is asked for while one runs joins
/// it (RefreshLoop), so the answers arrive in the order they were asked for, and a poll never overwrites a newer answer.
@MainActor
@Observable
final class SetupModel {
    var selectedTab: SetupTab = .overview

    private(set) var snapshot: SetupSnapshot?
    private(set) var checks: [DoctorCheck] = []
    private(set) var folders = FolderSnapshot()
    private(set) var isRefreshing = false
    /// An install, a repair, a launch test or a change to the folders is running: the buttons that would start another are off.
    private(set) var isWorking = false
    /// What is running is a change of the config (`edit`, `undoEdit`) and not an install or a launch test: the fields of a page may stay on, since the change is short and the person may be on
    /// the next field already, which a field that goes off would take the focus from.
    private(set) var isEditingConfig = false
    private(set) var isTestingLaunch = false
    /// What happened last: a confirmation, or why an action did not work. The next action replaces it.
    private(set) var notice: SetupNotice?
    private(set) var worktrees: WorktreeListing = .idle
    /// The repository the worktrees tab lists when the person chose one; otherwise the first repository of the folders.
    private(set) var chosenRepository: URL?
    /// The submenus of the Finder menu that are open, by `MenuPreviewRow.id`.
    private(set) var openSubmenus: Set<String> = []
    /// The menu page shows rows to drag, remove and add to instead of the preview.
    private(set) var isEditingMenu = false
    /// The agent whose own options the Agents page shows in place of the list; `nil` is the list.
    private(set) var agentDetail: String?
    /// The prompt preset that the Agents page shows in place of the list; `nil` is the list.
    private(set) var presetDetail: String?
    /// The new-file template that the Finder menu page shows in place of the menu; `nil` is the menu.
    private(set) var templateDetail: String?
    /// The start option of an agent whose page is open in place of the page of its agent.
    private(set) var variantDetail: VariantRef?
    /// The app of the config whose page the Overview shows in place of itself; `nil` is the Overview.
    private(set) var appDetail: String?
    /// A change waits for the person's yes because it would make agents start without their permission prompts.
    private(set) var pendingLoosening: PendingLoosening?
    /// Counts the answers to a held change: a no, and a yes that was made. The field that raised the question takes its text from the config when this changes (`FieldDraft.answered`): what was
    /// typed is not what the file says after a no, and after a yes it would ask the same question again, or add the same argument a second time, when the field is left or the page is.
    private(set) var fieldAnswerToken = 0
    /// What VoiceOver was last told by a change, announced or not; a test reads it, as there is no VoiceOver to listen.
    private(set) var lastAnnouncement: String?
    /// What the last change in an editor did; it stays, with a button that takes it back, until the next change or until the page is left.
    private(set) var configEdit: ConfigEdit?
    /// Why the last change in an editor was refused; it stays until the next change or until the page is left.
    private(set) var editRefusal: EditRefusal?
    /// The row (from 1) that is being dragged, in whichever list is edited, and the text the drag carries: only a drop of that text moves anything. A drag that was cancelled leaves
    /// this behind, and text dropped from another app then is not what it holds.
    @ObservationIgnored private(set) var drag: (row: Int, token: String, scope: String)?
    /// When the config was last changed through the window, which a read that began before it knows nothing of.
    @ObservationIgnored private var editedAt: ContinuousClock.Instant?
    /// What the checks of the draft said about a text, so that the page that asks twice for each keystroke does not run them twice.
    @ObservationIgnored private let draftChecks = DraftChecks()
    /// What the Config page shows for the file it is on; `nil` until it has been read.
    private(set) var configPage: ConfigPageState?
    /// The file the Config page is on: the shared one, or this Mac's own.
    private(set) var configTarget: ConfigTarget = .shared
    /// The text in the Config page's editor: what the person typed, or the file's text until they type.
    var draftText = ""
    /// What a person with no config file can choose from, and what they have chosen so far. The choices start from what the Mac
    /// has (`SetupOffer.detected`) once, and are the person's from then on: a refresh does not put them back.
    private(set) var offer: SetupOffer?
    var selectedTerminal: String?
    var selectedEditor: String?
    var selectedAgents: Set<String> = []
    /// Setting up (the first-run button) is running.
    private(set) var isSettingUp = false
    /// What a setup or a repair that is running does now; `nil` when none runs. It takes seconds, and a button that only greys out for that long looks stuck.
    private(set) var setupPhase: SetupPhase?
    /// Install or Repair runs: its button shows a spinner from the press to the end, also before the first phase is said.
    private(set) var isRepairing = false
    /// A newer copy of the app that is installed while this older one runs: the window says so before anything else, since nothing this copy shows is what the person
    /// has (a person opened 0.3.2 from `~/Applications` and looked for what 0.3.7 in `/Applications` added). `nil` when this is the newest.
    private(set) var newerCopy: AppCopy?
    /// Whether this copy may set Right Here up: not from a disk image or a download (`locationProblem`), and not while a newer copy is installed. An older
    /// copy would point the runner script, the Quick Actions and the Finder extension at itself, and every click would run the old `rh`: a person who
    /// opened an old copy by mistake and pressed Install or Repair did that.
    var canSetUp: Bool { locationProblem == nil && newerCopy == nil }

    /// Whether a check's fix is what Install or Repair does: then its button is the window's main one, and otherwise an ordinary one, so that it does not
    /// compete with the step that is next (switching on the Finder extension is in System Settings, which Install or Repair does not do).
    var repairIsWanted: Bool {
        !needsFirstRunChoice && checks.contains { $0.fix.flatMap { SetupFixAction(fix: $0, firstRun: false) } == .repair }
    }
    /// The installed copies of the app other than the newest, which the check of the copies says to move to the Trash.
    private(set) var otherCopies: [AppCopy] = []

    /// This copy, the one that runs.
    private(set) var runningCopy: AppCopy
    /// How the last Install or Repair came out, said under the header of whichever page it was pressed on. It goes when the page is left or something else is said.
    private(set) var repairOutcome: SetupNotice?
    /// What the last setup did, for the list "What Right Here set up".
    private(set) var setupReport: SetupReport?
    /// How many times a setup or a repair has come back with an answer: the page scrolls to the answer when this changes.
    private(set) var setupAttempt = 0
    @ObservationIgnored private var choicesSeeded = false
    /// The answer of the last launch test: it is kept through refreshes, which read the checks and do not run the probe.
    @ObservationIgnored private var launchResult: DoctorCheck?
    /// Each listing of the worktrees gets a number; only the newest one is shown, so a listing that ends late cannot overwrite it.
    @ObservationIgnored private var worktreeRequest = 0

    private let loader: SetupLoader
    let actions: SetupActions
    private let browser = WorktreeBrowser()
    private let home: URL
    private let pollInterval: Duration
    private let idleInterval: Duration
    private let windowIsVisible: @MainActor () -> Bool
    private let activationQuietPeriod: Duration
    /// How long a change waits for the change that is being written before it is refused (`settled()`).
    let patience: Duration
    /// How long the window's change waits for the one that is being written: a write of the config, with its lock and its history, takes a moment on a busy Mac, and a click
    /// that came during it would be refused for nothing.
    static let defaultPatience: Duration = .seconds(2)
    /// When the state was last read; coming back to the app does not read it again within `activationQuietPeriod`.
    @ObservationIgnored private var lastRead: ContinuousClock.Instant?
    @ObservationIgnored private var icons: IconProvider
    @ObservationIgnored private var loop: RefreshLoop<SetupSnapshot>?

    /// The `rh` that ships inside this app.
    private static let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/rh").path

    /// - Parameters:
    ///   - helper: The `rh` inside the app, which tells where the app runs from (`InstallError.problem(runningFrom:)`).
    ///   - pollInterval: How often the Finder extension is looked at while it is not switched on.
    ///   - idleInterval: How often it is looked at once it is on.
    ///   - windowIsVisible: Whether the window can be seen; the look is skipped while it cannot.
    /// Everything it asks of the Mac comes through these, so that a test gives it a temporary home, a made-up Mac and a runner that answers as scripted.
    ///   - activationQuietPeriod: Coming back to the app reads the state again only when it was last read longer ago than this: each read starts the person's login
    ///     shell, which runs their startup files, and a person who switches between windows must not have those run at every switch.
    ///   - patience: How long a change waits for the one that is being written before it is refused and says so.
    init(loader: SetupLoader, actions: SetupActions, facts: any SystemFacts, helper: String, pollInterval: Duration = .seconds(2), idleInterval: Duration = .seconds(30),
         activationQuietPeriod: Duration = .seconds(20), patience: Duration = SetupModel.defaultPatience, windowIsVisible: @escaping @MainActor () -> Bool = SetupModel.liveWindowIsVisible) {
        self.loader = loader
        self.actions = actions
        icons = IconProvider(facts: facts)
        home = facts.homeDirectory
        locationProblem = InstallError.problem(runningFrom: helper)
        // The helper is Right Here.app/Contents/Helpers/rh.
        let app = URL(fileURLWithPath: helper).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let running = AppCopy(path: app.path, version: AppIdentity.version)
        runningCopy = running
        self.pollInterval = pollInterval
        self.idleInterval = idleInterval
        self.activationQuietPeriod = activationQuietPeriod
        self.patience = patience
        self.windowIsVisible = windowIsVisible
        take(installedCopies: AppCopies.installed(facts.applicationCopies(bundleID: AppIdentity.hostBundleID), home: facts.homeDirectory.path))
    }

    /// Which copy of the app is the one to keep, from the copies a read found: a person trashes or installs one while the window is open (it is what the
    /// window asks them to do), and a window that looked only when it opened stayed blocked, or showed a copy that is gone.
    private func take(installedCopies installed: [AppCopy]) {
        newerCopy = AppCopies.toKeep(instead: runningCopy, among: installed)
        otherCopies = Array(installed.dropFirst())
    }

    /// The window of the app: this Mac, and the `rh` that ships inside the app.
    convenience init() {
        let facts = LiveSystemFacts()
        self.init(loader: SetupLoader(facts: facts, runner: LiveProcessRunner(), helperPath: Self.helper),
                  actions: SetupActions(facts: facts, runner: LiveProcessRunner(), helperPath: Self.helper, app: Bundle.main.bundleURL),
                  facts: facts, helper: Self.helper)
    }

    /// The checks as a summary: whether anything is known yet, what is open, whether the first-run card is due.
    var summary: SetupSummary { SetupSummary(checks: checks) }

    /// There is no config file yet, so the window offers the choice of terminal, editor and agents before anything is written. False
    /// while nothing is known: a window that has not looked yet must not claim a first run.
    var needsFirstRunChoice: Bool { snapshot.map { !$0.configExists } ?? false }

    /// Why the app cannot set anything up from where it runs (a disk image, another volume, the temporary copy macOS makes of a downloaded
    /// app), or `nil`. Said on the first page before anything is tried; what a setup writes would point into a folder that goes away.
    private(set) var locationProblem: InstallError?

    /// The first look has ended and found a config file: what Install or Repair and Open Config act on. Before that the window does not know
    /// whether this is a first run (the look starts the login shell, which takes seconds), and on a first run the config is made from the
    /// person's choices, not from what was found.
    var configIsThere: Bool { snapshot?.configExists ?? false }

    func check(_ id: CheckID) -> DoctorCheck? {
        checks.first { $0.id == id }
    }

    /// The lines of the Finder menu preview that can be seen now.
    var menuRows: [MenuPreviewRow] {
        MenuPreview.rows(snapshot?.menu ?? [], expanded: openSubmenus)
    }

    /// The menu as rows to edit, and what can be added to it; `nil` while the config cannot be edited (it has an error, or there is none).
    var menuEditor: MenuEditorState? { snapshot?.menuEditor }

    /// This Mac's own config file lists the menu, so a change is made there and not in the shared one.
    var menuIsMachineOwn: Bool { snapshot?.menuTarget == .local }

    /// The terminal, the editor, the agents and the permission prompts as settings to change; `nil` while the config cannot be edited (it has an error, or there is none).
    var general: GeneralSettingsState? { snapshot?.general }

    /// This Mac's own config file lists the agents, so a change is made there and not in the shared one.
    var agentsAreMachineOwn: Bool { snapshot?.agentsTarget == .local }

    /// The home folder the paths of the window are written from `~` against: the snapshot's, which is the demo's in a preview.
    var homePath: String { snapshot?.home.path ?? home.path }

    /// The language the window is written in: the one the config names (`general.language`), or the system's.
    var localizer: Localizer { .preferring(snapshot?.language) }

    /// The program an MCP client starts (`SetupSnippets.mcpCommand`).
    var mcpCommand: String { snapshot?.mcpCommand ?? AppIdentity.cliName }

    /// The repository the worktrees tab lists now, if there is one.
    var repository: URL? { chosenRepository ?? folders.repositories.first }

    var repositories: [URL] { folders.repositories }

    /// The icon of a line of the window's lists. A new file's line has the New File glyph, as the lines around it have glyphs and apps' icons: the file type's
    /// own icon, a white page, drew as a faint sliver there (a design review of 0.3.21). The Finder menu's picture keeps the file type's icon, as Finder shows it.
    nonisolated static func listIcon(_ icon: Icon?) -> Icon? {
        guard let icon, icon.kind == .fileType else { return icon }
        return .symbol("doc.badge.plus")
    }

    func listImage(for icon: Icon?) -> NSImage? { image(for: Self.listIcon(icon)) }

    #if PREVIEW
    /// What a picture for the website draws in place of an app's or a document's own icon (`preview_setup.sh` sets it for its canned data).
    nonisolated(unsafe) static var drawIcon: ((Icon) -> NSImage?)?
    #endif

    func image(for icon: Icon?) -> NSImage? {
        #if PREVIEW
        if let icon, let drawn = Self.drawIcon?(icon) { return drawn }
        #endif
        let image = icons.image(for: icon)
        #if PREVIEW
        return image.map(Self.drawnInTheRenderer)
        #else
        return image
        #endif
    }

    func toggleSubmenu(_ id: String) {
        if !openSubmenus.insert(id).inserted { openSubmenus.remove(id) }
    }

    func select(_ tab: SetupTab) {
        if tab != selectedTab, configEdit?.tab != tab { configEdit = nil }
        if tab != selectedTab {
            editRefusal = nil
            repairOutcome = nil
            // "Copied" belongs to the button of the AI Assistants page it is under; it is not news on the next page.
            if [.promptCopied, .mcpConfigurationCopied, .pluginCommandsCopied].contains(notice) { notice = nil }
            agentDetail = nil
            presetDetail = nil
            templateDetail = nil
            variantDetail = nil
            appDetail = nil
        }
        selectedTab = tab
        if tab == .worktrees { Task { await refreshWorktrees() } }
        if tab == .config { Task { await openConfigPage(keepingDraft: true) } }
    }

    /// What a sidebar row shows beside its title: the checks that need attention, and for Config the changes an AI assistant proposed that wait for the person.
    func badge(for tab: SetupTab) -> SetupBadge? {
        // Before the first setup the checks find what setting up makes; a badge would say something is wrong with what the person has not made yet.
        if needsFirstRunChoice { return nil }
        if tab == .config, let waiting = snapshot?.proposals.count, waiting > 0 { return .attention(waiting) }
        return summary.badge(for: tab)
    }

    /// Changes proposed by an AI assistant that wait for the person.
    var proposalsWaiting: Int { snapshot?.proposals.count ?? 0 }

    /// Reads the whole state again. A call while a read runs waits for it and is answered by one read after it.
    func refresh() async {
        #if PREVIEW
        if simulated { return }
        #endif
        await refreshLoop().refresh()
    }

    /// Whether the window can be seen: not minimized, hidden or covered. A window beside System Settings is on screen while the app is not the active one,
    /// which is where the person is when they switch the extension on.
    static func liveWindowIsVisible() -> Bool {
        NSApplication.shared.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) }
    }

    /// Reads the state again when the app comes to the front: the person may be back from System Settings, from the editor of the config or from a
    /// terminal where an AI assistant ran `rh setup`, and what the window shows is old. Not while the first look runs, or while something the
    /// person started does; each ends with a read of its own.
    func refreshOnActivation() async {
        guard snapshot != nil, !isWorking, !isRefreshing else { return }
        if let lastRead, ContinuousClock.now - lastRead < activationQuietPeriod { return }
        await refresh()
    }

    /// Looks at the Finder extension for as long as the window is there: every two seconds while it is not switched on, so that the first-run card turns into the
    /// status by itself once the person flips the switch in System Settings, and every half minute once it is on, so that switching it off again (or a repair that
    /// macOS did not keep) is noticed. A look is one `pluginkit` call, not the whole doctor; when the extension has just come on, one full refresh follows. It skips
    /// a look while the window cannot be seen, and while work the person started runs. It ends when the window is closed (the task is cancelled).
    func watchExtension() async {
        while !Task.isCancelled {
            let waiting = summary.extensionNeedsSetup
            try? await Task.sleep(for: waiting ? pollInterval : idleInterval)
            #if PREVIEW
            if simulated { return }
            #endif
            guard !Task.isCancelled, !isWorking, !isRefreshing, windowIsVisible() else { continue }
            // Before the first look has ended nothing is known, and the first look reads the extension itself.
            guard snapshot != nil else { continue }
            let check = await actions.extensionCheck()
            // A refresh that is running, or that the person started meanwhile, has a newer look at the extension than this one.
            guard !Task.isCancelled, !isWorking, !isRefreshing else { continue }
            checks = checks.replacing(check)
            if waiting, check.status == .ok { await refresh() }
        }
    }

    /// Sets Right Here up as `rh setup` does, with what the person chose: the config file (made from the choices, only because there is
    /// none), the runner script, the command link, the Quick Actions and the Finder extension's registration. The same code as the
    /// command line, called here. Then the state is read again, and the first-run card waits for the extension to be switched on.
    func setUp() async {
        guard !isWorking, canSetUp, let offer else { return }
        isWorking = true
        isSettingUp = true
        say(nil)
        let result = await actions.setUp(offer.choices(terminal: selectedTerminal, editor: selectedEditor, agents: selectedAgents), progress: phaseReporter)
        setupPhase = nil
        setupReport = result.report
        setupAttempt += 1
        say(result.notice)
        isSettingUp = false
        // Still working while the state is read again: the chooser is drawn until that read says there is a config, and its button must not
        // start the whole setup a second time.
        await refresh(after: result.report)
        isWorking = false
        announceState(unless: result.notice)
    }

    /// Hands each phase of a setup to the window, on the main actor.
    private var phaseReporter: @Sendable (SetupPhase) async -> Void {
        { [weak self] phase in await MainActor.run { self?.setupPhase = phase } }
    }

    /// Reads the state again after a setup or a repair. The checks the setup ran at its end were made after everything it changed, so they are shown and
    /// not run again: the doctor starts the login shell and takes seconds, which the person would wait through twice.
    private func refresh(after report: SetupReport?) async {
        // A trial leaves the Finder extension's row out of its checks (`SetupRunner`); the window's own read has it.
        guard let checks = report?.checks, let shell = report?.shell, checks.contains(where: { $0.id == .finderExtension }) else { return await refresh() }
        #if PREVIEW
        if simulated { return }
        #endif
        await refreshLoop().refresh(using: { [loader] in await loader.load(reusing: (checks, shell)) })
    }

    /// Install or Repair: the same setup without choices, for a Mac that has a config. It makes what is missing, changes what is out of
    /// date and leaves the config alone.
    func repair() async {
        guard !isWorking, canSetUp else { return }
        isWorking = true
        isRepairing = true
        defer { isRepairing = false }
        say(nil)
        repairOutcome = nil
        let pressedOn = selectedTab
        let result = await actions.repair(progress: phaseReporter)
        setupPhase = .checkup
        setupReport = result.report ?? setupReport
        setupAttempt += 1
        await refresh(after: result.report)
        setupPhase = nil
        isWorking = false
        // A check that still asks for Install or Repair after one ran is one it cannot put right (a copy of the app that macOS registers again, say):
        // said by name, since the button stays the window's main one and a press that changed nothing looked like a press that did nothing.
        let left = checks.filter { $0.fix.flatMap { SetupFixAction(fix: $0, firstRun: false) } == .repair }.map { $0.title(in: localizer) }
        let outcome = result.notice ?? (left.isEmpty ? result.report.map { .repaired(changed: Self.changedPieces($0).count) } : .repairLeft(left))
        // Why it failed stays in the sidebar, as every action's notice does, also after the page is left; the line under the header is for the page the button
        // was pressed on, and a person who went to another page meanwhile does not get it there.
        notice = result.notice
        if selectedTab == pressedOn { repairOutcome = outcome }
        if let outcome {
            let state = outcome.isProblem || summary.state == .checking ? nil : localizer.string(summary.state.titleKey)
            announce([localizer.render(outcome.message), state].compactMap(\.self).joined(separator: " "))
        }
    }

    /// The parts that a setup made or changed, in its order.
    static func changedPieces(_ report: SetupReport) -> [SetupStep] {
        report.steps.filter { $0.outcome == .created || $0.outcome == .updated }
    }

    /// Has the Finder extension start a throwaway terminal session that runs a typed command, the way a menu click starts an
    /// agent, and puts the answer in the list of checks. A window opens and closes; the first time, macOS asks whether Right Here
    /// may control the terminal. Only that one check is asked again, not the whole doctor.
    func testLaunch() async {
        guard !isWorking, !isRefreshing else { return }
        isWorking = true
        isTestingLaunch = true
        say(nil)
        let check = await actions.launchCheck()
        launchResult = check
        checks = checks.replacingOrAppending(check)
        isTestingLaunch = false
        isWorking = false
        if let detail = check.detail { announce(localizer.render(detail)) }
    }

    /// Opens the config file. It does not make one: a Mac without a config chooses first.
    func openConfig() async {
        guard !isWorking else { return }
        isWorking = true
        say(await actions.openConfig())
        isWorking = false
    }

    // MARK: The Config page

    /// The text the file has and the draft differ: there is something to save, and something that a change of file or a reload would throw away.
    var textHasChanges: Bool {
        guard let text = configPage?.text else { return false }
        return draftText != text.text
    }

    /// What the config says about the text in the editor, as it is typed: errors and warnings, each with its line.
    var draftProblems: [ConfigDiagnostic] {
        guard let validation = configPage?.validation else { return [] }
        return draftChecks.problems(of: draftText, digest: configPage?.text?.digest ?? "", with: validation)
    }

    /// Reads the page: the file's text, the proposals that wait and the changes that can be taken back. A draft the person has typed is kept when `keepingDraft`.
    func openConfigPage(keepingDraft: Bool = false) async {
        #if PREVIEW
        if simulated { return }
        #endif
        let target = configTarget
        var page = await actions.configPage(target: target)
        guard target == configTarget else { return }
        if keepingDraft, textHasChanges, let started = configPage?.text, let now = page.text {
            // The draft started from `started`, and a save is held to that text: a file that something else changed since is not thrown away by a save, and the page says so.
            page.fileMovedUnderDraft = now.digest != started.digest
            page.text = started
        } else if !(keepingDraft && textHasChanges) {
            draftText = page.text?.text ?? ""
        }
        configPage = page
        if var current = snapshot, current.proposals != page.proposals.map(\.proposal) {
            current.proposals = page.proposals.map(\.proposal)
            snapshot = current
        }
    }

    /// Switches between the shared file and this Mac's own. Not while the text has changes: the person saves or reverts first, so that nothing they typed is lost.
    func chooseConfigFile(_ target: ConfigTarget) async {
        guard target != configTarget, !textHasChanges, !isWorking else { return }
        configTarget = target
        configPage = nil
        await openConfigPage()
    }

    /// Saves the text, when the file is still what it was when the page read it; a text that does not read, or a file that was changed meanwhile, is said and the draft stays.
    func saveConfigText() async {
        guard !isWorking, let text = configPage?.text, textHasChanges else { return }
        isWorking = true
        let result = await actions.saveConfigText(draftText, target: configTarget, unchangedSince: text.digest)
        if let change = result.change {
            configEdit = nil
            say(nil)
            if change.changed { announce(localizer.string(.appConfigSaved)) }
        } else {
            say(result.notice)
        }
        await openConfigPage(keepingDraft: result.change == nil)
        await refreshEditable()
        isWorking = false
    }

    /// Throws the changes in the editor away and reads the file again.
    func revertConfigText() async {
        guard !isWorking else { return }
        await openConfigPage()
    }

    /// Takes back the last change of the file the page is on, whoever made it.
    func undoConfigChange() async {
        guard !isWorking else { return }
        isWorking = true
        let result = await actions.undoConfigEdit(target: configTarget)
        configEdit = nil
        say(result.notice)
        await openConfigPage(keepingDraft: textHasChanges)
        await refreshEditable()
        isWorking = false
    }

    /// Makes a change an assistant proposed, after the person has looked at it on the page. One that would make agents start without their permission prompts is held for the person's yes in the
    /// alert that every change of the window raises, naming each agent and its flag: the card said that it switches the prompts off, and what it comes to depends on what the files hold when Apply is pressed.
    func approveProposal(_ id: String, confirmed: Bool = false) async {
        guard !isWorking else { return }
        if !confirmed {
            let agents = await actions.looseningEffects(ofProposal: id)
            if !agents.isEmpty {
                pendingLoosening = PendingLoosening(proposal: id, operations: [], key: "", anchor: nil, target: nil, message: .appEditSaved, tab: .config, agents: agents)
                return
            }
        }
        isWorking = true
        let digest = configPage?.proposals.first { $0.id == id }?.digest
        let result = await actions.approveProposal(id, unchangedSince: digest)
        if result.change != nil { configEdit = nil }
        say(result.change == nil ? result.notice : nil)
        await openConfigPage(keepingDraft: textHasChanges)
        await refreshEditable()
        isWorking = false
    }

    func dismissProposal(_ id: String) async {
        guard !isWorking else { return }
        isWorking = true
        say(await actions.dismissProposal(id))
        await openConfigPage(keepingDraft: textHasChanges)
        // A read that began before the dismissal still counts the proposal: the editors are read again, which marks what is shown as newer than such a read.
        await refreshEditable()
        isWorking = false
    }

    // MARK: Editing the Finder menu

    func setEditingMenu(_ on: Bool) {
        isEditingMenu = on && menuEditor != nil
        // The note of a change of the menu goes; the note of a change of the other editors of the page (the New File templates, Copy Path, the Quick Actions), which is under them, stays.
        if let edit = configEdit, !(edit.tab == .menu && edit.key != MenuEditorState.key) { configEdit = nil }
        drag = nil
    }

    /// Says under the editor of a change that it was not made because the window stayed busy.
    func refuseBusy(on tab: SetupTab, key: String) {
        refuse(.busy, on: tab, key: key)
    }

    /// Says under an editor why something the person did there was not done, and in the corner of the sidebar as every notice is.
    func refuse(_ notice: SetupNotice, on tab: SetupTab, key: String) {
        editRefusal = EditRefusal(notice: notice, tab: tab, key: key)
        say(notice)
    }

    /// Takes away what an editor said about a refusal of its own (a new choice makes it old).
    func clearRefusal(key: String) {
        if editRefusal?.key == key { editRefusal = nil }
    }

    /// A row was picked up; `token` is what the drag carries, and what a drop has to carry for the row to move.
    func beginDrag(row: Int, token: String, scope: String) {
        drag = (row, token, scope)
    }

    /// The drag ends with a drop on the list `scope` that carries `token`: the row that was picked up, or `nil` when what was dropped is not what the window put in the drag, or was picked up in
    /// another list (a page has several, and a row of one is not a row of another). The drag is over either way.
    func endDrag(token: String?, scope: String) -> Int? {
        defer { drag = nil }
        guard let drag, drag.token == token, drag.scope == scope else { return nil }
        return drag.row
    }

    /// The rows at `source` (from 0) go before the row at `destination` (from 0, in the list as it is): what a drag in the list says. The other rows keep their order.
    func moveMenuRows(from source: IndexSet, to destination: Int) async {
        guard let editor = menuEditor, let first = source.min(), editor.rows.indices.contains(first) else { return }
        let title = title(of: editor.rows[first])
        await edit(MenuEditor.operations(moving: source, to: destination, in: editor), deciding: MenuEditorState.key, saying: .appMenuEditedMoved(title), on: .menu)
    }

    /// The row at `position` (from 1) one place up (`-1`) or down (`1`), for the keyboard and for VoiceOver, which do not drag.
    func moveMenuRow(_ position: Int, by offset: Int) async {
        guard let editor = menuEditor, editor.rows.indices.contains(position - 1) else { return }
        let target = position - 1 + offset
        guard editor.rows.indices.contains(target) else { return }
        await moveMenuRows(from: IndexSet(integer: position - 1), to: offset > 0 ? target + 1 : target)
    }

    func removeMenuRow(_ position: Int) async {
        guard let editor = menuEditor, editor.rows.indices.contains(position - 1) else { return }
        let title = title(of: editor.rows[position - 1])
        await edit(MenuEditor.operations(removing: position, in: editor), deciding: MenuEditorState.key, saying: .appMenuEditedRemoved(title), on: .menu)
    }

    /// Puts an item (a group, an action or `-`) in the menu: at the end, or at `position` (from 1).
    func addMenuItem(_ entry: String, at position: Int? = nil) async {
        guard let editor = menuEditor else { return }
        let named = editor.choices.first { $0.entry == entry }?.title
        await edit(MenuEditor.operations(adding: entry, at: position, in: editor), deciding: MenuEditorState.key, saying: .appMenuEditedAdded(named ?? separatorTitle(entry)), on: .menu)
    }

    /// A line of the menu as the person knows it: the entries it makes, or for a separator the word.
    private func title(of row: MenuEditorRow) -> String {
        let shown = row.nodes.filter { $0.kind != .separator }.map(\.title)
        return shown.isEmpty ? (row.isSeparator ? localizer.string(.appMenuSeparator) : row.fallbackTitle) : shown.joined(separator: ", ")
    }

    private func separatorTitle(_ entry: String) -> String {
        entry == "-" ? localizer.string(.appMenuSeparator) : entry
    }

    // MARK: Editing the agents and the general settings

    /// The agents in the menu, one place up or down; the same drag as the menu's.
    func moveAgents(from source: IndexSet, to destination: Int) async {
        guard let general, let first = source.min(), general.enabledAgents.indices.contains(first) else { return }
        await edit(GeneralSettings.operations(movingAgents: source, to: destination, in: general), deciding: GeneralSettingsState.agentsKey,
                   saying: .appMenuEditedMoved(general.enabledAgents[first].name), on: .agents)
    }

    /// The agent at `position` (from 1, among the ones in the menu) one place up (`-1`) or down (`1`), for the keyboard and for VoiceOver.
    func moveAgent(_ position: Int, by offset: Int) async {
        guard let general, general.enabledAgents.indices.contains(position - 1) else { return }
        let target = position - 1 + offset
        guard general.enabledAgents.indices.contains(target) else { return }
        await moveAgents(from: IndexSet(integer: position - 1), to: offset > 0 ? target + 1 : target)
    }

    /// Puts an agent in the menu, after the ones that are there, or takes it out.
    func setAgent(_ id: String, enabled: Bool) async {
        guard let general, let agent = general.agents.first(where: { $0.id == id }) else { return }
        let operations = enabled ? GeneralSettings.operations(enabling: id, in: general) : GeneralSettings.operations(disabling: id, in: general)
        await edit(operations, deciding: GeneralSettingsState.agentsKey, saying: enabled ? .appMenuEditedAdded(agent.name) : .appMenuEditedRemoved(agent.name), on: .agents)
    }

    /// The default terminal; `nil` is the first one that is installed.
    func setTerminal(_ id: String?) async {
        await edit(GeneralSettings.operations(settingTerminal: id), deciding: "general.terminal", saying: .appEditSaved, on: .overview)
    }

    func setEditor(_ id: String?) async {
        await edit(GeneralSettings.operations(settingEditor: id), deciding: "general.editor", saying: .appEditSaved, on: .overview)
    }

    /// The language of the window, the Finder menu, the alerts and the names of the Quick Actions; `nil` follows the system.
    func setLanguage(_ code: String?) async {
        guard code.map(Localizer.supportedLanguages.contains) ?? true else { return }
        await edit(GeneralSettings.operations(settingLanguage: code), deciding: GeneralSettings.languageKey, saying: .appEditSaved, on: .overview)
    }

    func setPlacement(_ placement: TerminalPlacement) async {
        guard general?.placements.contains(placement) == true else { return }
        await edit(GeneralSettings.operations(settingPlacement: placement), deciding: "general.terminal_placement", saying: .appEditSaved, on: .overview)
    }

    /// Switches the permission prompts of the agents off or on. Switching them off waits for the person's yes like every other change that takes them away (`edit` asks the service which agents
    /// would then start without asking, whichever way a click reaches them, and the files as they are now, not as the window last read them).
    func setBypassPermissions(_ on: Bool) async {
        // Off does not make every agent ask: one whose own setting says "start without asking" still does not.
        let someStillDoNot = general?.enabledAgents.contains { $0.bypassOverride == true && $0.bypassFlag != nil } == true
        await edit(GeneralSettings.operations(settingBypassPermissions: on), deciding: "general.bypass_permissions", saying: on ? .appBypassEditedOn : (someStillDoNot ? .appEditSaved : .appBypassEditedOff), on: .agents)
    }

    /// Shows one agent's own options in place of the list of agents (`nil` goes back to the list).
    func openAgentOptions(_ id: String?) {
        agentDetail = id
        presetDetail = nil
        variantDetail = nil
    }

    /// Shows one prompt preset in place of the list of agents (`nil` goes back to the list).
    func openPreset(_ id: String?) {
        presetDetail = id
        agentDetail = nil
        variantDetail = nil
    }

    /// Whether the page of a template can stay open: the template is there and is one of the config's own. The built-in ones have no page (they have nothing to change), so the page of a
    /// template closes when the last one is taken out, or the customizing is undone, and the built-in ones come back under the same ids.
    static func templatePageStays(_ id: String, in state: NewFileState?) -> Bool {
        guard let state, !state.isBuiltIn else { return false }
        return state.row(id: id) != nil
    }

    /// Shows one start option of an agent in place of the page of the agent (`nil` goes back to it).
    func openVariant(_ ref: VariantRef?) {
        variantDetail = ref
    }

    /// Shows one new-file template in place of the Finder menu (`nil` goes back to the menu).
    func openTemplate(_ id: String?) {
        templateDetail = id
    }

    /// Shows one app of the config in place of the Overview (`nil` goes back to it). What Add App refused is said under the apps, and is not carried to the page of an app.
    func openApp(_ id: String?) {
        appDetail = id
        clearRefusal(key: "app")
    }

    /// Takes back the last change of the config, whoever made it last through the window, `rh config` or an assistant's tool, as long as the file is as it left it.
    func undoEdit() async {
        guard !isWorking, let last = configEdit else { return }
        isWorking = true
        isEditingConfig = true
        defer { isEditingConfig = false }
        let result = await actions.undoConfigEdit(target: last.target, expecting: last.digest, replacing: last.beforeDigest)
        configEdit = nil
        editRefusal = result.notice.map { EditRefusal(notice: $0, tab: last.tab, key: last.key) }
        say(result.notice)
        await refreshEditable()
        isWorking = false
    }

    /// Writes the changes to the file that decides `key`, says what was done, and reads the editors again from the config, without the doctor.
    /// - Parameters:
    ///   - anchor: A key that the setting's table stands on (`AgentOptions.anchor`): the file that holds it decides when this Mac's own file does not write the setting itself.
    ///   - confirmed: The person has said yes to what the change does to the agents' permission prompts. Without it, a change that would make an agent start without them is held
    ///     (`pendingLoosening`) and nothing is written.
    ///   - announcing: Whether VoiceOver is told what was changed. A text that is written while it is still being typed is not: the person is not waiting for an answer.
    /// - Returns: Whether the change was made or there was nothing to change (the field that asked can show what the config says); `false` when it was refused, held for the person's yes,
    ///   or dropped because another change is being written.
    @discardableResult
    func edit(_ operations: [ConfigOperation], deciding key: String, anchor: String? = nil, target: ConfigTarget? = nil, saying message: LocalizedMessage, on tab: SetupTab, confirmed: Bool = false, announcing: Bool = true) async -> Bool {
        guard !operations.isEmpty else { return true }
        guard !isWorking else { return false }
        isWorking = true
        isEditingConfig = true
        defer { isEditingConfig = false }
        drag = nil
        if !confirmed {
            let agents = await actions.looseningEffects(of: operations, deciding: key, anchor: anchor, target: target)
            if !agents.isEmpty {
                pendingLoosening = PendingLoosening(operations: operations, key: key, anchor: anchor, target: target, message: message, tab: tab, agents: agents)
                isWorking = false
                return false
            }
        }
        let result = await actions.editConfig(operations, deciding: key, anchor: anchor, target: target)
        var done = true
        if let change = result.change, change.changed {
            configEdit = ConfigEdit(message: message, key: key, tab: tab, digest: change.afterDigest, beforeDigest: change.beforeDigest, target: change.target, warnings: change.warnings)
            editRefusal = nil
            say(nil)
            if announcing { announce(localizer.render(message)) }
        } else {
            editRefusal = result.notice.map { EditRefusal(notice: $0, tab: tab, key: key) }
            say(result.notice)
            done = result.notice == nil
        }
        await refreshEditable()
        isWorking = false
        return done
    }

    /// The person said yes to the held change: it is made. The alert hands over the change it showed: the alert's dismissal clears `pendingLoosening` before the task that this starts runs.
    func confirmLoosening(_ held: PendingLoosening) async {
        pendingLoosening = nil
        if let proposal = held.proposal {
            await approveProposal(proposal, confirmed: true)
            return
        }
        if await edit(held.operations, deciding: held.key, anchor: held.anchor, target: held.target, saying: held.message, on: held.tab, confirmed: true) { fieldAnswerToken += 1 }
    }

    /// The same for a caller that has only the model.
    func confirmLoosening() async {
        if let held = pendingLoosening { await confirmLoosening(held) }
    }

    /// The held change is forgotten, and the file was never touched. The alert calls this whichever button closed it.
    func cancelLoosening() {
        pendingLoosening = nil
    }

    /// The person said no: the held change is forgotten, and the field that raised it takes the config's text.
    func declineLoosening() {
        pendingLoosening = nil
        fieldAnswerToken += 1
    }

    /// The menu, the rows of the editors and the config's problems read again from the config, without the doctor: what an edit shows at once.
    private func refreshEditable() async {
        #if PREVIEW
        if simulated { return }
        #endif
        let shown = await loader.menu()
        // A change of the list, of the agents that its default has or of the language of their names makes the Quick Actions on disk differ from the config. The person made it here, so
        // they are written again at once, as Install or Repair would (a few files and one `pbs -update`); where there are none yet, setting up is still the person's to start.
        var services = await loader.servicesCheck()
        // From an older copy, or one that is not the one to keep, setup refuses (InstallError.notTheCopyToKeep), and the check says they differ.
        if services.detail?.key == .doctorServicesDiffer, locationProblem == nil {
            _ = await actions.updateQuickActions()
            services = await loader.servicesCheck()
        }
        guard var current = snapshot else { return }
        if !checks.isEmpty { checks = checks.replacing(services) }
        editedAt = .now
        current.menu = shown.menu
        current.menuEditor = shown.editor
        current.menuTarget = shown.target
        current.general = shown.general
        current.agentsTarget = shown.agentsTarget
        current.agentOptions = shown.agentOptions
        current.presets = shown.presets
        current.newFile = shown.newFile
        current.copyPath = shown.copyPath
        current.quickActions = shown.quickActions
        current.apps = shown.apps
        current.configProblems = shown.problems
        current.language = shown.language
        snapshot = current
        if let open = templateDetail, !Self.templatePageStays(open, in: shown.newFile) { templateDetail = nil }
        if let open = appDetail, shown.apps?.row(id: open) == nil { appDetail = nil }
        if let open = agentDetail, !shown.agentOptions.contains(where: { $0.id == open }) { agentDetail = nil }
        if let open = presetDetail, shown.presets?.row(id: open) == nil { presetDetail = nil }
        if let open = variantDetail, !(shown.agentOptions.first { $0.id == open.agent }?.variants.contains { $0.id == open.id } ?? false) { variantDetail = nil }
        openSubmenus = MenuPreview.keepingOpen(openSubmenus, in: shown.menu)
        if shown.editor == nil { isEditingMenu = false }
        warmIcons(shown.menu, editor: shown.editor, general: shown.general, apps: shown.apps)
    }

    func showExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    func copySetupPrompt() {
        copy(SetupSnippets.setupPrompt(command: mcpCommand), confirmed: .promptCopied)
    }

    func copyMCPConfiguration() {
        copy(SetupSnippets.mcpConfiguration(command: mcpCommand), confirmed: .mcpConfigurationCopied)
    }

    func copyPluginCommands() {
        copy(SetupSnippets.pluginCommands, confirmed: .pluginCommandsCopied)
    }

    /// Changes the folders only while no read of the state is running: a read that started before the change could finish after
    /// it and put the old list back. The buttons that do this are off meanwhile.
    func unpin(_ folder: String) async {
        guard !isWorking, !isRefreshing else { return }
        isWorking = true
        say(await actions.unpin(folder))
        isWorking = false
        await refreshFolders()
    }

    func pin(_ folder: String) async {
        guard !isWorking, !isRefreshing else { return }
        isWorking = true
        say(await actions.pin(folder))
        isWorking = false
        await refreshFolders()
    }

    /// Pins a folder the person chooses.
    func choosePinnedFolder() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = localizer.string(.appPinChooseMessage)
        panel.prompt = localizer.string(.appPin)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        await pin(folder.standardizedFileURL.path)
    }

    func clearRecents() async {
        guard !isWorking, !isRefreshing else { return }
        isWorking = true
        say(await actions.clearRecents())
        isWorking = false
        await refreshFolders()
    }

    /// Lists the worktrees of the repository the tab shows. A repository chosen meanwhile has its own list coming; this one is dropped.
    func refreshWorktrees() async {
        #if PREVIEW
        if simulated { return }
        #endif
        worktreeRequest += 1
        let request = worktreeRequest
        guard let repository else {
            worktrees = .idle
            return
        }
        worktrees = .loading
        let listing = await browser.list(in: repository)
        // Newer than this listing: a later request, or a repository chosen meanwhile.
        guard request == worktreeRequest, self.repository == repository else { return }
        worktrees = listing
    }

    /// Lets the person pick a folder; the git repository it is in is the one the worktrees tab lists.
    func chooseRepository() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = localizer.string(.appChooseFolderMessage)
        panel.prompt = localizer.string(.appChooseFolderPrompt)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        guard let root = await actions.repository(containing: folder) else {
            say(.notARepository(PathDisplay.abbreviatingHome(folder.path, home: homePath)))
            return
        }
        selectRepository(root)
    }

    func selectRepository(_ root: URL) {
        chosenRepository = root
        Task { await refreshWorktrees() }
    }

    /// Removes a worktree Right Here made, after the person confirmed it. Git decides whether that is safe (uncommitted work is
    /// refused, and its refusal is what the window shows); the branch stays.
    func remove(_ row: WorktreeRow) async {
        guard let repository, !isWorking else { return }
        isWorking = true
        let result = await browser.remove(row, in: repository)
        if case .worktreeRemoved(let path) = result {
            say(.worktreeRemoved(PathDisplay.abbreviatingHome(path, home: homePath)))
        } else {
            say(result)
        }
        isWorking = false
        await refreshWorktrees()
    }

    private func refreshLoop() -> RefreshLoop<SetupSnapshot> {
        if let loop { return loop }
        let made = RefreshLoop<SetupSnapshot>(
            load: { [loader] in await loader.load() },
            apply: { [weak self] loaded in self?.apply(loaded) },
            busyChanged: { [weak self] busy in self?.isRefreshing = busy })
        loop = made
        return made
    }

    /// What a read found, shown. A test hands it a snapshot of its own.
    func apply(_ loaded: SetupSnapshot) {
        if let installed = loaded.installedCopies { take(installedCopies: installed) }
        var loaded = loaded
        if let editedAt, loaded.readAt < editedAt, let current = snapshot {
            // This read began before the config was last changed through the window, and the doctor made it take seconds: what it says of the config is older than what is shown.
            loaded.menu = current.menu
            loaded.menuEditor = current.menuEditor
            loaded.menuTarget = current.menuTarget
            loaded.general = current.general
            loaded.agentsTarget = current.agentsTarget
            loaded.agentOptions = current.agentOptions
            loaded.presets = current.presets
            loaded.newFile = current.newFile
            loaded.copyPath = current.copyPath
            loaded.quickActions = current.quickActions
            loaded.apps = current.apps
            loaded.configProblems = current.configProblems
            loaded.language = current.language
            loaded.proposals = current.proposals
            // The check of the Quick Actions that a change of their list made says they differ (`refreshEditable`): an older read does not know of the change, and would say they are as the config asks.
            if let services = checks.first(where: { $0.id == .services }) { loaded.checks = loaded.checks.replacing(services) }
        }
        snapshot = loaded
        if let open = agentDetail, !loaded.agentOptions.contains(where: { $0.id == open }) { agentDetail = nil }
        if let open = presetDetail, loaded.presets?.row(id: open) == nil { presetDetail = nil }
        if let open = templateDetail, !Self.templatePageStays(open, in: loaded.newFile) { templateDetail = nil }
        if let open = appDetail, loaded.apps?.row(id: open) == nil { appDetail = nil }
        if let open = variantDetail, !(loaded.agentOptions.first { $0.id == open.agent }?.variants.contains { $0.id == open.id } ?? false) { variantDetail = nil }
        lastRead = .now
        checks = loaded.checks + (launchResult.map { [$0] } ?? [])
        // A setup that failed is shown until the next read that is not the one it ends with: the Checks say the same, and somebody else (an AI assistant, `rh setup` in a
        // terminal) may have put it right meanwhile.
        if let report = setupReport, !report.ok, !isWorking { setupReport = nil }
        folders = loaded.folders
        offer = loaded.offer
        seedChoices(from: loaded.offer)
        // The ids of the open submenus are positions: a changed menu may have another entry at a position that was open.
        openSubmenus = MenuPreview.keepingOpen(openSubmenus, in: loaded.menu)
        warmIcons(loaded.menu, editor: loaded.menuEditor, general: loaded.general, apps: loaded.apps, offer: loaded.offer)
        if selectedTab == .worktrees { Task { await refreshWorktrees() } }
        if selectedTab == .config { Task { await openConfigPage(keepingDraft: true) } }
    }

    /// The first time the window is offered what is installed, the choices start from what the Mac has. They stay the person's after
    /// that, through every refresh.
    private func seedChoices(from offer: SetupOffer?) {
        guard let offer, !choicesSeeded else { return }
        choicesSeeded = true
        selectedTerminal = offer.detected.terminal ?? offer.terminals.first?.id
        selectedEditor = offer.detected.editor ?? offer.editors.first?.id
        selectedAgents = Set(offer.detected.agents)
    }

    private func refreshFolders() async {
        #if PREVIEW
        if simulated { return }
        #endif
        folders = await loader.folders()
        if selectedTab == .worktrees { await refreshWorktrees() }
    }

    private func copy(_ text: String, confirmed: SetupNotice) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        say(confirmed)
    }

    /// Shows what happened, and says it to VoiceOver: the notice is a line in the corner of the sidebar, which a person who cannot see it would never find.
    func say(_ new: SetupNotice?) {
        notice = new
        if new != nil { repairOutcome = nil }
        if let new { announce(localizer.render(new.message)) }
    }

    /// How the setup stands after a setup or a repair that raised no notice of its own, said aloud: "Everything is set up." or "Some checks need your attention."
    private func announceState(unless notice: SetupNotice?) {
        guard notice == nil, summary.state != .checking else { return }
        announce(localizer.string(summary.state.titleKey))
    }

    private func announce(_ text: String) {
        lastAnnouncement = text
        #if !PREVIEW
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        #endif
    }

    /// The icons of the menu are read from the apps on disk, which takes a moment for each; they are read off the main actor so
    /// that opening the menu does not wait for them.
    private func warmIcons(_ menu: [MenuNode], editor: MenuEditorState? = nil, general: GeneralSettingsState? = nil, apps: AppsState? = nil, offer: SetupOffer? = nil) {
        let provider = icons
        let wanted = Self.iconsToWarm(menu, editor: editor, general: general, apps: apps, offer: offer)
        Task.detached { provider.prewarm(wanted) }
    }

    /// Every icon a page of the window can draw from what was read: the menu, its editor, the Overview's apps and agents, the apps of the config, and the
    /// first run's terminals and editors.
    nonisolated static func iconsToWarm(_ menu: [MenuNode], editor: MenuEditorState? = nil, general: GeneralSettingsState? = nil, apps: AppsState? = nil, offer: SetupOffer? = nil) -> [Icon] {
        icons(in: menu) + (editor.map { icons(in: $0.rows.flatMap(\.nodes)) + $0.choices.compactMap(\.icon) } ?? [])
            + (general.map { $0.agents.compactMap(\.icon) + ($0.terminals + $0.editors).compactMap(\.icon) } ?? [])
            + (apps.map { $0.rows.compactMap(\.icon) } ?? [])
            + (offer.map { ($0.terminals + $0.editors).compactMap(\.icon) } ?? [])
    }

    private nonisolated static func icons(in nodes: [MenuNode]) -> [Icon] {
        nodes.flatMap { node in (node.icon.map { [$0] } ?? []) + icons(in: node.children) }
    }

    #if PREVIEW
    /// For `script/preview_setup.sh`: the window shows what it is given and nothing this Mac says, now or later (a refresh is
    /// ignored from here on).
    @ObservationIgnored private var simulated = false

    func simulate(_ demo: SetupSnapshot, tab: SetupTab, icons provider: IconProvider? = nil, worktrees listing: WorktreeListing = .idle,
                  repository: URL? = nil) {
        simulated = true
        if let provider { icons = provider }
        apply(demo)
        folders = demo.folders
        chosenRepository = repository
        worktrees = listing
        selectedTab = tab
    }

    /// For `--set-up`: the list of what the first setup did, as it is just after it ran.
    func simulate(setupReport report: SetupReport) {
        setupReport = report
    }

    /// For `--older-copy`: this copy is older than one that is installed.
    func simulate(running: AppCopy, newer: AppCopy) {
        runningCopy = running
        newerCopy = newer
    }

    /// For `--repairing`: Install or Repair runs, and is at this phase.
    func simulate(phase: SetupPhase) {
        isWorking = true
        isRepairing = true
        setupPhase = phase
    }

    /// For `--repaired`: Install or Repair has ended, with this report.
    func simulate(repaired report: SetupReport) {
        setupReport = report
        repairOutcome = .repaired(changed: Self.changedPieces(report).count)
    }

    /// For `--location`: the app runs from a disk image.
    func simulateLocationProblem() {
        locationProblem = .onAnotherVolume(path: "/Volumes/Right Here/Right Here.app/Contents/Helpers/rh")
    }

    /// For `--onboarding`: the first-run card, as it is when the Finder extension is off.
    func simulateExtensionOff() {
        checks = checks.map { check in
            var copy = check
            if check.id == .finderExtension { copy.status = .needsUser }
            return copy
        }
    }

    /// For `--tab config`: the Config page with a text, a proposal that waits and recent changes.
    func simulate(configPage page: ConfigPageState) {
        configPage = page
        configTarget = page.target
        draftText = page.text?.text ?? ""
        if var current = snapshot { current.proposals = page.proposals.map(\.proposal); snapshot = current }
        selectedTab = .config
    }

    /// For `--editing`: the Finder menu page is being edited, with the note of a change that was just made.
    func simulateEditingMenu(edit: ConfigEdit?) {
        selectedTab = .menu
        isEditingMenu = true
        configEdit = edit
    }

    /// For `--tab agents` and `--tab overview`: the page with the note of a change that was just made.
    func simulate(edit: ConfigEdit?) {
        configEdit = edit
    }

    /// For `--submenus`: these submenus of the Finder menu start open.
    func simulate(openSubmenus ids: Set<String>) {
        openSubmenus = ids
        selectedTab = .menu
    }

    /// An app's icon comes as a 16-bit extended-range image, and `ImageRenderer` renders the whole picture in extended range as soon
    /// as it meets one, which washes out every color in it. An icon drawn into the renderer's own context keeps the picture as it is
    /// on screen.
    private static func drawnInTheRenderer(_ image: NSImage) -> NSImage {
        guard !image.isTemplate else { return image }
        return NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
    }
    #endif
}
