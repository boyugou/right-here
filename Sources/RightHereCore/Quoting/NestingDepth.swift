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
        func hasPrefix(_ quote: UInt8, at position: Int) -> Bool {
            position + 2 < bytes.count && bytes[position] == quote && bytes[position + 1] == quote && bytes[position + 2] == quote
        }
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "#"):
                while index < bytes.count && bytes[index] != UInt8(ascii: "\n") { index += 1 }
                continue
            case UInt8(ascii: "\""), UInt8(ascii: "'"):
                let multiline = hasPrefix(byte, at: index)
                index += multiline ? 3 : 1
                while index < bytes.count {
                    if byte == UInt8(ascii: "\""), bytes[index] == UInt8(ascii: "\\") { index += 2; continue }
                    if multiline {
                        if hasPrefix(byte, at: index) {
                            index += 3
                            // TOML lets up to two more quotes sit just before the closing three: `"""a""""` is `a"`.
                            var extra = 0
                            while extra < 2, index < bytes.count, bytes[index] == byte { index += 1; extra += 1 }
                            break
                        }
                    } else if bytes[index] == byte || bytes[index] == UInt8(ascii: "\n") {
                        index += 1
                        break
                    }
                    index += 1
                }
                continue
            case UInt8(ascii: "["), UInt8(ascii: "{"):
                depth += 1
                if depth > limit { return true }
            case UInt8(ascii: "]"), UInt8(ascii: "}"):
                depth = max(0, depth - 1)
            default:
                break
            }
            index += 1
        }
        return false
    }
}
