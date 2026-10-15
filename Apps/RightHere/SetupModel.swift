import AppKit
import FinderSync
import Observation
import RightHereCore
import RightHereKit

enum SetupTab: String, CaseIterable, Identifiable {
    case overview = "overview"
    case menu = "menu"
    case ai = "ai"
    case worktrees = "worktrees"
    case bookmarks = "bookmarks"
    case diagnostics = "diagnostics"
    case config = "config"

    var id: String { rawValue }
}

/// What the setup window shows and does. All the work is done by the same code `rh` uses.
@MainActor
@Observable
final class SetupModel {
    var selectedTab: SetupTab = .overview
    private(set) var checks: [DoctorCheck] = []
    private(set) var isWorking = false
    private(set) var message: String?
    /// The Finder menu for a folder, built the way the Finder extension builds it; nothing when the config has errors.
    private(set) var menu: [MenuNode] = []
    /// The submenus of the menu preview that are open, by `MenuPreviewRow.id`.
    private(set) var openSubmenus: Set<String> = []

    private(set) var pins: [String] = []
    private(set) var recents: [String] = []
    private(set) var worktrees: [WorktreeEntry] = []
    private(set) var configContent: String = ""
    private(set) var configValid = true
    private(set) var configDiagnostics: [String] = []

    var knownAgents: [AgentDescriptor] { KnownAgents.all }

    private let facts = LiveSystemFacts()
    private var icons = IconProvider(facts: LiveSystemFacts())

