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

    @Flag(help: "Show an alert when the action fails. The Finder extension uses this.")
    var alert = false

    func run() async throws {
        guard let ref = ActionRef(parsing: action) else {
            throw ValidationError("\"\(action)\" is not an action id. Run `rh actions` to list them, or `rh docs actions` for the grammar.")
        }
        let runtime = Runtime()
        runtime.reportConfigProblems()
        let here = try context.makeContext(facts: runtime.facts)
        // Files created from Finder follow the system language; the command line stays English.
        let localizer: Localizer = here.origin == .cli ? .english : .system

        let plan: LaunchPlan
        do {
            plan = try Planner(config: runtime.config, facts: runtime.facts, localizer: localizer).plan(ref, context: here)
        } catch {
            try await fail(error)
        }

        if dryRun {
            if json { try Output.json(plan) } else { Output.print(Self.describe(plan)) }
            return
        }
        do {
            let report = try await LiveExecutor().execute(plan)
            RunLog.record("ok \(action) [\(here.origin.rawValue), \(here.items.count) items]: \(plan.summary)")
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
        if alert {
            let content = FailureAlert.content(for: error, action: action, localizer: .system)
            await MainActor.run { FailureAlert.show(content) }
        }
        throw Output.fail("error: " + error.localizedDescription)
    }

    static func describe(_ plan: LaunchPlan) -> String {
        var lines = [plan.summary]
        for (index, step) in plan.steps.enumerated() { lines.append("  \(index + 1). \(step.summary)") }
        for notice in plan.notices { lines.append("  note: \(notice)") }
        return lines.joined(separator: "\n")
    }
}

struct RunResult: Encodable {
    var ok: Bool
    var plan: LaunchPlan
    var report: ExecutionReport
}

/// A small append-only log so a failed action started from Finder leaves a trace.
enum RunLog {
    static func record(_ message: String) {
        let facts = LiveSystemFacts()
        let directory = facts.homeDirectory.appendingPathComponent("Library/Logs/right-here")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("rh.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: file)
        }
    }
}
