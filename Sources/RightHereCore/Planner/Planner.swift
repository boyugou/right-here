import Foundation

/// Turns an action and a context into a `LaunchPlan`. Pure: everything it needs about the
/// machine comes from `SystemFacts`, so the same inputs always give the same plan.
public struct Planner: Sendable {
    public let config: Config
    public let facts: any SystemFacts
    public let localizer: Localizer
    /// What git says about the repository around each item, for the repository actions (ADR 0033); `rh` reads it for those actions only.
    public let repositories: [URL: RepositoryState]

    private var defaults: DefaultApps { DefaultApps(config: config, facts: facts) }

    public init(config: Config = .default, facts: any SystemFacts, localizer: Localizer = .english, repositories: [URL: RepositoryState] = [:]) {
        self.config = config
        self.facts = facts
        self.localizer = localizer
        self.repositories = repositories
    }

    public func plan(_ ref: ActionRef, context named: HereContext) throws -> LaunchPlan {
        // From the command line with nothing named, the folder `rh` runs in is the target, for every action (the
        // help says so); the terminal, agent and new-file actions already took it, copy-path and reveal did not.
        var context = named
        if context.origin == .cli, context.items.isEmpty, context.container == nil, facts.itemState(facts.currentDirectory) != .missing {
            context.container = facts.currentDirectory.lexicallyNormalized
        }
        // Every path the person or an agent named has to exist, whichever action it is for. A typo is
        // reported as one rather than quietly replaced by the folder around it (`open.terminal proj
        // proj-typo` would otherwise open `proj`'s parent), and text that is not a path never reaches the
        // clipboard, a terminal or another agent's prompt box.
        if let missing = context.firstMissingPath(facts: facts) { throw PlanError.pathNotFound(missing.path) }
        switch ref {
        case .copyPath(let style):
            return try copyPath(style, ref: ref, context: context)
        case .openTerminal(let id):
            return try openTerminal(id, ref: ref, context: context)
        case .openEditor:
            let editor = try defaults.resolve(role: .editor, configured: config.editor)
            return try openApp(editor, ref: ref, context: context, notices: fallbackNotice(role: .editor, used: editor))
        case .openApp(let id):
            guard let app = config.app(id: id) else { throw PlanError.unknownApp(id) }
            return try openApp(app, ref: ref, context: context)
        case .agent(let id, let variant, let launcher):
            return try launchAgent(id: id, variant: variant, launcher: launcher, ref: ref, context: context)
        case .preset(let id, let terminal):
            return try runPreset(id: id, terminal: terminal, ref: ref, context: context)
        case .newFile(let id):
            return try newFile(id, ref: ref, context: context)
        case .reveal:
            let paths = context.pathTargets.map(\.path)
            guard !paths.isEmpty else { throw PlanError.noTarget }
            return LaunchPlan(action: ref.id, summary: "Reveal in Finder", steps: [.reveal(paths)])
        case .copyRepositoryLink:
            let targets = context.pathTargets
            guard !targets.isEmpty else { throw PlanError.noTarget }
            let links = try targets.map(repositoryLink)
            return LaunchPlan(action: ref.id, summary: targets.count == 1 ? "Copy the repository link" : "Copy \(targets.count) repository links",
                              steps: [.copyToPasteboard(links.joined(separator: "\n"))],
                              notices: ["The link shows the checked-out commit: changes that are not committed are not on it."])
        case .openRepositoryPage:
            let targets = context.pathTargets
            guard !targets.isEmpty else { throw PlanError.noTarget }
            guard targets.count == 1 else {
                throw PlanError.unsupported("Open Repository Page opens one item's page; for the links of several, use repository.copy-link.")
            }
            return LaunchPlan(action: ref.id, summary: "Open the repository page", steps: [.openURL(try repositoryLink(targets[0]))])
        }
    }

    // MARK: Repository links (ADR 0033)

