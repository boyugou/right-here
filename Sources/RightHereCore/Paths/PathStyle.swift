import Foundation

/// The forms a path can be copied in.
public enum PathStyle: String, Sendable, Codable, CaseIterable {
    /// `/Users/me/project/a b.txt`
    case absolute
    /// `~/project/a b.txt` (absolute outside the home directory)
    case tilde
    /// `src/a.txt`, relative to the git root (absolute outside a repository)
    case gitRelative = "git-relative"
    /// `a b.txt`
    case name
    /// The folder holding the item.
    case parent
    /// Backslash-escaped, ready to paste into a shell: `/Users/me/project/a\ b.txt`
    case shellEscaped = "shell-escaped"
    /// Single-quoted: `'/Users/me/project/a b.txt'`
    case shellQuoted = "shell-quoted"
    /// `file:///Users/me/project/a%20b.txt`
    case fileURL = "file-url"
    /// `@src/a.txt`, the form AI coding agents read as a file reference.
    case aiMention = "ai-mention"
    /// `[a.txt](src/a.txt)`
    case markdownLink = "markdown-link"

    /// How several items are joined: shell words and mentions sit on one line, the rest one per line.
    public var separator: String {
        switch self {
        case .shellEscaped, .shellQuoted, .aiMention: return " "
        default: return "\n"
        }
    }
}

public struct PathRenderer: Sendable {
    private let facts: any SystemFacts

    public init(facts: any SystemFacts) {
        self.facts = facts
    }

    /// - Parameter base: A known working directory. Mentions are then relative to it (or absolute
    ///   outside it), because that is where the agent that reads them will run.
    public func render(_ urls: [URL], style: PathStyle, relativeTo base: URL? = nil) -> String {
        urls.map { render($0, style: style, relativeTo: base) }.joined(separator: style.separator)
    }

    public func render(_ url: URL, style: PathStyle, relativeTo base: URL? = nil) -> String {
        let url = url.lexicallyNormalized
        switch style {
        case .absolute:
            return url.path
        case .tilde:
            return tildePath(url)
        case .gitRelative:
            return projectPath(url)
        case .name:
            return url.lastPathComponent
        case .parent:
            return url.deletingLastPathComponent().path
        case .shellEscaped:
            return ShellQuoting.backslashEscape(url.path)
        case .shellQuoted:
            return ShellQuoting.quote(url.path, for: facts.shellFlavor)
        case .fileURL:
            return url.absoluteString
        case .aiMention:
            if let base { return mention(PathMath.relativePath(from: base, to: url) ?? url.path) }
            return mention(projectPath(url))
        case .markdownLink:
            return "[\(Self.markdownText(url.lastPathComponent))](\(Self.markdownDestination(projectPath(url))))"
        }
    }

    private func tildePath(_ url: URL) -> String {
        let home = facts.homeDirectory.lexicallyNormalized.path
        if url.path == home { return "~" }
        if url.path.hasPrefix(home + "/") { return "~" + url.path.dropFirst(home.count) }
        return url.path
    }

    private func projectPath(_ url: URL) -> String {
        guard let root = facts.gitRoot(containing: url) else { return url.path }
        return PathMath.relativePath(from: root, to: url) ?? url.path
    }

    /// `@path`, or `@"path"` when it has whitespace; inside the quotes a quote or backslash is escaped, so
    /// no name can end the mention early and carry on as ordinary prompt text.
    private func mention(_ path: String) -> String {
        guard path.unicodeScalars.contains(where: { $0.properties.isWhitespace }) else { return "@" + path }
        return "@\"" + path.scalarReplacing(["\\": "\\\\", "\"": "\\\""]) + "\""
    }

    /// Link text with CommonMark's inline specials escaped, so a name with `]` or `*` stays one plain label.
    static func markdownText(_ text: String) -> String {
        var escaped: [Unicode.Scalar: String] = [:]
        for scalar in "\\`*_[]<>&".unicodeScalars { escaped[scalar] = "\\" + String(scalar) }
        return text.scalarReplacing(escaped)
    }

    /// A link destination: bare when it has nothing awkward in it, else inside `<…>` with `<`, `>` and
    /// backslash escaped. A line break cannot appear in a destination at all, so it is percent-encoded.
    static func markdownDestination(_ path: String) -> String {
        let awkward = path.unicodeScalars.contains { "()<>\\".unicodeScalars.contains($0) || $0.properties.isWhitespace || $0.properties.generalCategory == .control }
        guard awkward else { return path }
        let escaped = path.scalarReplacing(["\\": "\\\\", "<": "\\<", ">": "\\>", "\n": "%0A", "\r": "%0D"])
        return "<" + escaped + ">"
    }
}

enum PathMath {
    /// `""`-free relative path from `base` to `target`: `"."` when they are the same item,
    /// `nil` when `target` is not inside `base`.
    static func relativePath(from base: URL, to target: URL) -> String? {
        let baseComponents = base.lexicallyNormalized.pathComponents
        let targetComponents = target.lexicallyNormalized.pathComponents
        guard targetComponents.count >= baseComponents.count,
              Array(targetComponents.prefix(baseComponents.count)) == baseComponents else { return nil }
        let rest = targetComponents.dropFirst(baseComponents.count)
        return rest.isEmpty ? "." : rest.joined(separator: "/")
    }
}
