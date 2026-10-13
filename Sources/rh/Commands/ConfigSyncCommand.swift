import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

/// `rh config sync`: keep config.toml in step with a plain folder (iCloud Drive, Dropbox, a git checkout) by copying.
struct ConfigSyncCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Keep config.toml in sync with a folder (iCloud Drive, Dropbox, a git checkout).",
        discussion: """
        The config is copied, not linked: the Finder extension cannot read through a symlink out of its folder. \
        `enable` remembers the folder (by default an iCloud Drive folder called Right Here), `push` sends this \
        machine's config there, `pull` takes the copy from there, `status` compares them. Nothing is ever \
        deleted, writes are atomic, and a config that does not validate, is over 1 MiB or has key names that \
        look like secrets (token, secret, password, api_key) is refused. The folder is not trusted with programs: \
        a pull that would add or change a terminal template or an agent command is refused, with the list, unless \
        you pass --allow-commands. Machine-specific settings belong in config.local.toml, which is never synced; \
        see `rh docs sync`.
        """,
        subcommands: [Enable.self, Status.self, Pull.self, Push.self, Disable.self]
    )

    static func run(_ body: () throws -> Void) throws {
        do { try body() } catch let error as ConfigSyncError {
            throw Output.fail(error.description)
        }
    }

    struct Enable: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Choose the folder to keep the config in. Copies nothing.",
            discussion: "Without --folder, ~/Library/Mobile Documents/com~apple~CloudDocs/Right Here is used. Any folder works. The folder is created by the first `push`, not here."
        )

        @Option(help: "The folder to keep the copy in. A leading ~ is your home folder.")
        var folder: String?

        func run() throws {
            let runtime = Runtime()
            try ConfigSyncCommand.run {
                let report = try ConfigSync(paths: runtime.paths).enable(folder: folder)
                Output.print("Sync folder: \(report.folder.path)")
                Output.print(Status.describe(report))
                for line in Status.problems(report) { Output.print(line) }
                for line in Status.pendingCommands(report) { Output.print(line) }
                Output.print(Status.nextStep(report))
            }
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Compare this machine's config with the copy in the sync folder.")

        @Flag(help: "Print JSON.")
        var json = false

        struct Report: Encodable {
            var status: String
            var folder: String
            var folderReachable: Bool
            var localFile: String
            var remoteFile: String
            var localSHA256: String?
            var remoteSHA256: String?
            var lastSyncedSHA256: String?
            var conflictCopies: [String]
            /// What the folder's copy would add or change among what this machine starts (one line each).
            var pendingLaunchCommands: [String]
        }

        func run() throws {
            let runtime = Runtime()
            try ConfigSyncCommand.run {
                let report = try ConfigSync(paths: runtime.paths).status()
                if json {
                    try Output.json(Report(status: report.status.rawValue, folder: report.folder.path, folderReachable: report.folderReachable,
                                           localFile: report.localFile.path, remoteFile: report.remoteFile.path, localSHA256: report.localHash,
                                           remoteSHA256: report.remoteHash, lastSyncedSHA256: report.lastSynced, conflictCopies: report.conflictCopies,
                                           pendingLaunchCommands: report.pendingCommands.map(\.line)))
                    return
                }
                Output.print("Sync folder: \(report.folder.path)" + (report.folderReachable ? "" : " (not reachable)"))
                Output.print(Self.describe(report))
                for line in Self.problems(report) { Output.print(line) }
                for copy in report.conflictCopies {
                    Output.print("Conflict copy: \(copy) (two machines wrote at once; compare it with config.toml and remove it by hand)")
                }
                for line in Self.pendingCommands(report) { Output.print(line) }
                Output.print(Self.nextStep(report))
            }
        }

        static func describe(_ report: ConfigSync.Report) -> String {
            let words: [SyncStatus: String] = [
                .inSync: "this machine and the folder have the same config",
                .localAhead: "this machine's config changed since the last sync",
                .remoteAhead: "the folder's copy is newer than this machine's",
                .diverged: "both changed since the last sync (or they differ and nothing says which is newer)",
                .remoteMissing: report.folderReachable ? "there is no config.toml in the folder yet" : "the folder does not exist yet",
                .remoteEvicted: Self.remoteTooLarge(report).map { "config.toml in the folder is \($0 / 1024) KB, past the \(ConfigParser.maxBytes / 1024) KB a config may have; it is not read and never replaced" }
                    ?? "config.toml in the folder is not downloaded to this Mac (or cannot be read)"
            ]
            return "Status: \(report.status.rawValue): \(words[report.status] ?? "")"
        }

        /// The size of the copy in the folder when it is past the limit and so was not read.
        static func remoteTooLarge(_ report: ConfigSync.Report) -> Int? {
            if case .tooLarge(let bytes) = report.remote { return bytes }
            return nil
        }

        /// What would make `push` or `pull` refuse, said before anyone tries.
        static func problems(_ report: ConfigSync.Report) -> [String] {
            var lines: [String] = []
            if !report.localProblems.isEmpty {
                lines.append("This machine's config would be refused by `push`: " + report.localProblems.map(\.message).joined(separator: "; ") + ".")
            }
            if !report.remoteProblems.isEmpty {
                lines.append("The folder's copy would be refused by `pull`: " + report.remoteProblems.map(\.message).joined(separator: "; ") + ".")
            }
            return lines
        }

        /// What the folder's copy would start that this machine's config does not, one line each, or nothing.
        static func pendingCommands(_ report: ConfigSync.Report) -> [String] {
            guard !report.pendingCommands.isEmpty else { return [] }
            return ["The folder's copy adds or changes what Right Here starts (a pull is refused unless you pass --allow-commands):"]
                + report.pendingCommands.prefix(ConfigSyncError.listedChanges).map { "  " + $0.line }
                + (report.pendingCommands.count > ConfigSyncError.listedChanges ? ["  and \(report.pendingCommands.count - ConfigSyncError.listedChanges) more"] : [])
        }

        static func nextStep(_ report: ConfigSync.Report) -> String {
            let approval = report.pendingCommands.isEmpty ? "" : " --allow-commands"
            switch report.status {
            case .inSync: return "Nothing to do."
            case .localAhead, .remoteMissing: return "Next: `rh config sync push`."
            case .remoteAhead:
                return report.pendingCommands.isEmpty ? "Next: `rh config sync pull`." : "Next: read what the folder's copy would start, and if it is yours, `rh config sync pull\(approval)`."
            case .diverged: return "Next: compare the two files, then `rh config sync pull --force\(approval)` (take the folder's) or `rh config sync push --force` (keep this one); the replaced file is saved first."
            case .remoteEvicted:
                if remoteTooLarge(report) != nil { return "Next: is this the right folder? Move config.toml out of it, then run `rh config sync push`." }
                return "Next: open the folder in Finder, let config.toml download, then run `rh config sync status` again."
            }
        }
    }

    struct Pull: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Replace this machine's config with the copy in the sync folder.",
            discussion: """
            Refuses when this machine's config changed since the last sync, unless --force; then the old file is saved as \
            config.toml.bak-<date>. Refuses, listing them, when the copy would add or change a terminal template \
            (open_args, run_args) or an agent command that this machine's config does not already have, unless \
            --allow-commands: a synced folder can be written by other machines and services, so what it makes a click \
            run is yours to read first.
            """
        )

        @Flag(help: "Replace a locally changed config (the old one is saved first).")
        var force = false

        @Flag(help: "Accept the terminal templates and agent commands the copy adds or changes (a pull that would is refused, with the list, without this).")
        var allowCommands = false

        func run() throws {
            let runtime = Runtime()
            try ConfigSyncCommand.run {
                switch try ConfigSync(paths: runtime.paths).pull(force: force, allowCommands: allowCommands) {
                case .alreadyInSync: Output.print("Already in sync.")
                case .pulled(let backup):
                    Output.print("Pulled the config into \(runtime.paths.configFile.path).")
                    if let backup { Output.print("The replaced file is saved as \(backup.path).") }
                }
            }
        }
    }

    struct Push: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Copy this machine's config to the sync folder.",
            discussion: "Refuses when the folder's copy changed since the last sync, unless --force; then the old copy is saved next to it as config.toml.bak-<date>."
        )

        @Flag(help: "Replace a copy in the folder that changed since the last sync (it is saved first).")
        var force = false

        func run() throws {
            let runtime = Runtime()
            try ConfigSyncCommand.run {
                let sync = ConfigSync(paths: runtime.paths)
                switch try sync.push(force: force) {
                case .alreadyInSync: Output.print("Already in sync.")
                case .pushed(let backup, let created):
                    let folder = sync.settings()?.folder ?? ""
                    Output.print((created ? "Created \(folder) and pushed" : "Pushed") + " the config to \(folder)/config.toml.")
                    if let backup { Output.print("The replaced copy is saved as \(backup.path).") }
                }
            }
        }
    }

    struct Disable: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Forget the sync folder. Both copies of the config stay where they are.")

        func run() throws {
            let runtime = Runtime()
            try ConfigSyncCommand.run {
                if try ConfigSync(paths: runtime.paths).disable() {
                    Output.print("Sync is off. The config on this machine and the copy in the folder were left as they are.")
                } else {
                    Output.print("Sync was not enabled.")
                }
            }
        }
    }
}
