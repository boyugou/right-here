import Foundation
import RightHereCore

/// Reads what the repository actions need from git (ADR 0033), with commands that start nothing: with git 2.54, in a repository that
/// names a program for every hook, its file system monitor, a filter for every file, a pager and an ssh command, none of `rev-parse`,
/// `symbolic-ref`, `config --get`, `remote`, `remote get-url`, `rev-list` and `cat-file --batch-check` started one (`ls-files` started the
/// monitor and is not used).
public enum RepositoryReader {
    /// The state of each item that is in a repository, by the item's normalized URL (as the planner looks it up); an item outside any
    /// repository has no entry.
    public static func read(items: [URL], facts: any SystemFacts, runner: any ProcessRunner = LiveProcessRunner()) async throws -> [URL: RepositoryState] {
        var states: [URL: RepositoryState] = [:]
        var repositories: [String: RepositoryState] = [:]
        var found: [(item: URL, top: String, path: [String])] = []
        for item in items.map(\.lexicallyNormalized) {
            guard facts.gitRoot(containing: item) != nil else { continue }
            // git decides which repository it is, not a `.git` entry on the way up (an empty `.git` folder is none to git).
            let isFolder = facts.isDirectory(item) == true
            let top = try await git(["rev-parse", "--show-toplevel"], in: isFolder ? item : item.deletingLastPathComponent(), runner: runner)
            guard top.status == 0, let topPath = line(top) else {
                states[item] = RepositoryState(root: nil, gitError: firstLine(top.standardError) ?? "git could not read the repository.")
                continue
            }
            let root = URL(fileURLWithPath: topPath)
            if repositories[topPath] == nil { repositories[topPath] = try await readRepository(root, runner: runner) }
            guard let path = itemPath(of: item, facts: facts, inRepository: root) else {
                states[item] = RepositoryState(root: root, gitError: "\(item.path) is outside the repository git found, \(topPath).")
                continue
            }
            found.append((item, topPath, path))
        }
        for (top, entries) in Dictionary(grouping: found, by: \.top) {
            guard let repository = repositories[top] else { continue }
            let kinds = try await kinds(of: entries.map(\.path), in: repository, runner: runner)
            for (entry, kind) in zip(entries, kinds) {
                var state = repository
                state.itemPath = entry.path
                state.kind = kind
                states[entry.item] = state
            }
        }
        return states
    }

    /// What each path is in the repository's commit. The paths go to git on its input, NUL-separated, not as arguments: `Process` hands its
    /// arguments over decomposed, and git that does not precompose them (`core.precomposeunicode=false`) would look up a name that the
    /// commit, and the link, have precomposed.
    private static func kinds(of paths: [[String]], in repository: RepositoryState, runner: any ProcessRunner) async throws -> [RepositoryState.Kind?] {
        guard let commit = repository.commit, let root = repository.root else { return paths.map { _ in nil } }
        var step = GitCommand.step(["cat-file", "--batch-check=%(objecttype)", "-Z"], in: root.path, blanking: GitCommand.Defined())
        step.standardInput = paths.map { commit + ":" + $0.map(\.precomposedStringWithCanonicalMapping).joined(separator: "/") + "\u{0}" }.joined()
        let result = try await runner.run(step, timeout: GitCommand.reading)
        try GitCommand.requireFinished(result, "git cat-file")
        guard result.status == 0 else { return paths.map { _ in nil } }
        var answers = result.standardOutput.split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
        if answers.last == "" { answers.removeLast() }
        guard answers.count == paths.count else { return paths.map { _ in nil } }
        return answers.map { answer -> RepositoryState.Kind? in
            switch answer {
            case "blob": .file
            case "tree": .folder
            case "commit": .submodule
            default: nil
            }
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

    private static func readRepository(_ root: URL, runner: any ProcessRunner) async throws -> RepositoryState {
        let head = try await git(["rev-parse", "--verify", "--quiet", "HEAD^{commit}"], in: root, runner: runner)
        let commit = head.status == 0 ? line(head) : nil
        // `symbolic-ref`, not `rev-parse --abbrev-ref`, which says `heads/main` when a tag is also called main.
        let branch = line(try await git(["symbolic-ref", "-q", "HEAD"], in: root, runner: runner))
            .flatMap { $0.hasPrefix("refs/heads/") ? String($0.dropFirst("refs/heads/".count)) : nil }
        var preferred: [String] = []
        var keys = ["remote.pushDefault"]
        if let branch { keys = ["branch.\(branch).remote", "branch.\(branch).pushRemote"] + keys }
        for key in keys {
            if let name = line(try await git(["config", "--get", key], in: root, runner: runner)) { preferred.append(name) }
        }
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
        if let chosen {
            let got = try await git(["remote", "get-url", chosen], in: root, runner: runner)
            url = got.status == 0 ? line(got) : nil
        }
        return RepositoryState(root: root, remoteName: chosen, remoteNames: names, remoteURL: url, commit: commit, isPushed: pushed)
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
