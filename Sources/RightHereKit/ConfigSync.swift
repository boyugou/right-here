import CryptoKit
import Foundation
import RightHereCore

public enum ConfigSyncError: Error, Equatable, CustomStringConvertible {
    case notEnabled
    case badFolder(String)
    case noLocalConfig(String)
    case refused(SyncRefusal, folder: String)
    case invalid([SyncValidation.Problem], file: String)
    /// The copy in the folder would add or change something Right Here starts, and the caller did not say it is theirs.
    case commandsNeedApproval([LaunchCommands.Change])
    /// `config.toml` in the folder is a link that `push` will not write through: to a file outside the folder, or to nothing (`target` is `nil`).
    case remoteLink(String, target: String?)
    /// `makeParent` is the folder to create first when the person can (it is under their home folder).
    case folderUnreachable(String, makeParent: String?)
    case writeFailed(String)
    /// The copy in the folder is over the size limit of a config: it is not read, and never written over.
    case remoteTooLarge(file: String, bytes: Int)
    /// This machine's config file is there but was not read (past the size limit, or no permission): it can be neither
    /// compared with the copy nor saved first, so nothing is written over it.
    case localNotRead(file: String, why: String)
    /// Another process holds the lock of the config (every change of it is made under that lock, `ConfigService`) and did not let go of it in time.
    case configBusy(file: String)
    /// The lock of the config cannot be taken at all: it is a link, or its folder cannot be written to.
    case lockUnavailable(file: String)

    /// How many changed settings a message lists before saying "and N more".
    public static let listedChanges = 12

    public var description: String {
        switch self {
        case .notEnabled:
            "Config sync is not set up. Run `rh config sync enable` (or `rh config sync enable --folder <folder>`)."
        case .badFolder(let reason):
            reason
        case .noLocalConfig(let path):
            "There is no config file at \(path) to send. Run `rh setup` first, or `rh config sync pull` to fetch the synced one."
        case .refused(.localChanged, _):
            "Not pulling: the local config changed since the last sync, and pulling would overwrite it. Run `rh config sync status`; use `rh config sync push` to send it, or `rh config sync pull --force` to replace it (the old file is saved as config.toml.bak-<date>)."
        case .refused(.remoteChanged, _):
            "Not pushing: the copy in the sync folder changed since the last sync, and pushing would overwrite it. Run `rh config sync status`; use `rh config sync pull` to take it, or `rh config sync push --force` to replace it (the old copy is saved next to it as config.toml.bak-<date>)."
        case .refused(.remoteMissing, let folder):
            "There is no config.toml in \(folder) yet. Run `rh config sync push` to put this machine's config there."
        case .refused(.remoteEvicted, let folder):
            "The copy in \(folder) is not on this Mac yet (iCloud keeps it online only, or the file cannot be read). Open the folder in Finder, click the cloud icon beside config.toml, wait for the download, then try again. Nothing was changed."
        case .invalid(let problems, let file):
            "Refusing \(file): " + problems.map(\.message).joined(separator: "; ") + ". Nothing was changed."
        case .commandsNeedApproval(let changes):
            "Not pulling: the copy in the sync folder would add or change what Right Here starts on this Mac, and a folder that other machines or a sync service can write is not trusted with that:\n"
                + changes.prefix(Self.listedChanges).map { "  " + $0.line }.joined(separator: "\n")
                + (changes.count > Self.listedChanges ? "\n  and \(changes.count - Self.listedChanges) more" : "")
                + "\nRead them. If they are yours, run `rh config sync pull --allow-commands` (with --force as well when this Mac's config changed). Nothing was changed."
        case .remoteLink(let file, let target?):
            "Not pushing: \(file) is a symbolic link to \(target), which is outside the sync folder. A push writes through a link, and a folder that other machines or a sync service can write could point it at any file you can write. Replace the link with a regular file, or point it at a file inside the folder, then push again. Nothing was changed."
        case .remoteLink(let file, nil):
            "Not pushing: \(file) is a symbolic link that points nowhere. Remove it, then push again. Nothing was changed."
        case .folderUnreachable(let folder, let makeParent):
            "The sync folder \(folder) does not exist and cannot be created: `rh config sync push` creates the last folder of the path only, and its parent folder is missing. "
                + (makeParent.map { "Create the parent first: `mkdir -p \(ShellQuoting.quote($0, for: .posix))`, then push again. Or choose another folder" }
                    ?? "Is iCloud Drive on, or the drive mounted? Or choose another folder")
                + " with `rh config sync enable --folder <folder>`."
        case .writeFailed(let reason):
            "Could not write: \(reason). The existing file was left as it was."
        case .remoteTooLarge(let file, let bytes):
            "The copy in the sync folder, \(file), is \(bytes / 1024) KB; a config is a few kilobytes (the limit is \(ConfigParser.maxBytes / 1024) KB), so it was not read and is never replaced. Is this the right folder? Move the file out of it, then run `rh config sync push`. Nothing was changed."
        case .localNotRead(let file, let why):
            "\(file) \(why), so Right Here can neither compare it with the copy in the sync folder nor save it first. Fix it or move it aside, then try again. Nothing was changed."
        case .configBusy(let file):
            "Another Right Here process is changing the config (it holds \(file.withControlCharactersEscaped)) and did not finish in time. Nothing was changed; try again in a moment."
        case .lockUnavailable(let file):
            "The lock \(file.withControlCharactersEscaped) cannot be taken (it is a link, or its folder cannot be written to), so the config was not replaced: a change made at the same moment could not be told apart. Nothing was changed."
        }
    }
}

