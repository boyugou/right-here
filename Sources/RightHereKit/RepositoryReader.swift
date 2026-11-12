import Foundation
import RightHereCore

/// Reads what the repository actions need from git (ADR 0033), with commands that start nothing: with git 2.54, in a repository that
/// names a program for every hook, its file system monitor, a filter for every file, a pager and an ssh command, none of `rev-parse`,
/// `symbolic-ref`, `config --list`, `remote`, `remote get-url` (with `--push --all` too), `rev-list` and `cat-file --batch-check` started one
/// (`ls-files` started the monitor and is not used).
public enum RepositoryReader {
    /// The state of each item that is in a repository, by the item's normalized URL (as the planner looks it up); an item outside any
    /// repository has no entry.
    public static func read(items: [URL], facts: any SystemFacts, runner: any ProcessRunner = LiveProcessRunner(),
                            gitInstalled: Bool? = nil) async throws -> [URL: RepositoryState] {
        var states: [URL: RepositoryState] = [:]
        guard gitInstalled ?? GitCommand.gitIsInstalled() else {
            for item in items.map(\.lexicallyNormalized) where facts.gitRoot(containing: item) != nil {
                states[item] = RepositoryState(root: nil, gitError: .notInstalled)
            }
            return states
        }
        var repositories: [String: (state: RepositoryState, ignoresCase: Bool)] = [:]
        var found: [(item: URL, top: String, path: [String])] = []
        for item in items.map(\.lexicallyNormalized) {
            guard facts.gitRoot(containing: item) != nil else { continue }
            // git decides which repository it is, not a `.git` entry on the way up (an empty `.git` folder is none to git). A link is a file of the
            // repository it is in, wherever it points, so git is asked in the folder around it.
            let isFolder = facts.isDirectory(item) == true && !PathHazard.isSymbolicLink(item.path)
            let top = try await git(["rev-parse", "--show-toplevel"], in: isFolder ? item : item.deletingLastPathComponent(), runner: runner)
            guard top.status == 0, let topPath = line(top) else {
                states[item] = RepositoryState(root: nil, gitError: firstLine(top.standardError).map { .said($0) } ?? .failedSilently)
                continue
            }
            let root = URL(fileURLWithPath: topPath)
            if repositories[topPath] == nil { repositories[topPath] = try await readRepository(root, runner: runner) }
            guard let path = itemPath(of: item, facts: facts, inRepository: root) else {
                states[item] = RepositoryState(root: root, gitError: .outside(item: item.path, root: topPath))
                continue
            }
            found.append((item, topPath, path))
        }
        for (top, entries) in Dictionary(grouping: found, by: \.top) {
            guard let (repository, ignoresCase) = repositories[top] else { continue }
            switch try await lookUp(entries.map(\.path), in: repository, runner: runner) {
            case .answered(let answers):
                for (entry, answer) in zip(entries, answers) {
                    var state = repository
                    var found = answer
                    if found == nil, ignoresCase, let commit = repository.commit, let root = repository.root {
                        found = try await caseInsensitively(entry.path, commit: commit, root: root, runner: runner)
                    }
                    state.itemPath = found?.path ?? entry.path
                    state.kind = found?.kind
                    states[entry.item] = state
                }
            case .failed(let problem):
                // git did not answer: what it said is the reason, and not that the items are outside the commit.
                for entry in entries { states[entry.item] = RepositoryState(root: repository.root, gitError: problem) }
            }
        }
        return states
    }

    /// What each path is in the repository's commit, with its names as the commit holds them; nil for a path that is not in it. The paths go to git on
    /// its input, NUL-separated, not as arguments: `Process` hands its arguments over decomposed, and git that does not precompose them
    /// (`core.precomposeunicode=false`) would look up a name that the commit has precomposed. Each path is asked for precomposed, as git on a Mac
    /// commits a name, and then decomposed, as a commit made elsewhere can hold it: the link carries the form the commit has, which the host serves.
    private static func lookUp(_ paths: [[String]], in repository: RepositoryState, runner: any ProcessRunner) async throws -> LookUp {
        guard let commit = repository.commit, let root = repository.root else { return .answered(paths.map { _ in nil }) }
        let forms = paths.map { path -> [[String]] in
            let precomposed = path.map(\.precomposedStringWithCanonicalMapping)
            let decomposed = path.map(\.decomposedStringWithCanonicalMapping)
            // Compared scalar by scalar: Swift's `==` takes the two forms of a name for the same string.
            return precomposed.map { Array($0.unicodeScalars) } == decomposed.map { Array($0.unicodeScalars) } ? [precomposed] : [precomposed, decomposed]
        }
        var step = GitCommand.step(["cat-file", "--batch-check=%(objecttype)", "-Z"], in: root.path, blanking: GitCommand.Defined())
        step.standardInput = forms.joined().map { commit + ":" + $0.joined(separator: "/") + "\u{0}" }.joined()
        let result = try await runner.run(step, timeout: GitCommand.reading)
        try GitCommand.requireFinished(result, "git cat-file")
        guard result.status == 0 else { return .failed(firstLine(result.standardError).map { .said($0) } ?? .failedSilently) }
        var answers = result.standardOutput.split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
        if answers.last == "" { answers.removeLast() }
        guard answers.count == forms.joined().count else { return .failed(.failedSilently) }
        var next = answers.makeIterator()
        var found: [(kind: RepositoryState.Kind, path: [String])?] = []
        for variants in forms {
            var first: (kind: RepositoryState.Kind, path: [String])?
            for variant in variants {
                if let kind = kind(next.next()), first == nil { first = (kind, variant) }
            }
            found.append(first)
        }
        return .answered(found)
    }

