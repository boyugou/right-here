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
public enum ShellQuoting {
    private static let bareSafe: Set<Character> = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.,:+@/-"
    )

    /// Quote one word so the shell reads it back as exactly `value`.
    public static func quote(_ value: String, for flavor: ShellFlavor = .posix) -> String {
        if value.isEmpty { return "''" }
        if value.allSatisfy({ bareSafe.contains($0) }) { return value }
        switch flavor {
        case .posix:
            return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        case .fish:
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            return "'" + escaped + "'"
        }
    }

    public static func join(_ words: [String], for flavor: ShellFlavor = .posix) -> String {
        words.map { quote($0, for: flavor) }.joined(separator: " ")
    }

    /// Escape with backslashes the way terminals do for a dropped path. Text with control
    /// characters cannot be backslash-escaped, so it falls back to single quotes.
    public static func backslashEscape(_ value: String) -> String {
        if value.isEmpty { return "''" }
        if value.unicodeScalars.contains(where: { isControl($0) }) { return quote(value) }
        var result = ""
        for character in value {
            if bareSafe.contains(character) || !character.isASCII {
                result.append(character)
            } else {
                result.append("\\")
                result.append(character)
            }
        }
        return result
    }

    /// Reject text that must not be typed into a terminal.
    public static func validateForTyping(_ value: String) throws(ShellQuotingError) {
        if value.unicodeScalars.contains(where: { isControl($0) }) {
            throw .unsafeForTyping(value)
        }
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }
}
