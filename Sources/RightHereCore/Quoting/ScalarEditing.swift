import Foundation

extension String {
    /// Replaces each listed Unicode scalar by its replacement text, comparing scalars and nothing else.
    ///
    /// Foundation's `replacingOccurrences` and Swift's `contains` work on grapheme clusters, so a
    /// combining mark, variation selector or emoji modifier after a character hides it: a quote followed
    /// by U+0301 is one `Character` that is not a quote, and is left alone. Anywhere text is made safe
    /// for a shell, a file name or a prompt, the check has to look at scalars, because the shell does.
    public func scalarReplacing(_ replacements: [Unicode.Scalar: String]) -> String {
        var result = String.UnicodeScalarView()
        for scalar in unicodeScalars {
            if let replacement = replacements[scalar] {
                result.append(contentsOf: replacement.unicodeScalars)
            } else {
                result.append(scalar)
            }
        }
        return String(result)
    }

    /// Whether any of the given scalars occurs, whatever follows it.
    public func containsAnyScalar(of scalars: Set<Unicode.Scalar>) -> Bool {
        unicodeScalars.contains { scalars.contains($0) }
    }
}

extension String {
    /// The text with control characters, line separators and paragraph separators replaced by visible
    /// escapes (`\n`, `\t`, `\u001b`). Used wherever a name from the file system is printed or logged:
    /// a name with a newline must not forge a log line, and one with a terminal escape sequence must not
    /// act on a terminal. Other text, backslashes included, is left as it is.
    ///
    /// The escapes are JSON's own (`\uXXXX`), so a line of JSON that has been through this still parses
    /// to the same text: `JSONEncoder` leaves U+007F to U+009F, U+2028 and U+2029 raw, and a different
    /// spelling would have turned them into something no JSON reader accepts.
    /// Marks and embeddings that reorder how text is shown (a name can be made to read differently from what it is).
    private static let bidiControls: Set<Unicode.Scalar> = ["\u{061C}", "\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
                                                           "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}"]

    public var withControlCharactersEscaped: String {
        var result = ""
        for scalar in unicodeScalars {
            switch scalar {
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if Self.bidiControls.contains(scalar) {
                    result += "\\u" + String(repeating: "0", count: 4 - String(scalar.value, radix: 16).count) + String(scalar.value, radix: 16)
                    continue
                }
                switch scalar.properties.generalCategory {
                case .control, .lineSeparator, .paragraphSeparator:
                    let hex = String(scalar.value, radix: 16)
                    result += "\\u" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex
                default: result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
}

