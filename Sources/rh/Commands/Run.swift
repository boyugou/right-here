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

    @Flag(name: [.customLong("bypass-permissions"), .customShort("y")], help: "Launch AI agents with bypass permissions / autonomous flags.")
    var bypassPermissions = false

    @Flag(name: .customLong("safe"), help: "Launch AI agents in safe mode, overriding config bypass_permissions.")
    var safe = false

    @Option(name: .customLong("arg"), parsing: .unconditionalSingleValue, help: "Additional argument to pass to the agent (can be repeated).")
    var extraArgs: [String] = []

    func run() async throws {
        let runtime = Runtime()
        var config = runtime.config
        if bypassPermissions {
            config.bypassPermissions = true
        }
        if safe {
            config.bypassPermissions = false
            for id in config.agents.keys {
                config.agents[id]?.bypassPermissions = false
            }
        }
        let ref: ActionRef
        do {
            ref = try ActionRegistry(config: config, facts: runtime.facts).resolve(action)
        } catch let unknown as UnknownActionID {
            throw ValidationError(unknown.message(next: "Run `rh actions` to list them, or `rh docs actions` for the grammar."))
        }
        if !extraArgs.isEmpty {
            switch ref {
            case .agent(let agentID, _, _):
                var settings = config.agents[agentID] ?? Config.AgentSettings()
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

    /// Logs the failure, shows the alert when asked to, and exits with status 1.
    private func fail(_ error: any Error) async throws -> Never {
        RunLog.record("\(action): \(error.localizedDescription)")
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
