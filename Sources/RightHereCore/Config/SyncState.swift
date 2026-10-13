import Foundation

/// How the local config compares with the copy in the sync folder, as far as the last sync lets anyone tell.
public enum SyncStatus: String, Sendable, Codable, CaseIterable {
    case inSync = "in-sync"
    /// Only the local file changed since the last sync.
    case localAhead = "local-ahead"
    /// Only the copy in the folder changed since the last sync.
    case remoteAhead = "remote-ahead"
    /// Both changed, or they differ and nothing says which is newer (no sync happened yet).
    case diverged
    case remoteMissing = "remote-missing"
    /// The copy is a placeholder iCloud has not downloaded (an `.config.toml.icloud` stub), or cannot be read.
    case remoteEvicted = "remote-evicted"
}

/// The copy in the sync folder.
public enum SyncRemote: Sendable, Equatable {
    case missing
    case evicted
    /// SHA-256 of the file's bytes, in hex.
    case present(hash: String)
}

/// What is known when deciding: hashes only, so the state machine is pure.
public struct SyncSnapshot: Sendable, Equatable {
    /// `nil` when there is no local config file.
    public var local: String?
    public var remote: SyncRemote
    /// The content both sides had at the last successful sync; `nil` before any.
    public var lastSynced: String?

    public init(local: String?, remote: SyncRemote, lastSynced: String?) {
        self.local = local
        self.remote = remote
        self.lastSynced = lastSynced
    }
}

public enum SyncDecision: Sendable, Equatable {
    case proceed
    case nothingToDo
    case refuse(SyncRefusal)
}

public enum SyncRefusal: Sendable, Equatable {
    /// Pull: the local file changed since the last sync, and pulling would overwrite it.
    case localChanged
    /// Push: the copy in the folder changed since the last sync, and pushing would overwrite it.
    case remoteChanged
    case remoteMissing
    case remoteEvicted
}

public enum SyncState {
    public static func status(_ snapshot: SyncSnapshot) -> SyncStatus {
        let remote: String
        switch snapshot.remote {
        case .evicted: return .remoteEvicted
        case .missing: return .remoteMissing
        case .present(let hash): remote = hash
        }
        if snapshot.local == remote { return .inSync }
        // A machine with no config file has nothing to lose and nothing to send, whatever was synced before: a deleted
        // file read as a local change would advise a push that cannot happen and refuse the pull that restores it.
        if snapshot.local == nil { return .remoteAhead }
        guard let last = snapshot.lastSynced else {
            // Never synced: two different files are a conflict only a person can settle.
            return .diverged
        }
        switch (snapshot.local != last, remote != last) {
        case (false, true): return .remoteAhead
        case (true, false): return .localAhead
        default: return .diverged
        }
    }

    public static func pull(_ status: SyncStatus, force: Bool) -> SyncDecision {
        switch status {
        case .inSync: return .nothingToDo
        case .remoteAhead: return .proceed
        case .localAhead, .diverged: return force ? .proceed : .refuse(.localChanged)
        case .remoteMissing: return .refuse(.remoteMissing)
        case .remoteEvicted: return .refuse(.remoteEvicted)
        }
    }

    public static func push(_ status: SyncStatus, force: Bool) -> SyncDecision {
        switch status {
        case .inSync: return .nothingToDo
        case .localAhead, .remoteMissing: return .proceed
        case .remoteAhead, .diverged: return force ? .proceed : .refuse(.remoteChanged)
        // Never written over, even with force: the copy there may be newer than anything this machine knows.
        case .remoteEvicted: return .refuse(.remoteEvicted)
        }
    }
}
