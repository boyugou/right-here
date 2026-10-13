import Foundation

/// Reading TOML text as bytes, without building anything: the part that tells a string from the text around it, shared by
/// the nesting guard (`NestingDepth`) and the outline of a config (`TOMLOutline`), so both read quotes the same way.
enum TOMLScan {
    /// Whether three of `quote` start at `position`.
    static func hasTriple(_ bytes: [UInt8], _ quote: UInt8, at position: Int) -> Bool {
        position + 2 < bytes.count && bytes[position] == quote && bytes[position + 1] == quote && bytes[position + 2] == quote
    }

    /// The string that starts at `start`, a `"` or a `'`: basic or literal, single-line or multi-line. `end` is one past
    /// its closing quote. A single-line string that is not closed ends with its line break (taken in), a multi-line one at the
    /// end of the text, and `terminated` is false.
    static func skipString(_ bytes: [UInt8], at start: Int) -> (end: Int, terminated: Bool) {
        let quote = bytes[start]
        let multiline = hasTriple(bytes, quote, at: start)
        var index = start + (multiline ? 3 : 1)
        while index < bytes.count {
            if quote == UInt8(ascii: "\""), bytes[index] == UInt8(ascii: "\\") { index += 2; continue }
            if multiline {
                if hasTriple(bytes, quote, at: index) {
                    index += 3
                    // TOML lets up to two more quotes sit just before the closing three: `"""a""""` is `a"`.
                    var extra = 0
                    while extra < 2, index < bytes.count, bytes[index] == quote { index += 1; extra += 1 }
                    return (index, true)
                }
            } else if bytes[index] == quote {
                return (index + 1, true)
            } else if bytes[index] == UInt8(ascii: "\n") {
                return (index + 1, false)
            }
            index += 1
        }
        return (min(index, bytes.count), false)
    }
}
