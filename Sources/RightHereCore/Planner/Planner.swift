import Foundation

/// Turns an action and a context into a `LaunchPlan`. Pure: everything it needs about the
/// machine comes from `SystemFacts`, so the same inputs always give the same plan.
public struct Planner: Sendable {
    public let config: Config
    public let facts: any SystemFacts
    public let localizer: Localizer

    /// Preference order when no default is configured. Terminal.app is always present, so it comes
    /// last: a terminal the user installed on purpose is a better guess.
    static let terminalOrder = ["ghostty", "cmux", "iterm", "wezterm", "kitty", "alacritty", "warp", "terminal"]
    static let editorOrder = ["vscode", "cursor", "zed", "windsurf", "sublime", "nova", "bbedit", "intellij", "pycharm", "webstorm", "textedit"]

    public init(config: Config = .default, facts: any SystemFacts, localizer: Localizer = .english) {
        self.config = config
        self.facts = facts
        self.localizer = localizer
    }

    public func plan(_ ref: ActionRef, context: HereContext) throws -> LaunchPlan {
        // Every path the person or an agent named has to exist, whichever action it is for. A typo is
        // reported as one rather than quietly replaced by the folder around it (`open.terminal proj
        // proj-typo` would otherwise open `proj`'s parent), and text that is not a path never reaches the
        // clipboard, a terminal or another agent's prompt box.
        if case .user = ref {} else if let missing = context.firstMissingPath(facts: facts) { throw PlanError.pathNotFound(missing.path) }
        switch ref {
        case .copyPath(let style):
            return try copyPath(style, ref: ref, context: context)
        case .openTerminal(let id):
            return try openTerminal(id, ref: ref, context: context)
        case .openEditor:
            return try openApp(try resolveDefault(role: .editor, configured: config.editor), ref: ref, context: context)
        case .openApp(let id):
            guard let app = config.app(id: id) else { throw PlanError.unknownApp(id) }
            return try openApp(app, ref: ref, context: context)
        case .agent(let id, let variant, let launcher):
            return try launchAgent(id: id, variant: variant, launcher: launcher, ref: ref, context: context)
        case .newFile(let id):
            return try newFile(id, ref: ref, context: context)
        case .reveal:
            let paths = context.pathTargets.map(\.path)
            guard !paths.isEmpty else { throw PlanError.noTarget }
            return LaunchPlan(action: ref.id, summary: "Reveal in Finder", steps: [.reveal(paths)])
        case .user(let id):
            throw PlanError.unknownAction("user.\(id)")
        }
    }

    // MARK: Copy path

    private func copyPath(_ style: PathStyle, ref: ActionRef, context: HereContext) throws -> LaunchPlan {
        let targets = context.pathTargets
        guard !targets.isEmpty else { throw PlanError.noTarget }
        let text = PathRenderer(facts: facts).render(targets, style: style)
        let noun = targets.count == 1 ? "path" : "\(targets.count) paths"
        return LaunchPlan(action: ref.id, summary: "Copy \(noun) (\(style.rawValue))", steps: [.copyToPasteboard(text)])
    }

    /// The folder an action works in.
    private func workingDirectory(for context: HereContext) throws -> URL {
        guard let directory = context.workingDirectory(facts: facts) else { throw PlanError.noTarget }
        return directory
    }

    // MARK: Open with an app

    private func openApp(_ app: AppDescriptor, ref: ActionRef, context: HereContext) throws -> LaunchPlan {
        guard let bundleID = app.installedBundleID(facts: facts) else { throw PlanError.appNotInstalled(app.name) }
        let targets: [URL]
        if app.role == .terminal {
            let directory = try workingDirectory(for: context)
            targets = [directory]
        } else {
            targets = context.pathTargets
        }
        guard !targets.isEmpty else { throw PlanError.noTarget }
        return LaunchPlan(
            action: ref.id,
            summary: "Open \(targets.count == 1 ? targets[0].lastPathComponent : "\(targets.count) items") in \(app.name)",
            steps: [.open(OpenStep(bundleID: bundleID, targets: targets.map(\.path)))]
        )
    }

    // MARK: Terminals

    private func openTerminal(_ id: String?, ref: ActionRef, context: HereContext) throws -> LaunchPlan {
        let directory = try workingDirectory(for: context)
        let (app, bundleID) = try resolveTerminal(id)
        let steps = try TerminalAdapters.adapter(for: app)
            .steps(for: TerminalSession(directory: directory, placement: config.terminalPlacement), bundleID: bundleID, facts: facts)
        return LaunchPlan(action: ref.id, summary: "Open \(directory.lastPathComponent) in \(app.name)", steps: steps)
    }

    private func resolveTerminal(_ id: String?) throws -> (AppDescriptor, String) {
        let app: AppDescriptor
        if let id {
            guard let found = config.app(id: id), found.role == .terminal else { throw PlanError.unknownTerminal(id) }
            app = found
        } else {
            app = try resolveDefault(role: .terminal, configured: config.terminal)
        }
        guard let bundleID = app.installedBundleID(facts: facts) else { throw PlanError.appNotInstalled(app.name) }
        return (app, bundleID)
    }

