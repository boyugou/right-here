import Cocoa
import FinderSync
import OSLog
import RightHereCore
import RightHereKit

/// The Finder menu. It only builds the menu from the config and hands actions over: copying a
/// path happens here, everything else runs in `rh` through the runner script, outside the sandbox.
final class FinderSyncExtension: FIFinderSync {
    private let log = Logger(subsystem: AppIdentity.extensionBundleID, category: "menu")
    private let facts = CachingSystemFacts()
    private lazy var icons = IconProvider(facts: facts)
    private lazy var paths = RHPaths.current(facts: facts)

    private var configCache: (stamp: ConfigStore.Stamp, loaded: LoadedConfig)?
    private var folderMenus = FinderMenuCache<NSMenu>()
    private var isWarmingUp = false
    /// Whether Finder draws a separator as a line; where it draws an empty row instead, the menu goes without (`FinderMenuPresentation`).
    private let showsSeparators = FinderMenuPresentation.showsSeparators()
    private var activityToken: (any NSObjectProtocol)?
    /// Finder receives a copy of each menu, and only the tag survives the trip back to the action method.
    /// The tags are stable (see `ActionTags`), so a menu built after the one being clicked cannot retarget it.
    private var tags = ActionTags()
    private var runningTasks: [ObjectIdentifier: NSUserUnixTask] = [:]

