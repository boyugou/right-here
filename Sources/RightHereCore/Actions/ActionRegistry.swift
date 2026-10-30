import Foundation

/// What is known about one action without running it.
public struct ActionInfo: Sendable, Equatable, Codable {
    public var id: String
    /// Full title for a flat list, for example "Open in Ghostty".
    public var title: String
    /// Title inside the group submenu it belongs to, for example "Full Path".
    public var shortTitle: String
    public var group: String
    public var icon: Icon?
    public var available: Bool
    public var unavailableReason: String?
    /// The reason as a sentence of the catalog, for the window, when it is one a person meets (a terminal that only opens folders, an app
    /// that is not installed); `nil` for the others, whose English `unavailableReason` is shown. Not in the JSON, which has the English.
    public var unavailableMessage: LocalizedMessage? = nil

    private enum CodingKeys: String, CodingKey {
        case id, title, shortTitle, group, icon, available, unavailableReason
    }
}

/// Describes actions: titles, icons and whether they can run on this machine.
public struct ActionRegistry: Sendable {
    public let config: Config
    public let facts: any SystemFacts
    public let localizer: Localizer

    private var defaults: DefaultApps { DefaultApps(config: config, facts: facts) }

    public init(config: Config, facts: any SystemFacts, localizer: Localizer = .english) {
        self.config = config
        self.facts = facts
        self.localizer = localizer
    }

    /// The name shown for an app: what the system calls it in the person's language when the menu
    /// is localized, otherwise the catalog name.
    private func name(of app: AppDescriptor) -> String {
        guard localizer.resolvedLanguage != "en", let bundleID = app.installedBundleID(facts: facts) else { return app.name }
        return facts.displayName(bundleID: bundleID) ?? app.name
    }

    public func info(_ ref: ActionRef) -> ActionInfo {
        var info = ActionInfo(id: ref.id, title: ref.id, shortTitle: ref.id, group: "", icon: nil, available: true, unavailableReason: nil)
        switch ref {
        case .copyPath(let style):
            info.group = "copy-path"
            info.title = localizer.copyPathTitle(style)
            info.shortTitle = localizer.copyPath(style)
            info.icon = .symbol("doc.on.doc")

        case .openTerminal(let id):
            info.group = "open"
            describeApp(&info, terminal: id)

        case .openEditor:
            info.group = "open"
            switch defaultApp(.editor, configured: config.editor) {
            case .success(let app): describeApp(&info, app: app)
            case .failure(let error): unavailable(&info, title: localizer.openIn("Editor"), reason: error.message)
            }

        case .openApp(let id):
            info.group = "open"
            if let app = config.app(id: id) {
                describeApp(&info, app: app)
            } else {
                unavailable(&info, title: localizer.openIn(id), reason: PlanError.unknownApp(id).message)
            }

        case .agent(let id, let variantID, let launcher):
            info.group = "agent"
            describeAgent(&info, id: id, variantID: variantID, launcher: launcher)

        case .preset(let id, let terminal):
            info.group = "preset"
            describePreset(&info, id: id, terminal: terminal)

        case .newFile(let id):
            info.group = "new-file"
            if let template = config.newFile.templates.first(where: { $0.id == id }) {
                info.title = template.localizedNewTitle(localizer)
                info.shortTitle = template.localizedTitle(localizer)
                // The icon of the kind of file it makes: a Markdown document and a text document are told apart at a glance.
                info.icon = template.fileExtension.isEmpty ? .symbol("doc.badge.plus") : .fileType(template.fileExtension)
            } else {
                unavailable(&info, title: localizer.newFile(id), reason: "Unknown template \"\(id)\".")
            }

        case .reveal:
            info.group = "reveal"
            info.title = localizer.revealInFinder
            info.shortTitle = localizer.revealInFinder
            info.icon = .symbol("magnifyingglass")
        }
        return info
    }