    /// The app used when an action does not name one: the configured default, else the first
    /// installed one in a fixed preference order.
    public func resolveDefault(role: AppDescriptor.Role, configured: String?) throws -> AppDescriptor {
        if let configured {
            guard let app = config.app(id: configured) else { throw PlanError.unknownApp(configured) }
            // The config can redefine a built-in id with another role; a terminal that is now an editor (or
            // the reverse) is not what the setting asked for, and `rh actions` already says so.
            if role == .terminal, app.role != .terminal {
                throw PlanError.unsupported("\(app.name) is not a terminal. Use open.app.\(app.id) to open files with it.")
            }
            if role == .editor, app.role == .terminal {
                throw PlanError.unsupported("\(app.name) is a terminal, not an editor. Use open.terminal@\(app.id) to open a folder in it.")
            }
            return app
        }
        let order = role == .terminal ? Self.terminalOrder : Self.editorOrder
        let candidates = order.compactMap { config.app(id: $0) } + config.apps.filter { $0.role == role }
        guard let app = candidates.first(where: { $0.installedBundleID(facts: facts) != nil }) else {
            throw PlanError.appNotInstalled(role == .terminal ? "A terminal" : "An editor")
        }
        return app
    }

    // MARK: Agents

    private func launchAgent(id: String, variant variantID: String?, launcher: AgentLauncher?, ref: ActionRef, context: HereContext) throws -> LaunchPlan {
        guard let agent = config.agent(id: id) else { throw PlanError.unknownAgent(id) }
        var variant: AgentDescriptor.Variant?
        if let variantID {
            guard let found = agent.variants.first(where: { $0.id == variantID }) else {
                throw PlanError.unknownVariant(agent: id, variant: variantID)
            }
            variant = found
        }
        let directory = try workingDirectory(for: context)
        let resolved = config.launcher(forAgent: id, explicit: launcher, hasVariant: variant != nil)
        if let conflict = resolved.conflict { throw PlanError.unsupported(conflict) }
        let chosen = resolved.launcher

        switch chosen {
        case .desktop:
            guard let link = agent.desktopLink else {
                throw PlanError.unsupported("\(agent.name) has no desktop app link.")
            }
            let url = Self.expand(link, directory: directory, prompt: "")
            return LaunchPlan(action: ref.id, summary: "Open \(agent.name) desktop in \(directory.lastPathComponent)", steps: [.openURL(url)])

        case .terminalLink:
            guard let link = agent.terminalLink else {
                throw PlanError.unsupported("\(agent.name) has no terminal link. Use a terminal launcher instead.")
            }
            let url = Self.expand(link, directory: directory, prompt: mentionPrefill(context: context, directory: directory))
            return LaunchPlan(action: ref.id, summary: "Open \(agent.name) in \(directory.lastPathComponent)", steps: [.openURL(url)])

        case .terminal(let terminalID):
            let typed = ([agent.command] + (variant?.arguments ?? [])).joined(separator: " ")
            do { try ShellQuoting.validateForTyping(typed) } catch { throw PlanError.unsafeText(typed) }
            do { try ShellQuoting.validateForTyping(directory.path) } catch { throw PlanError.unsafeText(directory.path) }
            let (app, bundleID) = try resolveTerminal(terminalID)
            let steps = try TerminalAdapters.adapter(for: app)
                .steps(for: TerminalSession(directory: directory, typedInput: typed, placement: config.terminalPlacement), bundleID: bundleID, facts: facts)
            return LaunchPlan(
                action: ref.id,
                summary: "Run \(typed) in \(directory.lastPathComponent) with \(app.name)",
                steps: steps
            )
        }
    }

    /// Selected files become `@` mentions in the prompt box; nothing is sent.
    private func mentionPrefill(context: HereContext, directory: URL) -> String {
        let files = context.items.filter { facts.isDirectory($0) == false }
        guard !files.isEmpty else { return "" }
        return PathRenderer(facts: facts).render(files, style: .aiMention, relativeTo: directory) + " "
    }

    static func expand(_ link: AgentDescriptor.Link, directory: URL, prompt: String) -> String {
        var url = link.template.replacingOccurrences(of: "{dir}", with: percentEncode(directory.path))
        if let parameter = link.promptParameter, !prompt.isEmpty {
            url += (url.contains("?") ? "&" : "?") + "\(parameter)=\(percentEncode(prompt))"
        }
        return url
    }

    /// Everything except RFC 3986 unreserved characters is encoded, so no path can end a query value early.
    static func percentEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    // MARK: New file

    private func newFile(_ id: String, ref: ActionRef, context: HereContext) throws -> LaunchPlan {
        let directory = try workingDirectory(for: context)
        guard let template = config.newFile.templates.first(where: { $0.id == id }) else { throw PlanError.unknownTemplate(id) }
        guard let name = NewFileNamer.uniqueName(for: template, in: directory, facts: facts, localizer: localizer) else { throw PlanError.nameExhausted }
        let path = directory.appendingPathComponent(name).path

        var steps: [Step] = [.createFile(CreateFileStep(path: path, contents: template.contents))]
        switch config.newFile.then {
        case .reveal:
            steps.append(.reveal([path]))
        case .open:
            let chosen = template.openWith.flatMap(config.app(id:)).flatMap { $0.installedBundleID(facts: facts) != nil ? $0 : nil }
            let editor = chosen ?? (try? resolveDefault(role: .editor, configured: config.editor))
            steps.append(.open(OpenStep(bundleID: editor?.installedBundleID(facts: facts), targets: [path])))
        case .nothing:
            break
        }
        return LaunchPlan(action: ref.id, summary: "Create \(name)", steps: steps)
    }
}
