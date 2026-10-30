import Foundation

/// A git host whose web pages Right Here can link to (ADR 0033), by the name its remotes use.
public enum GitHost: String, Sendable, CaseIterable {
    case github = "github.com"
    case gitlab = "gitlab.com"
    case codeberg = "codeberg.org"
    case bitbucket = "bitbucket.org"
}

/// A remote of a repository, as far as a link needs it: the host and the path of the repository there. Nothing else of the remote's URL
/// is kept, so a user name or a password in it never reaches a link.
public struct RepositoryRemote: Equatable, Sendable {
    public let host: GitHost
    /// The owner (on GitLab, the groups) and the repository, without `.git`.
    public let path: [String]
}

public enum RepositoryLinkError: Error, Equatable, Sendable {
    /// Not a form of remote URL that a host serves: another scheme (`ext::`, `file://`), a local path, characters a host does not allow.
    case unreadableRemote
    /// A host other than the four; its name, reduced to the characters a host name has.
    case unknownHost(String)
}

public enum RepositoryLink {
    /// The schemes a host serves a repository over. One string, not a list of quoted words: a test makes sure that only `GitCommand` names
    /// git's program, and it looks for the quoted name.
    private static let remoteSchemes = Set("https http ssh git git+ssh".split(separator: " ").map(String.init))

    /// Reads `https://host/owner/repo(.git)`, `ssh://user@host[:port]/owner/repo.git` and `user@host:owner/repo.git`.
    public static func parse(remote: String) -> Result<RepositoryRemote, RepositoryLinkError> {
        let text = remote.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return .failure(.unreadableRemote)
        }
        let authority: Substring
        let path: Substring
        if let scheme = text.range(of: "://") {
            guard remoteSchemes.contains(text[..<scheme.lowerBound].lowercased()) else { return .failure(.unreadableRemote) }
            let rest = text[scheme.upperBound...]
            guard let slash = rest.firstIndex(of: "/") else { return .failure(.unreadableRemote) }
            authority = rest[..<slash]
            path = rest[rest.index(after: slash)...]
        } else {
            // git reads `host:path` as the scp form only when the colon comes before any slash; otherwise it is a local path.
            guard let colon = text.firstIndex(of: ":"), !text[..<colon].contains("/") else { return .failure(.unreadableRemote) }
            // `<transport>::<address>` (`ext::`, a remote helper) names a program, not a host.
            guard !text[colon...].hasPrefix("::") else { return .failure(.unreadableRemote) }
            authority = text[..<colon]
            path = text[text.index(after: colon)...]
        }
        var host = authority.split(separator: "@", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        if let port = host.lastIndex(of: ":") {
            guard host[host.index(after: port)...].allSatisfy(\.isASCII), host[host.index(after: port)...].allSatisfy(\.isNumber) else {
                return .failure(.unreadableRemote)
            }
            host = String(host[..<port])
        }
        host = host.lowercased()
        guard let known = GitHost(rawValue: host) else {
            // Named only when it reads as a host name: what is left of a token that lost its "@" (`ghp_…:x@host`) or a host
            // with a space in it would otherwise be shown, in an alert, the log or an agent's reply.
            let isHostName = host.contains(".") && host.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-").contains($0) }
            return .failure(isHostName ? .unknownHost(host) : .unreadableRemote)
        }
        var segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if let last = segments.last, last.lowercased().hasSuffix(".git") { segments[segments.count - 1] = String(last.dropLast(4)) }
        guard segments.allSatisfy(isSafeSegment) else { return .failure(.unreadableRemote) }
        switch known {
        case .gitlab: guard segments.count >= 2 else { return .failure(.unreadableRemote) }
        case .github, .codeberg, .bitbucket: guard segments.count == 2 else { return .failure(.unreadableRemote) }
        }
        return .success(RepositoryRemote(host: known, path: segments))
    }

    /// The page of the item at `itemPath` (its path from the git root, by segment; empty for the root) at `commit`, or nil when the commit
    /// is not a full hash or a segment is empty.
    public static func url(remote: RepositoryRemote, commit: String, itemPath: [String], isDirectory: Bool) -> String? {
        guard isFullHash(commit), !itemPath.contains(where: \.isEmpty) else { return nil }
        let base = "https://\(remote.host.rawValue)/" + remote.path.joined(separator: "/")
        let encoded = itemPath.map(encode).joined(separator: "/")
        let tail = encoded.isEmpty ? "" : "/" + encoded
        switch remote.host {
        case .github:
            return base + (isDirectory || encoded.isEmpty ? "/tree/" : "/blob/") + commit + tail
        case .gitlab:
            return base + (isDirectory || encoded.isEmpty ? "/-/tree/" : "/-/blob/") + commit + tail
        case .codeberg:
            return base + "/src/commit/" + commit + tail
        case .bitbucket:
            return base + "/src/" + commit + (encoded.isEmpty ? "/" : tail)
        }
    }

    /// The item's path from the repository's top folder, by segment: empty for the top folder itself, nil outside it.
    public static func itemPath(of item: URL, inRepository root: URL) -> [String]? {
        let base = root.lexicallyNormalized.pathComponents
        let target = item.lexicallyNormalized.pathComponents
        guard target.count >= base.count, Array(target.prefix(base.count)) == base else { return nil }
        return Array(target.dropFirst(base.count))
    }

    private static func isSafeSegment(_ segment: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
        // A leading "-" is no owner or repository on these hosts, and on GitLab it starts the part of a URL that names a page (`/-/tree`).
        return !segment.isEmpty && segment != "." && segment != ".." && !segment.hasPrefix("-") && segment.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isFullHash(_ commit: String) -> Bool {
        (commit.count == 40 || commit.count == 64) && commit.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdef").contains($0) }
    }

    /// Precomposed first: Finder can hand over decomposed names, and git on macOS keeps precomposed ones, which is what the host shows.
    private static func encode(_ segment: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return segment.precomposedStringWithCanonicalMapping.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