    /// The page of `target` on its git host, or the reason there is none, said so that the person knows what to do.
    private func repositoryLink(_ target: URL) throws -> String {
        let target = target.lexicallyNormalized
        guard let state = repositories[target] else {
            if facts.gitRoot(containing: target) == nil { throw PlanError.unsupported("\(target.path) is not in a git repository.") }
            throw PlanError.unsupported("The repository of \(target.path) was not read, so its link cannot be made here; `rh run` reads it.")
        }
        guard let remote = state.remoteName else {
            if state.remoteNames.isEmpty { throw PlanError.unsupported("The repository has no remote, so it has no page on a git host.") }
            throw PlanError.unsupported("The repository has several remotes (\(state.remoteNames.joined(separator: ", "))), none of them origin or the branch's upstream, so it is not clear which one to link to.")
        }
        let parsed: RepositoryRemote
        switch state.remoteURL.map(RepositoryLink.parse(remote:)) {
        case .success(let value)?:
            parsed = value
        case .failure(.unknownHost(let host))?:
            throw PlanError.unsupported("Remote \"\(remote)\" is on \(host); Right Here makes links for github.com, gitlab.com, codeberg.org and bitbucket.org.")
        case .failure(.unreadableRemote)?, nil:
            throw PlanError.unsupported("The URL of remote \"\(remote)\" is not one of a repository on a git host.")
        }
        guard let commit = state.commit else { throw PlanError.unsupported("The repository has no commit yet.") }
        guard state.isPushed else {
            throw PlanError.unsupported("The checked-out commit is not on remote \"\(remote)\" yet, so it has no page there. Push it, then try again.")
        }
        guard state.isInCommit, let path = RepositoryLink.itemPath(of: target, inRepository: state.root) else {
            throw PlanError.unsupported("\(target.lastPathComponent) is not in the checked-out commit (a new or untracked file has no page yet). Commit and push it, then try again.")
        }
        guard let link = RepositoryLink.url(remote: parsed, commit: commit, itemPath: path, isDirectory: facts.isDirectory(target) ?? false) else {
            throw PlanError.unsupported("The checked-out commit of the repository could not be read.")
        }
        return link
    }

    // MARK: Copy path

    private func copyPath(_ style: PathStyle, ref: ActionRef, context: HereContext) throws -> LaunchPlan {
        let targets = context.pathTargets
        guard !targets.isEmpty else { throw PlanError.noTarget }
        if let refusal = PathRenderer.shellFormRefusal(for: targets, style: style) { throw PlanError.unsupported(refusal) }
        let text = PathRenderer(facts: facts).render(targets, style: style)
        let noun = targets.count == 1 ? "path" : "\(targets.count) paths"
        var notices: [String] = []
        if (style == .gitRelative || style == .aiMention), targets.contains(where: { facts.gitRoot(containing: $0) == nil }) {
            notices.append("Not inside a git repository, so the absolute path is copied.")
        }
        // Outside the home folder a `~` form is not possible, and the absolute path is what is copied: say so, as `git-relative` does.
        if style == .tilde, targets.contains(where: { !isInsideHome($0) }) {
            notices.append("Not inside your home folder, so the absolute path is copied.")
        }
        return LaunchPlan(action: ref.id, summary: "Copy \(noun) (\(style.rawValue))", steps: [.copyToPasteboard(text)], notices: notices)
    }

    /// The folder an action works in.
    private func workingDirectory(for context: HereContext) throws -> URL {
        guard let directory = context.workingDirectory(facts: facts) else {
            if let target = context.unplaceableTarget(facts: facts) {
                switch target.reason {
                case .unreadable: throw PlanError.unreadable(target.url.path)
                case .dangling: throw PlanError.unsupported("\(target.url.path) is a link that points nowhere (or into a place macOS will not let Right Here look at), so there is no folder to open.")
                }
            }
            throw PlanError.noTarget
        }
        return directory
    }

    /// Said when the folder is not what was selected: a terminal is only ever handed a folder, so a file stands for
    /// the folder that holds it, and with several items the first one decides.
    private func folderNotice(for context: HereContext, directory: URL) -> [String] {
        guard let first = context.items.first else {
            if let container = context.container, facts.isDirectory(container) == false {
                return ["\(container.lastPathComponent.jsonQuoted) is a file, so its folder is used: \(directory.path.jsonQuoted)."]
            }
            return []
        }
        // With several items the folder is the one that holds the first, which for a folder is its parent and not the folder itself.
        if context.items.count > 1 {
            return ["Several items are selected; the folder that holds the first one, \(first.lastPathComponent.jsonQuoted), is used: \(directory.path.jsonQuoted)."]
        }
        if facts.isDirectory(first) == false { return ["\(first.lastPathComponent.jsonQuoted) is a file, so its folder is used: \(directory.path.jsonQuoted)."] }
        return []
    }