/// Keeps the config in step with a plain folder (an iCloud Drive folder, Dropbox, a git checkout, a USB stick) by
/// copying the file, not by linking it: the Finder extension is sandboxed and cannot read through a symlink out of
/// its allowed folder, and a file iCloud has not downloaded looks like a missing file through a link.
/// Both sides keep an ordinary file. Nothing is deleted; every write goes through `AtomicFile`.
public struct ConfigSync: Sendable {
    public static let remoteFileName = "config.toml"
    public static let defaultFolderComponents = ["Library", "Mobile Documents", "com~apple~CloudDocs", "Right Here"]

    public let paths: RHPaths
    private let beforeRename: (@Sendable (URL) throws -> Void)?
    private let environment: [String: String]
    private let realHome: URL
    private let lockTimeout: Duration

    /// `environment` and `realHome` are what `RealHomeGuard` reads, and `lockTimeout` how long a pull waits for the lock of the config: the process's own and five seconds, but for a test.
    public init(paths: RHPaths, environment: [String: String] = ProcessInfo.processInfo.environment, realHome: URL = LiveSystemFacts.realHomeDirectory,
                lockTimeout: Duration = .seconds(5)) {
        self.paths = paths
        self.beforeRename = nil
        self.environment = environment
        self.realHome = realHome
        self.lockTimeout = lockTimeout
    }

    /// For tests: runs between writing a temporary file and renaming it into place.
    init(paths: RHPaths, beforeRename: @escaping @Sendable (URL) throws -> Void) {
        self.paths = paths
        self.beforeRename = beforeRename
        self.environment = ProcessInfo.processInfo.environment
        self.realHome = LiveSystemFacts.realHomeDirectory
        self.lockTimeout = .seconds(5)
    }

