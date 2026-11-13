import Foundation

/// How Claude Code turns the `@` mentions of a prompt into the files it attaches, as the script bundled with Claude Code 2.1.323 does it (read in its
/// `claude.exe` by an independent review, 2026-11-13). Written from that behaviour, not copied:
/// - a quoted mention `@"…"` (after the start, white space or 。、？！) runs to the next `"`, with no escapes, and one that ends in ` (agent)` names an agent;
/// - otherwise each whitespace-separated word that starts with `@` is cut back to its last ASCII letter, digit or underscore (a `\b` without the `u` flag),
///   and a word with none of them after the `@` is no mention at all;
/// - each mention is then split at a `#` (`file#L3-5` names lines): the file is what stands before a lone `#…` part;
/// - the path is trimmed of white space before it is resolved against the working folder.
enum ClaudeCodeMentionReader {
    private static let beforeAt: Set<Unicode.Scalar> = ["\u{3002}", "\u{3001}", "\u{FF1F}", "\u{FF01}"]

    static func files(in prompt: String) -> [String] {
        var mentions: [String] = []
        let ns = prompt as NSString
        if let quoted = try? NSRegularExpression(pattern: #"(^|[\s\x{3002}\x{3001}\x{FF1F}\x{FF01}])@"([^"]+)""#) {
            for match in quoted.matches(in: prompt, range: NSRange(location: 0, length: ns.length)) {
                let name = ns.substring(with: match.range(at: 2))
                if !name.hasSuffix(" (agent)") { mentions.append(name) }
            }
        }
        for word in prompt.split(whereSeparator: { $0.isWhitespace }) {
            let units = Array(String(word).utf16)
            guard var at = units.firstIndex(of: 0x40) else { continue }
            while at > 0, let previous = Unicode.Scalar(units[at - 1]), !beforeAt.contains(previous) {
                guard let next = units[(at + 1)...].firstIndex(of: 0x40) else { at = -1; break }
                at = next
            }
            guard at >= 0 else { continue }
            func isWord(_ index: Int) -> Bool {
                guard index < units.count else { return false }
                let unit = units[index]
                return (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit) || unit == 0x5F || (0x61...0x7A).contains(unit)
            }
            var end = units.count
            while end >= at + 2, isWord(end - 1) == isWord(end) { end -= 1 }
            guard end >= at + 2 else { continue }
            let mention = String(decoding: units[(at + 1)..<end], as: UTF16.self)
            if !mention.hasPrefix("\"") { mentions.append(mention) }
        }
        var seen = Set<String>()
        return mentions.filter { seen.insert($0).inserted }.map { file(of: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func file(of mention: String) -> String {
        let ns = mention as NSString
        guard let pattern = try? NSRegularExpression(pattern: #"^([^#]+)(?:#L(\d+)(?:-(\d+))?)?(?:#[^#]*)?$"#),
              let match = pattern.firstMatch(in: mention, range: NSRange(location: 0, length: ns.length)),
              match.range(at: 1).location != NSNotFound else { return mention }
        return ns.substring(with: match.range(at: 1))
    }
}
