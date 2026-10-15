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

    @Flag(name: .customLong("worktree"), help: "Launch the action in an isolated git worktree branch.")
    var worktree = false

    @Option(name: .customLong("branch"), help: "Branch name for the isolated git worktree (implies --worktree).")
    var branch: String?

    @Flag(name: .customLong("bypass-permissions"), help: "Start the AI agent with its permission prompts switched off. For an agent (agent.<id>): a preset keeps its prompts on.")
    var bypassPermissions = false

    @Flag(name: .customLong("safe"), help: "Start the AI agent with its permission prompts on, whatever the config says. For an agent.")
    var safe = false

    @Option(name: .customLong("arg"), parsing: .unconditionalSingleValue, help: "An extra argument for the AI agent, typed after its command (can be repeated). For an agent or a preset.")
    var extraArgs: [String] = []

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

        let effectiveContext: HereContext
        if worktree || branch != nil {
            guard let dir = here.workingDirectory(facts: runtime.facts) else {
                throw ValidationError("--worktree requires a folder target.")
            }
            guard let root = runtime.facts.gitRoot(containing: dir) else {
                throw ValidationError("--worktree requires a git repository (no git root found for \(dir.path)).")
            }
            if let name = branch, let refusal = GitWorktreeManager.branchNameRefusal(name.trimmingCharacters(in: .whitespacesAndNewlines)) {
                throw ValidationError("Not a usable branch name: \(refusal).")
            }
            if dryRun {
                let targetBranch = branch ?? "rh/<auto-branch>"
                let previewURL = GitWorktreeManager.worktreeDirectory(gitRoot: root, branch: targetBranch)
                // Notes go to standard error so that `--json` stays one document on standard output.
                Output.error("note: --worktree will create or attach branch '\(targetBranch.withControlCharactersEscaped)' at \(previewURL.path.withControlCharactersEscaped)")
                effectiveContext = HereContext(origin: here.origin, container: previewURL)
            } else {
                let res = try await GitWorktreeManager.prepareWorktree(gitRoot: root, branch: branch)
                Output.error("note: isolated worktree ready on branch '\(res.branch.withControlCharactersEscaped)' at \(res.worktreeURL.path.withControlCharactersEscaped)")
                effectiveContext = HereContext(origin: here.origin, container: res.worktreeURL)
            }
        } else {
            effectiveContext = here
        }

        // Files created from Finder follow the system language; the command line stays English.
        let localizer: Localizer = effectiveContext.origin == .cli ? .english : .system

        let plan: LaunchPlan
        do {
            plan = try Planner(config: config, facts: runtime.facts, localizer: localizer).plan(ref, context: effectiveContext)
        } catch {
            try await fail(error)
        }

        if dryRun {
            if json { try Output.json(plan) } else { Output.print(Self.describe(plan)) }
            return
        }
        do {
            let report = try await LiveExecutor().execute(plan)
            RunLog.record(RunLog.Entry(actionID: action, origin: here.origin, itemCount: here.items.count))
            if let dir = here.workingDirectory(facts: runtime.facts) {
                var state = StateStore.load(paths: runtime.paths)
                state.recordRecent(dir.path)
                try? state.save(paths: runtime.paths)
            }
            if json {
                try Output.json(RunResult(ok: true, plan: plan, report: report))
            } else {
                Output.print("ok: " + plan.summary)
            }
        } catch {
            try await fail(error)
        }
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
            let content = FailureAlert.content(for: error, action: action, localizer: .system)
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
