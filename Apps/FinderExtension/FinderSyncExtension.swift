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
    /// Action ids of the menu built last, indexed by menu item tag. Finder receives a copy of the
    /// menu, and only the tag survives the trip back to the action method.
    private var actionTable: [String] = []
    private var lastKind: FinderMenuKind = .items
    private var runningTasks: [ObjectIdentifier: NSUserUnixTask] = [:]

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: Toolbar

    override var toolbarItemName: String { AppIdentity.productName }
    override var toolbarItemToolTip: String { "Open here, copy a path, start an agent" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: AppIdentity.productName) ?? NSImage()
    }

    // MARK: Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let started = ContinuousClock.now
        let kind = Self.kind(menuKind)
        lastKind = kind
        let context = currentContext(kind)
        let nodes = MenuBuilder(config: currentConfig(), facts: facts).build(for: context)
        guard !nodes.isEmpty else { return nil }

        var table: [String] = []
        let menu = makeMenu(nodes, table: &table)
        actionTable = table
        log.debug("menu \(kind.rawValue, privacy: .public) built in \(String(describing: ContinuousClock.now - started), privacy: .public)")
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
        let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        if let cache = configCache, cache.modified == modified { return cache.loaded.config }
        let loaded = ConfigStore.load(paths: paths)
        configCache = (modified, loaded)
        return loaded.config
    }

    private func makeMenu(_ nodes: [MenuNode], table: inout [String]) -> NSMenu {
        let menu = NSMenu(title: "")
        for node in nodes {
            switch node.kind {
            case .separator:
                menu.addItem(.separator())
            case .action:
                let item = NSMenuItem(title: node.title, action: #selector(performAction(_:)), keyEquivalent: "")
                item.target = self
                item.tag = table.count
                table.append(node.actionID ?? "")
                decorate(item, node.icon)
                menu.addItem(item)
            case .submenu:
                let item = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
                decorate(item, node.icon)
                item.submenu = makeMenu(node.children, table: &table)
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
        guard let item = sender as? NSMenuItem, actionTable.indices.contains(item.tag) else {
            log.error("action without a matching menu entry")
            return
        }
        let id = actionTable[item.tag]
        let context = currentContext(lastKind)
        if case .copyPath(let style)? = ActionRef(parsing: id) {
            copyPath(style, context)
        } else {
            runThroughRunner(id, context)
        }
    }

    private func copyPath(_ style: PathStyle, _ context: HereContext) {
        let targets = context.pathTargets
        guard !targets.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(PathRenderer(facts: facts).render(targets, style: style), forType: .string)
    }

    private func runThroughRunner(_ id: String, _ context: HereContext) {
        var arguments = [id, "--origin", context.origin.rawValue]
        if let container = context.container { arguments += ["--container", container.path] }
        arguments.append("--")
        arguments += context.items.map(\.path)

        do {
            let directory = try FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let task = try NSUserUnixTask(url: directory.appendingPathComponent(AppIdentity.runnerScriptName))
            let errors = Pipe()
            task.standardError = errors.fileHandleForWriting
            let key = ObjectIdentifier(task)
            runningTasks[key] = task
            task.execute(withArguments: arguments) { [weak self] failure in
                try? errors.fileHandleForWriting.close()
                let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                DispatchQueue.main.async {
                    self?.runningTasks[key] = nil
                    guard let failure else { return }
                    self?.log.error("\(id, privacy: .public) failed: \(message, privacy: .public) \(failure.localizedDescription, privacy: .public)")
                    NSSound.beep()
                }
            }
        } catch {
            log.error("runner script unavailable: \(error.localizedDescription, privacy: .public). Run `rh install --scripts`.")
            NSSound.beep()
        }
    }
}
