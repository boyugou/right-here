import Foundation
import RightHereCore

/// Every git command Right Here runs in a repository is built here, and nowhere else, so that a new command cannot be added without the
/// guards below.
///
/// A repository is whatever somebody sent: an archive, a copy, a clone of a stranger's project, and its own files can name programs that git
/// starts by itself. Measured with git 2.54 (ADR 0016, "What git may start"): `worktree add` runs the repository's hooks (`post-checkout`,
/// `reference-transaction`, `post-index-change`; files in a hooks folder, and since 2.54 also `hook.<name>.command` in the configuration, which
/// `core.hooksPath` does not stop), its `core.fsmonitor` program and the filter drivers its attributes select, and it fetches missing objects from a
/// promisor remote, which starts whatever that remote's URL or `core.sshCommand` names; `status` and `worktree remove` (which runs a `status` of its own
/// inside the worktree) run `core.fsmonitor`, `post-index-change` and the `clean` filters; `branch -d` runs `reference-transaction`.
/// `worktree list` and `config` start nothing.
enum GitCommand {
    static let executable = "/usr/bin/git"

    /// How long a command that only reads (the list of worktrees, the configuration, deleting a branch) may take. A repository whose configuration includes
    /// a named pipe makes every git command in it wait for a writer, which would hold a request of the MCP server, or the setup window, for ever
    /// (measured: `git worktree list`, `git config` and `git status` all stay).
    static let reading: Duration = .seconds(20)

    /// Throws when the process was stopped for running past its limit: its status then says how it died, not what git answered.
    static func requireFinished(_ result: ProcessResult, _ description: String) throws {
        if let limit = result.terminatedAfter { throw ExecutionError.timedOut(step: description, seconds: Int(limit.components.seconds)) }
    }

    /// What a repository's configuration names that git would start, found by `defined(in:runner:)`.
    struct Defined: Equatable {
        /// Filter drivers (`filter.<driver>.smudge` and the others) of the repository itself.
        var filterDrivers: [String] = []
        /// Hooks named in the configuration (`hook.<name>.command`), wherever it is written.
        var hooks: [String] = []
        /// The conditions of the conditional includes (`includeIf "<condition>"`) that the repository's own configuration has. What such an include brings in depends on
        /// the branch checked out and the git directory, which differ in a worktree that does not exist yet, so what is defined there cannot be known from here.
        var conditionalIncludes: [String] = []

        func merging(_ other: Defined) -> Defined {
            Defined(filterDrivers: Array(Set(filterDrivers).union(other.filterDrivers)).sorted(), hooks: Array(Set(hooks).union(other.hooks)).sorted(),
                    conditionalIncludes: Array(Set(conditionalIncludes).union(other.conditionalIncludes)).sorted())
        }
    }

