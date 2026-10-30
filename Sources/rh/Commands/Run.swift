import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run an action.",
        discussion: """
        The action id says what to do (list them with `rh actions`, read the grammar with `rh docs actions`):

          rh run copy-path.git-relative src/main.swift
          rh run open.terminal ~/code/project
          rh run agent.claude              start Claude Code in the current folder
          rh run agent.claude.continue@ghostty ~/code/project
          rh run new-file.md --container ~/notes
          rh run agent.claude --worktree ~/code/project/src   start it in a new git worktree, in src

        Use --dry-run to see exactly what would happen without doing it.
        """
    )

    @Argument(help: "The action id, for example copy-path.absolute or agent.claude.")
    var action: String

    @OptionGroup var context: ContextOptions

    @Flag(help: "Print the plan and do nothing.")
    var dryRun = false

    @Flag(help: "Print the plan and the result as JSON.")
    var json = false

    @Flag(help: "Show an alert when the action fails. The Finder extension uses this. Never with --dry-run. RH_NO_UI turns alerts off and stops rh from starting open or osascript.")
    var alert = false

    @Flag(name: .customLong("worktree"), help: "Start the AI agent in an isolated git worktree of the repository, in the same folder the request names. For an agent or a preset.")
    var worktree = false

    @Option(name: .customLong("branch"), help: "Branch name for the isolated git worktree (implies --worktree). Without it a new branch is made.")
    var branch: String?

    @Flag(name: .customLong("bypass-permissions"), help: "Start the AI agent with its permission prompts switched off. For an agent (agent.<id>): a preset keeps its prompts on.")
    var bypassPermissions = false

    @Flag(name: .customLong("safe"), help: "Start the AI agent with its permission prompts on, whatever the config says. For an agent.")
    var safe = false

    @Option(name: .customLong("arg"), parsing: .unconditionalSingleValue, help: "An extra argument for the AI agent, typed after its command (can be repeated). For an agent or a preset.")
    var extraArgs: [String] = []

    @Option(name: .customLong("language"), help: "The language a new file's name is made in, most preferred first (repeat the option). Without it the command line uses English and a request from Finder uses the system's languages. Languages the app does not have fall back to English.")
    var languages: [String] = []

    func run() async throws {
        let runtime = Runtime()
        let ref: ActionRef
        do {
            ref = try ActionRegistry(config: runtime.config, facts: runtime.facts).resolve(action)
        } catch let unknown as UnknownActionID {
            throw ValidationError(unknown.message(next: "Run `rh actions` to list them, or `rh docs actions` for the grammar."))
        }
        try checkOptions(for: ref)
        var config = runtime.config
        switch ref {
        case .agent(let agentID, _, _):
            // The options are for this run only: they are set on the agent that starts, so a config that switches the prompts off for
            // this agent does not swallow `--bypass-permissions`.
            var settings = config.agents[agentID] ?? Config.AgentSettings()
            if bypassPermissions { settings.bypassPermissions = true }
            if safe { settings.bypassPermissions = false }
            settings.args.append(contentsOf: extraArgs)
            config.agents[agentID] = settings
        case .preset(let presetID, _):
            if let preset = config.preset(id: presetID), let agent = config.agent(for: preset) {
                var settings = config.agents[agent.id] ?? Config.AgentSettings()
                settings.args.append(contentsOf: extraArgs)
                config.agents[agent.id] = settings
            }
        default:
            break
        }
        runtime.reportConfigProblems()
        let here = try context.makeContext(facts: runtime.facts)
        // Files created from Finder follow the config's language (or the system's), and the command line stays English unless it is given a language.
        let localizer: Localizer = !languages.isEmpty ? Localizer(languages: languages) : (here.origin == .cli ? .english : config.localizer)

        if worktree || branch != nil {
            try await runInWorktree(ref, config: config, here: here, localizer: localizer, runtime: runtime)
            return
        }
        let plan: LaunchPlan
        do {
            let repositories = try await RepositoryReader.read(for: ref, context: here, facts: runtime.facts)
            plan = try Planner(config: config, facts: runtime.facts, localizer: localizer, repositories: repositories).plan(ref, context: here)
        } catch {
            try await fail(error)
        }
        try await present(plan, ref: ref, config: config, here: here, runtime: runtime)
    }

    /// `--worktree`: the action runs in a git worktree of the repository, on a new branch (or the one `--branch` names), in the same
    /// folder the request names. The plan is made first, against the worktree as it will be, so a refusal creates nothing. The worktree
    /// is made after that and the plan is made again for real. If the run then fails, a worktree this run made and nothing changed in is
    /// removed again, and one that existed before is never touched.
    private func runInWorktree(_ ref: ActionRef, config: Config, here: HereContext, localizer: Localizer, runtime: Runtime) async throws {
        guard let folder = here.workingDirectory(facts: runtime.facts) else {
            // The same refusals as without --worktree: a folder that is not there is named, and is not replaced by the folder around it.
            if let missing = here.firstMissingPath(facts: runtime.facts) { try await fail(PlanError.pathNotFound(missing.path)) }
            if let target = here.unplaceableTarget(facts: runtime.facts), target.reason == .unreadable { try await fail(PlanError.unreadable(target.url.path)) }
            throw ValidationError("--worktree requires a folder target.")
        }
        guard let root = runtime.facts.gitRoot(containing: folder) else {
            throw ValidationError("--worktree requires a git repository (no git root found for \(folder.path.withControlCharactersEscaped)).")
        }
        let name: String
        if let branch {
            let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
            if let refusal = GitWorktreeManager.branchNameRefusal(trimmed) { throw ValidationError("Not a usable branch name: \(refusal).") }
            name = trimmed
        } else {
            // A dry run cannot know the name a real run gives a new branch, so it shows a placeholder where the name goes.
            name = dryRun ? "rh/<auto-branch>" : GitWorktreeManager.freshBranchName()
        }
        let worktreeURL = GitWorktreeManager.worktreeDirectory(gitRoot: root, branch: name)
        let inWorktree = try Self.moved(here, folder: folder, from: root, to: worktreeURL)

        let preview: LaunchPlan
        do {
            preview = try Planner(config: config, facts: WorktreeFacts(base: runtime.facts, repository: root, worktree: worktreeURL), localizer: localizer)
                .plan(ref, context: inWorktree)
        } catch {
            try await fail(error)
        }
        if dryRun {
            // Notes go to standard error so that `--json` stays one document on standard output.
            let branchWord = branch == nil ? "a new branch (--branch names one)" : "branch '\(name.withControlCharactersEscaped)'"
            Output.error("note: --worktree would create the worktree at \(worktreeURL.path.withControlCharactersEscaped) on \(branchWord)")
            try await present(preview, ref: ref, config: config, here: here, runtime: runtime)
            return
        }

        let made: WorktreeResult
        do {
            made = try await GitWorktreeManager.prepareWorktree(gitRoot: root, branch: name)
        } catch {
            try await fail(error)
        }
        Output.error("note: isolated worktree ready on branch '\(made.branch.withControlCharactersEscaped)' at \(made.worktreeURL.path.withControlCharactersEscaped)")
        let plan: LaunchPlan
        do {
            plan = try Planner(config: config, facts: runtime.facts, localizer: localizer).plan(ref, context: inWorktree)
        } catch {
            await discard(made, root: root)
            try await fail(error)
        }
        try await present(plan, ref: ref, config: config, here: here, runtime: runtime, madeWorktree: (made, root))
    }

    /// A dry run prints the plan, and a real run executes it. A failure is logged, and a worktree this run made for it is removed again when
    /// nothing in it changed.
    private func present(_ plan: LaunchPlan, ref: ActionRef, config: Config, here: HereContext, runtime: Runtime, madeWorktree: (WorktreeResult, URL)? = nil) async throws {
        if dryRun {
            var shown = plan
            if let note = await commandNote(for: ref, config: config, facts: runtime.facts) { shown.notices.append(note) }
            if json { try Output.json(shown) } else { Output.print(Self.describe(shown)) }
            return
        }
        do {
            let report = try await LiveExecutor().execute(plan)
            RunLog.record(RunLog.Entry(actionID: action, origin: here.origin, itemCount: here.items.count))
            if let dir = here.workingDirectory(facts: runtime.facts) {
                // A recent folder is not worth a click that waits: when another program holds the state for longer than this, it is not recorded.
                try? StateStore.update(paths: runtime.paths, timeout: .milliseconds(500)) { $0.recordRecent(dir.path) }
            }
            if json {
                try Output.json(RunResult(ok: true, plan: plan, report: report))
            } else {
                Output.print("ok: " + plan.summary)
            }
        } catch {
            if let madeWorktree { await discard(madeWorktree.0, root: madeWorktree.1) }
            try await fail(error)
        }
    }

    /// The request moved into a worktree: the folder and every item keep the place they have below the repository's root, so an agent
    /// starts in the folder that was named (not at the root of the worktree) and a file keeps its folder.
    static func moved(_ here: HereContext, folder: URL, from root: URL, to worktree: URL) throws -> HereContext {
        // Compared as the file system resolves the names (`/tmp` is `/private/tmp`, and the root may have been spelled either way), and
        // written with the worktree's own spelling.
        let top = root.resolvingSymlinksInPath().path
        func place(_ url: URL) throws -> URL {
            let path = url.resolvingSymlinksInPath().path
            guard path == top || path.hasPrefix(top + "/") else {
                throw ValidationError("\(path.withControlCharactersEscaped) is outside the git repository \(top.withControlCharactersEscaped), so it has no place in a worktree of it.")
            }
            return URL(fileURLWithPath: worktree.path + path.dropFirst(top.count))
        }
        return HereContext(origin: here.origin, items: try here.items.map(place), container: try place(folder))
    }

    /// Removes a worktree this run made, when a failure left nothing changed in it, and says so.
    private func discard(_ made: WorktreeResult, root: URL) async {
        if await GitWorktreeManager.discardIfUnchanged(made, gitRoot: root) {
            Output.error("note: the worktree \(made.worktreeURL.path.withControlCharactersEscaped) was removed again, since the action failed and nothing in it changed.")
        }
    }

    /// In a dry run, `rh` asks the login shell whether the agent's command is there, which a real run started from Finder must not do.
    /// The note says what that would mean: the terminal would say "command not found".
    private func commandNote(for ref: ActionRef, config: Config, facts: any SystemFacts) async -> String? {
        let agent: AgentDescriptor?
        switch ref {
        case .agent(let id, _, _): agent = config.agent(id: id)
        case .preset(let id, _): agent = config.preset(id: id).flatMap { config.agent(for: $0) }
        default: agent = nil
        }
        guard let agent else { return nil }
        let shell = await Detector(facts: facts).probe(commands: [agent.executable])
        // A shell that said nothing (an `exec tmux` in its startup file, a hang) has not said the command is missing.
        guard shell.answered, !shell.found.contains(agent.executable) else { return nil }
        return "\(agent.executable) is not found by your login shell (`rh agents` says so), so starting it would end with \"command not found\" in the terminal."
    }

    /// The options that change how an agent starts apply to an agent (`agent.<id>`) or a preset (`preset.<id>`) and to nothing else. One that
    /// would do nothing is an error, never silently ignored (`rh run copy-path.absolute --bypass-permissions` used to exit 0).
    private func checkOptions(for ref: ActionRef) throws {
        let named = [
            (bypassPermissions, "--bypass-permissions"), (safe, "--safe"), (!extraArgs.isEmpty, "--arg"),
            (worktree, "--worktree"), (branch != nil, "--branch")
        ].filter(\.0).map(\.1)
        let launchesAnAgent: Bool
        let isPreset: Bool
        switch ref {
        case .agent:
            launchesAnAgent = true
            isPreset = false
        case .preset:
            launchesAnAgent = true
            isPreset = true
        default:
            launchesAnAgent = false
            isPreset = false
        }
        if !launchesAnAgent, !named.isEmpty {
            throw ValidationError("\(named.joined(separator: ", ")) can only be used with an AI agent (agent.<id>) or a preset (preset.<id>), and \(action) is neither.")
        }
        if bypassPermissions, safe {
            throw ValidationError("--bypass-permissions and --safe cannot be used together.")
        }
        // A preset keeps its agent's prompts on whatever the config says (ADR 0012): the prompt carries the names of the files, so the
        // permission flag never reaches it, and asking for it, or for --safe, which would change nothing, is an error.
        if isPreset, bypassPermissions || safe {
            throw ValidationError("\(bypassPermissions ? "--bypass-permissions" : "--safe") does not apply to a preset: a preset keeps its agent's permission prompts on, since its prompt carries file names. Start the agent itself (agent.<id>) to switch them off.")
        }
    }

    /// Logs the failure, shows the alert when asked to, and exits with status 1. A dry run is a question answered on the command line, so
    /// it is not a failure in the log.
    private func fail(_ error: any Error) async throws -> Never {
        if !dryRun { RunLog.record("\(action): \(error.localizedDescription)") }
        if FailureAlert.shouldShow(requested: alert, dryRun: dryRun) {
            let runtime = Runtime()
            let app = FailureAlert.app(rhPath: Installer.currentExecutablePath(), facts: runtime.facts)
            let content = FailureAlert.content(for: error, action: action, localizer: runtime.config.localizer, app: app)
            await MainActor.run { FailureAlert.show(content) }
        }
        // A script that asked for JSON gets JSON on stdout for a failure too, not only an empty stream and a message on stderr.
        if json { try Output.json(RunFailure(ok: false, error: error.localizedDescription)) }
        throw Output.fail("error: " + error.localizedDescription)
    }

    static func describe(_ plan: LaunchPlan) -> String {
        var lines = [plan.summary]
        for (index, step) in plan.steps.enumerated() {
            lines.append("  \(index + 1). \(step.heading)")
            lines += step.details.map { "       \($0)" }
        }
        for notice in plan.notices { lines.append("  note: \(notice)") }
        return lines.joined(separator: "\n")
    }
}

struct RunResult: Encodable {
    var ok: Bool
    var plan: LaunchPlan
    var report: ExecutionReport
}

struct RunFailure: Encodable {
    var ok: Bool
    var error: String
}