    private enum LookUp {
        case answered([(kind: RepositoryState.Kind, path: [String])?])
        case failed(RepositoryState.GitProblem)
    }

    /// The path as the commit holds it, found folder by folder with the names compared as a disk that ignores case compares them: a name whose case
    /// changed only on the disk is one git (`core.ignorecase`) sees no change in, and the commit has it in the old case. Only one name may match at each
    /// level. The trees are named by their ids, so no name goes to git as an argument.
    private static func caseInsensitively(_ path: [String], commit: String, root: URL, runner: any ProcessRunner) async throws
        -> (kind: RepositoryState.Kind, path: [String])? {
        var tree = commit + "^{tree}"
        var held: [String] = []
        var kind = RepositoryState.Kind.folder
        for name in path {
            guard kind == .folder else { return nil }
            let listed = try await git(["ls-tree", "-z", tree], in: root, runner: runner)
            guard listed.status == 0 else { return nil }
            // `<mode> <type> <id>\t<name>`, the name as it is with -z.
            let matches = listed.standardOutput.split(separator: "\u{0}").compactMap { entry -> (type: String, id: String, name: String)? in
                guard let tab = entry.firstIndex(of: "\t") else { return nil }
                let fields = entry[..<tab].split(separator: " ")
                guard fields.count == 3 else { return nil }
                return (String(fields[1]), String(fields[2]), String(entry[entry.index(after: tab)...]))
            }.filter { $0.name.lowercased() == name.lowercased() }
            guard matches.count == 1, let match = matches.first, let matchKind = self.kind(match.type) else { return nil }
            held.append(match.name)
            tree = match.id
            kind = matchKind
        }
        return (kind, held)
    }

    private static func kind(_ answer: String?) -> RepositoryState.Kind? {
        switch answer {
        case "blob": .file
        case "tree": .folder
        case "commit": .submodule
        default: nil
        }
    }

    /// What the planner needs for `ref` and `context`: nothing for an action that does not read the repository, which then runs no git.
    public static func read(for ref: ActionRef, context: HereContext, facts: any SystemFacts, runner: any ProcessRunner = LiveProcessRunner()) async throws -> [URL: RepositoryState] {
        guard ref.readsRepository else { return [:] }
        // With nothing named on the command line the planner acts on the folder `rh` runs in.
        let targets = context.pathTargets.isEmpty && context.origin == .cli ? [facts.currentDirectory] : context.pathTargets
        return try await read(items: targets, facts: facts, runner: runner)
    }

    /// The item's path from git's top folder, with the folders above it as they are on disk (their links followed and their names in the case
    /// the disk has, as git's top folder is) and its own name as it is, since a link that is the item is a file to git.
    static func itemPath(of item: URL, facts: any SystemFacts, inRepository root: URL) -> [String]? {
        let parent = URL(fileURLWithPath: facts.onDiskPath(item.deletingLastPathComponent())).resolvingSymlinksInPath()
        let name = URL(fileURLWithPath: facts.onDiskPath(item)).lastPathComponent
        let resolved = item.path == "/" ? parent : parent.appendingPathComponent(name)
        return RepositoryLink.itemPath(of: resolved, inRepository: root.resolvingSymlinksInPath())
    }

