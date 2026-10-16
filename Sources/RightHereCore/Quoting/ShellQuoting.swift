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
