import Foundation
import RightHereCore

/// Where Right Here keeps its files.
public struct RHPaths: Sendable, Equatable {
    public var configDirectory: URL
    public var configFile: URL
    /// `RH_LOG_DIR`, else `~/Library/Logs/right-here`.
    public var logDirectory: URL

    public var logFile: URL { logDirectory.appendingPathComponent("rh.log") }

    /// `RH_CONFIG` names the file itself; `RH_CONFIG_DIR` or `XDG_CONFIG_HOME` name its folder;
    /// otherwise it is `~/.config/right-here/config.toml`.
    public init(environment: [String: String], home: URL) {
        func expanded(_ path: String) -> URL {
            URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        if let logs = environment["RH_LOG_DIR"], !logs.isEmpty {
            logDirectory = expanded(logs)
        } else {
            logDirectory = home.appendingPathComponent("Library/Logs/right-here")
        }
        if let file = environment["RH_CONFIG"], !file.isEmpty {
            configFile = expanded(file)
            configDirectory = configFile.deletingLastPathComponent()
            return
        }
        if let directory = environment["RH_CONFIG_DIR"], !directory.isEmpty {
            configDirectory = expanded(directory)
        } else if let base = environment["XDG_CONFIG_HOME"], !base.isEmpty {
            configDirectory = expanded(base).appendingPathComponent("right-here")
        } else {
            configDirectory = home.appendingPathComponent(".config/right-here")
        }
        configFile = configDirectory.appendingPathComponent("config.toml")
    }

    public static func current(facts: any SystemFacts = LiveSystemFacts()) -> RHPaths {
        RHPaths(environment: ProcessInfo.processInfo.environment, home: facts.homeDirectory)
    }
}

public struct LoadedConfig: Sendable, Equatable {
    public var result: ConfigLoadResult
    public var fileExists: Bool
    public var file: URL

    public var config: Config { result.config }
}

public enum ConfigStore {
    /// Reads the config file. A missing file is not an error: the defaults apply.
    public static func load(paths: RHPaths) -> LoadedConfig {
        guard let data = try? Data(contentsOf: paths.configFile) else {
            return LoadedConfig(result: ConfigLoadResult(config: .default, diagnostics: []), fileExists: false, file: paths.configFile)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            let diagnostic = ConfigDiagnostic(severity: .error, path: "", message: "The file is not valid UTF-8.")
            return LoadedConfig(result: ConfigLoadResult(config: .default, diagnostics: [diagnostic]), fileExists: true, file: paths.configFile)
        }
        // Some editors put a byte order mark at the start of a UTF-8 file; TOML does not allow one.
        let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        return LoadedConfig(result: ConfigParser.parse(body), fileExists: true, file: paths.configFile)
    }

    public enum InitializeOutcome: Sendable, Equatable {
        case created
        /// An existing file was replaced because `force` was set; the old one was copied here first.
        case replaced(backup: URL)
        case kept
    }

    /// Writes a fresh config file unless one exists. With `force` an existing file is replaced, after
    /// a copy of it is saved next to it (`config.toml.bak-<date>`), since it may hold hand-made settings.
    @discardableResult
    public static func initialize(paths: RHPaths, detected: DetectedEnvironment, force: Bool = false, now: Date = Date()) throws -> InitializeOutcome {
        let exists = FileManager.default.fileExists(atPath: paths.configFile.path)
        if exists, !force { return .kept }
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        var backup: URL?
        if exists {
            let copy = backupURL(for: paths.configFile, now: now)
            try FileManager.default.copyItem(at: paths.configFile, to: copy)
            backup = copy
        }
        try ConfigTemplate.render(detected).write(to: paths.configFile, atomically: true, encoding: .utf8)
        return backup.map { .replaced(backup: $0) } ?? .created
    }

    /// `config.toml.bak-20261011-215500`, numbered when that name is taken.
    static func backupURL(for file: URL, now: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".bak-" + formatter.string(from: now))
        var candidate = base
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = URL(fileURLWithPath: base.path + "-\(number)")
            number += 1
        }
        return candidate
    }
}
