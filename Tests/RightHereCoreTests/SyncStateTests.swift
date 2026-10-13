import Testing
@testable import RightHereCore

@Suite("SyncState")
struct SyncStateTests {
    private func status(_ local: String?, _ remote: SyncRemote, last: String?) -> SyncStatus {
        SyncState.status(SyncSnapshot(local: local, remote: remote, lastSynced: last))
    }

    @Test func identicalContentIsInSyncWithOrWithoutHistory() {
        #expect(status("a", .present(hash: "a"), last: "a") == .inSync)
        #expect(status("a", .present(hash: "a"), last: nil) == .inSync)
        #expect(status("a", .present(hash: "a"), last: "old") == .inSync)
    }

    @Test func onlyLocalChanged() {
        #expect(status("b", .present(hash: "a"), last: "a") == .localAhead)
    }

    @Test func onlyRemoteChanged() {
        #expect(status("a", .present(hash: "b"), last: "a") == .remoteAhead)
    }

    @Test func bothChanged() {
        #expect(status("b", .present(hash: "c"), last: "a") == .diverged)
    }

    @Test func twoDifferentFilesWithNoHistoryAreDiverged() {
        #expect(status("b", .present(hash: "c"), last: nil) == .diverged)
    }

    @Test func noLocalFileAndAFolderCopyMeansPull() {
        #expect(status(nil, .present(hash: "c"), last: nil) == .remoteAhead)
        // A local file removed after a sync is not a change to send: there is nothing to send, and pulling restores it
        // without --force, whether or not the folder's copy changed since.
        #expect(status(nil, .present(hash: "c"), last: "c") == .remoteAhead)
        #expect(status(nil, .present(hash: "d"), last: "c") == .remoteAhead)
        #expect(SyncState.pull(status(nil, .present(hash: "c"), last: "c"), force: false) == .proceed)
    }

    @Test func missingAndEvictedWinOverTheHashes() {
        #expect(status("a", .missing, last: "a") == .remoteMissing)
        #expect(status(nil, .missing, last: nil) == .remoteMissing)
        #expect(status("a", .evicted, last: "a") == .remoteEvicted)
        #expect(status(nil, .evicted, last: nil) == .remoteEvicted)
    }

    @Test("pull", arguments: [
        (SyncStatus.inSync, false, SyncDecision.nothingToDo),
        (.inSync, true, .nothingToDo),
        (.remoteAhead, false, .proceed),
        (.remoteAhead, true, .proceed),
        (.localAhead, false, .refuse(.localChanged)),
        (.localAhead, true, .proceed),
        (.diverged, false, .refuse(.localChanged)),
        (.diverged, true, .proceed),
        (.remoteMissing, false, .refuse(.remoteMissing)),
        (.remoteMissing, true, .refuse(.remoteMissing)),
        (.remoteEvicted, false, .refuse(.remoteEvicted)),
        (.remoteEvicted, true, .refuse(.remoteEvicted))
    ])
    func pull(status: SyncStatus, force: Bool, expected: SyncDecision) {
        #expect(SyncState.pull(status, force: force) == expected)
    }

    @Test("push", arguments: [
        (SyncStatus.inSync, false, SyncDecision.nothingToDo),
        (.inSync, true, .nothingToDo),
        (.localAhead, false, .proceed),
        (.localAhead, true, .proceed),
        (.remoteMissing, false, .proceed),
        (.remoteMissing, true, .proceed),
        (.remoteAhead, false, .refuse(.remoteChanged)),
        (.remoteAhead, true, .proceed),
        (.diverged, false, .refuse(.remoteChanged)),
        (.diverged, true, .proceed),
        (.remoteEvicted, false, .refuse(.remoteEvicted)),
        (.remoteEvicted, true, .refuse(.remoteEvicted))
    ])
    func push(status: SyncStatus, force: Bool, expected: SyncDecision) {
        #expect(SyncState.push(status, force: force) == expected)
    }

    @Test func everyStatusIsHandledByBothDecisions() {
        for status in SyncStatus.allCases {
            _ = SyncState.pull(status, force: false)
            _ = SyncState.push(status, force: false)
        }
        #expect(SyncStatus.allCases.map(\.rawValue) == ["in-sync", "local-ahead", "remote-ahead", "diverged", "remote-missing", "remote-evicted"])
    }
}
