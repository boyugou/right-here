import Foundation
import RightHereCore

/// Where Right Here keeps its files.
public struct RHPaths: Sendable, Equatable {
    public var configDirectory: URL
    public var configFile: URL
    /// The per-machine overlay next to the config file; `ConfigLayers.overlayName(forConfigFile:)` names it.
    public var localConfigFile: URL {
        configFile.deletingLastPathComponent().appendingPathComponent(ConfigLayers.overlayName(forConfigFile: configFile.lastPathComponent))
    }
    /// What `rh config sync` remembers: the folder and the content last synced.
    public var syncStateFile: URL { configDirectory.appendingPathComponent("sync.toml") }
    /// What `rh pin` and `rh recents` remember: pinned and recent folders.
    public var stateFile: URL { configDirectory.appendingPathComponent("state.toml") }
    /// The lock that one setup at a time takes (`FileLock`): the setup window, `rh setup` in a terminal and an AI agent's take turns.
    public var setupLockFile: URL { configDirectory.appendingPathComponent(".setup.lock") }
    /// The lock of the state file, taken for the moment that it is read, changed and written (`StateStore.update`). Not the setup's: pinning
    /// a folder, or a click that records one, does not wait for a setup that takes seconds.
    public var stateLockFile: URL { configDirectory.appendingPathComponent(".state.lock") }
    /// The lock of the config files, taken for the moment that one is read, changed and written (`ConfigService`): the window, `rh config` and an AI agent's edits take turns.
    public var configLockFile: URL { configDirectory.appendingPathComponent(".config.lock") }
    /// The texts the config files had before an edit (`ConfigHistory`), for undo.
    public var historyDirectory: URL { configDirectory.appendingPathComponent(".history") }
    /// The changes an AI assistant proposed that wait for the person (`ConfigProposals`).
    public var proposalsDirectory: URL { configDirectory.appendingPathComponent(".pending") }
    /// The home the paths were derived from; the default sync folder is under it.
    public var home: URL
    /// `RH_LOG_DIR`, else `~/Library/Logs/right-here`.
    public var logDirectory: URL

    public var logFile: URL { logDirectory.appendingPathComponent("rh.log") }

