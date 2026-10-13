import Foundation

/// How deeply a JSON or TOML text nests its arrays and objects, found by scanning bytes without building anything.
///
/// The decoders recurse once per level, and the stack of a Swift concurrency thread is small: measured, an array
/// nested 480 deep (a request of about a kilobyte) overflowed it and killed `rh mcp`, and a config nested a few
/// hundred deep killed every `rh` command. Honest messages and configs nest a handful of levels, so a text nested
/// past a generous limit is refused before any decoder sees it.
public enum NestingDepth {
    /// Whether `bytes` (JSON) opens `[` or `{` more than `limit` levels deep. Brackets inside strings do not count.
    public static func jsonExceeds(_ bytes: some Sequence<UInt8>, limit: Int) -> Bool {
        var depth = 0
        var inString = false
        var escaped = false
        for byte in bytes {
            if inString {
                if escaped { escaped = false } else if byte == UInt8(ascii: "\\") { escaped = true } else if byte == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "["), UInt8(ascii: "{"):
                depth += 1
                if depth > limit { return true }
            case UInt8(ascii: "]"), UInt8(ascii: "}"): depth = max(0, depth - 1)
            default: break
            }
        }
        return false
    }

    /// Whether `text` (TOML) opens `[` or `{` more than `limit` levels deep. Brackets inside strings (basic, literal
    /// and the multi-line forms) and comments do not count; a table header such as `[[agent.claude.variant]]` is
    /// two levels while it lasts.
    public static func tomlExceeds(_ text: String, limit: Int) -> Bool {
        let bytes = Array(text.utf8)
        var depth = 0
        var index = 0
        // The decoder also recurses once per segment of a dotted key (`a.b.c = 1`), about 8 KB of stack each, and
        // 200 segments killed `rh`. A chain is segments joined by dots; any other punctuation ends it, so the
        // single dot of a float never builds one.
        var chain = 0
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "#"):
                while index < bytes.count && bytes[index] != UInt8(ascii: "\n") { index += 1 }
                continue
            case UInt8(ascii: "\""), UInt8(ascii: "'"):
                index = TOMLScan.skipString(bytes, at: index).end
                continue
            case UInt8(ascii: "["), UInt8(ascii: "{"):
                chain = 0
                depth += 1
                if depth > limit { return true }
            case UInt8(ascii: "]"), UInt8(ascii: "}"):
                chain = 0
                depth = max(0, depth - 1)
            case UInt8(ascii: "."):
                chain += 1
                if chain > limit { return true }
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "_"), UInt8(ascii: "-"), UInt8(ascii: " "), UInt8(ascii: "\t"):
                break
            default:
                chain = 0
            }
            index += 1
        }
        return false
    }
}
