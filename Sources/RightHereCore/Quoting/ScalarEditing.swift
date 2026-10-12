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
    /// escapes (`\n`, `\t`, `\u{1b}`). Used wherever a name from the file system is printed or logged:
    /// a name with a newline must not forge a log line, and one with a terminal escape sequence must not
    /// act on a terminal. Other text, backslashes included, is left as it is.
    public var withControlCharactersEscaped: String {
        var result = ""
        for scalar in unicodeScalars {
            switch scalar {
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                switch scalar.properties.generalCategory {
                case .control, .lineSeparator, .paragraphSeparator: result += "\\u{\(String(scalar.value, radix: 16))}"
                default: result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
}

