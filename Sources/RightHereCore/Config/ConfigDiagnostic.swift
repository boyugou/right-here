import Foundation

public struct ConfigDiagnostic: Sendable, Equatable, Codable {
    public enum Severity: String, Sendable, Codable {
        case error
        case warning
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

    public init(severity: Severity, path: String, message: String, line: Int? = nil, suggestion: String? = nil, replacement: String? = nil) {
        self.severity = severity
        self.path = path
        self.message = message
        self.line = line
        self.suggestion = suggestion
        self.replacement = replacement
    }

    /// One line for a terminal or a log: `error: config.toml:3 [agent.claude.launcher]: message (suggestion)`.
    public func summary(file: URL) -> String {
        var text = "\(severity.rawValue): \(file.lastPathComponent)"
        if let line { text += ":\(line)" }
        if !path.isEmpty { text += " [\(path)]" }
        text += ": \(message)"
        if let suggestion { text += " (\(suggestion))" }
        return text
    }
}

public struct ConfigLoadResult: Sendable, Equatable {
    public var config: Config
    public var diagnostics: [ConfigDiagnostic]

    public init(config: Config, diagnostics: [ConfigDiagnostic]) {
        self.config = config
        self.diagnostics = diagnostics
    }

    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
}