    /// `info` for an action about to be offered in a menu: a preset also needs something to run on and, when its prompt
    /// names files, a selection of the right size that is not only folders.
    ///
    /// The size is counted without looking at the items. Whether they are folders is asked only when the count already
    /// fits, so at most `max_files` (50 at the most) items are looked at, and only until one is not known to be a folder.
    /// This is the one place a menu asks the file system about the selection: a menu that offers a preset on a selected
    /// folder offers what `rh` then refuses. An item that cannot be told (a path the system will not let us look at, a
    /// link that points nowhere) keeps the preset in the menu: it is hidden only when every item is known to be a folder,
    /// and `rh` says why when it cannot run.
    public func info(_ ref: ActionRef, context: HereContext) -> ActionInfo {
        var info = info(ref)
        guard info.available, case .preset(let id, _) = ref, let preset = config.preset(id: id) else { return info }
        if context.items.isEmpty, context.container == nil, context.origin != .cli {
            unavailable(&info, reason: "There is no folder to run in.")
        } else if let refusal = preset.refusal(forFileCount: context.items.count) {
            unavailable(&info, reason: refusal)
        } else if !context.items.isEmpty, let refusal = preset.refusal(forFileCount: 0), context.items.allSatisfy({ facts.isDirectory($0) == true }) {
            // The refusal for no file at all is the planner's own sentence, and it is nil for a prompt that names no files.
            unavailable(&info, reason: refusal)
        }
        return info
    }

    // MARK: Descriptions

    private func describePreset(_ info: inout ActionInfo, id: String, terminal terminalID: String?) {
        guard let preset = config.preset(id: id) else {
            unavailable(&info, title: id, reason: "Unknown preset \"\(id)\".")
            return
        }
        let presetTitle = preset.localizedTitle(localizer)
        info.title = presetTitle
        info.shortTitle = presetTitle
        if let refusal = AgentPreset.launcherRefusal(terminalID) {
            unavailable(&info, reason: refusal)
            return
        }
        if let refusal = config.presetAgentRefusal(preset) {
            unavailable(&info, reason: refusal)
            return
        }
        guard let agent = config.agent(for: preset) else { return }
        info.title = localizer.agentVariant(agent.name, presetTitle)
        info.icon = icon(of: agent)
        let resolution = AgentLaunchResolution.resolve(agent: agent, hasVariant: true, explicit: terminalID.map { .terminal($0) }, config: config, facts: facts)
        if case .failure(let why) = resolution.route { unavailable(&info, reason: why.text, message: why.message) }
    }

    private func describeApp(_ info: inout ActionInfo, terminal id: String?) {
        do throws(PlanError) {
            describeApp(&info, app: try defaults.terminal(id: id))
        } catch {
            unavailable(&info, title: localizer.openIn(id ?? "Terminal"), reason: error.message)
        }
    }

    private func describeApp(_ info: inout ActionInfo, app: AppDescriptor) {
        info.title = localizer.openIn(name(of: app))
        info.shortTitle = name(of: app)
        if let bundleID = app.installedBundleID(facts: facts) {
            info.icon = .app(bundleID)
        } else {
            info.available = false
            info.unavailableReason = PlanError.appNotInstalled(app.name).message
            info.unavailableMessage = .doctorAppNotInstalled(app.name)
        }
    }

    private func describeAgent(_ info: inout ActionInfo, id: String, variantID: String?, launcher: AgentLauncher?) {
        guard let agent = config.agent(id: id) else {
            unavailable(&info, title: localizer.agentHere(id), reason: "Unknown agent \"\(id)\".")
            return
        }
        var variant: AgentDescriptor.Variant?
        if let variantID {
            guard let found = agent.variants.first(where: { $0.id == variantID }) else {
                unavailable(&info, title: localizer.agentHere(agent.name), reason: "\(agent.name) has no variant \"\(variantID)\".")
                return
            }
            variant = found
        }
        info.icon = icon(of: agent)

        // Titles follow the launcher whether or not it can start; availability is the resolution's.
        let resolution = AgentLaunchResolution.resolve(agent: agent, hasVariant: variant != nil, explicit: launcher, config: config, facts: facts)
        switch resolution.launcher {
        case .desktop:
            info.title = localizer.agentDesktop(agent.name)
            info.shortTitle = info.title
        case .terminalLink:
            info.title = localizer.agentLink(agent.name)
            info.shortTitle = info.title
        case .terminal(let terminalID):
            let terminalName = terminalID.flatMap { config.terminalApp(id: $0) }.map(name(of:)) ?? terminalID ?? ""
            if let variant {
                let variantTitle = variant.localizedTitle(localizer)
                info.title = terminalID == nil ? localizer.agentVariant(agent.name, variantTitle) : localizer.agentVariantIn(agent.name, variantTitle, terminal: terminalName)
                info.shortTitle = variantTitle
            } else {
                info.title = terminalID == nil ? localizer.agentHere(agent.name) : localizer.agentIn(agent.name, terminal: terminalName)
                info.shortTitle = info.title
            }
        }
        if case .failure(let why) = resolution.route {
            unavailable(&info, reason: why.text, message: why.message)
        } else if case .terminal = resolution.launcher, case .failure(let why) = AgentLaunchResolution.typedLine(agent: agent, variant: variant, options: config.launchOptions(for: agent)) {
            unavailable(&info, reason: why.text, message: why.message)
        }
    }

