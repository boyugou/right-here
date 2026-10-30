import Foundation

/// The words of a command line as bash and zsh read them, for looking at what the line says: quotes are taken off (single, double, and `$'…'` with its escapes decoded), a backslash outside
/// single quotes makes the next character a plain one, and `; | & ( ) < >` end a word the way a space does (a redirection such as `>&1` is not part of the word before it). A word ends at its
/// first NUL, as zsh hands it to the program that is started (`$'--flag\0x'` is `--flag`; bash cuts less). Words end at a space, a tab or a line break only: the shells do not split at another
/// kind of space. Whatever the line would make the shell compute, which no reading of the line can know, is said so: `Reading.hasExpansion`; so is an escape in `$'…'` that bash and zsh read
/// differently, a NUL, a glob (the names in the folder are the words), a brace expansion and a history expansion (`!`, which a shell that is typed into expands before it reads the line).
/// It is never used to run or to build a command (that is `ShellQuoting`): it answers whether a typed line carries a word.
enum ShellWords {
    struct Reading: Equatable {
        var words: [String]
        /// Part of the line depends on something that is not in it: a parameter (`$x`, `${x}`), a command (`$(…)`, a backtick), a brace expansion (`{a,b}`, whatever stands between the braces), a glob
        /// (`*`, `?`, `[`), a history expansion (`!` outside single quotes), a quote that is never closed, or an escape of
        /// `$'…'` that the two shells read differently (an unknown one such as `\d`, which bash keeps whole and zsh reads as `d`; `\c`; `\x` or `\u` with no digit after it, which zsh reads as NUL), or a
        /// NUL, after which bash and zsh go on differently.
        var hasExpansion: Bool
    }

    static func split(_ line: String) -> [String] { read(line).words }

    static func hasExpansion(_ line: String) -> Bool { read(line).hasExpansion }

    private enum Quote { case single, double, ansi }

    static func read(_ line: String) -> Reading {
        var words: [String] = []
        var current = String.UnicodeScalarView()
        var inWord = false
        var quote: Quote?
        var escaped = false
        var expansion = false
        var scalars = Array(line.unicodeScalars)[...]

        func endWord() {
            if inWord {
                // A program gets the word up to its first NUL from zsh (`$'A\0B'` is `A`), and bash cuts only the `$'…'` string that holds it (`$'A\0B'x` is `Ax`): the word is read as zsh
                // passes it, which is the shorter one, and the line is said not to be readable.
                let kept = current.prefix { $0 != "\u{0}" }
                if kept.count != current.count { expansion = true }
                words.append(String(String.UnicodeScalarView(kept)))
            }
            current = String.UnicodeScalarView()
            inWord = false
        }

        while let scalar = scalars.popFirst() {
            if escaped {
                escaped = false
                // A backslash and a line break join the line: neither is part of a word.
                if scalar != "\n" { current.append(scalar); inWord = true }
                continue
            }
            switch quote {
            case .single?:
                if scalar == "'" { quote = nil } else { current.append(scalar) }
            case .ansi?:
                if scalar == "'" {
                    quote = nil
                } else if scalar == "\\" {
                    current.append(contentsOf: decodeEscape(&scalars, shellDependent: &expansion).unicodeScalars)
                } else {
                    if scalar == "!" { expansion = true }
                    current.append(scalar)
                }
            case .double?:
                switch scalar {
                case "\"": quote = nil
                case "\\":
                    // Inside double quotes a backslash only takes away the meaning of `$`, a backtick, a quote, a backslash and a line break; before another character it stays.
                    if let next = scalars.first, "$`\"\\\n".unicodeScalars.contains(next) { escaped = true } else { current.append(scalar) }
                case "$", "`", "!":
                    expansion = true
                    current.append(scalar)
                default: current.append(scalar)
                }
            case nil:
                switch scalar {
                case "\\":
                    escaped = true
                    inWord = true
                case "'":
                    quote = .single
                    inWord = true
                case "\"":
                    quote = .double
                    inWord = true
                case "$":
                    if scalars.first == "'" {
                        scalars.removeFirst()
                        quote = .ansi
                        inWord = true
                    } else if scalars.first == "\"" {
                        // `$"…"` is a double-quoted string that the locale may translate.
                        scalars.removeFirst()
                        quote = .double
                        inWord = true
                    } else {
                        expansion = true
                        current.append(scalar)
                        inWord = true
                    }
                case "`":
                    expansion = true
                    current.append(scalar)
                    inWord = true
                case "{":
                    // A brace expansion needs a closing brace in the same word, whatever stands between them (a quoted space, an escaped one); a lone one is a plain character.
                    if closesBrace(scalars) { expansion = true }
                    current.append(scalar)
                    inWord = true
                case "*", "?", "[", "!":
                    // A glob is the names in the folder, and `!` a line of the history: neither is a word that is in the line.
                    expansion = true
                    current.append(scalar)
                    inWord = true
                case ";", "|", "&", "(", ")", "<", ">":
                    // `2>file` is a redirection of a descriptor, and the digit is not a word.
                    if (scalar == ">" || scalar == "<"), inWord, !current.isEmpty, current.allSatisfy({ ("0"..."9").contains($0) }) {
                        current = String.UnicodeScalarView()
                        inWord = false
                    }
                    endWord()
                case " ", "\t", "\n":
                    endWord()
                default:
                    current.append(scalar)
                    inWord = true
                }
            }
        }
        if quote != nil || escaped { expansion = true }
        endWord()
        return Reading(words: words, hasExpansion: expansion)
    }