    /// `RH_CONFIG` names the file itself; `RH_CONFIG_DIR` or `XDG_CONFIG_HOME` name its folder;
    /// otherwise it is `~/.config/right-here/config.toml`. A variable of Right Here's that is set to nothing is not "not set"
    /// (`RHEnvironment`); `XDG_CONFIG_HOME` is not Right Here's, and the XDG specification reads an empty one as not set.
    public init(environment: [String: String], home: URL) {
        self.home = home
        if let logs = RHEnvironment.path("RH_LOG_DIR", in: environment) {
            logDirectory = logs
        } else {
            logDirectory = home.appendingPathComponent("Library/Logs/" + AppIdentity.configDirectoryName)
        }
        if let file = RHEnvironment.path("RH_CONFIG", in: environment) {
            configFile = file
            configDirectory = configFile.deletingLastPathComponent()
            return
        }
        if let directory = RHEnvironment.path("RH_CONFIG_DIR", in: environment) {
            configDirectory = directory
        } else if let base = environment["XDG_CONFIG_HOME"], !base.isEmpty {
            configDirectory = URL(fileURLWithPath: (base as NSString).expandingTildeInPath).appendingPathComponent(AppIdentity.configDirectoryName)
        } else {
            configDirectory = home.appendingPathComponent(".config/" + AppIdentity.configDirectoryName)
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
    /// Why `config.toml` is there and was not read (it cannot be read, is too large, is not text), as the error that is also
    /// among the diagnostics; `nil` when it was read or is not there.
    public var fileProblem: ConfigDiagnostic?

    public init(result: ConfigLoadResult, fileExists: Bool, file: URL, localFile: URL, localFileExists: Bool, fileProblem: ConfigDiagnostic? = nil) {
        self.result = result
        self.fileExists = fileExists
        self.file = file
        self.localFile = localFile
        self.localFileExists = localFileExists
        self.fileProblem = fileProblem
    }

    public var config: Config { result.config }

    /// Whether the person has a config, as the first run decides it: the file, the per-machine overlay, or a link to a file that is not there (a
    /// dotfiles manager makes the link before it has cloned its repository). A read takes the link for no file, and the setup leaves it as it is,
    /// so the window must not offer a first run whose button could only fail; the checks say what the link is (`Doctor.configCheck`).
    public var hasConfig: Bool {
        fileExists || localFileExists || [file, localFile].contains { ConfigProblem.danglingTarget(of: $0) != nil }
    }
}

extension LoadedConfig {
    /// The result of reading the config, with what only a built menu can say added: a config that is valid and leaves the Finder
    /// menu empty for a folder (`agents = []` with a menu of groups, no copy-path style, nothing installed) has nothing wrong
    /// in its text, yet the menu does not appear. That is a warning, with the reasons. The extension's own code path does not
    /// run this; `rh config validate` does, with the real facts.
    public func resultWithMenuCheck(facts: any SystemFacts) -> ConfigLoadResult {
        var checked = result
        // `items = []` is already a warning of its own, from the parser: one is enough.
        guard config.menuItems?.isEmpty != true else { return checked }
        let folder = HereContext(origin: .container, container: facts.homeDirectory)
        let explained = MenuBuilder(config: config, facts: facts).explain(for: folder)
        if let summary = explained.emptyMenuSummary {
            checked.diagnostics.append(ConfigDiagnostic(severity: .warning, path: "menu", message: summary + " (`rh menu --explain` lists each entry)"))
        }
        return checked
    }
}

public enum ConfigStore {
    /// Reads the config file. A missing file is not an error: the defaults apply. A file over `ConfigParser.maxBytes` is refused.
    /// With `validating`, the shared file is also checked on its own, as other Macs read it (`ConfigLayers.validate`): what
    /// `rh config validate` shows. The Finder menu and `rh run` read the config without it.
    /// - Parameter withOrigins: Also where each entry of the lists of tables is written (`ConfigLoadResult.entryOrigins`), for an editor that changes the entries by place.
    public static func load(paths: RHPaths, validating: Bool = false, withOrigins: Bool = false) -> LoadedConfig {
        let base = read(paths.configFile)
        let local = read(paths.localConfigFile)
        let name = paths.localConfigFile.lastPathComponent
        let result = validating
            ? ConfigLayers.validate(base: base.source, local: local.source, overlayName: name)
            : ConfigLayers.load(base: base.source, local: local.source, overlayName: name, withOrigins: withOrigins)
        var problem: ConfigDiagnostic?
        if case .unreadable(let diagnostic) = base.source { problem = diagnostic }
        return LoadedConfig(result: result, fileExists: base.exists, file: paths.configFile, localFile: paths.localConfigFile, localFileExists: local.exists, fileProblem: problem)
    }

    /// A config file's text as `rh config show` prints it: what `load` would have read (the size limit, a link followed, no byte
    /// order mark), or why there is none.
    public enum FileText: Sendable, Equatable {
        case absent
        case text(String)
        case problem(String)
    }

    public static func text(of file: URL) -> FileText {
        let found = read(file)
        switch found.source {
        case .absent: return .absent
        case .text(let text): return .text(text)
        case .unreadable(let diagnostic): return .problem(diagnostic.message)
        }
    }

    /// The config as the shared file alone makes it, without the per-machine overlay: what another Mac that reads only that file
    /// gets. `rh menu --explain` compares it with the merged config to say what the overlay disabled.
    public static func sharedConfig(paths: RHPaths) -> Config {
        ConfigLayers.load(base: read(paths.configFile).source, local: .absent, overlayName: paths.localConfigFile.lastPathComponent).config
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

    /// One file: its text, or the reason it was not read. A file that is there and cannot be read is not a missing one: the
    /// defaults would apply without a word, and `rh init` would say the file exists.
    private static func read(_ file: URL) -> (source: ConfigSource, exists: Bool) {
        // Through a link: a config kept in a dotfiles repository is a symlink, and `BoundedRead` follows it.
        switch BoundedRead.read(file) {
        case .absent:
            return (.absent, false)
        case .tooLarge(let size):
            let diagnostic = ConfigDiagnostic(severity: .error, path: "", message: "The file is \(size / 1024) KB; a config is a few kilobytes, so it was not read. Is this the right file?")
            return (.unreadable(diagnostic), true)
        case .unreadable(let reason):
            return (.unreadable(ConfigDiagnostic(severity: .error, path: "", message: "cannot read \(file.path): \(reason)")), true)
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                return (.unreadable(ConfigDiagnostic(severity: .error, path: "", message: "The file is not valid UTF-8.")), true)
            }
            // Some editors put a byte order mark at the start of a UTF-8 file; TOML does not allow one.
            return (.text(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text), true)
        }
    }

    public enum InitializeOutcome: Sendable, Equatable {
        case created
        /// An existing file was replaced because `force` was set; the old one was copied here first.
        case replaced(backup: URL)
        case kept
    }

    /// `.config.lock` cannot be taken (it is a link, or its folder cannot be written to), so a forced replacement could not be told apart from an edit made at the
    /// same moment.
    public struct LockUnavailable: Error, LocalizedError, Equatable {
        public var file: String
        public var errorDescription: String? {
            "The lock \(file.withControlCharactersEscaped) cannot be taken (it is a link, or its folder cannot be written to), so the config was not replaced: a change made at the same moment could not be told apart. Nothing was changed."
        }
    }

    /// Writes a fresh config file unless one exists. The file is created only if nothing has its name, in one step (`link`
    /// refuses a name that is taken), so two callers that create it at the same moment (the setup window and `rh setup` in a
    /// terminal) cannot replace each other's file: one creates, the other finds it kept. `beforeCreate` is for tests, which put
    /// a file in the way at the last moment.
    ///
    /// With `force` an existing file is replaced, after a copy of it is saved next to it (`config.toml.bak-<date>`), since it
    /// may hold hand-made settings. The replacement is made under the lock of the config, which every edit and every pull
    /// takes, so an edit under way cannot write over the new file, nor the new file over the edit. A create needs no lock: it
    /// cannot replace anything. Both ask `RealHomeGuard` first (`environment`, `realHome`): a test that forgot its home must
    /// not write the person's config.
    @discardableResult
    public static func initialize(paths: RHPaths, detected: DetectedEnvironment, force: Bool = false, now: Date = Date(),
                                  environment: [String: String] = ProcessInfo.processInfo.environment,
                                  realHome: URL = LiveSystemFacts.realHomeDirectory, lockTimeout: Duration = .seconds(5),
                                  beforeCreate: ((URL) throws -> Void)? = nil) throws -> InitializeOutcome {
        try RealHomeGuard.checkWriting(paths.configDirectory, environment: environment, realHome: realHome)
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        let content = Data(ConfigTemplate.render(detected).utf8)
        guard force else {
            switch try AtomicFile.createExclusively(content, at: paths.configFile, beforeLink: beforeCreate) {
            case .created: return .created
            case .exists: return .kept
            }
        }
        let lock = try FileLock.acquireNow(paths.configLockFile, timeout: lockTimeout)
        guard lock.isHeld else { throw LockUnavailable(file: paths.configLockFile.path) }
        defer { lock.release() }
        var backup: URL?
        if FileManager.default.fileExists(atPath: paths.configFile.path) {
            let copy = backupURL(for: paths.configFile, now: now)
            try FileManager.default.copyItem(at: paths.configFile, to: copy)
            backup = copy
        }
        try AtomicFile.write(content, to: paths.configFile)
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
