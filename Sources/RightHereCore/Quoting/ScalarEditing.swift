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
    /// The text with the characters that act on a terminal, or that cannot be seen, replaced by visible escapes (`\n`, `\t`, `\u001b`). Used wherever a name from
    /// the file system or the config is printed, logged or put in front of an AI agent: a name with a newline must not forge a log line, one with a terminal
    /// escape sequence must not act on a terminal, and one with characters that draw nothing must not say one thing to the person and another to a program that
    /// reads it. Other text, backslashes included, is left as it is.
    ///
    /// What is escaped:
    /// - control characters, and line and paragraph separators;
    /// - every format character (category Cf) except the ones a script is written with (the Arabic number signs, the Kaithi and Syriac marks, the Mongolian vowel
    ///   separator, the hieroglyph, shorthand and music controls). That covers the controls that reorder text (U+202E and the like: a name can be made to read backwards),
    ///   the zero-width space, the word joiner, the byte order mark, the soft hyphen and the Unicode tag characters U+E0000 to U+E007F, which draw nothing and spell
    ///   ASCII that a language model reads ("ASCII smuggling": a name that shows as `report.txt` can carry a sentence);
    /// - U+200C and U+200D (the zero-width non-joiner and joiner) unless the scalar before them is a non-ASCII letter, mark or emoji, which is where emoji sequences
    ///   (`👨‍👩‍👧`), Persian and Indic words have them and nowhere else is one visible or meant;
    /// - a variation selector right after another one: a character has one, and a run of them selects nothing and can only carry bytes. The one that selects an emoji or a
    ///   text form (U+FE0F), or an ideographic variant, is left.
    ///
    /// The escapes are JSON's own (`\uXXXX`, and a surrogate pair for a scalar above U+FFFF), so a line of JSON that has been through this still parses to the same text:
    /// `JSONEncoder` leaves U+007F to U+009F, U+2028 and U+2029, and everything above, raw, and a different spelling would have turned them into something no JSON
    /// reader accepts.
    public var withControlCharactersEscaped: String {
        escapingControlCharacters()
    }

    /// The same, for text that has lines of its own (what a command prints, a block of JSON): the scalars in `kept` stay as they are, and a line feed, a carriage return
    /// or a tab not in it is `\n`, `\r` or `\t`. Everything else a terminal acts on or that draws nothing is written as the JSON escape, so what is printed is still
    /// the text it was, to a JSON reader.
    public func escapingControlCharacters(keeping kept: Set<Unicode.Scalar> = []) -> String {
        var result = ""
        var previous: Unicode.Scalar?
        for scalar in unicodeScalars {
            defer { previous = scalar }
            if kept.contains(scalar) {
                result.unicodeScalars.append(scalar)
                continue
            }
            switch scalar {
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if Self.isEscaped(scalar, after: previous) {
                    result += Self.jsonEscape(scalar)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }

    /// Format characters that are part of how a script is written and show something: they are not escaped.
    private static let writtenFormatCharacters: [ClosedRange<UInt32>] = [
        0x0600...0x0605, 0x06DD...0x06DD, 0x070F...0x070F, 0x0890...0x0891, 0x08E2...0x08E2, 0x180E...0x180E, 0x110BD...0x110BD, 0x110CD...0x110CD,
        0x13430...0x1343F, 0x1BCA0...0x1BCA3, 0x1D173...0x1D17A
    ]

    private static func isEscaped(_ scalar: Unicode.Scalar, after previous: Unicode.Scalar?) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator:
            return true
        case .format:
            if scalar == "\u{200C}" || scalar == "\u{200D}" { return !joins(previous) }
            return !writtenFormatCharacters.contains { $0.contains(scalar.value) }
        default:
            if scalar.properties.isVariationSelector { return !selectsSomething(scalar, after: previous) }
            // A mark or a letter that Unicode says to show as nothing (the combining grapheme joiner, the Khmer inherent vowels, the Hangul fillers): a run of them
            // behind a letter reads as nothing and carries bits.
            return scalar.properties.isDefaultIgnorableCodePoint
        }
    }

    /// Whether a variation selector that follows `previous` selects a variant of it, as opposed to carrying a byte. The two presentation selectors (text and emoji) are free wherever they stand: one
    /// bit is all they could carry. One after another selector, or at the start, selects nothing. A selector of the supplement (U+E0100 to U+E01EF, eight bits each) belongs to an ideograph, and
    /// the others to a few non-ASCII characters: after an ASCII letter they select nothing, and spread one after each letter of a name they could carry a sentence behind a name that reads `report.txt`.
    private static func selectsSomething(_ selector: Unicode.Scalar, after previous: Unicode.Scalar?) -> Bool {
        // What draws nothing (another selector, a joiner, the combining grapheme joiner) has no variant: a selector after it selects nothing, and would let one
        // through after an ASCII letter.
        guard let previous, !previous.properties.isDefaultIgnorableCodePoint else { return false }
        if selector.value == 0xFE0E || selector.value == 0xFE0F { return true }
        if (0xE0100...0xE01EF).contains(selector.value) { return previous.properties.isIdeographic }
        return !previous.isASCII
    }

    /// Marks that names in Arabic and Hebrew have and that show something to the reader of that script: the left-to-right and right-to-left marks and the Arabic letter mark.
    private static let readingMarks: Set<UInt32> = [0x200E, 0x200F, 0x061C]

    /// Whether the text has a character that draws nothing or changes how it reads: the ones `changesHowTextReads` lists (a direction override, a zero-width space, a tag character...) and
    /// everything else that `escapingControlCharacters` writes as an escape for being invisible: a format character that no script is written with (the invisible operators of mathematics, say), a
    /// joiner that joins nothing, a variation selector that selects nothing where it stands, and a mark or letter that Unicode shows as nothing (U+034F, U+17B4, U+3164...). The reading marks stay. A name or a prompt that
    /// has one says one thing to the person who looks at it and another to the program that reads it (DESIGN 9.6).
    /// - Parameter ignoringJoiners: Leave the joiners alone. The schema's pattern for a name cannot say where a joiner joins something, and a name that the pattern accepts the parser must not refuse.
    func hasMisleadingCharacter(ignoringJoiners: Bool = false) -> Bool {
        var previous: Unicode.Scalar?
        for scalar in unicodeScalars {
            defer { previous = scalar }
            if ConfigBuilder.changesHowTextReads(scalar) { return true }
            if Self.readingMarks.contains(scalar.value) || (ignoringJoiners && (scalar == "\u{200C}" || scalar == "\u{200D}")) { continue }
            if scalar.properties.generalCategory == .format || scalar.properties.isDefaultIgnorableCodePoint, Self.isEscaped(scalar, after: previous) { return true }
        }
        return false
    }

    /// The name as a person tells two names apart, for checking that two are not the same: what Unicode shows as nothing (a joiner, a selector) left out, white space
    /// folded to single spaces and trimmed, case, width and the form of an accent ignored. "Hel\u{200D}per" and "helper" are one name to a reader, so they are one here.
    public var comparableName: String {
        let shown = String(String.UnicodeScalarView(unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint }))
        let words = shown.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return words.decomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }

    /// Whether a joiner after `previous` has something to join: a non-ASCII letter or mark (Persian, Indic) or an emoji.
    private static func joins(_ previous: Unicode.Scalar?) -> Bool {
        guard let previous, !previous.isASCII else { return false }
        switch previous.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return previous.properties.isAlphabetic || previous.properties.isEmoji
        }
    }

    private static func jsonEscape(_ scalar: Unicode.Scalar) -> String {
        func unit(_ value: UInt32) -> String {
            let hex = String(value, radix: 16)
            return "\\u" + String(repeating: "0", count: Swift.max(0, 4 - hex.count)) + hex
        }
        guard scalar.value > 0xFFFF else { return unit(scalar.value) }
        let offset = scalar.value - 0x10000
        return unit(0xD800 + (offset >> 10)) + unit(0xDC00 + (offset & 0x3FF))
    }

    /// The text as a JSON string literal, for printing a value where it must read back as exactly that text: in double
    /// quotes, `\` and `"` escaped, control characters, separators and bidirectional controls written as `\n`, `\t` or
    /// `\uXXXX` (so it cannot act on a terminal), everything else, non-ASCII included, as it is. A plan prints every
    /// path, argument and text this way. `JSONEncoder` is not used for it: it leaves U+0080 to U+009F raw, and a C1
    /// control such as U+009B is a control sequence introducer to some terminals.
    public var jsonQuoted: String {
        "\"" + scalarReplacing(["\\": "\\\\", "\"": "\\\""]).withControlCharactersEscaped + "\""
    }
}

