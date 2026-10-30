import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

extension ConfigCommand {
    struct Pending: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "pending",
            abstract: "List the changes an AI assistant proposed, and apply or dismiss them.",
            discussion: """
            An assistant that changes the config through its MCP tool may do most of it by itself (a menu, a title, a prompt, the agents offered). A change that decides which \
            program starts, or switches an agent's permission prompts off (an agent's command and arguments, an app's bundle identifier and the program that opens it, \
            bypass_permissions), is not made on its say-so: it is kept here until you have looked at it. `rh config pending show <id>` shows what it would change in the file as it \
            is now, `apply <id>` makes it, `dismiss <id>` forgets it. A proposal is forgotten after a week.
            """,
            subcommands: [List.self, Show.self, Apply.self, Dismiss.self],
            defaultSubcommand: List.self
        )

        struct Row: Encodable {
            var id: String
            var time: String
            var by: String
            var file: String
            var change: String
            var waitsFor: [ConfigTrust.Approval]
        }

        static func rows(_ proposals: [ConfigProposal], paths: RHPaths) -> [Row] {
            let formatter = ISO8601DateFormatter()
            return proposals.map {
                Row(id: $0.id, time: formatter.string(from: $0.time), by: $0.actor.rawValue,
                    file: $0.target == .shared ? paths.configFile.lastPathComponent : paths.localConfigFile.lastPathComponent, change: $0.summary, waitsFor: $0.approvals)
            }
        }

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "List the changes that wait, newest first.")

            @Flag(help: "Print JSON.")
            var json = false

            func run() throws {
                let paths = Runtime().paths
                let rows = Pending.rows(ConfigService(paths: paths).pending(), paths: paths)
                if json {
                    try Output.json(rows)
                } else if rows.isEmpty {
                    Output.print("No change waits for you.")
                } else {
                    for row in rows {
                        Output.print("\(row.id)  \(row.time)  \(Output.column(row.by, 4))\(row.file): \(row.change)")
                        for approval in row.waitsFor { Output.print("          waits for you because of \(approval.key): \(approval.reason)") }
                    }
                    Output.print("`rh config pending show <id>` shows one; `apply <id>` makes it and `dismiss <id>` forgets it.")
                }
            }
        }

        struct Show: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Show what a proposed change would do to the file as it is now.")

            @Argument(help: "The id `rh config pending` lists.")
            var id: String

            @Flag(help: "Print JSON.")
            var json = false

            struct Answer: Encodable {
                var proposal: Row
                var change: ConfigChange
            }

            func run() throws {
                let paths = Runtime().paths
                let shown: (proposal: ConfigProposal, change: ConfigChange, digest: String)
                do { shown = try ConfigService(paths: paths).preview(proposal: id, recordingLook: true) } catch { throw Output.fail(ConfigEditSupport.describe(error)) }
                if json {
                    try Output.json(Answer(proposal: Pending.rows([shown.proposal], paths: paths)[0], change: shown.change))
                    return
                }
                Output.print("\(shown.proposal.id): \(shown.proposal.summary)")
                for approval in shown.proposal.approvals { Output.print("It waits for you because of \(approval.key): \(approval.reason).") }
                if shown.change.changed {
                    for line in shown.change.diff { Output.print(line) }
                } else {
                    Output.print("The file already says that.")
                }
                for warning in shown.change.warnings { Output.print(warning) }
                Output.print("`rh config pending apply \(shown.proposal.id)` makes the change as it is shown here, if nothing in the config has changed since; `dismiss \(shown.proposal.id)` forgets it.")
            }
        }

        struct Apply: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Make a proposed change, after you have looked at it with `show`.",
                discussion: "It is refused when `show` was not run for it, and when the config changed after `show` (an assistant may change it between the two, and what the change would start is then not what you saw): look at it again."
            )

            @Argument(help: "The id `rh config pending` lists.")
            var id: String

            @Flag(help: "Print JSON.")
            var json = false

            func run() throws {
                let change: ConfigChange
                do { change = try ConfigService(paths: Runtime().paths).approve(id, actor: .cli, afterLooking: true) } catch { throw Output.fail(ConfigEditSupport.describe(error)) }
                try ConfigEditSupport.print(change, dryRun: false, json: json)
            }
        }

        struct Dismiss: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Forget a proposed change without making it.")

            @Argument(help: "The id `rh config pending` lists.")
            var id: String

            func run() throws {
                do { try ConfigService(paths: Runtime().paths).dismiss(id) } catch { throw Output.fail(ConfigEditSupport.describe(error)) }
                Output.print("Forgot \(id).")
            }
        }
    }
}
