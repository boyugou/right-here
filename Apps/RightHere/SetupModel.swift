import AppKit
import FinderSync
import Observation
import RightHereCore
import RightHereKit

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
    /// A window-local query survives reads, folder edits and visits to another section.
    var folderQuery = ""
    private(set) var folderSearchRequest = 0
    private(set) var isRefreshing = false
    /// An install, a repair, a launch test or a change to the folders is running: the buttons that would start another are off.
    private(set) var isWorking = false
    private(set) var isTestingLaunch = false
    private(set) var isChoosingFolder = false
    /// What happened last: a confirmation, or why an action did not work. The next action replaces it.
    private(set) var notice: SetupNotice?
    private(set) var worktrees: WorktreeListing = .idle
    /// The repository the worktrees tab lists when the person chose one; otherwise the first repository of the folders.
    private(set) var chosenRepository: URL?
    private var chosenRepositories: [URL] = []
    /// The submenus of the Finder menu that are open, by `MenuPreviewRow.id`.
    private(set) var openSubmenus: Set<String> = []
    /// What a person with no config file can choose from, and what they have chosen so far. The choices start from what the Mac
    /// has (`SetupOffer.detected`) once, and are the person's from then on: a refresh does not put them back.
    private(set) var offer: SetupOffer?
    var selectedTerminal: String?
    var selectedEditor: String?
    var selectedAgents: Set<String> = []
    /// Setting up (the first-run button) is running.
    private(set) var isSettingUp = false
    /// What the last setup did, for the list "What Right Here set up".
    private(set) var setupReport: SetupReport?
    /// How many times a setup or a repair has come back with an answer: the page scrolls to the answer when this changes.
    private(set) var setupAttempt = 0
    @ObservationIgnored private var choicesSeeded = false
    /// The answer of the last launch test: it is kept through refreshes, which read the checks and do not run the probe.
    @ObservationIgnored private var launchResult: DoctorCheck?
    /// Each listing of the worktrees gets a number; only the newest one is shown, so a listing that ends late cannot overwrite it.
    @ObservationIgnored private var worktreeRequest = 0
    @ObservationIgnored private var isRemovingWorktree = false

    private let loader: SetupLoader
    private let actions: SetupActions
    private let browser: WorktreeBrowser
    private let home: URL
    private let pollInterval: Duration
    private let idleInterval: Duration
    private let windowIsVisible: @MainActor () -> Bool
    private let activationQuietPeriod: Duration
    private let readFolders: @Sendable () async -> FolderSnapshot
    private let pickFolder: @MainActor (FolderChoice) async -> URL?
    private let writeClipboard: @MainActor (String) -> Void

    enum FolderChoice: Equatable { case pin, repository }
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
    init(loader: SetupLoader, actions: SetupActions, facts: any SystemFacts, helper: String, pollInterval: Duration = .seconds(2), idleInterval: Duration = .seconds(30),
         activationQuietPeriod: Duration = .seconds(20), windowIsVisible: @escaping @MainActor () -> Bool = SetupModel.liveWindowIsVisible,
         readFolders: (@Sendable () async -> FolderSnapshot)? = nil,
         pickFolder: @escaping @MainActor (FolderChoice) async -> URL? = SetupModel.livePickFolder,
         browser: WorktreeBrowser = WorktreeBrowser(),
         writeClipboard: @escaping @MainActor (String) -> Void = SetupModel.liveWriteClipboard) {
        self.loader = loader
        self.actions = actions
        icons = IconProvider(facts: facts)
        home = facts.homeDirectory
        locationProblem = InstallError.problem(runningFrom: helper)
        self.pollInterval = pollInterval
        self.idleInterval = idleInterval
        self.activationQuietPeriod = activationQuietPeriod
        self.windowIsVisible = windowIsVisible
        self.readFolders = readFolders ?? { await loader.folders() }
        self.pickFolder = pickFolder
        self.browser = browser
        self.writeClipboard = writeClipboard
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

    /// Missing setup pieces are expected before the person has chosen anything.
    var statusTitle: LocalizationKey { needsFirstRunChoice ? .appSetupTitle : summary.state.titleKey }

    var attentionCount: Int { needsFirstRunChoice ? 0 : summary.attentionChecks.count }

    enum MenuState: Equatable {
        case loading, needsSetup, invalidConfig, empty, ready
    }

    var menuState: MenuState {
        guard let snapshot else { return .loading }
        guard snapshot.configExists else { return .needsSetup }
        guard !snapshot.configHasErrors else { return .invalidConfig }
        return snapshot.menu.isEmpty ? .empty : .ready
    }

    func check(_ id: CheckID) -> DoctorCheck? {
        checks.first { $0.id == id }
    }

    /// The lines of the Finder menu preview that can be seen now.
    var menuRows: [MenuPreviewRow] {
        MenuPreview.rows(snapshot?.menu ?? [], expanded: openSubmenus)
    }

    /// The home folder the paths of the window are written from `~` against: the snapshot's, which is the demo's in a preview.
    var homePath: String { snapshot?.home.path ?? home.path }

    var showsFolderSearch: Bool { !folders.pins.isEmpty || !folders.recents.isEmpty || !folderQuery.isEmpty }

    var canFindFolders: Bool { selectedTab == .folders && snapshot != nil && folders.problem == nil && showsFolderSearch }

    func findFolders() {
        guard canFindFolders else { return }
        folderSearchRequest += 1
    }

    /// The program an MCP client starts (`SetupSnippets.mcpCommand`).
    var mcpCommand: String { snapshot?.mcpCommand ?? AppIdentity.cliName }

    /// The repository the worktrees tab lists now, if there is one.
    var repository: URL? { chosenRepository ?? folders.repositories.first }

    /// Choices made in this window stay available when another repository is selected. They are not added to pinned folders.
    var repositories: [URL] {
        var seen = Set<URL>()
        return (folders.repositories + chosenRepositories + (chosenRepository.map { [$0] } ?? [])).filter { seen.insert($0).inserted }
    }

    var isLoadingWorktrees: Bool {
        if case .loading = worktrees { return true }
        return false
    }

    func image(for icon: Icon?) -> NSImage? {
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
        selectedTab = tab
        if tab == .worktrees { Task { await refreshWorktrees() } }
    }

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
        guard !isWorking, locationProblem == nil, let offer else { return }
        isWorking = true
        isSettingUp = true
        say(nil)
        let result = await actions.setUp(offer.choices(terminal: selectedTerminal, editor: selectedEditor, agents: selectedAgents))
        setupReport = result.report
        setupAttempt += 1
        say(result.notice)
        isSettingUp = false
        // Still working while the state is read again: the chooser is drawn until that read says there is a config, and its button must not
        // start the whole setup a second time.
        await refresh()
        isWorking = false
        announceState(unless: result.notice)
    }

    /// Install or Repair: the same setup without choices, for a Mac that has a config. It makes what is missing, changes what is out of
    /// date and leaves the config alone.
    func repair() async {
        guard !isWorking, locationProblem == nil else { return }
        isWorking = true
        let result = await actions.repair()
        setupReport = result.report ?? setupReport
        setupAttempt += 1
        say(result.notice)
        await refresh()
        isWorking = false
        announceState(unless: result.notice)
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
        say(.launchFinished(check))
    }

    /// Opens the config file. It does not make one: a Mac without a config chooses first.
    func openConfig(_ file: SetupConfigFile? = nil) async {
        guard !isWorking else { return }
        isWorking = true
        say(await actions.openConfig(file))
        isWorking = false
    }

    func showExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    func perform(_ action: SetupCheckAction) async {
        switch action {
        case .setup: select(.overview)
        case .repair: await repair()
        case .openConfig: await openConfig()
        case .extensionSettings: showExtensionSettings()
        }
    }

    func dismissNotice() { notice = nil }

    /// Copy the complete problem, including lines outside its viewport, without replacing it with a confirmation.
    @discardableResult
    func copyNotice(_ shown: SetupNotice) -> Bool {
        guard notice == shown, shown.isProblem else { return false }
        writeClipboard(Localizer.system.render(shown.message))
        announce(Localizer.system.string(.appMessageCopied))
        return true
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
    func pin(_ folder: String) async {
        guard !isWorking, !isRefreshing else { return }
        isWorking = true
        defer { isWorking = false }
        say(await actions.pin(folder) ?? .folderPinned(displayPath(folder)))
        await refreshFolders()
    }

    func unpin(_ folder: String) async {
        guard !isWorking, !isRefreshing else { return }
        isWorking = true
        defer { isWorking = false }
        say(await actions.unpin(folder) ?? .folderUnpinned(displayPath(folder)))
        await refreshFolders()
    }

    func clearRecents() async {
        guard !isWorking, !isRefreshing else { return }
        isWorking = true
        defer { isWorking = false }
        say(await actions.clearRecents() ?? .recentsCleared)
        await refreshFolders()
    }

    func revealFolder(_ folder: String) async {
        guard !isWorking, !isRefreshing else { return }
        isWorking = true
        defer { isWorking = false }
        say(await actions.revealFolder(folder))
    }

    func retryFolders() async {
        guard !isWorking, !isRefreshing else { return }
        isWorking = true
        defer { isWorking = false }
        say(nil)
        await refreshFolders()
    }

    func revealSavedFolders() async {
        guard !isWorking, !isRefreshing else { return }
        isWorking = true
        defer { isWorking = false }
        say(await actions.revealSavedFolders())
    }

    private func displayPath(_ path: String) -> String {
        PathDisplay.abbreviatingHome(path.withControlCharactersEscaped, home: homePath)
    }

    /// Lists the worktrees of the repository the tab shows. A repository chosen meanwhile has its own list coming; this one is dropped.
    func refreshWorktrees() async {
        guard !isRemovingWorktree else { return }
        await loadWorktrees()
    }

    private func loadWorktrees() async {
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
        await chooseFolder(for: .repository)
    }

    func choosePinnedFolder() async {
        await chooseFolder(for: .pin)
    }

    private func chooseFolder(for purpose: FolderChoice) async {
        guard !isWorking, !isRefreshing else { return }
        isWorking = true
        isChoosingFolder = true
        defer { isWorking = false; isChoosingFolder = false }
        guard let folder = await pickFolder(purpose) else { return }
        isChoosingFolder = false
        say(nil)
        switch purpose {
        case .pin:
            say(await actions.pin(folder.path) ?? .folderPinned(displayPath(folder.path)))
            await refreshFolders()
        case .repository:
            guard let root = await actions.repository(containing: folder) else {
                say(.notARepository(displayPath(folder.path)))
                return
            }
            showRepository(root)
        }
    }

    static func livePickFolder(_ purpose: FolderChoice) async -> URL? {
        // Accessibility can press the button while the app is inactive and has neither a key nor a main window.
        let app = NSApplication.shared
        guard let window = app.keyWindow ?? app.mainWindow ?? app.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return nil }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = Localizer.system.string(purpose == .pin ? .appPin : .appChooseFolderPrompt)
        if purpose == .repository {
            panel.message = Localizer.system.string(.appChooseFolderMessage)
        }
        return await panel.beginSheetModal(for: window) == .OK ? panel.url : nil
    }

    func selectRepository(_ root: URL) {
        guard !isWorking, !isRefreshing, root != repository else { return }
        showRepository(root)
    }

    private func showRepository(_ root: URL) {
        chosenRepository = root
        rememberRepository(root)
        say(nil)
        // The old rows must disappear with their old heading, before the asynchronous read gets a turn.
        worktrees = .loading
        Task {
            guard repository == root else { return }
            await refreshWorktrees()
        }
    }

    private func rememberRepository(_ root: URL) {
        if !chosenRepositories.contains(root) { chosenRepositories.append(root) }
    }

    struct WorktreeRemovalRequest: Equatable {
        let row: WorktreeRow
        let repository: URL
    }

    func removalRequest(for row: WorktreeRow) -> WorktreeRemovalRequest? {
        guard !isWorking, !isRefreshing, let repository, case .loaded(let rows) = worktrees,
              row.canBeRemoved, rows.contains(row) else { return nil }
        return WorktreeRemovalRequest(row: row, repository: repository)
    }

    /// Removes a worktree Right Here made, after the person confirmed it. Git decides whether that is safe (uncommitted work is
    /// refused, and its refusal is what the window shows); the branch stays.
    func remove(_ request: WorktreeRemovalRequest) async {
        guard !isWorking, !isRefreshing else { return }
        isWorking = true
        isRemovingWorktree = true
        worktreeRequest += 1
        defer { isWorking = false; isRemovingWorktree = false }
        say(nil)
        let result = await browser.remove(request.row, in: request.repository)
        if case .worktreeRemoved(let path) = result {
            say(.worktreeRemoved(displayPath(path)))
        } else {
            say(result)
        }
        await loadWorktrees()
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
        snapshot = loaded
        lastRead = .now
        checks = loaded.checks + (launchResult.map { [$0] } ?? [])
        // A setup that failed is shown until the next read that is not the one it ends with: the Checks say the same, and somebody else (an AI assistant, `rh setup` in a
        // terminal) may have put it right meanwhile.
        if let report = setupReport, !report.ok, !isWorking { setupReport = nil }
        applyFolders(loaded.folders)
        offer = loaded.offer
        seedChoices(from: loaded.offer)
        // The ids of the open submenus are positions: a changed menu may have another entry at a position that was open.
        openSubmenus = MenuPreview.keepingOpen(openSubmenus, in: loaded.menu)
        warmIcons(loaded.menu)
        if selectedTab == .worktrees { Task { await refreshWorktrees() } }
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
        applyFolders(await readFolders())
        if selectedTab == .worktrees { await refreshWorktrees() }
    }

    private func applyFolders(_ loaded: FolderSnapshot) {
        let previousRepository = repository
        folders = loaded
        // Without a chosen repository the first saved folder determines the heading, so refreshing folders can switch it too.
        if repository != previousRepository {
            worktreeRequest += 1
            worktrees = repository == nil ? .idle : .loading
        }
    }

    private func copy(_ text: String, confirmed: SetupNotice) {
        writeClipboard(text)
        say(confirmed)
    }

    static func liveWriteClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Shows what happened, and announces it without moving the person's keyboard focus.
    private func say(_ new: SetupNotice?) {
        notice = new
        if let new { announce(Localizer.system.render(new.message)) }
    }

    /// How the setup stands after a setup or a repair that raised no notice of its own, said aloud: "Everything is set up." or "Some checks need your attention."
    private func announceState(unless notice: SetupNotice?) {
        guard notice == nil, summary.state != .checking else { return }
        announce(Localizer.system.string(summary.state.titleKey))
    }

    private func announce(_ text: String) {
        #if !PREVIEW
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        #endif
    }

    /// The icons of the menu are read from the apps on disk, which takes a moment for each; they are read off the main actor so
    /// that opening the menu does not wait for them.
    private func warmIcons(_ menu: [MenuNode]) {
        let provider = icons
        let wanted = Self.icons(in: menu)
        Task.detached { provider.prewarm(wanted) }
    }

    private static func icons(in nodes: [MenuNode]) -> [Icon] {
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

    func simulate(notice: SetupNotice) {
        self.notice = notice
    }

    /// For `--location`: the app runs from a disk image.
    func simulateLocationProblem() {
        locationProblem = .onAnotherVolume(path: "/Volumes/Right Here/Right Here.app/Contents/Helpers/rh")
    }

    func simulate(check: DoctorCheck) {
        checks = checks.replacingOrAppending(check)
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
