import Foundation

final class ConfigSink {
    /// Agents whose definition was refused with an error of its own; later checks do not complain about them again.
    var rejectedAgents = Set<String>()
    var items: [ConfigDiagnostic] = []

    /// The text being read, which says how a value was written when the TOML library cannot (`rawValue`).
    private let source: String?
    private var outline: TOMLOutline?

    init(source: String? = nil) {
        self.source = source
    }

    /// The value at this path as it was written, for a problem that is better said with it.
    func rawValue(of path: [String]) -> String? {
        guard let source else { return nil }
        if outline == nil { outline = TOMLOutline(source) }
        return outline?.rawValue(of: path.map(\.withControlCharactersEscaped).joined(separator: "."))
    }

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
