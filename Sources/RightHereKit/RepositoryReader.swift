import Foundation
import RightHereCore

/// Reads what the repository actions need from git (ADR 0033), with commands that start nothing: with git 2.54, in a repository that
/// names a program for every hook, its file system monitor, a filter for every file, a pager and an ssh command, none of `rev-parse`,
/// `config --get`, `remote`, `remote get-url`, `rev-list` and `cat-file -e` started one (`ls-files` started the monitor and is not used).
public enum RepositoryReader {
    /// The state of the repository around each item that is in one; an item outside a repository has no entry.
    public static func read(items: [URL], facts: any SystemFacts, runner: any ProcessRunner = LiveProcessRunner()) async throws -> [URL: RepositoryState] {
        var states: [URL: RepositoryState] = [:]
        var byRoot: [URL: RepositoryState] = [:]
        for item in items {
            guard let root = facts.gitRoot(containing: item), let path = RepositoryLink.itemPath(of: item, inRepository: root) else { continue }
            var state: RepositoryState
            if let known = byRoot[root] {
                state = known
            } else {
                state = try await readRepository(root, runner: runner)
                byRoot[root] = state
            }
            if let commit = state.commit, !path.isEmpty {
                // `<commit>:<path>` keeps a name that starts with "-" a path.
                let found = try await git(["cat-file", "-e", "\(commit):\(path.joined(separator: "/"))"], in: root, runner: runner)
                state.isInCommit = found.status == 0
            } else {
                state.isInCommit = state.commit != nil
            }
            states[item] = state
        }
        return states
    }

    private static func readRepository(_ root: URL, runner: any ProcessRunner) async throws -> RepositoryState {
        let head = try await git(["rev-parse", "--verify", "--quiet", "HEAD^{commit}"], in: root, runner: runner)
        let commit = head.status == 0 ? line(head) : nil
        let branch = line(try await git(["rev-parse", "--abbrev-ref", "HEAD"], in: root, runner: runner))
        var upstream: String?
        if let branch, branch != "HEAD" {
            upstream = line(try await git(["config", "--get", "branch.\(branch).remote"], in: root, runner: runner))
        }
        let names = (try await git(["remote"], in: root, runner: runner)).standardOutput
            .split(separator: "\n").map(String.init).filter(isPlainRemoteName)
        let chosen = upstream.flatMap { names.contains($0) ? $0 : nil } ?? (names.contains("origin") ? "origin" : (names.count == 1 ? names[0] : nil))
        var url: String?
        var pushed = false
        if let chosen {
            let got = try await git(["remote", "get-url", chosen], in: root, runner: runner)
            url = got.status == 0 ? line(got) : nil
            if let commit {
                let unpushed = try await git(["rev-list", "-n1", commit, "--not", "--remotes=\(chosen)"], in: root, runner: runner)
                pushed = unpushed.status == 0 && line(unpushed) == nil
            }
        }
        return RepositoryState(root: root, remoteName: chosen, remoteNames: names, remoteURL: url, commit: commit, isPushed: pushed, isInCommit: false)
    }

    /// A remote name `--remotes=<name>` reads as itself: no glob characters, nothing that is not a plain name.
    private static func isPlainRemoteName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-").contains($0) }
    }

    private static func git(_ arguments: [String], in root: URL, runner: any ProcessRunner) async throws -> ProcessResult {
        let result = try await runner.run(GitCommand.step(arguments, in: root.path, blanking: GitCommand.Defined()), timeout: GitCommand.reading)
        try GitCommand.requireFinished(result, "git \(arguments.first ?? "")")
        return result
    }

    private static func line(_ result: ProcessResult) -> String? {
        let text = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.status == 0 && !text.isEmpty ? text : nil
    }
}
