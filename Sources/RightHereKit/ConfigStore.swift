import Foundation
import RightHereCore

/// Where Right Here keeps its files.
public struct RHPaths: Sendable, Equatable {
    public var configDirectory: URL
    public var configFile: URL

    /// `RH_CONFIG` names the file itself; `RH_CONFIG_DIR` or `XDG_CONFIG_HOME` name its folder;
    /// otherwise it is `~/.config/right-here/config.toml`.
    public init(environment: [String: String], home: URL) {
        func expanded(_ path: String) -> URL {
            URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
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
        return LoadedConfig(result: ConfigParser.parse(text), fileExists: true, file: paths.configFile)
    }

    /// Writes a fresh config file unless one exists (or `force` is set). Returns whether it wrote.
    @discardableResult
    public static func initialize(paths: RHPaths, detected: DetectedEnvironment, force: Bool = false) throws -> Bool {
        if FileManager.default.fileExists(atPath: paths.configFile.path), !force { return false }
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        try ConfigTemplate.render(detected).write(to: paths.configFile, atomically: true, encoding: .utf8)
        return true
    }
}