    /// Whether a `}` that is not quoted ends the word that has just opened a brace: the word goes on until a space, a tab, a line break or one of `; | & ( ) < >` that is not quoted. A
    /// quoted space does not end it, and neither does an escaped one; a quoted `}` does not close it.
    private static func closesBrace(_ rest: ArraySlice<Unicode.Scalar>) -> Bool {
        var quote: Quote?
        var escaped = false
        var index = rest.startIndex
        while index < rest.endIndex {
            let scalar = rest[index]
            index = rest.index(after: index)
            if escaped { escaped = false; continue }
            switch quote {
            case .single?:
                if scalar == "'" { quote = nil }
            case .ansi?:
                if scalar == "\\" { escaped = true } else if scalar == "'" { quote = nil }
            case .double?:
                if scalar == "\\" { escaped = true } else if scalar == "\"" { quote = nil }
            case nil:
                switch scalar {
                case "\\": escaped = true
                case "'": quote = .single
                case "\"": quote = .double
                case "$" where index < rest.endIndex && rest[index] == "'":
                    quote = .ansi
                    index = rest.index(after: index)
                case "}": return true
                case " ", "\t", "\n", ";", "|", "&", "(", ")", "<", ">": return false
                default: break
                }
            }
        }
        return false
    }

    /// One escape of a `$'…'` string, after its backslash, as bash and zsh decode it. An escape that the two read differently is decoded as bash does and `shellDependent` is set, so that the line is
    /// not trusted to say what it starts (measured with /bin/zsh 5.9 and /bin/bash 3.2: `$'\d'` is `\d` to bash and `d` to zsh; `$'\c'` makes a control character in bash and is `c` in zsh).
    private static func decodeEscape(_ scalars: inout ArraySlice<Unicode.Scalar>, shellDependent: inout Bool) -> String {
        guard let next = scalars.popFirst() else { return "\\" }
        switch next {
        case "a": return "\u{07}"
        case "b": return "\u{08}"
        case "e", "E": return "\u{1B}"
        case "f": return "\u{0C}"
        case "n": return "\n"
        case "r": return "\r"
        case "t": return "\t"
        case "v": return "\u{0B}"
        case "\\", "'", "\"", "?": return String(next)
        case "0"..."7":
            var value = next.value - 48
            for _ in 0..<2 {
                guard let digit = scalars.first, ("0"..."7").contains(digit) else { break }
                value = value * 8 + (digit.value - 48)
                scalars.removeFirst()
            }
            // A byte: `\455` is 0x2D (a minus) to the shells. Above 0x7F the bytes make a character only together, which the line says nothing of.
            value &= 0xFF
            if value > 0x7F { shellDependent = true }
            return scalar(value)
        case "x":
            let decoded = hex(&scalars, limit: 2, introducer: "x", shellDependent: &shellDependent)
            if let first = decoded.unicodeScalars.first, first.value > 0x7F { shellDependent = true }
            return decoded
        case "u": return hex(&scalars, limit: 4, introducer: "u", shellDependent: &shellDependent)
        case "U": return hex(&scalars, limit: 8, introducer: "U", shellDependent: &shellDependent)
        case "c":
            shellDependent = true
            guard let control = scalars.popFirst() else { return "\\c" }
            return scalar(control.value & 0x1F)
        default:
            shellDependent = true
            return "\\" + String(next)
        }
    }

