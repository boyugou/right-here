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
    /// Single-quoted, `'/Users/me/project/a b.txt'` (backslash-escaped instead when the path has a backslash). It
    /// reads the same in every shell, whichever one the person uses: they may paste it into an ssh session.
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
        let path = facts.onDiskPath(url)
        let name = path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? "/"
        switch style {
        case .absolute:
            return path
        case .tilde:
            return tildePath(url, path: path)
        case .gitRelative:
            return projectPath(url, path: path)
        case .name:
            return name
        case .parent:
            return Self.parent(of: path)
        case .shellEscaped:
            return ShellQuoting.backslashEscape(path)
        case .shellQuoted:
            return Self.shellQuotedForAnyShell(path)
        case .fileURL:
            return Self.fileURLString(path)
        case .aiMention:
            if let base { return mention(Self.onDiskRelative(PathMath.relativePath(from: base, to: url), path: path) ?? path) }
            return mention(projectPath(url, path: path))
        case .markdownLink:
            return "[\(Self.markdownText(name))](\(Self.markdownDestination(projectPath(url, path: path))))"
        }
    }

    private static func parent(of path: String) -> String {
        var parts = path.split(separator: "/", omittingEmptySubsequences: true)
        if !parts.isEmpty { parts.removeLast() }
        return "/" + parts.joined(separator: "/")
    }

    /// A `file://` URL spelled from the on-disk path, percent-encoded the way `URL` does it.
    private static func fileURLString(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: ";?#")
        return "file://" + (path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path)
    }

    /// A path relative to some folder, with the on-disk spelling of its trailing names: the last components of the
    /// full on-disk `path`, as many as the relative path has. A path that climbs out (`..`) is left as it is.
    private static func onDiskRelative(_ relative: String?, path: String) -> String? {
        guard let relative else { return nil }
        let parts = relative.split(separator: "/", omittingEmptySubsequences: true)
        let stored = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.isEmpty, !parts.contains(".."), !parts.contains("."), parts.count <= stored.count else { return relative }
        return stored.suffix(parts.count).joined(separator: "/")
    }

    /// Why these paths cannot be given in a shell form that every shell reads the same way, or `nil`. A name with a
    /// backslash is escaped with backslashes (fish reads a backslash inside single quotes as an escape, the other
    /// shells do not), and a name with a control character cannot be backslash-escaped at all, so a name with both has
    /// no form that is safe to paste into any shell: it is refused, and the person can copy it another way.
    public static func shellFormRefusal(for urls: [URL], style: PathStyle) -> String? {
        guard style == .shellEscaped || style == .shellQuoted else { return nil }
        for url in urls {
            let path = url.lexicallyNormalized.path
            if path.unicodeScalars.contains("\\") && ShellQuoting.containsControlCharacter(path) {
                return "\(url.lastPathComponent.withControlCharactersEscaped) has a backslash and a control character, and no single quoting of that reads the same in every shell (fish reads a backslash inside quotes differently). Copy it as an absolute path instead."
            }
        }
        return nil
    }

    /// POSIX single quotes read identically in sh, bash, zsh and fish unless the text has a backslash (fish takes one
    /// inside single quotes as an escape, so `\'` ends the quoting in the others and not in fish); a backslash-escaped
    /// word reads identically everywhere. So the form follows the text and never the person's login shell: this
    /// text is pasted somewhere, and not necessarily into the shell they log in with.
    static func shellQuotedForAnyShell(_ path: String) -> String {
        path.unicodeScalars.contains("\\") ? ShellQuoting.backslashEscape(path) : ShellQuoting.quote(path, for: .posix)
    }

    private func tildePath(_ url: URL, path: String) -> String {
        let home = facts.onDiskPath(facts.homeDirectory)
        if path == home { return "~" }
        // Scalars again: a combining mark right after the slash would hide it from a Character-level prefix test.
        let scalars = path.unicodeScalars
        if scalars.starts(with: (home + "/").unicodeScalars) {
            return "~" + String(String.UnicodeScalarView(scalars.dropFirst(home.unicodeScalars.count)))
        }
        return path
    }

    private func projectPath(_ url: URL, path: String) -> String {
        guard let root = facts.gitRoot(containing: url) else { return path }
        return Self.onDiskRelative(PathMath.relativePath(from: root, to: url), path: path) ?? path
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