    /// Refuses before `file` is written when a process that a test started would change the real home (`RealHomeGuard`): the settings of the sync and the config are the person's.
    private func checkWriting(_ file: URL) throws {
        do { try RealHomeGuard.checkWriting(file, environment: environment, realHome: realHome) } catch {
            throw ConfigSyncError.writeFailed("\(file.path): \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
        }
    }

    public struct Report: Sendable, Equatable {
        public var status: SyncStatus
        public var folder: URL
        public var remoteFile: URL
        public var localFile: URL
        public var folderReachable: Bool
        /// Finder-style conflict copies next to the remote (`config 2.toml`).
        public var conflictCopies: [String]
        public var localHash: String?
        public var remoteHash: String?
        public var lastSynced: String?
        /// What the folder's copy would add to, or change in, what this machine's config starts (`LaunchCommands`).
        public var pendingCommands: [LaunchCommands.Change]
        /// The copy in the folder as it was found: `.tooLarge` means it was not read at all.
        public var remote: SyncRemote
        /// What stops this machine's config from being sent (`push` refuses it), and what stops the folder's copy from being
        /// taken (`pull` refuses it). Empty when there is nothing, or no such file.
        public var localProblems: [SyncValidation.Problem]
        public var remoteProblems: [SyncValidation.Problem]
        /// This machine's config is there but cannot be read as TOML (a syntax error, too large, not text, no permission), so
        /// `rh` runs with the defaults and `pendingCommands` is the folder's custom settings against those.
        public var localRunsWithDefaults: Bool
        /// The folder is not there and neither is its parent, which `push` does not make; `nil` when the folder is there, or
        /// when its parent is.
        public var missingParent: MissingParent?
    }

    /// The sync folder's parent is missing: `makeParent` is the folder the person can create first (`mkdir -p`), when it is
    /// theirs to create, and `nil` where it is not (iCloud Drive is switched on, a drive is mounted).
    public struct MissingParent: Sendable, Equatable {
        public var makeParent: String?
    }

    public enum PullOutcome: Sendable, Equatable {
        case alreadyInSync
        case pulled(backup: URL?)
    }

    public enum PushOutcome: Sendable, Equatable {
        case alreadyInSync
        case pushed(backup: URL?, createdFolder: Bool)
    }

    // MARK: State

    public var defaultFolder: URL {
        Self.defaultFolderComponents.reduce(paths.home) { $0.appendingPathComponent($1, isDirectory: true) }
    }

    /// `nil` when sync is not enabled or `sync.toml` cannot be read.
    public func settings() -> SyncSettings? {
        guard let data = try? Data(contentsOf: paths.syncStateFile), data.count < 64 * 1024, let text = String(data: data, encoding: .utf8) else { return nil }
        return SyncSettings.parse(text)
    }

    private func save(_ settings: SyncSettings) throws {
        try checkWriting(paths.syncStateFile)
        do {
            try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
            try AtomicFile.write(Data(settings.render().utf8), to: paths.syncStateFile)
        } catch {
            throw ConfigSyncError.writeFailed("\(paths.syncStateFile.path): \(error)")
        }
    }

    /// A folder as typed: `~` is the home the paths were built from, and a relative path is taken from the current folder.
    /// Only `.`, `..` and doubled slashes are taken out, by text: the path prints as it was given. `standardizedFileURL` also
    /// rewrote `/private/tmp` to `/tmp` for a folder that exists, so `status` named another path than the one typed.
    func resolve(folder text: String) -> URL {
        let absolute: String
        if text == "~" { absolute = paths.home.path }
        else if text.hasPrefix("~/") { absolute = paths.home.path + "/" + text.dropFirst(2) }
        else if text.hasPrefix("/") { absolute = text }
        else { absolute = FileManager.default.currentDirectoryPath + "/" + text }
        return URL(fileURLWithPath: Self.lexicallyNormalized(absolute), isDirectory: true)
    }

    static func lexicallyNormalized(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { _ = parts.popLast(); continue }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }

    /// The folder `push` could not create `folder` in, when the person can make it with `mkdir -p`: it is under their home
    /// folder, and not in iCloud Drive's own tree, which is theirs to switch on and not to make by hand.
    private func parentToMake(for folder: URL) -> String? {
        let parent = folder.deletingLastPathComponent().path
        let home = paths.home.path.hasSuffix("/") ? paths.home.path : paths.home.path + "/"
        guard (parent + "/").hasPrefix(home) else { return nil }
        let mobileDocuments = home + "Library/Mobile Documents"
        guard parent != mobileDocuments, !parent.hasPrefix(mobileDocuments + "/") else { return nil }
        return parent
    }

    // MARK: Inspection

    struct Inspection {
        var folder: URL
        var folderReachable: Bool
        /// This machine's config file as `BoundedRead` found it.
        var local: BoundedRead.Outcome
        var remoteData: Data?
        var remote: SyncRemote
        var conflicts: [String]
        /// This Mac's own file, `config.local.toml`, which is never synced and decides settings that belong to the Mac: what a pull would start is compared with it laid over both copies.
        var localOverlayData: Data?

        var localData: Data? {
            if case .data(let data) = local { return data }
            return nil
        }

        /// Why the local file was not read, in words that follow its path; `nil` when it was read or is not there.
        var localNotRead: String? {
            switch local {
            case .tooLarge(let bytes): "is \(bytes / 1024) KB, over the \(ConfigParser.maxBytes / 1024) KB limit for a config"
            case .unreadable(let reason): "cannot be read (\(reason))"
            case .absent, .data: nil
            }
        }
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func inspect(folder: URL) -> Inspection {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        let reachable = manager.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue
        // Neither side is read past `ConfigParser.maxBytes`: a file over it is a mistake or an attack, and reading and
        // parsing it costs seconds and memory every time anything looks at the folder.
        let local = BoundedRead.read(paths.configFile)
        var overlay: Data?
        if case .data(let bytes) = BoundedRead.read(paths.localConfigFile) { overlay = bytes }
        guard reachable else {
            return Inspection(folder: folder, folderReachable: false, local: local, remoteData: nil, remote: .missing, conflicts: [], localOverlayData: overlay)
        }
        let file = folder.appendingPathComponent(Self.remoteFileName)
        var remote = SyncRemote.missing
        var remoteData: Data?
        // Asked first: reading a file iCloud has not downloaded would wait for the network.
        if (try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus == .notDownloaded {
            remote = .evicted
        } else {
            switch BoundedRead.read(file) {
            case .absent: remote = .missing
            case .data(let data):
                remoteData = data
                remote = .present(hash: Self.hash(data))
            case .tooLarge(let bytes): remote = .tooLarge(bytes: bytes)
            case .unreadable: remote = .evicted
            }
        }
        let names = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
        let conflicts = names.filter { $0.wholeMatch(of: #/config \d+\.toml/#) != nil }.sorted()
        return Inspection(folder: folder, folderReachable: true, local: local, remoteData: remoteData, remote: remote, conflicts: conflicts, localOverlayData: overlay)
    }

    private func report(_ inspection: Inspection, settings: SyncSettings) -> Report {
        let local = inspection.localData.map(Self.hash)
        let snapshotLocal: SyncLocal
        switch inspection.local {
        case .absent: snapshotLocal = .missing
        case .data: snapshotLocal = .present(hash: local ?? "")
        case .tooLarge, .unreadable: snapshotLocal = .unknown
        }
        let snapshot = SyncSnapshot(local: snapshotLocal, remote: inspection.remote, lastSynced: settings.lastSynced)
        var remoteHash: String?
        if case .present(let hash) = inspection.remote { remoteHash = hash }
        var pending: [LaunchCommands.Change] = []
        var remoteProblems: [SyncValidation.Problem] = []
        if let remoteData = inspection.remoteData {
            // Both copies are read with this Mac's own file laid over them, as a click reads the config: the switch that starts agents without asking, or a terminal that only that file defines, decides
            // what the copy would start.
            let overlay = inspection.localOverlayData
            let known = inspection.localData.map { LaunchCommands(configData: $0, overlay: overlay) } ?? LaunchCommands(.default)
            pending = LaunchCommands(configData: remoteData, overlay: overlay).additions(to: known)
            remoteProblems = SyncValidation.check(remoteData)
        } else if case .tooLarge(let bytes) = inspection.remote {
            remoteProblems = [.tooLarge(bytes: bytes)]
        }
        var localProblems: [SyncValidation.Problem] = []
        switch inspection.local {
        case .data(let data): localProblems = SyncValidation.check(data)
        case .tooLarge(let bytes): localProblems = [.tooLarge(bytes: bytes)]
        case .unreadable(let reason): localProblems = [.unreadable(reason: reason)]
        case .absent: break
        }
        var missingParent: MissingParent?
        if !inspection.folderReachable {
            var isDirectory: ObjCBool = false
            let parent = inspection.folder.deletingLastPathComponent()
            if !(FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory) && isDirectory.boolValue) {
                missingParent = MissingParent(makeParent: parentToMake(for: inspection.folder))
            }
        }
        var runsWithDefaults = false
        switch inspection.local {
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) { runsWithDefaults = !ConfigParser.canBeRead(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text) } else { runsWithDefaults = true }
        case .tooLarge, .unreadable: runsWithDefaults = true
        case .absent: break
        }
        return Report(status: SyncState.status(snapshot), folder: inspection.folder, remoteFile: inspection.folder.appendingPathComponent(Self.remoteFileName),
                      localFile: paths.configFile, folderReachable: inspection.folderReachable, conflictCopies: inspection.conflicts,
                      localHash: local, remoteHash: remoteHash, lastSynced: settings.lastSynced, pendingCommands: pending,
                      remote: inspection.remote, localProblems: localProblems, remoteProblems: remoteProblems, localRunsWithDefaults: runsWithDefaults,
                      missingParent: missingParent)
    }

    // MARK: Commands

    /// Remembers the folder. Nothing is copied and the folder is not created: `push` does that.
    @discardableResult
    public func enable(folder text: String?) throws -> Report {
        // `--folder "$UNSET"` is an empty string, which would have meant the current folder.
        if let text, text.allSatisfy(\.isWhitespace) {
            throw ConfigSyncError.badFolder("The folder is empty (is a shell variable unset?). Give a folder, or leave --folder out to use the iCloud Drive folder.")
        }
        let folder = text.map(resolve(folder:)) ?? defaultFolder
        func same(_ a: URL, _ b: URL) -> Bool { a.resolvingSymlinksInPath().standardizedFileURL.path == b.resolvingSymlinksInPath().standardizedFileURL.path }
        if same(folder, paths.configDirectory) {
            throw ConfigSyncError.badFolder("\(folder.path) is the folder the config lives in; choose another folder to keep the copy in.")
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            throw ConfigSyncError.badFolder("\(folder.path) is a file, not a folder.")
        }
        let previous = settings()
        var next = SyncSettings(folder: folder.path, lastSynced: previous?.folder == folder.path ? previous?.lastSynced : nil)
        let inspection = inspect(folder: folder)
        if let local = inspection.localData, case .present(let remote) = inspection.remote, Self.hash(local) == remote {
            next.lastSynced = remote
        }
        try save(next)
        return report(inspection, settings: next)
    }

    public func status() throws -> Report {
        guard let settings = settings() else { throw ConfigSyncError.notEnabled }
        return report(inspect(folder: URL(fileURLWithPath: settings.folder, isDirectory: true)), settings: settings)
    }

    @discardableResult
    public func pull(force: Bool = false, allowCommands: Bool = false, now: Date = Date()) throws -> PullOutcome {
        guard settings() != nil else { throw ConfigSyncError.notEnabled }
        return try underTheLockOfTheConfig { try pullLocked(force: force, allowCommands: allowCommands, now: now) }
    }

    /// Every other change of the config is made under its lock (`ConfigService`), and a pull compares the file with the copy and then replaces it: without the lock, an edit made in between would be
    /// written over, with no saved copy, because the file looked unchanged when it was compared. A Mac that has no config has nothing to protect, and no lock is made for it (that would make its folder).
    private func underTheLockOfTheConfig<Result>(_ body: () throws -> Result) throws -> Result {
        guard FileManager.default.fileExists(atPath: paths.configFile.resolvingSymlinksInPath().path) else { return try body() }
        try checkWriting(paths.configLockFile)
        let lock: FileLock
        do { lock = try FileLock.acquireNow(paths.configLockFile, timeout: lockTimeout) } catch {
            throw ConfigSyncError.configBusy(file: paths.configLockFile.path)
        }
        guard lock.isHeld else { throw ConfigSyncError.lockUnavailable(file: paths.configLockFile.path) }
        defer { lock.release() }
        return try body()
    }

    private func pullLocked(force: Bool, allowCommands: Bool, now: Date) throws -> PullOutcome {
        guard var settings = settings() else { throw ConfigSyncError.notEnabled }
        let inspection = inspect(folder: URL(fileURLWithPath: settings.folder, isDirectory: true))
        let current = report(inspection, settings: settings)
        // A file that was not read is never read afterwards and never written over, whatever `force` says.
        if case .tooLarge(let bytes) = inspection.remote { throw ConfigSyncError.remoteTooLarge(file: current.remoteFile.path, bytes: bytes) }
        if let why = inspection.localNotRead { throw ConfigSyncError.localNotRead(file: paths.configFile.path, why: why) }
        switch SyncState.pull(current.status, force: force) {
        case .refuse(let refusal): throw ConfigSyncError.refused(refusal, folder: settings.folder)
        case .nothingToDo:
            if let hash = current.remoteHash, settings.lastSynced != hash { settings.lastSynced = hash; try save(settings) }
            return .alreadyInSync
        case .proceed: break
        }
        guard let data = inspection.remoteData, let hash = current.remoteHash else { throw ConfigSyncError.refused(.remoteMissing, folder: settings.folder) }
        let problems = current.remoteProblems
        if !problems.isEmpty { throw ConfigSyncError.invalid(problems, file: current.remoteFile.path) }
        // A config carries commands, and the folder is written by things this Mac does not control: what it would start
        // that this Mac's config does not is never taken without the caller saying so (`force` is about something else).
        if !current.pendingCommands.isEmpty, !allowCommands { throw ConfigSyncError.commandsNeedApproval(current.pendingCommands) }

        // Through a link: a config kept in a dotfiles repository is a symlink, and replacing the link would end that.
        let destination = paths.configFile.resolvingSymlinksInPath()
        // The lock of the config, which a pull has taken, is in the folder of the record of what was synced, so one question covers that; the file the config is a link to may be elsewhere.
        try checkWriting(destination)
        var backup: URL?
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if inspection.localData != nil, current.status == .localAhead || current.status == .diverged {
                let copy = ConfigStore.backupURL(for: destination, now: now)
                try FileManager.default.copyItem(at: destination, to: copy)
                backup = copy
            }
            try AtomicFile.write(data, to: destination, beforeRename: beforeRename)
        } catch {
            throw ConfigSyncError.writeFailed("\(destination.path): \(error)")
        }
        settings.lastSynced = hash
        try save(settings)
        return .pulled(backup: backup)
    }

    @discardableResult
    public func push(force: Bool = false, now: Date = Date()) throws -> PushOutcome {
        guard var settings = settings() else { throw ConfigSyncError.notEnabled }
        let folder = URL(fileURLWithPath: settings.folder, isDirectory: true)
        let inspection = inspect(folder: folder)
        let data: Data
        switch inspection.local {
        case .data(let bytes): data = bytes
        case .absent: throw ConfigSyncError.noLocalConfig(paths.configFile.path)
        case .tooLarge(let bytes): throw ConfigSyncError.invalid([.tooLarge(bytes: bytes)], file: paths.configFile.path)
        case .unreadable: throw ConfigSyncError.localNotRead(file: paths.configFile.path, why: inspection.localNotRead ?? "cannot be read")
        }
        let current = report(inspection, settings: settings)
        if case .tooLarge(let bytes) = inspection.remote { throw ConfigSyncError.remoteTooLarge(file: current.remoteFile.path, bytes: bytes) }
        switch SyncState.push(current.status, force: force) {
        case .refuse(let refusal): throw ConfigSyncError.refused(refusal, folder: settings.folder)
        case .nothingToDo:
            if let hash = current.localHash, settings.lastSynced != hash { settings.lastSynced = hash; try save(settings) }
            return .alreadyInSync
        case .proceed: break
        }
        let problems = current.localProblems
        if !problems.isEmpty { throw ConfigSyncError.invalid(problems, file: paths.configFile.path) }

        // The record of what was synced is asked first: a push that wrote the copy and then could not say so would leave the two sides looking different.
        try checkWriting(paths.syncStateFile)
        var createdFolder = false
        if !inspection.folderReachable {
            try checkWriting(folder)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                createdFolder = true
            } catch {
                throw ConfigSyncError.folderUnreachable(folder.path, makeParent: parentToMake(for: folder))
            }
        }
        let destination = try remoteWriteTarget(in: folder)
        try checkWriting(destination)
        var backup: URL?
        do {
            if inspection.remoteData != nil, current.status == .remoteAhead || current.status == .diverged {
                let copy = ConfigStore.backupURL(for: destination, now: now)
                try FileManager.default.copyItem(at: destination, to: copy)
                backup = copy
            }
            try AtomicFile.write(data, to: destination, beforeRename: beforeRename)
        } catch {
            throw ConfigSyncError.writeFailed("\(destination.path): \(error)")
        }
        settings.lastSynced = Self.hash(data)
        try save(settings)
        return .pushed(backup: backup, createdFolder: createdFolder)
    }

    /// The file `push` writes: `config.toml` in the folder, or what it is a link to, so that a link stays a link (as `pull`
    /// does on this machine's side) and the backup is a copy of real content, not a second link. The link may only lead
    /// to a file inside the folder: the folder is written by things this Mac does not control, and a link they plant must
    /// not turn a push into an overwrite of any file the person can write.
    private func remoteWriteTarget(in folder: URL) throws -> URL {
        let file = folder.appendingPathComponent(Self.remoteFileName)
        guard (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true else { return file }
        let target = file.resolvingSymlinksInPath()
        // A link that points nowhere resolves to itself.
        guard target.path != file.path else { throw ConfigSyncError.remoteLink(file.path, target: nil) }
        let inside = folder.resolvingSymlinksInPath().path
        guard target.path.hasPrefix(inside.hasSuffix("/") ? inside : inside + "/") else { throw ConfigSyncError.remoteLink(file.path, target: target.path) }
        return target
    }

    /// Forgets the folder and the sync state. Both copies of the config stay where they are.
    @discardableResult
    public func disable() throws -> Bool {
        guard FileManager.default.fileExists(atPath: paths.syncStateFile.path) else { return false }
        try checkWriting(paths.syncStateFile)
        do { try FileManager.default.removeItem(at: paths.syncStateFile) } catch {
            throw ConfigSyncError.writeFailed("\(paths.syncStateFile.path): \(error)")
        }
        return true
    }

    // MARK: Doctor

    /// Nothing when sync is off. When it is on: the folder, the copy there, whether it is valid, how it compares, and
    /// conflict copies a sync service may have left.
    public func doctorChecks() -> [DoctorCheck] {
        guard let settings = settings() else {
            guard FileManager.default.fileExists(atPath: paths.syncStateFile.path) else { return [] }
            return [DoctorCheck(.syncState, status: .warn, detail: .doctorSyncStateUnreadable(paths.syncStateFile.path), fix: .doctorFixSyncReenable)]
        }
        let inspection = inspect(folder: URL(fileURLWithPath: settings.folder, isDirectory: true))
        let report = report(inspection, settings: settings)
        guard inspection.folderReachable else {
            return [DoctorCheck(.syncFolder, status: .warn, detail: .doctorSyncFolderUnreachable(settings.folder), fix: .doctorFixSyncFolder)]
        }
        var checks = [DoctorCheck(.syncFolder, status: .ok, detail: .doctorVerbatim(settings.folder))]
        switch inspection.remote {
        case .evicted:
            checks.append(DoctorCheck(.syncRemote, status: .warn, detail: .doctorSyncRemoteEvicted, fix: .doctorFixSyncDownload))
        case .missing:
            checks.append(DoctorCheck(.syncRemote, status: .warn, detail: .doctorSyncRemoteMissing, fix: .doctorFixSyncPush))
        case .tooLarge:
            // Not read, so not parsed either; and never replaced, so `push --force` is not the way out.
            checks.append(DoctorCheck(.syncRemote, status: .fail, detail: .doctorVerbatim(report.remoteProblems.map(\.message).joined(separator: "; ")),
                                      fix: .doctorVerbatim("Is this the right folder? Move the file out of it, then run `rh config sync push`.")))
        case .present:
            if inspection.remoteData != nil {
                let problems = report.remoteProblems
                if problems.isEmpty {
                    checks.append(DoctorCheck(.syncRemote, status: .ok, detail: .doctorSyncRemoteValid))
                } else {
                    checks.append(DoctorCheck(.syncRemote, status: .fail, detail: .doctorVerbatim(problems.map(\.message).joined(separator: "; ")), fix: .doctorFixSyncFixRemote))
                }
            }
        }
        if let row = commandsCheck(report, localData: inspection.localData, overlay: inspection.localOverlayData) { checks.append(row) }
        switch report.status {
        case .inSync:
            checks.append(DoctorCheck(.syncState, status: .ok, detail: .doctorSyncInSync))
        case .localAhead:
            checks.append(DoctorCheck(.syncState, status: .warn, detail: .doctorSyncLocalAhead, fix: .doctorFixSyncPushShort))
        case .remoteAhead:
            checks.append(DoctorCheck(.syncState, status: .warn, detail: .doctorSyncRemoteAhead, fix: .doctorFixSyncPull))
        case .diverged:
            checks.append(DoctorCheck(.syncState, status: .warn, detail: .doctorSyncDiverged, fix: .doctorFixSyncCompare))
        case .remoteMissing, .remoteEvicted:
            break
        }
        if !inspection.conflicts.isEmpty {
            checks.append(DoctorCheck(.syncConflict, status: .warn, detail: .doctorSyncConflict(inspection.conflicts.joined(separator: ", "), settings.folder), fix: .doctorFixSyncConflict))
        }
        return checks
    }

    /// How many changed settings a row of the doctor lists before it says how many more there are.
    private static let listedInRow = 3

    /// What starts programs, as one row: the folder's copy adding something (a pull will ask), or else what this Mac's
    /// config already starts that Right Here does not start by itself. Nothing when there is none of either.
    private func commandsCheck(_ report: Report, localData: Data?, overlay: Data?) -> DoctorCheck? {
        func listed(_ changes: [LaunchCommands.Change]) -> String {
            changes.prefix(Self.listedInRow).map(\.line).joined(separator: "; ")
        }
        func more(_ changes: [LaunchCommands.Change]) -> [LocalizedMessage] {
            changes.count > Self.listedInRow ? [.doctorSyncCommandsMore(String(changes.count - Self.listedInRow))] : []
        }
        if !report.pendingCommands.isEmpty {
            let changes = report.pendingCommands
            return DoctorCheck(.syncCommands, status: .warn, detail: .doctorSyncCommandsPending(String(changes.count), listed(changes)),
                               notes: more(changes), fix: .doctorFixSyncCommands)
        }
        let custom = localData.map { LaunchCommands(configData: $0, overlay: overlay).custom } ?? []
        guard !custom.isEmpty else { return nil }
        return DoctorCheck(.syncCommands, status: .ok, detail: .doctorSyncCommandsOwn(String(custom.count), listed(custom)), notes: more(custom))
    }
}