    private static func readRepository(_ root: URL, runner: any ProcessRunner) async throws -> (state: RepositoryState, ignoresCase: Bool) {
        let head = try await git(["rev-parse", "--verify", "--quiet", "HEAD^{commit}"], in: root, runner: runner)
        let commit = head.status == 0 ? line(head) : nil
        // `symbolic-ref`, not `rev-parse --abbrev-ref`, which says `heads/main` when a tag is also called main.
        let branch = line(try await git(["symbolic-ref", "-q", "HEAD"], in: root, runner: runner))
            .flatMap { $0.hasPrefix("refs/heads/") ? String($0.dropFirst("refs/heads/".count)) : nil }
        // The settings are read in one go, not key by key: a key with the branch's name in it would go to git as an argument, which `Process` hands over
        // decomposed, and git that does not precompose (`core.precomposeunicode=false`) would miss the settings of a branch with an accent in its name.
        // Swift compares the names as Unicode does.
        let listed = try await git(["config", "--list", "-z"], in: root, runner: runner)
        let settings = listed.status == 0 ? ConfigList(listed.standardOutput) : ConfigList("")
        var preferred: [String] = []
        if let branch {
            preferred += [settings.last("branch", branch, "remote"), settings.last("branch", branch, "pushremote")].compactMap { $0 }
        }
        if let pushDefault = settings.last("remote", nil, "pushdefault") { preferred.append(pushDefault) }
        let names = (try await git(["remote"], in: root, runner: runner)).standardOutput
            .split(separator: "\n").map(String.init).filter(isPlainRemoteName)
        var candidates: [String] = []
        for name in preferred + (names.contains("origin") ? ["origin"] : []) + (names.count == 1 ? names : [])
        where names.contains(name) && !candidates.contains(name) {
            candidates.append(name)
        }
        // The first that has the commit: the upstream is where the branch goes, a fork where it was pushed.
        var chosen = candidates.first
        var pushed = false
        if let commit {
            for name in candidates {
                let unpushed = try await git(["rev-list", "-n1", commit, "--not", "--remotes=\(name)"], in: root, runner: runner)
                if unpushed.status == 0, line(unpushed) == nil {
                    chosen = name
                    pushed = true
                    break
                }
            }
        }
        var url: String?
        var pushesElsewhere = false
        if let chosen {
            let got = try await git(["remote", "get-url", chosen], in: root, runner: runner)
            url = got.status == 0 ? line(got) : nil
            // A push goes where `--push` says (a pushurl, a pushInsteadOf rule) and moves the remote's branches as a fetch does: when none of those is the
            // repository fetched from, the branches do not tell whether the link's repository has the commit. Over another transport it is the same one.
            if let url {
                let push = try await git(["remote", "get-url", "--push", "--all", chosen], in: root, runner: runner)
                let pushURLs = push.status == 0 ? push.standardOutput.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } : []
                pushesElsewhere = !pushURLs.isEmpty && !pushURLs.contains { RepositoryLink.sameRepository($0, url) }
            }
        }
        // What git does with a name whose case differs from the commit's: with `core.ignorecase` it is the same file (a disk that ignores case).
        let ignoresCase = ["true", "yes", "on", "1"].contains(settings.last("core", nil, "ignorecase")?.lowercased() ?? "")
        return (RepositoryState(root: root, remoteName: chosen, remoteNames: names, remoteURL: url, commit: commit, isPushed: pushed, pushesElsewhere: pushesElsewhere),
                ignoresCase)
    }

    /// What `git config --list -z` says: each entry is the key, a line feed and the value (a key alone has no value). git gives the section and the
    /// variable in lower case and a subsection, such as a branch's name, as it is written.
    private struct ConfigList {
        let entries: [(key: Substring, value: Substring?)]

        init(_ text: String) {
            entries = text.split(separator: "\u{0}").map { entry in
                guard let newline = entry.firstIndex(of: "\n") else { return (entry, nil) }
                return (entry[..<newline], entry[entry.index(after: newline)...])
            }
        }

        /// The value the last entry of `section.subsection.name` gives (the one git uses); `nil` subsection is a key with none.
        func last(_ section: String, _ subsection: String?, _ name: String) -> String? {
            for entry in entries.reversed() {
                guard let firstDot = entry.key.firstIndex(of: "."), let lastDot = entry.key.lastIndex(of: "."),
                      entry.key[..<firstDot] == section, entry.key[entry.key.index(after: lastDot)...] == name else { continue }
                let middle: Substring? = firstDot == lastDot ? nil : entry.key[entry.key.index(after: firstDot)..<lastDot]
                guard middle.map(String.init) == subsection, let value = entry.value, !value.isEmpty else { continue }
                return String(value)
            }
            return nil
        }
    }

    /// A remote name that `--remotes=` reads as itself (no glob characters) and that no command reads as an option.
    private static func isPlainRemoteName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("-")
            && name.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-/").contains($0) }
    }

    private static func git(_ arguments: [String], in directory: URL, runner: any ProcessRunner) async throws -> ProcessResult {
        let result = try await runner.run(GitCommand.step(arguments, in: directory.path, blanking: GitCommand.Defined()), timeout: GitCommand.reading)
        try GitCommand.requireFinished(result, "git \(arguments.first ?? "")")
        return result
    }

    private static func line(_ result: ProcessResult) -> String? {
        let text = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.status == 0 && !text.isEmpty ? text : nil
    }

    private static func firstLine(_ text: String) -> String? {
        text.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
    }
}