    /// `git -C <directory> <arguments>` with these guards, which the repository's own configuration files cannot undo:
    ///
    /// - `core.hooksPath=/dev/null` and `hook.<name>.enabled=false` for every hook in `defined`: no hook runs, whether it is a file or a configured command.
    /// - `core.fsmonitor=false`: no file system monitor runs.
    /// - Every filter driver in `defined` is blanked (`smudge`, `clean`, `process`, and `required=false` so that git does not fail for the missing
    ///   command): those the repository defines, never the person's own (Git LFS in the global configuration keeps working).
    /// - `GIT_NO_LAZY_FETCH=1`: a partial clone does not fetch what it lacks, so no transport (`ext::`, `core.sshCommand`, a credential
    ///   helper, `core.gitProxy`) is started. None of these commands needs the network.
    /// - `--no-pager`: nothing is paged, whatever `core.pager` or `pager.<command>` say.
    ///
    /// The settings are given as `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_<n>` and `GIT_CONFIG_VALUE_<n>`, which beat the configuration files like
    /// `-c` does, and which keep a name whole: `-c filter.a=b.smudge=` is split at the first equals sign, so the driver `a=b` is never
    /// blanked, and git lets a repository choose such a name. A `GIT_CONFIG_COUNT` in the caller's environment is replaced: these
    /// commands run with the person's configuration files and the settings here, and with nothing else that was passed through the environment.
    ///
    /// `defined` has no default, so whoever adds a command has to say whether it can run a hook, or write or compare files (add, remove and status
    /// can; list and `branch -d` touch no file of the work tree, so only the hooks of `branch -d` matter; `config` is what finds what is defined).
    static func step(_ arguments: [String], in directory: String, blanking defined: Defined) -> ProcessStep {
        var settings: [(name: String, value: String)] = [
            ("core.hooksPath", "/dev/null"),
            ("core.fsmonitor", "false")
        ]
        for hook in defined.hooks.sorted() { settings.append(("hook.\(hook).enabled", "false")) }
        for driver in defined.filterDrivers.sorted() {
            for key in ["smudge", "clean", "process"] { settings.append(("filter.\(driver).\(key)", "")) }
            settings.append(("filter.\(driver).required", "false"))
        }
        var environment = ["GIT_NO_LAZY_FETCH": "1", "GIT_CONFIG_COUNT": String(settings.count)]
        for (index, setting) in settings.enumerated() {
            environment["GIT_CONFIG_KEY_\(index)"] = setting.name
            environment["GIT_CONFIG_VALUE_\(index)"] = setting.value
        }
        return ProcessStep(executable: executable, arguments: ["--no-pager", "-C", directory] + arguments, environment: environment)
    }

    /// The configuration scopes whose filter drivers are the person's own: the system's and the person's global configuration, and what was
    /// given on the command line or through the environment. Every other scope (the repository's `config`, a file it includes, its
    /// `config.worktree`, one a later git adds) is the repository's.
    static let ownScopes: Set<String> = ["system", "global", "command"]

    /// What the repository's configuration defines for the work tree at `directory`. `git config --local` would see neither a file that the
    /// repository's configuration includes nor its `config.worktree`; with the scope shown, the person's drivers are left out and the repository's
    /// are all found, whichever file defines them. The output is NUL-separated (`scope`, `name`, `scope`, `name`...), and everything is read by
    /// Unicode scalars: a name may hold an equals sign, a tab, a dot, or start with a combining mark, which would hide the dot before it from a
    /// comparison by `Character`.
    static func defined(in directory: String, runner: any ProcessRunner) async throws -> Defined {
        let listing = try await runner.run(step(["config", "-z", "--show-scope", "--name-only", "--get-regexp", "^(filter|hook|includeif)\\."], in: directory, blanking: Defined()),
                                           timeout: reading)
        try requireFinished(listing, "git config")
        // Exit status 1 is "no such setting".
        guard listing.status == 0 || listing.status == 1 else {
            throw ExecutionError.stepFailed(index: 0, step: "git config", message: listing.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let fields = listing.standardOutput.unicodeScalars.split(separator: "\0", omittingEmptySubsequences: false).map { String(String.UnicodeScalarView($0)) }
        var drivers = Set<String>()
        var hooks = Set<String>()
        var conditions = Set<String>()
        var index = 0
        while index + 1 < fields.count {
            let (scope, name) = (fields[index], Array(fields[index + 1].unicodeScalars))
            index += 2
            if !ownScopes.contains(scope), let driver = middle(of: name, after: "filter.") { drivers.insert(driver) }
            if let hook = middle(of: name, after: "hook.") { hooks.insert(hook) }
            if !ownScopes.contains(scope), let condition = middle(of: name, after: "includeif.") { conditions.insert(condition) }
        }
        return Defined(filterDrivers: drivers.sorted(), hooks: hooks.sorted(), conditionalIncludes: conditions.sorted())
    }

    /// `<name>` of `<prefix><name>.<key>`: the key never has a dot, so the last dot ends the name. `nil` for a setting that has no name in it
    /// (`hook.jobs`).
    private static func middle(of key: [Unicode.Scalar], after prefix: String) -> String? {
        let start = Array(prefix.unicodeScalars)
        guard key.starts(with: start), let dot = key.lastIndex(of: "."), dot >= start.count else { return nil }
        return String(String.UnicodeScalarView(key[start.count..<dot]))
    }
}