    private static func hex(_ scalars: inout ArraySlice<Unicode.Scalar>, limit: Int, introducer: Character, shellDependent: inout Bool) -> String {
        var digits = ""
        while digits.count < limit, let next = scalars.first, next.properties.isASCIIHexDigit {
            digits.unicodeScalars.append(next)
            scalars.removeFirst()
        }
        guard let value = UInt32(digits, radix: 16) else {
            // With no digit bash keeps the escape as it is written and zsh reads a NUL.
            shellDependent = true
            return "\\" + String(introducer)
        }
        return scalar(value)
    }

    private static func scalar(_ value: UInt32) -> String {
        Unicode.Scalar(value).map { String($0) } ?? ""
    }

    /// The words of a flag as it may be spelled: `--approval-mode=yolo` and `--approval-mode yolo` are the same two words to the tools that read flags like this.
    static func flagWords(_ words: [String]) -> [String] {
        words.flatMap { word -> [String] in
            guard word.hasPrefix("-"), let equals = word.firstIndex(of: "=") else { return [word] }
            return [String(word[..<equals]), String(word[word.index(after: equals)...])]
        }
    }

    /// Whether `typed` has the words of `flag` next to each other and in order. A word that is a line of its own (`sh -c 'claude --flag'`, `eval 'claude --flag'`, `env -S 'claude --flag'`) is read
    /// as one, as far as such lines go inside one another.
    static func carries(_ typed: [String], flag: String, depth: Int = 0) -> Bool {
        let wanted = flagWords(split(flag))
        guard !wanted.isEmpty else { return false }
        return carries(typed, wanted: wanted, depth: depth)
    }

    private static func carries(_ typed: [String], wanted: [String], depth: Int) -> Bool {
        let words = flagWords(typed)
        if words.count >= wanted.count, (0...(words.count - wanted.count)).contains(where: { start in Array(words[start..<(start + wanted.count)]) == wanted }) { return true }
        guard depth < 4 else { return false }
        return typed.contains { word in
            let inner = split(word)
            return inner != [word] && carries(inner, wanted: wanted, depth: depth + 1)
        }
    }

    /// The names of the programs a line mentions, whatever stands in front of them (`FOO=1 claude`, `env claude`, `exec claude`, `/usr/local/bin/Claude`, zsh's `=claude`, which is the path of
    /// the program): the last part of each word's path, in lower case, since the file system of a Mac does not tell `Claude` from `claude`.
    static func programNames(in words: [String], depth: Int = 0) -> Set<String> {
        var names = Set(words.map { word in ((word.hasPrefix("=") ? String(word.dropFirst()) : word) as NSString).lastPathComponent.lowercased() }.filter { !$0.isEmpty })
        // A word that is a line of its own (`sh -c 'claude …'`, `eval 'claude …'`) names the programs of that line.
        if depth < 4 {
            for word in words {
                let inner = split(word)
                if inner != [word] { names.formUnion(programNames(in: inner, depth: depth + 1)) }
            }
        }
        return names
    }
}
