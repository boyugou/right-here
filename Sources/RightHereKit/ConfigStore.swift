import Foundation
import RightHereCore

/// Where Right Here keeps its files.
public struct RHPaths: Sendable, Equatable {
    public var configDirectory: URL
    public var configFile: URL
    /// The per-machine overlay next to the config file: `config.local.toml` (`<name>.local.toml` for another file name).
    public var localConfigFile: URL {
        let name = configFile.deletingPathExtension().lastPathComponent + ".local." + (configFile.pathExtension.isEmpty ? "toml" : configFile.pathExtension)
        return configFile.deletingLastPathComponent().appendingPathComponent(name)
    }
    /// What `rh config sync` remembers: the folder and the content last synced.
    public var syncStateFile: URL { configDirectory.appendingPathComponent("sync.toml") }
    /// The home the paths were derived from; the default sync folder is under it.
    public var home: URL
    /// `RH_LOG_DIR`, else `~/Library/Logs/right-here`.
    public var logDirectory: URL

    public var logFile: URL { logDirectory.appendingPathComponent("rh.log") }

    /// `RH_CONFIG` names the file itself; `RH_CONFIG_DIR` or `XDG_CONFIG_HOME` name its folder;
    /// otherwise it is `~/.config/right-here/config.toml`.
    public init(environment: [String: String], home: URL) {
        self.home = home
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
    /// The per-machine overlay, `config.local.toml`; it is optional.
    public var localFile: URL
    public var localFileExists: Bool

    public init(result: ConfigLoadResult, fileExists: Bool, file: URL, localFile: URL? = nil, localFileExists: Bool = false) {
        self.result = result
        self.fileExists = fileExists
        self.file = file
        self.localFile = localFile ?? file.deletingLastPathComponent().appendingPathComponent("config.local.toml")
        self.localFileExists = localFileExists
    }

    public var config: Config { result.config }
}

public enum ConfigStore {
    /// Reads the config file. A missing file is not an error: the defaults apply.
    /// A config is a few kilobytes. The menu is built from it on every right-click, so a file far past that (a wrong
    /// path, a log pasted over it) is refused instead of read: parsing 60 MB took four seconds.
    public static let maxConfigBytes = 1_048_576

    public static func load(paths: RHPaths) -> LoadedConfig {
        let base = read(paths.configFile)
        let local = read(paths.localConfigFile)
        let result = ConfigLayers.load(base: base.source, local: local.source, overlayName: paths.localConfigFile.lastPathComponent)
        return LoadedConfig(result: result, fileExists: base.exists, file: paths.configFile, localFile: paths.localConfigFile, localFileExists: local.exists)
    }

    /// What identifies the config as the menu sees it: the modification dates of both files and whether each exists.
    /// A pair, not the later date: an overlay copied in with an older date (`cp -p`, a sync tool) must still count as a change.
    public struct Stamp: Sendable, Equatable {
        var base: Date?
        var local: Date?
    }

    public static func stamp(paths: RHPaths) -> Stamp {
        func modified(_ file: URL) -> Date? {
            // Of what the path leads to: for a config kept as a link (dotfile managers do that), the link's own date never changes.
            (try? FileManager.default.attributesOfItem(atPath: file.resolvingSymlinksInPath().path))?[.modificationDate] as? Date
        }
        return Stamp(base: modified(paths.configFile), local: modified(paths.localConfigFile))
    }

    /// One file: its text, or the reason it was not read.
    private static func read(_ file: URL) -> (source: ConfigSource, exists: Bool) {
        // Through a link: a config kept in a dotfiles repository is a symlink, and the link itself is a few bytes.
        let target = file.resolvingSymlinksInPath().path
        if let size = (try? FileManager.default.attributesOfItem(atPath: target))?[.size] as? Int, size > maxConfigBytes {
            let diagnostic = ConfigDiagnostic(severity: .error, path: "", message: "The file is \(size / 1024) KB; a config is a few kilobytes, so it was not read. Is this the right file?")
            return (.unreadable(diagnostic), true)
        }
        guard let data = try? Data(contentsOf: file) else { return (.absent, false) }
        guard let text = String(data: data, encoding: .utf8) else {
            return (.unreadable(ConfigDiagnostic(severity: .error, path: "", message: "The file is not valid UTF-8.")), true)
        }
        // Some editors put a byte order mark at the start of a UTF-8 file; TOML does not allow one.
        return (.text(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text), true)
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
