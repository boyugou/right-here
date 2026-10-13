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
    case folderUnreachable(String)
    case writeFailed(String)

    /// How many changed settings a message lists before saying "and N more".
    public static let listedChanges = 12

    public var description: String {
        switch self {
        case .notEnabled:
            "Config sync is not set up. Run `rh config sync enable` (or `rh config sync enable --folder <folder>`)."
        case .badFolder(let reason):
            reason
        case .noLocalConfig(let path):
            "There is no config file at \(path) to send. Run `rh init` first, or `rh config sync pull` to fetch the synced one."
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
        case .folderUnreachable(let folder):
            "The sync folder \(folder) does not exist and cannot be created (its parent folder is missing). Is iCloud Drive on, or the drive mounted? Choose another with `rh config sync enable --folder <folder>`."
        case .writeFailed(let reason):
            "Could not write: \(reason). The existing file was left as it was."
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

    public init(paths: RHPaths) {
        self.paths = paths
        self.beforeRename = nil
    }

    /// For tests: runs between writing a temporary file and renaming it into place.
    init(paths: RHPaths, beforeRename: @escaping @Sendable (URL) throws -> Void) {
        self.paths = paths
        self.beforeRename = beforeRename
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
        do {
            try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
            try AtomicFile.write(Data(settings.render().utf8), to: paths.syncStateFile)
        } catch {
            throw ConfigSyncError.writeFailed("\(paths.syncStateFile.path): \(error)")
        }
    }

    /// A folder as typed: `~` is the home the paths were built from, and a relative path is taken from the current folder.
    func resolve(folder text: String) -> URL {
        if text == "~" { return paths.home }
        if text.hasPrefix("~/") { return paths.home.appendingPathComponent(String(text.dropFirst(2)), isDirectory: true).standardizedFileURL }
        return URL(fileURLWithPath: text, isDirectory: true).standardizedFileURL
    }

    // MARK: Inspection

    struct Inspection {
        var folder: URL
        var folderReachable: Bool
        var localData: Data?
        var remoteData: Data?
        var remote: SyncRemote
        var conflicts: [String]
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func inspect(folder: URL) -> Inspection {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        let reachable = manager.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue
        let localData = try? Data(contentsOf: paths.configFile)
        guard reachable else {
            return Inspection(folder: folder, folderReachable: false, localData: localData, remoteData: nil, remote: .missing, conflicts: [])
        }
        let file = folder.appendingPathComponent(Self.remoteFileName)
        var remote = SyncRemote.missing
        var remoteData: Data?
        let fileThere = manager.fileExists(atPath: file.path)
        // Asked first: reading a file iCloud has not downloaded would wait for the network.
        let notDownloaded = (try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus == .notDownloaded
        if fileThere, !notDownloaded, let data = try? Data(contentsOf: file) {
            remoteData = data
            remote = .present(hash: Self.hash(data))
        } else if fileThere || notDownloaded {
            remote = .evicted
        }
        let names = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
        let conflicts = names.filter { $0.wholeMatch(of: #/config \d+\.toml/#) != nil }.sorted()
        return Inspection(folder: folder, folderReachable: true, localData: localData, remoteData: remoteData, remote: remote, conflicts: conflicts)
    }

    private func report(_ inspection: Inspection, settings: SyncSettings) -> Report {
        let local = inspection.localData.map(Self.hash)
        let snapshot = SyncSnapshot(local: local, remote: inspection.remote, lastSynced: settings.lastSynced)
        var remoteHash: String?
        if case .present(let hash) = inspection.remote { remoteHash = hash }
        var pending: [LaunchCommands.Change] = []
        if let remoteData = inspection.remoteData {
            let known = inspection.localData.map(LaunchCommands.init(configData:)) ?? LaunchCommands(.default)
            pending = LaunchCommands(configData: remoteData).additions(to: known)
        }
        return Report(status: SyncState.status(snapshot), folder: inspection.folder, remoteFile: inspection.folder.appendingPathComponent(Self.remoteFileName),
                      localFile: paths.configFile, folderReachable: inspection.folderReachable, conflictCopies: inspection.conflicts,
                      localHash: local, remoteHash: remoteHash, lastSynced: settings.lastSynced, pendingCommands: pending)
    }

    // MARK: Commands

    /// Remembers the folder. Nothing is copied and the folder is not created: `push` does that.
    @discardableResult
    public func enable(folder text: String?) throws -> Report {
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
        guard var settings = settings() else { throw ConfigSyncError.notEnabled }
        let inspection = inspect(folder: URL(fileURLWithPath: settings.folder, isDirectory: true))
        let current = report(inspection, settings: settings)
        switch SyncState.pull(current.status, force: force) {
        case .refuse(let refusal): throw ConfigSyncError.refused(refusal, folder: settings.folder)
        case .nothingToDo:
            if let hash = current.remoteHash, settings.lastSynced != hash { settings.lastSynced = hash; try save(settings) }
            return .alreadyInSync
        case .proceed: break
        }
        guard let data = inspection.remoteData, let hash = current.remoteHash else { throw ConfigSyncError.refused(.remoteMissing, folder: settings.folder) }
        let problems = SyncValidation.check(data)
        if !problems.isEmpty { throw ConfigSyncError.invalid(problems, file: current.remoteFile.path) }
        // A config carries commands, and the folder is written by things this Mac does not control: what it would start
        // that this Mac's config does not is never taken without the caller saying so (`force` is about something else).
        if !current.pendingCommands.isEmpty, !allowCommands { throw ConfigSyncError.commandsNeedApproval(current.pendingCommands) }

        // Through a link: a config kept in a dotfiles repository is a symlink, and replacing the link would end that.
        let destination = paths.configFile.resolvingSymlinksInPath()
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
        guard let data = inspection.localData else { throw ConfigSyncError.noLocalConfig(paths.configFile.path) }
        let current = report(inspection, settings: settings)
        switch SyncState.push(current.status, force: force) {
        case .refuse(let refusal): throw ConfigSyncError.refused(refusal, folder: settings.folder)
        case .nothingToDo:
            if let hash = current.localHash, settings.lastSynced != hash { settings.lastSynced = hash; try save(settings) }
            return .alreadyInSync
        case .proceed: break
        }
        let problems = SyncValidation.check(data)
        if !problems.isEmpty { throw ConfigSyncError.invalid(problems, file: paths.configFile.path) }

        var createdFolder = false
        if !inspection.folderReachable {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                createdFolder = true
            } catch {
                throw ConfigSyncError.folderUnreachable(folder.path)
            }
        }
        let destination = try remoteWriteTarget(in: folder)
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
        case .present:
            if let data = inspection.remoteData {
                let problems = SyncValidation.check(data)
                if problems.isEmpty {
                    checks.append(DoctorCheck(.syncRemote, status: .ok, detail: .doctorSyncRemoteValid))
                } else {
                    checks.append(DoctorCheck(.syncRemote, status: .fail, detail: .doctorVerbatim(problems.map(\.message).joined(separator: "; ")), fix: .doctorFixSyncFixRemote))
                }
            }
        }
        if let row = commandsCheck(report, localData: inspection.localData) { checks.append(row) }
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
    private func commandsCheck(_ report: Report, localData: Data?) -> DoctorCheck? {
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
        let custom = localData.map { LaunchCommands(configData: $0).custom } ?? []
        guard !custom.isEmpty else { return nil }
        return DoctorCheck(.syncCommands, status: .ok, detail: .doctorSyncCommandsOwn(String(custom.count), listed(custom)), notes: more(custom))
    }
}