    /// The agent's own app icon when that app is installed, else a terminal symbol.
    private func icon(of agent: AgentDescriptor) -> Icon {
        agent.iconBundleID.flatMap { facts.applicationURL(bundleID: $0) != nil ? Icon.app($0) : nil } ?? .symbol("terminal")
    }

    private func unavailable(_ info: inout ActionInfo, title: String? = nil, reason: String, message: LocalizedMessage? = nil) {
        if let title {
            info.title = title
            info.shortTitle = title
        }
        info.available = false
        info.unavailableReason = reason
        // A message whose English is the reason itself says nothing more; the window shows the reason.
        info.unavailableMessage = message?.key == .doctorVerbatim ? nil : message
    }

    // MARK: Defaults

    private func defaultApp(_ role: AppDescriptor.Role, configured: String?) -> Result<AppDescriptor, PlanError> {
        do throws(PlanError) { return .success(try defaults.resolve(role: role, configured: configured)) } catch { return .failure(error) }
    }

    // MARK: Catalog

    /// The canonical set of actions on this machine, for `rh actions` and documentation. Terminal
    /// choices for agents are patterns (`agent.<id>@<terminal>`) and are not enumerated.
    /// The catalog id closest to a mistyped one ("copy-path.absolut"), if any is near.
    public func closestID(to word: String) -> String? {
        Suggestion.closest(to: word, in: catalog().map(\.id))
    }

    /// Reads an action id typed by a person or an agent. A word that is not an id comes back as an error that
    /// names the closest real id, so every surface says it the same way.
    public func resolve(_ id: String) throws -> ActionRef {
        guard let ref = ActionRef(parsing: id) else { throw UnknownActionID(id: id, suggestion: closestID(to: id)) }
        return ref
    }

    public func catalog() -> [ActionInfo] {
        var refs: [ActionRef] = []
        refs += PathStyle.allCases.map { .copyPath($0) }
        refs.append(.openTerminal(nil))
        refs += config.allApps.filter { $0.role == .terminal }.map { .openTerminal($0.id) }
        refs.append(.openEditor)
        refs += config.allApps.filter { $0.role != .terminal }.map { .openApp($0.id) }
        // An agent that this Mac turns off is not offered: what names it is left out of every list of the config, so an action added for it would never be shown.
        for agent in (config.customAgents + KnownAgents.all).filter({ !config.disabledAgents.contains($0.id) }).map({ config.agent(id: $0.id) ?? $0 }) {
            refs.append(.agent(id: agent.id, variant: nil, launcher: nil))
            refs += agent.variants.map { .agent(id: agent.id, variant: $0.id, launcher: nil) }
            if agent.desktopLink != nil { refs.append(.agent(id: agent.id, variant: nil, launcher: .desktop)) }
            if agent.terminalLink != nil { refs.append(.agent(id: agent.id, variant: nil, launcher: .terminalLink)) }
        }
        refs += config.presets.map { .preset(id: $0.id, terminal: nil) }
        refs += config.newFile.templates.map { .newFile($0.id) }
        refs.append(.reveal)

        var seen = Set<String>()
        return refs.filter { seen.insert($0.id).inserted }.map(info)
    }
}