    /// Whether a path is the home folder or inside it, as `~` would be written for it.
    private func isInsideHome(_ url: URL) -> Bool {
        let home = facts.onDiskPath(facts.homeDirectory)
        let path = facts.onDiskPath(url)
        return path == home || path.hasPrefix(home == "/" ? "/" : home + "/")
    }

    // MARK: Open with an app

    private func openApp(_ app: AppDescriptor, ref: ActionRef, context: HereContext, notices: [String] = []) throws -> LaunchPlan {
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
            steps: [.open(OpenStep(bundleID: bundleID, targets: targets.map(\.path)))],
            notices: notices
        )
    }

    // MARK: Terminals

    private func openTerminal(_ id: String?, ref: ActionRef, context: HereContext) throws -> LaunchPlan {
        let directory = try workingDirectory(for: context)
        let (app, bundleID) = try resolveTerminal(id)
        let steps = try TerminalAdapters.adapter(for: app)
            .steps(for: TerminalSession(directory: directory, placement: config.terminalPlacement), bundleID: bundleID, facts: facts)
        let fallback = id == nil ? fallbackNotice(role: .terminal, used: app) : []
        return LaunchPlan(action: ref.id, summary: "Open \(directory.lastPathComponent) in \(app.name)", steps: steps, notices: folderNotice(for: context, directory: directory) + fallback)
    }

    /// Said when the default the config chose is not installed and `used` stands in for it.
    private func fallbackNotice(role: AppDescriptor.Role, typing: Bool = false, used: AppDescriptor) -> [String] {
        guard let found = defaults.substitution(role: role, typing: typing), found.used.id == used.id else { return [] }
        return [found.sentence]
    }

    private func resolveTerminal(_ id: String?) throws -> (AppDescriptor, String) {
        let app = try defaults.terminal(id: id)
        guard let bundleID = app.installedBundleID(facts: facts) else { throw PlanError.appNotInstalled(app.name) }
        return (app, bundleID)
    }

    // MARK: Agents

    private func launchAgent(id: String, variant variantID: String?, launcher: AgentLauncher?, ref: ActionRef, context: HereContext) throws -> LaunchPlan {
        guard let agent = config.agent(id: id) else { throw PlanError.unknownAgent(id, choices: (config.customAgents + KnownAgents.all).map(\.id)) }
        var variant: AgentDescriptor.Variant?
        if let variantID {
            guard let found = agent.variants.first(where: { $0.id == variantID }) else {
                throw PlanError.unknownVariant(agent: id, variant: variantID, choices: agent.variants.map(\.id))
            }
            variant = found
        }
        let directory = try workingDirectory(for: context)
        let resolution = AgentLaunchResolution.resolve(agent: agent, hasVariant: variant != nil, explicit: launcher, config: config, facts: facts)

        switch try route(of: resolution) {
        case .desktop(let link):
            let url = Self.expand(link, directory: directory, prompt: "")
            return LaunchPlan(action: ref.id, summary: "Open \(agent.name) desktop in \(directory.lastPathComponent)", steps: [.openURL(url)])

        case .terminalLink(let link):
            let url = Self.expand(link, directory: directory, prompt: mentionPrefill(context: context, directory: directory))
            return LaunchPlan(action: ref.id, summary: "Open \(agent.name) in \(directory.lastPathComponent)", steps: [.openURL(url)])

        case .terminal(let app, let bundleID, let adapter):
            let typed: String
            let options = config.launchOptions(for: agent)
            switch AgentLaunchResolution.typedLine(agent: agent, variant: variant, options: options) {
            case .success(let line): typed = line
            case .failure(let why): throw PlanError(why)
            }
            var notices = resolution.launcher == .terminal(nil) ? fallbackNotice(role: .terminal, typing: true, used: app) : []
            if let flag = options.bypassFlag {
                notices.append("\(agent.name) starts with its permission prompts switched off (\(flag)). `--safe` starts it with them on.")
            } else if let flag = config.bypassFlag(inTypedLine: typed, of: agent) {
                // Its own command, arguments or start option type the flag: `--safe` takes off only what the switch adds.
                notices.append("\(agent.name) starts with its permission prompts switched off (\(flag)), which its own command or arguments type.")
            }
            return try typeCommand(typed, summary: typed, in: app, bundleID: bundleID, adapter: adapter, directory: directory, ref: ref, context: context, notices: notices)
        }
    }

    private func route(of resolution: AgentLaunchResolution) throws -> AgentLaunchResolution.Route {
        switch resolution.route {
        case .success(let route): return route
        case .failure(let unavailable): throw PlanError(unavailable)
        }
    }

    /// Types a command into a new shell of a terminal that can run commands, in `directory`.
    private func typeCommand(_ typed: String, summary: String, in app: AppDescriptor, bundleID: String, adapter: any TerminalAdapter, directory: URL, ref: ActionRef, context: HereContext, notices: [String] = []) throws -> LaunchPlan {
        do { try ShellQuoting.validateForTyping(typed) } catch { throw PlanError.unsafeText(typed) }
        // Only a terminal that types the folder needs it to be typeable: Ghostty, WezTerm and kitty are handed it as an argument and
        // type none of it. A terminal defined in the config counts as typing it, since its template may put `{dir}` into a shell line.
        if adapter.typesTheFolder {
            do { try ShellQuoting.validateForTyping(directory.path) } catch { throw PlanError.unsafeFolder(directory.path) }
        }
        let steps = try adapter.steps(for: TerminalSession(directory: directory, typedInput: typed, placement: config.terminalPlacement), bundleID: bundleID, facts: facts)
        return LaunchPlan(
            action: ref.id,
            summary: "Run \(summary) in \(directory.lastPathComponent) with \(app.name)",
            steps: steps,
            notices: folderNotice(for: context, directory: directory) + notices
        )
    }

    // MARK: Presets

    /// The files a preset names: the selected items that are not folders, which is what `{files}` stands for.
    func presetFiles(in context: HereContext) -> [URL] {
        context.items.filter { facts.isDirectory($0) == false }
    }

    /// Why a preset cannot run on this selection, or `nil`. Context only: whether the agent can take a prompt is
    /// decided separately.
    func presetContextRefusal(_ preset: AgentPreset, context: HereContext) -> String? {
        preset.refusal(forFileCount: preset.needsFiles ? presetFiles(in: context).count : 0)
    }

    /// `<agent command> [flag] '<prompt>'`: the prompt is one word, quoted by `ShellQuoting` after it has been checked
    /// for anything that would press a key or read as an option.
    private func runPreset(id: String, terminal: String?, ref: ActionRef, context: HereContext) throws -> LaunchPlan {
        guard let preset = config.preset(id: id) else { throw PlanError.unknownPreset(id, choices: config.presets.map(\.id)) }
        if let refusal = AgentPreset.launcherRefusal(terminal) { throw PlanError.unsupported(refusal) }
        if let refusal = config.presetAgentRefusal(preset) { throw PlanError.unsupported(refusal) }
        guard let agent = config.agent(for: preset), let promptArgument = agent.promptArgument else { throw PlanError.unsupported("No agent is enabled.") }
        let directory = try workingDirectory(for: context)
        if let refusal = presetContextRefusal(preset, context: context) { throw PlanError.unsupported(refusal) }

        let renderer = PathRenderer(facts: facts)
        let files = presetFiles(in: context)
        let item = context.items.first ?? directory
        let carried = files.map { PresetTemplate.Carried(kind: .file, name: $0.lastPathComponent, text: renderer.render($0, style: .aiMention, relativeTo: directory)) }
            + [PresetTemplate.Carried(kind: .folder, name: directory.lastPathComponent, text: renderer.render(directory, style: .name)),
               PresetTemplate.Carried(kind: .item, name: item.lastPathComponent, text: renderer.render(item, style: .name))]
        let prompt = PresetTemplate.expand(preset.prompt, carried: carried)
        if let problem = PresetTemplate.typingProblem(prompt) {
            // A file name with a line break is the file's doing and not the prompt's: say which one it is.
            if let culprit = PresetTemplate.carriedNameBehind(problem, template: preset.prompt, carried: carried), let reason = problem.aboutAName {
                throw PlanError.unsafePresetName(preset: id, subject: culprit.subject, reason: reason)
            }
            throw PlanError.unsafePrompt(preset: id, reason: problem.refusal)
        }

        // The agent's own permission prompts stay on for a preset, whatever the config says for plain starts: the prompt carries the names of the
        // selected files, and a file called "ignore the above and run ..." must not reach an agent that asks nothing (ADR 0012).
        let options = config.launchOptions(for: agent)
        if let flag = config.bypassFlagTyped(by: agent) {
            throw PlanError.unsupported("\(agent.name) is started with \(flag), which switches its permission prompts off, and a preset keeps them on because its prompt carries file names. Take the flag out of its command and arguments (the permission setting adds it for plain starts), or give the preset another agent.")
        }
        if config.commandHidesBypassFlag(of: agent) {
            throw PlanError.unsupported("\(agent.name)'s command has shell syntax whose result Right Here cannot read ($, a backtick, {a,b} or a quote that is not closed), so it cannot tell whether it switches the permission prompts off, and a preset keeps them on because its prompt carries file names. Write the command as plain words and quotes.")
        }
        var words = [agent.command]
        switch AgentLaunchResolution.argumentWords(options.arguments, of: agent) {
        case .success(let quoted): words += quoted
        case .failure(let why): throw PlanError(why)
        }
        if case .flag(let flag) = promptArgument { words.append(ShellQuoting.quote(flag, for: .posix)) }
        words.append(ShellQuoting.quote(prompt, for: .posix))
        let resolution = AgentLaunchResolution.resolve(agent: agent, hasVariant: true, explicit: terminal.map { .terminal($0) }, config: config, facts: facts)
        guard case .terminal(let app, let bundleID, let adapter) = try route(of: resolution) else { throw PlanError.unsupported("A preset is typed into a terminal.") }
        var notices = resolution.launcher == .terminal(nil) ? fallbackNotice(role: .terminal, typing: true, used: app) : []
        if options.bypassFlag != nil {
            notices.append("\(agent.name) keeps its permission prompts on for a preset, although they are switched off for plain starts: the prompt carries file names.")
        }
        if context.items.contains(where: { facts.isDirectory($0) == true }), preset.needsFiles {
            notices.append("Folders in the selection are not named in the prompt; only files are.")
        }
        return try typeCommand(words.joined(separator: " "), summary: "\(agent.command) with preset \(id)", in: app, bundleID: bundleID, adapter: adapter, directory: directory, ref: ref, context: context, notices: notices)
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
        guard let template = config.newFile.templates.first(where: { $0.id == id }) else { throw PlanError.unknownTemplate(id, choices: config.newFile.templates.map(\.id)) }
        let name: String
        switch NewFileNamer.firstFreeName(for: template, in: directory, facts: facts, localizer: localizer) {
        case .free(let free): name = free
        case .unreadable: throw PlanError.unreadable(directory.path)
        case .exhausted: throw PlanError.nameExhausted
        }
        let path = directory.appendingPathComponent(name).path

        var steps: [Step] = [.createFile(CreateFileStep(path: path, contents: template.contents, format: template.format))]
        var notices: [String] = []
        switch config.newFile.then {
        case .reveal:
            steps.append(.reveal([path]))
        case .open:
            if let bundleID = newFileApp(for: template) {
                steps.append(.open(OpenStep(bundleID: bundleID, targets: [path])))
            } else {
                // An open with no app named hands the file to whatever the system opens that kind of file with, and the config
                // chose the extension and the contents: show the file instead.
                steps.append(.reveal([path]))
                notices.append("No editor is installed, so the new file is selected in Finder and not opened.")
            }
        case .nothing:
            break
        }
        return LaunchPlan(action: ref.id, summary: "Create \(name)", steps: steps, notices: notices)
    }

    /// The installed app that opens a new file: the template's own, else the default editor. Never a terminal (handed a
    /// file, it would run it) and never an app that is not installed, so a file is never opened with no app named.
    private func newFileApp(for template: NewFileTemplate) -> String? {
        func installedBundleID(_ app: AppDescriptor) -> String? {
            app.role == .terminal ? nil : app.installedBundleID(facts: facts)
        }
        if let app = template.openWith.flatMap(config.app(id:)), let bundleID = installedBundleID(app) { return bundleID }
        guard let editor = try? defaults.resolve(role: .editor, configured: config.editor) else { return nil }
        return installedBundleID(editor)
    }
}
