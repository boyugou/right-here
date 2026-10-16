import Foundation
import RightHereCore

/// A config file that is there and cannot be used as the config: the text is not TOML, or the file cannot be read (no permission, past the
/// size limit, not UTF-8), or it is a link to a file that is not there. What is built from such a config is built from the defaults, which
/// is not what the person has, so setup does not use it for anything and does not compute edits against it: it says so, and the file stays
/// as it is, because a config is never rewritten.
///
/// A problem with a key or a value is no such problem: the rest of the file still applies, and the doctor and `rh config validate` list it.
struct ConfigProblem: Sendable, Equatable {
    var file: URL
    /// What is wrong, as a clause: `line 1: TOML syntax error: ...`, `cannot read ...: Permission denied`, `it is a link to ..., which does not exist`.
    var reason: String

    /// The first of the two files of the config (`config.toml`, then the per-machine overlay) that cannot be used, or `nil` when each can.
    init?(_ result: ConfigLoadResult, paths: RHPaths) {
        for file in [paths.configFile, paths.localConfigFile] {
            let isOverlay = file == paths.localConfigFile
            if let target = Self.danglingTarget(of: file) {
                self.init(file: file, reason: "it is a link to \(target.withControlCharactersEscaped), which does not exist")
                return
            }
            // A problem with a file as a whole has no key: its path is empty (`ConfigDiagnostic.path`).
            if let error = result.diagnostics.first(where: { $0.severity == .error && $0.path.isEmpty && ($0.file != nil) == isOverlay }) {
                self.init(file: file, reason: (error.line.map { "line \($0): " } ?? "") + error.message)
                return
            }
        }
        return nil
    }

    /// Where `file` points, when it is a link to a file that is not there. `ConfigStore` reads such a link as no file at all, so the entry is
    /// looked for as it is, not through the link.
    static func danglingTarget(of file: URL) -> String? {
        var status = stat()
        guard lstat(file.path, &status) == 0, !FileManager.default.fileExists(atPath: file.path) else { return nil }
        return (try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)) ?? ""
    }

    init(file: URL, reason: String) {
        self.file = file
        self.reason = reason
    }

    /// `/path/config.toml cannot be used (line 1: ...)`.
    var sentence: String { "\(file.path) cannot be used (\(reason))" }
}
