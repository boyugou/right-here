import Foundation

public struct ConfigDiagnostic: Sendable, Equatable, Codable {
    public enum Severity: String, Sendable, Codable {
        case error
        case warning
        /// Something to know that needs no action: it never fails `--strict`, and it is only in `ConfigLoadResult.notes`.
        case note
    }

    public var severity: Severity
    /// Dotted location in the file, for example `agent.claude.launcher`; empty for the whole file.
    public var path: String
    public var message: String
    /// Line number, known for syntax errors.
    public var line: Int?
    /// A concrete fix, for example `did you mean "terminal"?`.
    public var suggestion: String?
    /// The text to put in place of the wrong key or value, when there is a likely candidate.
    public var replacement: String?
    /// The file name when the problem is in the per-machine overlay (`config.local.toml`); `nil` means the main config.
    public var file: String?

    /// A diagnostic quotes the config: a key, a value, an id. Those are text somebody else may have written (a config
    /// that came through the sync folder), and they are printed to terminals, logs and tool output, so every string is
    /// stored with control characters escaped (`\u001b`): an escape sequence in a key name must not act on a terminal.
    public init(severity: Severity, path: String, message: String, line: Int? = nil, suggestion: String? = nil, replacement: String? = nil, file: String? = nil) {
        self.severity = severity
        self.path = path.withControlCharactersEscaped
        self.message = message.withControlCharactersEscaped
        self.line = line
        self.suggestion = suggestion?.withControlCharactersEscaped
        self.replacement = replacement?.withControlCharactersEscaped
        self.file = file
    }

    /// One line for a terminal or a log: `error: config.toml:3 [agent.claude.launcher]: message (suggestion)`.
    public func summary(file: URL) -> String {
        var text = "\(severity.rawValue): \((self.file ?? file.lastPathComponent).withControlCharactersEscaped)"
        if let line { text += ":\(line)" }
        if !path.isEmpty { text += " [\(path)]" }
        text += ": \(message)"
        if let suggestion { text += " (\(suggestion))" }
        return text
    }
}

/// Where one entry of a list of tables that the config shows is written: its id as the parser reads it, the file that holds it, and its place among the entries of that file.
public struct ConfigEntryOrigin: Sendable, Equatable {
    public var id: String?
    public var target: ConfigTarget
    public var position: Int

    public init(id: String?, target: ConfigTarget, position: Int) {
        self.id = id
        self.target = target
        self.position = position
    }
}

public struct ConfigLoadResult: Sendable, Equatable {
    public var config: Config
    /// Errors and warnings: what is wrong, and what `--strict` fails on.
    public var diagnostics: [ConfigDiagnostic]
    /// What the config's own settings did that is no mistake and cannot be silenced (a preset left out because its agent is
    /// disabled on this machine). Kept apart from `diagnostics`, which every consumer counts as problems.
    public var notes: [ConfigDiagnostic]
    /// The entries of each list of tables that the config shows (`preset`, `new_file.template`, `agent.claude.variant`), in order, with the file and the place each is written at. What the merge
    /// of the two files leaves out (an entry the other file replaces, one that `disabled` takes away) is not here, so this is the config's own view of where its entries are.
    public var entryOrigins: [String: [ConfigEntryOrigin]]

    public init(config: Config, diagnostics: [ConfigDiagnostic], notes: [ConfigDiagnostic] = [], entryOrigins: [String: [ConfigEntryOrigin]] = [:]) {
        self.config = config
        self.diagnostics = diagnostics
        self.notes = notes
        self.entryOrigins = entryOrigins
    }

    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
}
