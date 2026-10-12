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

    private var configCache: (modified: Date?, loaded: LoadedConfig)?
    /// Finder receives a copy of each menu, and only the tag survives the trip back to the action method.
    /// The tags are stable (see `ActionTags`), so a menu built after the one being clicked cannot retarget it.
    private var tags = ActionTags()
    private var runningTasks: [ObjectIdentifier: NSUserUnixTask] = [:]

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        probeIfRequested()
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
    override var toolbarItemToolTip: String { Localizer.system.string(.toolbarTooltip) }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: AppIdentity.productName) ?? NSImage()
    }

    // MARK: Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let started = ContinuousClock.now
        let kind = Self.kind(menuKind)
        let context = currentContext(kind)
        let nodes = MenuBuilder(config: currentConfig(), facts: facts, localizer: .system).build(for: context)
        guard !nodes.isEmpty else { return nil }

        let menu = makeMenu(nodes, kind: kind)
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

    /// The config, re-read only when the file changed.
    private func currentConfig() -> Config {
        let file = paths.configFile
        // Of what the path leads to: for a config kept as a link (dotfile managers do that), the link's own date never changes.
        let modified = (try? FileManager.default.attributesOfItem(atPath: file.resolvingSymlinksInPath().path))?[.modificationDate] as? Date
        if let cache = configCache, cache.modified == modified { return cache.loaded.config }
        let loaded = ConfigStore.load(paths: paths)
        configCache = (modified, loaded)
        return loaded.config
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
            log.error("runner script unavailable: \(error.localizedDescription, privacy: .public). Run `rh install --scripts`.")
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

