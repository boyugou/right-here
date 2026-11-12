import Foundation

/// The family of shell syntax a piece of text will be read by.
public enum ShellFlavor: String, Sendable, Codable, CaseIterable {
    /// sh, bash, zsh, dash, ksh.
    case posix
    /// fish treats a backslash inside single quotes as an escape character.
    case fish

    public init(loginShellPath: String) {
        switch URL(fileURLWithPath: loginShellPath).lastPathComponent {
        case "fish": self = .fish
        default: self = .posix
        }
    }
}

public enum ShellQuotingError: Error, Equatable, Sendable {
    /// Text typed into a terminal is read as keystrokes: a line break would run the
    /// command early and other control characters would be interpreted by the terminal.
    case unsafeForTyping(String)
}

/// The single place where user-derived text becomes shell syntax.
///
/// Everything here works on Unicode scalars, never on `Character`s: a shell reads bytes, so a quote or a
/// semicolon followed by a combining mark is still a quote or a semicolon.
public enum ShellQuoting {
    private static let bareSafe: Set<Unicode.Scalar> = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.,:+@/-".unicodeScalars
    )

    /// Quote one word so the shell reads it back as exactly `value`.
    public static func quote(_ value: String, for flavor: ShellFlavor = .posix) -> String {
        if value.isEmpty { return "''" }
        if value.unicodeScalars.allSatisfy({ bareSafe.contains($0) }) { return value }
        switch flavor {
        case .posix:
            return "'" + value.scalarReplacing(["'": "'\\''"]) + "'"
        case .fish:
            return "'" + value.scalarReplacing(["\\": "\\\\", "'": "\\'"]) + "'"
        }
    }

    /// One word of text a person pastes into a shell of their own (Copy Path's shell-quoted form), which may be csh or tcsh: they expand `!` (history) even
    /// inside single quotes, and `!#:1` is the quoted word before it with its quote, so a file name could close the quoting and run what follows. `!` is written
    /// outside the quotes, escaped (`'\!'`), which sh, bash, zsh, dash, ksh, fish and tcsh all read as `!` (measured on macOS 27.2). A line Right Here types into
    /// a terminal is written with `quoteTyped`, which no shell reads otherwise.
    public static func quotePasted(_ value: String) -> String {
        let quoted = quote(value, for: .posix)
        guard value.unicodeScalars.contains("!") else { return quoted }
        return quoted.scalarReplacing(["!": "'\\!'"])
    }

    /// Single quotes as PowerShell reads them: it takes ‘ ’ ‚ ‛ for `'`.
    static let singleQuotes: Set<Unicode.Scalar> = ["'", "\u{2018}", "\u{2019}", "\u{201A}", "\u{201B}"]
    /// Double quotes as PowerShell reads them: “ ” „ for `"`.
    static let doubleQuotes: Set<Unicode.Scalar> = ["\"", "\u{201C}", "\u{201D}", "\u{201E}"]
    /// What some shells read inside double quotes besides a backslash and `!`: a variable, a command.
    static let readInsideDoubleQuotes: Set<Unicode.Scalar> = ["$", "`"]
    /// What every shell reads as itself outside quotes (PowerShell reads `,` as an array and `@` as splatting, nushell `:` and `@` in some places).
    static let typedBareSafe: Set<Unicode.Scalar> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./+-".unicodeScalars)

    /// One word of a line that is typed into a terminal, or handed to the login shell to read. Terminal.app, iTerm and Ghostty run the shell their own settings
    /// name, so which shell reads it cannot be known: sh, bash, zsh, dash, ksh, fish, csh, tcsh, nushell, elvish and PowerShell all read the word as `value`. It
    /// is written as quoted runs with nothing between them. What holds no single quote goes in single quotes, inside which nushell, elvish and PowerShell take no
    /// escape at all, so POSIX's `'\''` would end their quoting where a name says (PowerShell also takes ‘ ’ ‚ ‛ for a single quote). A single quote goes in a run
    /// of double quotes, which holds nothing these shells read inside them (`"`, “ ” „, `$`, `` ` ``). `!`, which csh and tcsh expand inside both kinds, stands
    /// outside them as `\!` (sh, bash, zsh, fish and tcsh read `!`; nushell, elvish and PowerShell keep the backslash, which is wrong text but runs nothing). No
    /// other character is ever outside quotes. A backslash (fish reads one inside single quotes, most shells inside double quotes) or a control character cannot
    /// be typed the same everywhere: `nil`, which every caller has refused before.
    public static func quoteTyped(_ value: String) -> String? {
        if value.isEmpty { return "''" }
        let scalars = value.unicodeScalars
        if scalars.contains("\\") || scalars.contains(where: { isControl($0) }) { return nil }
        if scalars.allSatisfy({ typedBareSafe.contains($0) }) { return value }
        // Each scalar's kind of run: one that is a single quote needs double quotes, one that double quotes would read needs single quotes, the rest go with either.
        func needsDouble(_ scalar: Unicode.Scalar) -> Bool { singleQuotes.contains(scalar) }
        func needsSingle(_ scalar: Unicode.Scalar) -> Bool { doubleQuotes.contains(scalar) || readInsideDoubleQuotes.contains(scalar) }
        var double = scalars.first(where: { needsDouble($0) || needsSingle($0) }).map(needsDouble) ?? false
        var result = String.UnicodeScalarView()
        var run = String.UnicodeScalarView()
        func close() {
            guard !run.isEmpty else { return }
            let quote: Unicode.Scalar = double ? "\"" : "'"
            result.append(quote)
            result.append(contentsOf: run)
            result.append(quote)
            run.removeAll()
        }
        for scalar in scalars {
            if scalar == "!" {
                close()
                result.append(contentsOf: "\\!".unicodeScalars)
                continue
            }
            if needsDouble(scalar), !double { close(); double = true }
            if needsSingle(scalar), double { close(); double = false }
            run.append(scalar)
        }
        close()
        return String(result)
    }

    /// What a terminal that starts a program (WezTerm, kitty, Alacritty) is given to type `line` in the login shell and then stay in it. A login, interactive shell
    /// (`-lic`) reads the person's PATH; csh and tcsh take `-l` only as their one option ("Unknown option: `-lic'", measured), so they get `-ic`, which reads their rc
    /// file. The shell that stays is a login shell (`-l` alone).
    public static func shellArguments(loginShell shell: String, typing line: String) -> [String] {
        let cshFamily = ["csh", "tcsh"].contains(URL(fileURLWithPath: shell).lastPathComponent)
        // A login shell's path has no backslash or control character; the POSIX form stands in if one ever did.
        return [shell, cshFamily ? "-ic" : "-lic", line + "; exec " + (quoteTyped(shell) ?? quote(shell)) + " -l"]
    }

    /// Escape with backslashes the way terminals do for a dropped path. Text with control
    /// characters cannot be backslash-escaped, so it falls back to single quotes.
    public static func backslashEscape(_ value: String) -> String {
        if value.isEmpty { return "''" }
        if value.unicodeScalars.contains(where: { isControl($0) }) { return quote(value) }
        var result = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            if bareSafe.contains(scalar) || !scalar.isASCII {
                result.append(scalar)
            } else {
                result.append("\\")
                result.append(scalar)
            }
        }
        return String(result)
    }

    /// Reject text that must not be typed into a terminal.
    public static func validateForTyping(_ value: String) throws(ShellQuotingError) {
        if value.unicodeScalars.contains(where: { isControl($0) }) {
            throw .unsafeForTyping(value)
        }
    }

    /// Whether the text holds a control character, a line separator or a paragraph separator.
    public static func containsControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains(where: { isControl($0) })
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }
}