    /// The `rh` that ships inside this app.
    private var helper: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/rh")
    }

    private var paths: RHPaths { RHPaths.current(facts: facts) }

    /// Whether any check is anything but ok, warnings included.
    var needsAttention: Bool {
        checks.contains { $0.status != .ok }
    }

    /// The Finder extension is the one thing the first-run card waits for.
    var extensionNeedsSetup: Bool {
        checks.contains { $0.id == .finderExtension && $0.status != .ok }
    }

    /// Default terminal name from checks or config.
    var defaultTerminalName: String {
        if let detail = check(.terminalDefault)?.detail {
            let rendered = Localizer.system.render(detail)
            let cleaned = rendered
                .replacingOccurrences(of: "Open in ", with: "")
                .replacingOccurrences(of: "Öffnen in ", with: "")
                .replacingOccurrences(of: "Ouvrir dans ", with: "")
            if !cleaned.isEmpty { return cleaned }
        }
        return "Ghostty"
    }

    /// Default editor name from checks or config.
    var defaultEditorName: String {
        if let detail = check(.editorDefault)?.detail {
            let rendered = Localizer.system.render(detail)
            let cleaned = rendered
                .replacingOccurrences(of: "Open in ", with: "")
                .replacingOccurrences(of: "Öffnen in ", with: "")
                .replacingOccurrences(of: "Ouvrir dans ", with: "")
            if !cleaned.isEmpty { return cleaned }
        }
        return "Visual Studio Code"
    }

    /// Count of checks by status.
    var doctorStats: (ok: Int, warn: Int, fail: Int, needsUser: Int) {
        var ok = 0, warn = 0, fail = 0, needsUser = 0
        for check in checks {
            switch check.status {
            case .ok: ok += 1
            case .warn: warn += 1
            case .fail: fail += 1
            case .needsUser: needsUser += 1
            }
        }
        return (ok, warn, fail, needsUser)
    }

    /// Whether the details list starts open: when something needs attention, except under the first-run card.
    var detailsStartOpen: Bool {
        #if PREVIEW
        if previewOpensDetails { return true }
        #endif
        return needsAttention && !extensionNeedsSetup
    }

    #if PREVIEW
    private var simulated = false
    private var previewOpensDetails = false

    /// For `script/preview_setup.sh --onboarding`: shows the first-run card on a machine where the extension is on.
    func simulateExtensionOff() {
        checks = checks.map { check in
            var copy = check
            if check.id == .finderExtension { copy.status = .needsUser }
            return copy
        }
        selectedTab = .overview
    }

    /// For `script/preview_setup.sh --demo` and `--gallery`: shows these checks and nothing this machine says, now or
    /// later: a refresh is ignored from here on.
    func simulate(checks: [DoctorCheck], opensDetails: Bool = false) {
        self.checks = checks
        simulated = true
        previewOpensDetails = opensDetails
        if opensDetails {
            selectedTab = .diagnostics
        }
    }

    /// For `script/preview_setup.sh --demo`: this menu, drawn with the icons of these facts.
    func simulate(menu: [MenuNode], icons: IconProvider) {
        self.menu = menu
        self.icons = icons
        if !previewOpensDetails {
            selectedTab = .menu
        }
    }

    /// For `script/preview_setup.sh --submenus`: these submenus of the menu preview start open.
    func simulate(openSubmenus ids: Set<String>) {
        openSubmenus = ids
        selectedTab = .menu
    }

    /// An app's icon comes as a 16-bit extended-range image, and `ImageRenderer` renders the whole picture in extended
    /// range as soon as it meets one, which washes out every color in it. An icon drawn into the renderer's own context
    /// keeps the picture as it is on screen.
    private static func drawnInTheRenderer(_ image: NSImage) -> NSImage {
        guard !image.isTemplate else { return image }
        return NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
    }
    #endif

    func check(_ id: CheckID) -> DoctorCheck? {
        checks.first { $0.id == id }
    }

    /// The lines of the menu preview that can be seen now.
    var menuRows: [MenuPreviewRow] {
        MenuPreview.rows(menu, expanded: openSubmenus)
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

    /// While the extension is not switched on, looks at it every two seconds, so the card turns green by itself
    /// after the person flips the switch in System Settings. A look is the extension's check alone (one `pluginkit`
    /// call), not the whole doctor; when the extension is on, one full refresh follows. It stops as soon as the
    /// extension is ok, and when the caller's task is cancelled (the window closed). It stays out of the way of work
    /// the person started.
    func watchExtension() async {
        while extensionNeedsSetup, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            if !isWorking, !Task.isCancelled, await refreshExtension() { await refresh(quiet: true) }
        }
    }

    /// Looks at the Finder extension alone and puts the answer in the extension's place in `checks`.
    /// - Returns: whether the extension is ok.
    private func refreshExtension() async -> Bool {
        #if PREVIEW
        if simulated { return false }
        #endif
        let check = await Doctor.extensionCheck(runner: LiveProcessRunner())
        // Work the person started meanwhile ends in a full refresh of its own, which is newer than this look; and a
        // look that was cut short by the window closing says nothing.
        guard !isWorking, !Task.isCancelled else { return false }
        checks = checks.replacing(check)
        return check.status == .ok
    }

    /// - Parameter quiet: Do not show the busy state (buttons stay enabled); used by the refresh after a background look.
    func refresh(quiet: Bool = false) async {
        #if PREVIEW
        if simulated { return }
        #endif
        if !quiet { isWorking = true }
        defer { if !quiet { isWorking = false } }
        let loaded = ConfigStore.load(paths: paths)
        let doctor = Doctor(facts: facts, paths: paths, loaded: loaded, rhPath: helper.path)
        checks = await doctor.run()
        refreshMenu()
        refreshBookmarks()
        await refreshWorktrees()
        refreshConfigState(loaded: loaded)
    }

    /// The preview follows the config and the installed apps as they are now, in the language of the system.
    private func refreshMenu() {
        menu = MenuPreview.folderMenu(ConfigStore.load(paths: paths).result, facts: facts, folder: facts.homeDirectory, localizer: .system)
    }

    func refreshBookmarks() {
        let store = StateStore.load(paths: paths)
        pins = store.pins
        recents = store.recents
    }

    func pinFolder(_ path: String) {
        var store = StateStore.load(paths: paths)
        if store.pin(path) {
            try? store.save(paths: paths)
            refreshBookmarks()
        }
    }

    func unpinFolder(_ path: String) {
        var store = StateStore.load(paths: paths)
        if store.unpin(path) {
            try? store.save(paths: paths)
            refreshBookmarks()
        }
    }

    func clearRecents() {
        var store = StateStore.load(paths: paths)
        store.clearRecents()
        try? store.save(paths: paths)
        refreshBookmarks()
    }

    func refreshWorktrees() async {
        guard let gitRoot = facts.gitRoot(containing: facts.currentDirectory) else {
            worktrees = []
            return
        }
        worktrees = (try? await GitWorktreeManager.listWorktrees(in: gitRoot)) ?? []
    }

    func removeWorktree(_ path: String) async {
        guard let gitRoot = facts.gitRoot(containing: facts.currentDirectory) else { return }
        try? await GitWorktreeManager.removeWorktree(worktreePath: path, gitRoot: gitRoot, deleteBranch: true)
        await refreshWorktrees()
    }

    func refreshConfigState(loaded: LoadedConfig) {
        configValid = !loaded.result.hasErrors
        configDiagnostics = loaded.result.diagnostics.map { $0.summary(file: loaded.file) }
        configContent = (try? String(contentsOf: paths.configFile, encoding: .utf8)) ?? "# No config.toml created yet. Run `rh init`."
    }

    /// Runs `rh install`: runner script, command link, config file and the Finder extension.
    func installOrRepair() async {
        isWorking = true
        message = nil
        do {
            let result = try await LiveProcessRunner().run(ProcessStep(executable: helper.path, arguments: ["install"]), timeout: .seconds(60))
            if result.status != 0 {
                let text = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                message = text.isEmpty ? "rh install exited with status \(result.status)" : text
            }
        } catch {
            // The system's own wording, in the system language; the install did not run to its end.
            message = error.localizedDescription
        }
        isWorking = false
        await refresh()
    }

    /// Has the Finder extension start a throwaway terminal session that runs a typed command, the
    /// way a menu click starts an agent, and shows what the doctor makes of it. A window opens and
    /// closes; the first time, macOS asks whether Right Here may control the terminal.
    func testTerminalLaunch() async {
        isWorking = true
        message = Localizer.system.string(.appTesting)
        let doctor = Doctor(facts: facts, paths: paths, loaded: ConfigStore.load(paths: paths), rhPath: helper.path)
        checks = await doctor.run(probeLaunch: true)
        message = nil
        isWorking = false
    }

    func showExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    func openConfig() async {
        do {
            if !FileManager.default.fileExists(atPath: paths.configFile.path) {
                let created = try await LiveProcessRunner().run(ProcessStep(executable: helper.path, arguments: ["init"]), timeout: .seconds(30))
                if created.status != 0 {
                    let text = created.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                    message = text.isEmpty ? "rh init exited with status \(created.status)" : text
                    return
                }
            }
            let opened = try await LiveProcessRunner().run(ProcessStep(executable: "/usr/bin/open", arguments: ["-t", paths.configFile.path]))
            if opened.status != 0 {
                let text = opened.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                message = text.isEmpty ? "open exited with status \(opened.status)" : text
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func copySetupPrompt() {
        let prompt = """
        Set up Right Here for me. Run `rh docs agent-setup` and follow it: run `rh doctor --json` and fix \
        whatever fails, then tailor ~/.config/right-here/config.toml to how I work, check it with \
        `rh config validate`, and show me the result with `rh menu`.
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        message = Localizer.system.string(.appPromptCopied)
    }

    func copyClaudePluginCommand() {
        let cmd = "/plugin marketplace add boyugou/right-here\n/plugin install right-here@right-here"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        message = "Plugin install command copied"
    }

    func copyMCPConfig() {
        let config = """
        {
          "mcpServers": {
            "right-here": {
              "command": "rh",
              "args": ["mcp"]
            }
          }
        }
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config, forType: .string)
        message = "MCP configuration copied"
    }
}