    override init() {
        super.init()
        ProcessInfo.processInfo.disableAutomaticTermination("Keep Finder Sync Extension responsive")
        ProcessInfo.processInfo.disableSuddenTermination()
        // Keeps App Nap from slowing the first right-click after a pause. `.userInitiated` and `.latencyCritical` each also hold
        // a PreventUserIdleSystemSleep assertion (measured with `pmset -g assertions`), which would keep the Mac from ever
        // sleeping while Finder runs; this option does not (docs/decisions/0015-finder-extension-stays-loaded.md).
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Right Here Finder Sync Menu"
        )
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        probeIfRequested()
        warmupInBackground()
    }

    /// Fills the icon cache and the folder menus before the first right-click, and again when a menu that is served has grown old (`MenuCachePolicy.Freshness.stale`):
    /// what is installed is asked again, in the background, so that no right-click waits for it. Only values that are safe to share cross to the
    /// background queue (the facts, the icon cache, the paths); the config cache and the menus belong to the main queue, which gets the
    /// menu nodes back. Reading `configCache` from the background was a data race with `menu(for:)`.
    private func warmupInBackground() {
        guard !isWarmingUp else { return }
        isWarmingUp = true
        let facts = self.facts
        let icons = self.icons
        let paths = self.paths
        let separators = showsSeparators
        let owner = MainThreadOwner(self)
        let startedAt = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            facts.expire()
            let stamp = ConfigStore.stamp(paths: paths)
            let config = ConfigStore.load(paths: paths).config
            var iconsToWarm: [Icon] = []
            for app in config.allApps {
                if let bundleID = app.installedBundleID(facts: facts) {
                    _ = facts.displayName(bundleID: bundleID)
                    _ = facts.bundleVersion(bundleID: bundleID)
                    iconsToWarm.append(.app(bundleID))
                }
            }
            for glyph in IconProvider.dedicatedGlyphs.keys {
                iconsToWarm.append(.symbol(glyph))
            }
            for ext in config.newFile.templates.map(\.fileExtension) where !ext.isEmpty {
                iconsToWarm.append(.fileType(ext))
            }
            icons.prewarm(iconsToWarm)
            let folderContext = HereContext(origin: .container, container: URL(fileURLWithPath: "/tmp"))
            let nodes = FinderMenuPresentation.nodes(MenuBuilder(config: config, facts: facts, localizer: config.localizer).build(for: folderContext), separators: separators)
            DispatchQueue.main.async {
                guard let self = owner.object else { return }
                self.isWarmingUp = false
                self.folderMenus.storeWarmup(hasMenu: !nodes.isEmpty, stamp: stamp, startedAt: startedAt, now: Date()) { self.makeMenu(nodes, kind: $0) }
            }
        }
    }

    /// `rh doctor --probe-extension` leaves a marker in the config folder; the extension then runs
    /// a probe through the runner, the same way a menu action would, so the result describes what a
    /// click can really do. The marker's text picks the probe from a fixed list; `rh probe
    /// --from-extension` removes the marker, which also keeps a second extension process (several
    /// run at once) from running it again. A request that has been lying there for minutes (the doctor was
    /// interrupted) is ignored.
    private func probeIfRequested() {
        guard let text = ProbeMarker.pending(in: paths) else { return }
        let arguments = RunnerArguments.probe(markerText: text)
        log.notice("probe \(arguments[1], privacy: .public) requested; running it through the runner script")
        runner(arguments, label: "probe.\(arguments[1])")
    }

    // MARK: Toolbar

    override var toolbarItemName: String { AppIdentity.productName }
    override var toolbarItemToolTip: String { currentConfigWithStamp().0.localizer.string(.toolbarTooltip) }
    override var toolbarItemImage: NSImage {
        NSImage(named: NSImage.Name(IconProvider.toolbarGlyph))
            ?? NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: AppIdentity.productName) ?? NSImage()
    }

    // MARK: Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let started = ContinuousClock.now
        let kind = Self.kind(menuKind)
        let context = currentContext(kind)
        let isSingleFolder = context.items.isEmpty || (context.items.count == 1 && facts.isDirectory(context.items[0]) == true)
        let (config, stamp) = currentConfigWithStamp()

        if isSingleFolder, let cached = folderMenus[kind] {
            switch MenuCachePolicy.freshness(builtAt: cached.builtAt, now: Date(), sameConfig: cached.stamp == stamp) {
            case .fresh:
                log.notice("menu \(kind.rawValue, privacy: .public): \(context.items.count, privacy: .public) items, served from cache in \(String(describing: ContinuousClock.now - started), privacy: .public)")
                return cached.menu.copy() as? NSMenu
            case .stale:
                // The click does not wait for what is installed to be asked again: the old menu is served and a new one is made meanwhile.
                warmupInBackground()
                log.notice("menu \(kind.rawValue, privacy: .public): \(context.items.count, privacy: .public) items, served from an old cache in \(String(describing: ContinuousClock.now - started), privacy: .public); building a new one")
                return cached.menu.copy() as? NSMenu
            case .unusable:
                break
            }
        }

        let nodes = FinderMenuPresentation.nodes(MenuBuilder(config: config, facts: facts, localizer: config.localizer).build(for: context), separators: showsSeparators)
        guard !nodes.isEmpty else { return nil }

        let menu = makeMenu(nodes, kind: kind)
        if isSingleFolder {
            folderMenus.store(menu, kind: kind, stamp: stamp, now: Date())
        }
        log.notice("menu \(kind.rawValue, privacy: .public): \(context.items.count, privacy: .public) items, built in \(String(describing: ContinuousClock.now - started), privacy: .public)")
        return menu
    }

    private static func kind(_ kind: FIMenuKind) -> FinderMenuKind {
        switch kind {
        case .contextualMenuForItems: return .items
        case .contextualMenuForContainer: return .container
        case .contextualMenuForSidebar: return .sidebar
        case .toolbarItemMenu: return .toolbar
        @unknown default: return .items
        }
    }

    private func currentContext(_ kind: FinderMenuKind) -> HereContext {
        let controller = FIFinderSyncController.default()
        return HereContext.finder(kind: kind, selected: controller.selectedItemURLs() ?? [], targeted: controller.targetedURL())
    }

    /// The config, re-read only when one of its two files (the config and the per-machine overlay) changed.
    private func currentConfigWithStamp() -> (config: Config, stamp: ConfigStore.Stamp) {
        let stamp = ConfigStore.stamp(paths: paths)
        if let cache = configCache, cache.stamp == stamp { return (cache.loaded.config, stamp) }
        let loaded = ConfigStore.load(paths: paths)
        configCache = (stamp, loaded)
        return (loaded.config, stamp)
    }

    private func makeMenu(_ nodes: [MenuNode], kind: FinderMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        for node in nodes {
            switch node.kind {
            case .separator:
                menu.addItem(.separator())
            case .action:
                let item = NSMenuItem(title: node.title, action: #selector(performAction(_:)), keyEquivalent: "")
                item.target = self
                item.tag = tags.tag(for: node.actionID ?? "", kind: kind)
                decorate(item, node.icon)
                menu.addItem(item)
            case .submenu:
                let item = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
                decorate(item, node.icon)
                item.submenu = makeMenu(node.children, kind: kind)
                menu.addItem(item)
            }
        }
        return menu
    }

    private func decorate(_ item: NSMenuItem, _ icon: Icon?) {
        guard let image = icons.image(for: icon) else { return }
        item.image = image
        #if compiler(>=6.4)
        // macOS 27 hides menu item images unless a menu asks for them.
        if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
        #endif
    }

    // MARK: Actions

    @objc func performAction(_ sender: AnyObject?) {
        guard let item = sender as? NSMenuItem, let entry = tags.resolve(item.tag) else {
            log.error("action without a matching menu entry")
            return
        }
        let id = entry.actionID
        let context = currentContext(entry.kind)
        log.notice("action \(id, privacy: .public) from \(entry.kind.rawValue, privacy: .public) menu, \(context.items.count, privacy: .public) items")
        if case .copyPath(let style)? = ActionRef(parsing: id) {
            copyPath(style, context)
        } else {
            runThroughRunner(id, context)
        }
    }

    private func copyPath(_ style: PathStyle, _ context: HereContext) {
        let targets = context.pathTargets
        guard !targets.isEmpty else { return }
        if let refusal = PathRenderer.shellFormRefusal(for: targets, style: style) {
            log.error("copy refused: \(refusal, privacy: .private)")
            NSSound.beep()
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(PathRenderer(facts: facts).render(targets, style: style), forType: .string)
    }

    private func runThroughRunner(_ id: String, _ context: HereContext) {
        runner(RunnerArguments.run(actionID: id, context: context), label: id)
    }

    /// Runs `rh` through the runner script, outside the sandbox.
    private func runner(_ arguments: [String], label id: String) {
        do {
            let directory = try FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let task = try NSUserUnixTask(url: directory.appendingPathComponent(AppIdentity.runnerScriptName))
            let errors = Pipe()
            task.standardError = errors.fileHandleForWriting
            let key = ObjectIdentifier(task)
            runningTasks[key] = task
            // Drained while the task runs: a task that fills the pipe's buffer would otherwise wait for a reader that
            // only starts when it has finished. Only the first few kilobytes are kept.
            let captured = CapturedOutput()
            errors.fileHandleForReading.readabilityHandler = { handle in captured.append(handle.availableData) }
            let owner = MainThreadOwner(self)
            task.execute(withArguments: arguments) { failure in
                try? errors.fileHandleForWriting.close()
                errors.fileHandleForReading.readabilityHandler = nil
                captured.append(errors.fileHandleForReading.availableData)
                let message = captured.text
                DispatchQueue.main.async {
                    let extensionObject = owner.object
                    extensionObject?.runningTasks[key] = nil
                    guard let failure else {
                        extensionObject?.log.notice("\(id, privacy: .public) finished ok")
                        return
                    }
                    // What `rh` printed can name the person's files, so it stays private in the unified log.
                    extensionObject?.log.error("\(id, privacy: .public) failed: \(message, privacy: .private) \(failure.localizedDescription, privacy: .private)")
                    NSSound.beep()
                }
            }
        } catch {
            log.error("runner script unavailable: \(error.localizedDescription, privacy: .public). Run `rh setup`.")
            NSSound.beep()
        }
    }
}

/// The start of a task's error output, kept to a few kilobytes; the rest is read and dropped.
private final class CapturedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        if data.count < 8_192 { data.append(chunk.prefix(8_192 - data.count)) }
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

/// A weak reference to the extension that is only ever read on the main queue, so it can be captured by the task's
/// completion handler (which the system calls on another thread) without making the extension itself Sendable.
private final class MainThreadOwner: @unchecked Sendable {
    private weak var target: FinderSyncExtension?
    init(_ target: FinderSyncExtension) { self.target = target }
    var object: FinderSyncExtension? { target }
}

