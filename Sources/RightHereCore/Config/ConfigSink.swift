import Foundation

final class ConfigSink {
    /// Agents whose definition was refused with an error of its own; later checks do not complain about them again.
    var rejectedAgents = Set<String>()
    var items: [ConfigDiagnostic] = []

    func error(_ path: [String], _ message: String, suggestion: Hint? = nil) {
        items.append(ConfigDiagnostic(severity: .error, path: path.joined(separator: "."), message: message,
                                      suggestion: suggestion?.text, replacement: suggestion?.replacement))
    }

    func warning(_ path: [String], _ message: String, suggestion: Hint? = nil) {
        items.append(ConfigDiagnostic(severity: .warning, path: path.joined(separator: "."), message: message,
                                      suggestion: suggestion?.text, replacement: suggestion?.replacement))
    }

    func syntaxError(_ message: String, line: Int? = nil) {
        items.append(ConfigDiagnostic(severity: .error, path: "", message: "TOML syntax error: " + message, line: line))
    }
}
