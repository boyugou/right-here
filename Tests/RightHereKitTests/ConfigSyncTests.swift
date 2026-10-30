import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

/// A config folder and a sync folder inside one throwaway directory; nothing outside it is touched.
private struct Fixture {
    let root: URL
    let paths: RHPaths
    let remote: URL
    var local: URL { paths.configFile }
    var remoteFile: URL { remote.appendingPathComponent("config.toml") }

    init() throws {
        root = try makeTemporaryDirectory()
        let config = root.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        paths = RHPaths(environment: ["RH_CONFIG_DIR": config.path], home: root.appendingPathComponent("home"))
        remote = root.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
    }

    func cleanUp() {
        // Test files only; a test that made a folder unreadable undoes it first.
        for url in [remoteFile, remote.appendingPathComponent("config 2.toml")] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ text: String, to file: URL) throws { try text.write(to: file, atomically: true, encoding: .utf8) }
    func read(_ file: URL) throws -> String { try String(contentsOf: file, encoding: .utf8) }
    var sync: ConfigSync { ConfigSync(paths: paths) }
    /// What is in a folder, not counting the lock of the config, which a pull takes and leaves where it is (`FileLock`).
    func names(in folder: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0 != ".config.lock" }.sorted() }
}

private let one = "[general]\nterminal = \"ghostty\"\n"
private let two = "[general]\nterminal = \"terminal\"\n"
private let three = "[general]\neditor = \"vscode\"\n"

@Suite("ConfigSync: enable and status")
struct ConfigSyncEnableTests {
    @Test func theDefaultFolderIsUnderTheHomeTheCallerGives() {
        let paths = RHPaths(environment: [:], home: URL(fileURLWithPath: "/Users/tester"))
        #expect(ConfigSync(paths: paths).defaultFolder.path == "/Users/tester/Library/Mobile Documents/com~apple~CloudDocs/Right Here")
    }

    @Test func tildeMeansTheHomeOfThePaths() {
        let paths = RHPaths(environment: [:], home: URL(fileURLWithPath: "/Users/tester"))
        #expect(ConfigSync(paths: paths).resolve(folder: "~/Sync/rh").path == "/Users/tester/Sync/rh")
        #expect(ConfigSync(paths: paths).resolve(folder: "~").path == "/Users/tester")
        #expect(ConfigSync(paths: paths).resolve(folder: "/a/b/../c").path == "/a/c")
    }

    @Test func enableRemembersTheFolderAndCopiesNothing() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        let target = f.root.appendingPathComponent("not-yet")
        let report = try f.sync.enable(folder: target.path)
        #expect(report.status == .remoteMissing)
        #expect(!report.folderReachable)
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(f.sync.settings()?.folder == target.path)
        #expect(f.names(in: f.paths.configDirectory) == ["config.toml", "sync.toml"])
    }

    @Test func identicalCopiesAreRecordedAsSynced() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.write(one, to: f.remoteFile)
        let report = try f.sync.enable(folder: f.remote.path)
        #expect(report.status == .inSync)
        #expect(f.sync.settings()?.lastSynced == report.localHash)
    }

    @Test func differentCopiesWithNoHistoryAreDiverged() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.write(two, to: f.remoteFile)
        #expect(try f.sync.enable(folder: f.remote.path).status == .diverged)
    }

    @Test func aFolderThatHoldsTheConfigItselfIsRefused() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        #expect(throws: ConfigSyncError.self) { try f.sync.enable(folder: f.paths.configDirectory.path) }
        #expect(f.sync.settings() == nil)
    }

    @Test func aFileIsNotAFolder() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        let file = f.root.appendingPathComponent("plain")
        try f.write("x", to: file)
        #expect(throws: ConfigSyncError.self) { try f.sync.enable(folder: file.path) }
    }

    @Test func everythingNeedsEnableFirst() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        #expect(throws: ConfigSyncError.notEnabled) { try f.sync.status() }
        #expect(throws: ConfigSyncError.notEnabled) { try f.sync.pull() }
        #expect(throws: ConfigSyncError.notEnabled) { try f.sync.push() }
        #expect(try f.sync.disable() == false)
    }

    @Test func disableForgetsTheStateAndKeepsBothCopies() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.write(one, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        #expect(try f.sync.disable())
        #expect(f.sync.settings() == nil)
        #expect(try f.read(f.local) == one)
        #expect(try f.read(f.remoteFile) == one)
    }
}

@Suite("ConfigSync: push and pull")
struct ConfigSyncTransferTests {
    @Test func pushCreatesTheFolderWhenItsParentExists() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        let target = f.root.appendingPathComponent("Right Here")
        try f.sync.enable(folder: target.path)
        #expect(try f.sync.push() == .pushed(backup: nil, createdFolder: true))
        #expect(try f.read(target.appendingPathComponent("config.toml")) == one)
        #expect(try f.sync.status().status == .inSync)
    }

    @Test func pushWithoutAParentExplainsInsteadOfCreatingTrees() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        let target = f.root.appendingPathComponent("no/such/parent/Right Here")
        try f.sync.enable(folder: target.path)
        #expect(throws: ConfigSyncError.folderUnreachable(target.path, makeParent: nil)) { try f.sync.push() }
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("no").path))
    }

    @Test func aLocalEditIsAheadAndPushSendsIt() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(two, to: f.local)
        #expect(try f.sync.status().status == .localAhead)
        #expect(try f.sync.push() == .pushed(backup: nil, createdFolder: false))
        #expect(try f.read(f.remoteFile) == two)
    }

    @Test func pushRefusesWhenTheFolderChangedSinceTheLastSync() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(two, to: f.remoteFile)
        try f.write(three, to: f.local)
        #expect(try f.sync.status().status == .diverged)
        #expect(throws: ConfigSyncError.refused(.remoteChanged, folder: f.remote.path)) { try f.sync.push() }
        #expect(try f.read(f.remoteFile) == two)
    }

    @Test func forcedPushSavesTheReplacedCopy() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(two, to: f.remoteFile)
        let outcome = try f.sync.push(force: true)
        guard case .pushed(let backup?, _) = outcome else { Issue.record("expected a backup"); return }
        #expect(backup.deletingLastPathComponent().path == f.remote.path)
        #expect(backup.lastPathComponent.hasPrefix("config.toml.bak-"))
        #expect(try f.read(backup) == two)
        #expect(try f.read(f.remoteFile) == one)
    }

    @Test func pullTakesANewerFolderCopy() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(two, to: f.remoteFile)
        #expect(try f.sync.status().status == .remoteAhead)
        #expect(try f.sync.pull() == .pulled(backup: nil))
        #expect(try f.read(f.local) == two)
        #expect(try f.sync.status().status == .inSync)
        #expect(try f.sync.pull() == .alreadyInSync)
    }

    @Test func pullCreatesTheLocalFileOnANewMachine() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        #expect(try f.sync.status().status == .remoteAhead)
        #expect(try f.sync.pull() == .pulled(backup: nil))
        #expect(try f.read(f.local) == one)
    }

    @Test func pullRefusesToOverwriteALocallyChangedConfig() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(two, to: f.local)
        try f.write(three, to: f.remoteFile)
        #expect(throws: ConfigSyncError.refused(.localChanged, folder: f.remote.path)) { try f.sync.pull() }
        #expect(try f.read(f.local) == two)
        // Local ahead only (the folder did not change) also refuses: pulling would throw the edit away.
        try f.write(one, to: f.remoteFile)
        #expect(throws: ConfigSyncError.refused(.localChanged, folder: f.remote.path)) { try f.sync.pull() }
        #expect(try f.read(f.local) == two)
    }

    @Test func forcedPullSavesTheReplacedFile() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(two, to: f.local)
        try f.write(three, to: f.remoteFile)
        let outcome = try f.sync.pull(force: true)
        guard case .pulled(let backup?) = outcome else { Issue.record("expected a backup"); return }
        #expect(backup.lastPathComponent.hasPrefix("config.toml.bak-"))
        #expect(backup.deletingLastPathComponent().path == f.paths.configDirectory.path)
        #expect(try f.read(backup) == two)
        #expect(try f.read(f.local) == three)
    }

    @Test func aDeletedLocalConfigIsRestoredByAPlainPull() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try FileManager.default.removeItem(at: f.local)
        // It used to read as "local ahead": status advised a push, push said to pull, and pull refused to overwrite the change.
        #expect(try f.sync.status().status == .remoteAhead)
        #expect(throws: ConfigSyncError.noLocalConfig(f.local.path)) { try f.sync.push() }
        #expect(try f.sync.pull() == .pulled(backup: nil))
        #expect(try f.read(f.local) == one)
        #expect(try f.sync.status().status == .inSync)
        // The same when the folder's copy changed while the file was gone.
        try FileManager.default.removeItem(at: f.local)
        try f.write(two, to: f.remoteFile)
        #expect(try f.sync.status().status == .remoteAhead)
        #expect(try f.sync.pull() == .pulled(backup: nil))
        #expect(try f.read(f.local) == two)
    }

    @Test func pullFromAMissingCopyExplains() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        #expect(throws: ConfigSyncError.refused(.remoteMissing, folder: f.remote.path)) { try f.sync.pull(force: true) }
    }

    @Test func pushWithoutALocalConfigExplains() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.sync.enable(folder: f.remote.path)
        #expect(throws: ConfigSyncError.noLocalConfig(f.local.path)) { try f.sync.push() }
    }

    @Test func pullKeepsASymlinkedConfigALink() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        let real = f.root.appendingPathComponent("dotfiles-config.toml")
        try f.write(one, to: real)
        try FileManager.default.createSymbolicLink(at: f.local, withDestinationURL: real)
        try f.write(one, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(two, to: f.remoteFile)
        #expect(try f.sync.pull() == .pulled(backup: nil))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: f.local.path)) == real.path)
        #expect(try f.read(real) == two)
    }
}

@Suite("ConfigSync: refusals and failures")
struct ConfigSyncSafetyTests {
    private func prepared(_ remoteText: String, local: String? = one) throws -> Fixture {
        let f = try Fixture()
        if let local { try f.write(local, to: f.local) }
        try f.write(remoteText, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        return f
    }

    @Test func aRemoteThatDoesNotParseIsNotPulled() throws {
        let f = try prepared("[general\n", local: nil); defer { f.cleanUp() }
        #expect(throws: (any Error).self) { try f.sync.pull(force: true) }
        #expect(!FileManager.default.fileExists(atPath: f.local.path))
    }

    @Test func aLocalThatDoesNotParseIsNotPushed() throws {
        let f = try prepared(one, local: "[general\n"); defer { f.cleanUp() }
        #expect(throws: (any Error).self) { try f.sync.push(force: true) }
        #expect(try f.read(f.remoteFile) == one)
    }

    @Test func anOversizedConfigIsNotCopiedEitherWay() throws {
        let big = "# " + String(repeating: "x", count: ConfigParser.maxBytes + 1) + "\n"
        let pushing = try prepared(one, local: big); defer { pushing.cleanUp() }
        #expect(throws: (any Error).self) { try pushing.sync.push(force: true) }
        #expect(try pushing.read(pushing.remoteFile) == one)
        let pulling = try prepared(big, local: nil); defer { pulling.cleanUp() }
        #expect(throws: (any Error).self) { try pulling.sync.pull(force: true) }
        #expect(!FileManager.default.fileExists(atPath: pulling.local.path))
    }

    @Test func aSecretLookingKeyIsNotCopiedEitherWay() throws {
        let secret = "[agent.mine]\nname = \"M\"\ncommand = \"m\"\napi_key = \"x\"\n"
        let pushing = try prepared(one, local: secret); defer { pushing.cleanUp() }
        do { try pushing.sync.push(force: true); Issue.record("pushed") } catch let error as ConfigSyncError {
            #expect(error.description.contains("agent.mine.api_key"))
        }
        #expect(try pushing.read(pushing.remoteFile) == one)
        let pulling = try prepared(secret, local: nil); defer { pulling.cleanUp() }
        #expect(throws: (any Error).self) { try pulling.sync.pull(force: true) }
        #expect(!FileManager.default.fileExists(atPath: pulling.local.path))
    }

    @Test func aRefusalNeverPrintsTheTextOfTheFileRaw() throws {
        // A key name is whatever the file's author typed; here it is an OSC 52 sequence (set the clipboard) and a bell.
        let hostile = "[general]\nagents = [\"claude\"]\n\"token\\u001b]52;c;ZWNobyBwd25lZA==\\u0007\" = \"x\"\n"
        let f = try prepared(hostile, local: nil); defer { f.cleanUp() }
        do { try f.sync.pull(force: true); Issue.record("pulled") } catch let error as ConfigSyncError {
            let text = error.description
            #expect(text.contains(#"token\u001b]52;c;ZWNobyBwd25lZA==\u0007"#), "\(text)")
            #expect(!text.unicodeScalars.contains { $0.properties.generalCategory == .control && $0 != "\n" }, "a control character reached the message: \(text.debugDescription)")
        }
        // The doctor's detail for the same file.
        let remote = f.sync.doctorChecks().first { $0.id == .syncRemote }
        #expect(remote?.status == .fail)
        #expect(remote?.detail?.english().unicodeScalars.contains { $0.properties.generalCategory == .control } == false)
    }

    @Test func aRefusalEndsWithOnePeriod() throws {
        let secret = try prepared("[agent.mine]\nname = \"M\"\ncommand = \"m\"\napi_key = \"x\"\n", local: nil); defer { secret.cleanUp() }
        let syntax = try prepared("[general\n", local: nil); defer { syntax.cleanUp() }
        for f in [secret, syntax] {
            do { try f.sync.pull(force: true); Issue.record("pulled") } catch let error as ConfigSyncError {
                #expect(!error.description.contains(".."), "\(error.description)")
                #expect(error.description.hasSuffix("Nothing was changed."))
            }
        }
    }

    @Test func aCopyThatCannotBeReadIsEvictedNeitherMissingNorOverwritten() throws {
        // The stand-in for a file iCloud has not downloaded: it is there, and its content is not readable.
        let f = try prepared(one); defer { f.cleanUp() }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: f.remoteFile.path)
        try #require(!FileManager.default.isReadableFile(atPath: f.remoteFile.path), "running as a user that ignores permissions")
        try f.write(two, to: f.local)
        #expect(try f.sync.status().status == .remoteEvicted)
        #expect(throws: ConfigSyncError.refused(.remoteEvicted, folder: f.remote.path)) { try f.sync.push() }
        #expect(throws: ConfigSyncError.refused(.remoteEvicted, folder: f.remote.path)) { try f.sync.push(force: true) }
        #expect(throws: ConfigSyncError.refused(.remoteEvicted, folder: f.remote.path)) { try f.sync.pull(force: true) }
        #expect(try f.read(f.local) == two)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: f.remoteFile.path)
        #expect(try f.read(f.remoteFile) == one, "the copy that could not be read was written over")
        #expect(f.names(in: f.remote) == ["config.toml"])
    }

    @Test func aCopyThatChangedIsNotAnOverwriteOfThePullSource() throws {
        let f = try prepared(one); defer { f.cleanUp() }
        try f.sync.push()
        let before = try f.read(f.remoteFile)
        try f.write(two, to: f.local)
        _ = try? f.sync.pull()
        #expect(try f.read(f.remoteFile) == before)
    }

    @Test func aWriteInterruptedBeforeTheRenameLeavesTheOldFile() throws {
        struct Interrupted: Error {}
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.write(two, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push(force: true)
        try f.write(three, to: f.remoteFile)
        let before = f.names(in: f.remote).filter { !$0.hasPrefix("config.toml.bak-") }
        // Pull: the local file is the one being replaced.
        let pullInterrupted = ConfigSync(paths: f.paths, beforeRename: { _ in throw Interrupted() })
        #expect(throws: (any Error).self) { try pullInterrupted.pull() }
        #expect(try f.read(f.local) == one)
        #expect(f.names(in: f.paths.configDirectory) == ["config.toml", "sync.toml"])
        // Push: the copy in the folder is the one being replaced.
        try f.write(two, to: f.local)
        let pushInterrupted = ConfigSync(paths: f.paths, beforeRename: { _ in throw Interrupted() })
        #expect(throws: (any Error).self) { try pushInterrupted.push(force: true) }
        #expect(try f.read(f.remoteFile) == three)
        #expect(f.names(in: f.remote).filter { !$0.hasPrefix("config.toml.bak-") } == before)
    }

    @Test func theTemporaryFileLivesBesideTheDestination() throws {
        final class Seen: @unchecked Sendable { var folders: [String] = [] }
        let seen = Seen()
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        let recording = ConfigSync(paths: f.paths, beforeRename: { seen.folders.append($0.deletingLastPathComponent().path) })
        try recording.push()
        try f.write(two, to: f.remoteFile)
        try recording.pull()
        #expect(seen.folders == [f.remote.path, f.paths.configDirectory.path])
    }

    @Test func aFinderConflictCopyIsReported() throws {
        let f = try prepared(one); defer { f.cleanUp() }
        try f.write(two, to: f.remote.appendingPathComponent("config 2.toml"))
        try f.write(two, to: f.remote.appendingPathComponent("notes 2.toml"))
        #expect(try f.sync.status().conflictCopies == ["config 2.toml"])
        let conflict = f.sync.doctorChecks().first { $0.id == .syncConflict }
        #expect(conflict?.status == .warn)
        #expect(conflict?.detail?.english().contains("config 2.toml") == true)
    }
}

@Suite("ConfigSync: a link in the sync folder")
struct ConfigSyncFolderLinkTests {
    private func isLink(_ url: URL) -> Bool { (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil }

    @Test func aLinkToAFileInsideTheFolderStaysALinkAndTheBackupIsARealCopy() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        let store = f.remote.appendingPathComponent("store/config.toml")
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try f.write(two, to: store)
        try FileManager.default.createSymbolicLink(at: f.remoteFile, withDestinationURL: store)
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        guard case .pushed(let backup?, _) = try f.sync.push(force: true) else { Issue.record("expected the replaced copy to be saved"); return }
        #expect(isLink(f.remoteFile), "the push replaced the link with a regular file")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: f.remoteFile.path)) == store.path)
        #expect(try f.read(store) == one)
        #expect(!isLink(backup), "the backup is a second link, not a copy of what was replaced")
        #expect(try f.read(backup) == two)
        #expect(try f.sync.status().status == .inSync)
    }

    @Test func aLinkToAFileOutsideTheFolderIsNeverWrittenThrough() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        // Stands for any file the person can write, which a link planted in the folder could name.
        let elsewhere = f.root.appendingPathComponent("elsewhere.toml")
        try f.write(one, to: f.local)
        try f.write(one, to: elsewhere)
        try FileManager.default.createSymbolicLink(at: f.remoteFile, withDestinationURL: elsewhere)
        try f.sync.enable(folder: f.remote.path)
        #expect(try f.sync.status().status == .inSync)
        // This Mac's config changes, so a plain push would proceed (the folder's copy did not change).
        try f.write(two, to: f.local)
        let lastSynced = f.sync.settings()?.lastSynced
        for force in [false, true] {
            do { try f.sync.push(force: force); Issue.record("pushed through a link that leaves the folder") } catch ConfigSyncError.remoteLink(let file, let target) {
                #expect(file == f.remoteFile.path)
                #expect(target?.hasSuffix("/elsewhere.toml") == true, "\(String(describing: target))")
            }
        }
        #expect(try f.read(elsewhere) == one)
        #expect(isLink(f.remoteFile))
        #expect(f.names(in: f.remote) == ["config.toml"], "a refused push must not leave a saved copy")
        #expect(f.sync.settings()?.lastSynced == lastSynced)
        let description = ConfigSyncError.remoteLink(f.remoteFile.path, target: elsewhere.path).description
        #expect(description.contains("outside the sync folder") && description.hasSuffix("Nothing was changed."))
    }

    @Test func aLinkThatPointsNowhereIsRefusedToo() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        let nowhere = f.root.appendingPathComponent("not-there.toml")
        try f.write(one, to: f.local)
        try FileManager.default.createSymbolicLink(at: f.remoteFile, withDestinationURL: nowhere)
        try f.sync.enable(folder: f.remote.path)
        #expect(try f.sync.status().status == .remoteMissing)
        #expect(throws: ConfigSyncError.remoteLink(f.remoteFile.path, target: nil)) { try f.sync.push() }
        #expect(!FileManager.default.fileExists(atPath: nowhere.path))
        #expect(isLink(f.remoteFile))
    }
}

@Suite("ConfigSync: doctor")
struct ConfigSyncDoctorTests {
    @Test func nothingWhenSyncIsOff() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        #expect(f.sync.doctorChecks().isEmpty)
    }

    @Test func aHealthyFolderIsAllOk() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.write(one, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        let checks = f.sync.doctorChecks()
        #expect(checks.map(\.id) == [.syncFolder, .syncRemote, .syncState])
        #expect(checks.allSatisfy { $0.status == .ok })
    }

    @Test func anUnreachableFolderIsAWarning() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.sync.enable(folder: f.root.appendingPathComponent("gone").path)
        let checks = f.sync.doctorChecks()
        #expect(checks.map(\.id) == [.syncFolder])
        #expect(checks.first?.status == .warn)
    }

    @Test func anEvictedCopyIsAWarningWithAFix() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.write(one, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: f.remoteFile.path)
        try #require(!FileManager.default.isReadableFile(atPath: f.remoteFile.path), "running as a user that ignores permissions")
        let remote = f.sync.doctorChecks().first { $0.id == .syncRemote }
        #expect(remote?.status == .warn)
        #expect(remote?.detail?.english().contains("not downloaded") == true)
    }

    @Test func aRemoteThatDoesNotValidateFails() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.write("[general\n", to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        #expect(f.sync.doctorChecks().first { $0.id == .syncRemote }?.status == .fail)
    }

    @Test func divergenceIsAWarning() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(two, to: f.local)
        try f.write(three, to: f.remoteFile)
        let state = f.sync.doctorChecks().first { $0.id == .syncState }
        #expect(state?.status == .warn)
        #expect(state?.detail?.english().contains("both changed") == true)
    }

    @Test func aBrokenStateFileIsReported() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write("folder = 3\n", to: f.paths.syncStateFile)
        #expect(f.sync.doctorChecks().first?.id == .syncState)
    }

    /// The checks as `id: status | detail | fix`, so a state's whole wording is pinned in one line.
    private func lines(_ checks: [DoctorCheck]) -> [String] {
        checks.map { "\($0.id.rawValue): \($0.status.rawValue) | \($0.detail?.english() ?? "-") | \($0.fix?.english() ?? "-")" }
    }

    @Test func theWordingOfAHealthyFolder() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.write(one, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        #expect(lines(f.sync.doctorChecks()) == [
            "sync.folder: ok | \(f.remote.path) | -",
            "sync.remote: ok | config.toml in the folder validates | -",
            "sync.state: ok | in sync | -"
        ])
    }

    @Test func theWordingOfAFolderThatIsNotThere() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        let gone = f.root.appendingPathComponent("gone").path
        try f.sync.enable(folder: gone)
        #expect(lines(f.sync.doctorChecks()) == [
            "sync.folder: warn | \(gone) is not reachable | Check that the drive or iCloud Drive is available. Or run `rh config sync push` to create the folder, or choose another with `rh config sync enable --folder <folder>`."
        ])
    }

    @Test func theWordingOfACopyThatIsMissingOrNotDownloaded() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        #expect(lines(f.sync.doctorChecks()) == [
            "sync.folder: ok | \(f.remote.path) | -",
            "sync.remote: warn | no config.toml in the folder yet | Run `rh config sync push` to put this machine's config there."
        ])
        try f.write(one, to: f.remoteFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: f.remoteFile.path)
        try #require(!FileManager.default.isReadableFile(atPath: f.remoteFile.path), "running as a user that ignores permissions")
        #expect(lines(f.sync.doctorChecks()).dropFirst() == [
            "sync.remote: warn | config.toml in the folder is not downloaded yet (or cannot be read) | Open the folder in Finder, let the download finish, then run `rh config sync status`."
        ])
    }

    @Test func theWordingOfACopyThatDoesNotValidate() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.write("[general\n", to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        let remote = try #require(f.sync.doctorChecks().first { $0.id == .syncRemote })
        let problems = SyncValidation.check(try Data(contentsOf: f.remoteFile)).map(\.message).joined(separator: "; ")
        #expect(!problems.isEmpty)
        #expect(lines([remote]) == ["sync.remote: fail | \(problems) | Fix the file in the folder, or run `rh config sync push --force` from a machine with a good config."])
    }

    @Test func theWordingOfEachWayTheTwoCopiesCanDiffer() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(two, to: f.local)
        #expect(lines(f.sync.doctorChecks()).last == "sync.state: warn | this machine's config is ahead of the folder | Run `rh config sync push`.")
        try f.write(one, to: f.local)
        try f.write(three, to: f.remoteFile)
        #expect(lines(f.sync.doctorChecks()).last == "sync.state: warn | the folder has a newer config than this machine | Run `rh config sync pull`.")
        try f.write(two, to: f.local)
        #expect(lines(f.sync.doctorChecks()).last == "sync.state: warn | this machine and the folder both changed since the last sync | Compare them with `rh config sync status`. Then run `rh config sync pull --force` to take the folder's copy, or `push --force` to keep this one. The replaced file is saved first.")
    }

    @Test func theWordingOfConflictCopiesAndOfAStateFileThatCannotBeRead() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.write(one, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        try f.write(two, to: f.remote.appendingPathComponent("config 2.toml"))
        #expect(lines(f.sync.doctorChecks()).last == "sync.conflict: warn | config 2.toml in \(f.remote.path) | Two machines wrote config.toml at once. Compare the copies, keep the right content in config.toml, and delete the others by hand.")
        let g = try Fixture(); defer { g.cleanUp() }
        try g.write("folder = 3\n", to: g.paths.syncStateFile)
        #expect(lines(g.sync.doctorChecks()) == ["sync.state: warn | \(g.paths.syncStateFile.path) cannot be read | Run `rh config sync enable` again, or `rh config sync disable`."])
    }

    @Test func theWordingOfTheRowAboutLaunchSettingsTheFolderWouldAdd() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(withCommands, to: f.remoteFile)
        let row = try #require(f.sync.doctorChecks().first { $0.id == .syncCommands })
        let changes = try f.sync.status().pendingCommands.map(\.line)
        #expect(changes.count == 4)
        // The first three are listed as the config writes them; how many more there are is a line of its own.
        #expect(lines([row]) == ["sync.commands: warn | the folder's copy would add or change 4 launch setting(s): \(changes.prefix(3).joined(separator: "; ")) | Read them with `rh config sync status`. If they are yours, `rh config sync pull --allow-commands` takes the copy."])
        #expect(row.notes.map { $0.english() } == ["and 1 more"])
    }

    @Test func theWordingOfTheRowAboutProgramsThisConfigStartsByItself() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        let agent = "[general]\nagents = [\"claude\"]\n[agent.claude]\ncommand = \"claude --model opus\"\n"
        try f.write(agent, to: f.local)
        try f.write(agent, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        let one = try #require(f.sync.doctorChecks().first { $0.id == .syncCommands })
        #expect(lines([one]) == [#"sync.commands: ok | this config starts programs of its own through 1 setting(s): [agent.claude] command = "claude --model opus" (was "claude") | -"#])
        #expect(one.notes.isEmpty)
        // With more than three, the first three are listed and the rest is a line of its own.
        try f.write(withCommands, to: f.local)
        try f.write(withCommands, to: f.remoteFile)
        let many = try #require(f.sync.doctorChecks().first { $0.id == .syncCommands })
        let custom = LaunchCommands(configData: Data(withCommands.utf8)).custom.map(\.line)
        #expect(custom.count == 4)
        #expect(lines([many]) == ["sync.commands: ok | this config starts programs of its own through 4 setting(s): \(custom.prefix(3).joined(separator: "; ")) | -"])
        #expect(many.notes.map { $0.english() } == ["and 1 more"])
    }

    @Test func launchCommandsAreOneRowAndOnlyWhenThereAreSome() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(withCommands, to: f.local)
        try f.write(withCommands, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        let row = try #require(f.sync.doctorChecks().filter { $0.id == .syncCommands }.first)
        #expect(row.status == .ok)
        #expect(row.detail?.english().contains("/usr/bin/id") == true && row.detail?.english().contains("/bin/sh") == true)
        // Without any, no row (the healthy-folder test above has none).
        try f.write(one, to: f.local)
        try f.write(one, to: f.remoteFile)
        #expect(f.sync.doctorChecks().filter { $0.id == .syncCommands }.isEmpty)
    }

    @Test func aFolderCopyThatWouldAddCommandsIsAWarningBeforeAnyPull() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(withCommands, to: f.remoteFile)
        let rows = f.sync.doctorChecks().filter { $0.id == .syncCommands }
        #expect(rows.count == 1)
        #expect(rows.first?.status == .warn)
        #expect(rows.first?.fix?.english().contains("--allow-commands") == true)
    }
}

private let withCommands = """
[general]
terminal = "terminal"

[[app]]
id = "terminal"
name = "Terminal"
bundle_id = "com.apple.Terminal"
role = "terminal"
open_args = ["/usr/bin/id", "-un", "{dir}"]
run_args = ["/bin/sh", "-c", "{command}"]
"""

@Suite("ConfigSync: the folder is not trusted with programs")
struct ConfigSyncTrustTests {
    /// A synced config, a machine that has pulled it, and then a change in the folder.
    private func machine(local: String = one, folder: String = one) throws -> Fixture {
        let f = try Fixture()
        try f.write(local, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(folder, to: f.remoteFile)
        return f
    }

    private func refusal(_ body: () throws -> Void) -> [LaunchCommands.Change]? {
        do { try body() } catch ConfigSyncError.commandsNeedApproval(let changes) { return changes } catch { Issue.record("a different error: \(error)") }
        return nil
    }

    /// What this Mac's own file decides is part of what a copy would start: the switch that starts agents without asking, an agent's own setting, a terminal that only that file defines. A copy is read
    /// with it laid over (the pull was once taken with nothing listed when the switch was in `config.local.toml`).
    private func overlaid(_ overlay: String, shared: String = "[general]\nterminal = \"terminal\"\nagents = [\"claude\"]\n", copy: String) throws -> Fixture {
        let f = try machine(local: shared, folder: copy)
        try f.write(overlay, to: f.paths.localConfigFile)
        return f
    }

    @Test func aCopyThatPutsAnAgentInTheMenuWhileTheSwitchOfThisMacsOwnFileIsOnIsListed() throws {
        let f = try overlaid("[general]\nbypass_permissions = true\n", copy: "[general]\nterminal = \"terminal\"\nagents = [\"claude\", \"codex\"]\n"); defer { f.cleanUp() }
        let changes = try #require(refusal { try f.sync.pull() })
        #expect(changes.map(\.place) == ["[agent.codex] offered with its permission prompts switched off (it is in the menu or the Quick Actions)"], "\(changes.map(\.line))")
        #expect(try f.read(f.local) == "[general]\nterminal = \"terminal\"\nagents = [\"claude\"]\n")
        // The status and the doctor say it too, before anything is pulled.
        #expect(try f.sync.status().pendingCommands.map(\.place) == changes.map(\.place))
    }

    @Test func aCopyThatOffersAnAgentThatThisMacsOwnFileTellsToStartWithoutAskingIsListed() throws {
        let f = try overlaid("[agent.codex]\nbypass_permissions = true\n", copy: "[general]\nterminal = \"terminal\"\nagents = [\"claude\"]\n[services]\nitems = [\"agent.codex\"]\n"); defer { f.cleanUp() }
        let changes = try #require(refusal { try f.sync.pull() })
        #expect(changes.map(\.place).contains("[agent.codex] offered with its permission prompts switched off (it is in the menu or the Quick Actions)"), "\(changes.map(\.line))")
    }

    @Test func aCopyThatTakesOutTheSettingThatKeepsOneAgentAskingIsListedWhenTheSwitchIsOnInThisMacsOwnFile() throws {
        let kept = "[general]\nterminal = \"terminal\"\nagents = [\"claude\"]\n[agent.claude]\nbypass_permissions = false\n"
        let f = try overlaid("[general]\nbypass_permissions = true\n", shared: kept, copy: "[general]\nterminal = \"terminal\"\nagents = [\"claude\"]\n"); defer { f.cleanUp() }
        let changes = try #require(refusal { try f.sync.pull() })
        #expect(changes.map(\.place).contains("[agent.claude] offered with its permission prompts switched off (it is in the menu or the Quick Actions)"), "\(changes.map(\.line))")
    }

    @Test func aCopyThatOffersAnAgentWhoseOwnCommandTypesTheFlagIsListedEvenWhenTheCommandIsTheSameOnBothSides() throws {
        let typed = "[general]\nterminal = \"terminal\"\nagents = [\"claude\"]\n[agent.yolo]\nname = \"Claude (no prompts)\"\ncommand = \"claude --dangerously-skip-permissions\"\n"
        let f = try machine(local: typed, folder: typed.replacingOccurrences(of: "agents = [\"claude\"]", with: "agents = [\"claude\", \"yolo\"]")); defer { f.cleanUp() }
        let changes = try #require(refusal { try f.sync.pull() })
        #expect(changes.map(\.place) == ["[agent.yolo] offered with its permission prompts switched off (it is in the menu or the Quick Actions)"], "\(changes.map(\.line))")
    }

    @Test func aTerminalThatOnlyThisMacsOwnFileDefinesIsKnownWhenACopyGivesAnAppItsIdentifierAnotherRole() throws {
        let terminal = "[[app]]\nid = \"myterm\"\nname = \"MyTerm\"\nbundle_id = \"com.example.myterm\"\nrole = \"terminal\"\n"
        let copy = "[general]\nterminal = \"terminal\"\nagents = [\"claude\"]\n[[app]]\nid = \"myterm-files\"\nname = \"MyTerm Files\"\nbundle_id = \"com.example.myterm\"\nrole = \"editor\"\n"
        let f = try overlaid(terminal, copy: copy); defer { f.cleanUp() }
        let changes = try #require(refusal { try f.sync.pull() })
        #expect(changes.map(\.place).contains { $0.hasPrefix("[[app]] myterm-files role") }, "\(changes.map(\.line))")
    }

    @Test func aCopyThatGivesAnAgentATerminalThatStartsThroughATemplateIsListed() throws {
        let remote = "[[app]]\nid = \"remote\"\nname = \"Remote Shell\"\nbundle_id = \"com.apple.Terminal\"\nrole = \"terminal\"\nrun_args = [\"/usr/bin/ssh\", \"build-server\", \"cd {dir} && {command}\"]\n"
        let base = "[general]\nterminal = \"terminal\"\nagents = [\"claude\"]\n" + remote
        let f = try machine(local: base, folder: base + "[agent.claude]\nterminal = \"remote\"\n"); defer { f.cleanUp() }
        let changes = try #require(refusal { try f.sync.pull() })
        #expect(changes.map(\.place) == ["[agent.claude] terminal (starts through a command template)"], "\(changes.map(\.line))")
        // And an item of the menu that names it.
        let g = try machine(local: base, folder: base + "[menu]\nitems = [\"open.terminal@remote\"]\n"); defer { g.cleanUp() }
        let items = try #require(refusal { try g.sync.pull() })
        #expect(items.map(\.place) == ["an item of the menu or of the Quick Actions: open.terminal@remote (starts through a command template)"], "\(items.map(\.line))")
    }

    @Test func aFolderConfigThatRedefinesTheTerminalWithItsOwnProgramsIsRefused() throws {
        let f = try machine(folder: withCommands); defer { f.cleanUp() }
        let lastSynced = f.sync.settings()?.lastSynced
        let changes = try #require(refusal { try f.sync.pull() })
        let lines = changes.map(\.line)
        #expect(lines.contains(#"[[app]] terminal open_args = ["/usr/bin/id", "-un", "{dir}"]"#), "\(lines)")
        #expect(lines.contains(#"[[app]] terminal run_args = ["/bin/sh", "-c", "{command}"]"#), "\(lines)")
        // Nothing moved: not the config, not the record of what was synced, no saved copy.
        #expect(try f.read(f.local) == one)
        #expect(f.sync.settings()?.lastSynced == lastSynced)
        #expect(f.names(in: f.paths.configDirectory) == ["config.toml", "sync.toml"])
    }

    @Test func theRefusalSaysWhatToDoAndNamesWhatItFound() throws {
        let f = try machine(folder: withCommands); defer { f.cleanUp() }
        let changes = try #require(refusal { try f.sync.pull() })
        let text = ConfigSyncError.commandsNeedApproval(changes).description
        #expect(text.contains("--allow-commands") && text.contains("Nothing was changed"))
        #expect(text.contains("/bin/sh") && text.contains("run_args"))
    }

    @Test func forceDoesNotApproveCommands() throws {
        let f = try machine(folder: withCommands); defer { f.cleanUp() }
        try f.write(two, to: f.local)
        #expect(throws: ConfigSyncError.refused(.localChanged, folder: f.remote.path)) { try f.sync.pull() }
        #expect(refusal { try f.sync.pull(force: true) } != nil)
        #expect(try f.read(f.local) == two)
        #expect(f.names(in: f.paths.configDirectory) == ["config.toml", "sync.toml"], "a forced pull that is refused must not leave a saved copy either")
    }

    @Test func allowCommandsTakesTheCopy() throws {
        let f = try machine(folder: withCommands); defer { f.cleanUp() }
        #expect(try f.sync.pull(allowCommands: true) == .pulled(backup: nil))
        #expect(try f.read(f.local) == withCommands)
        #expect(try f.sync.status().status == .inSync)
    }

    @Test func allowingCommandsDoesNotLiftTheOtherRefusals() throws {
        let f = try machine(folder: withCommands); defer { f.cleanUp() }
        try f.write(two, to: f.local)
        #expect(throws: ConfigSyncError.refused(.localChanged, folder: f.remote.path)) { try f.sync.pull(allowCommands: true) }
        #expect(try f.read(f.local) == two)
        let saved = try f.sync.pull(force: true, allowCommands: true)
        guard case .pulled(let backup?) = saved else { Issue.record("expected the replaced file to be saved"); return }
        #expect(try f.read(backup) == two)
    }

    @Test func aCommandThisMachineAlreadyHasIsNotAskedAboutAgain() throws {
        let f = try machine(local: withCommands, folder: withCommands + "\n[menu]\nitems = [\"open.terminal\"]\n"); defer { f.cleanUp() }
        #expect(try f.sync.pull() == .pulled(backup: nil))
    }

    @Test func aTerminalTheFolderConfigListsAsAnotherKindOfAppIsAskedAbout() throws {
        // A terminal that the config defines itself, and an app with its bundle identifier (in another case: the system finds an app by it whatever the case) and another role: the second would be
        // handed files, which a terminal runs. A built-in terminal listed as another kind of app is refused by the config itself (`ConfigParser`), so there is nothing in it to ask about.
        let relabeled = "[[app]]\nid = \"mine\"\nname = \"Mine\"\nbundle_id = \"com.example.term\"\nrole = \"terminal\"\n\n[[app]]\nid = \"mine-too\"\nname = \"Mine too\"\nbundle_id = \"Com.Example.TERM\"\nrole = \"general\"\n"
        let f = try machine(folder: relabeled); defer { f.cleanUp() }
        let changes = try #require(refusal { try f.sync.pull() })
        #expect(changes.map(\.line) == [#"[[app]] mine-too role (a terminal handed a file runs it) = "general""#])
        #expect(try f.read(f.local) == one)
        #expect(try f.sync.pull(allowCommands: true) == .pulled(backup: nil))
    }

    @Test func aBuiltInTerminalTheFolderConfigListsAsAnEditorIsLeftOutOfTheConfigAndAnAgentItPutsInTheMenuWhileThePromptsAreOffIsAskedAbout() throws {
        let relabeled = "[[app]]\nid = \"terminal\"\nname = \"Terminal\"\nbundle_id = \"com.apple.terminal\"\nrole = \"editor\"\n"
        #expect(ConfigParser.parse(relabeled).hasErrors && ConfigParser.parse(relabeled).config.apps.isEmpty)
        let f = try machine(local: "[general]\nbypass_permissions = true\nagents = [\"claude\"]\n", folder: "[general]\nbypass_permissions = true\nagents = [\"claude\", \"codex\"]\n"); defer { f.cleanUp() }
        let changes = try #require(refusal { try f.sync.pull() })
        #expect(changes.map(\.line) == [#"[agent.codex] offered with its permission prompts switched off (it is in the menu or the Quick Actions) = "--dangerously-bypass-approvals-and-sandbox""#])
    }

    @Test func aChangedCommandIsAskedAboutAndSaysWhatItWas() throws {
        let f = try machine(local: withCommands, folder: withCommands.replacingOccurrences(of: "/bin/sh", with: "/bin/zsh")); defer { f.cleanUp() }
        let changes = try #require(refusal { try f.sync.pull() })
        #expect(changes.map(\.line) == [#"[[app]] terminal run_args = ["/bin/zsh", "-c", "{command}"] (was ["/bin/sh", "-c", "{command}"])"#])
    }

    @Test func removingCommandsNeedsNoApproval() throws {
        let f = try machine(local: withCommands, folder: one); defer { f.cleanUp() }
        #expect(try f.sync.pull() == .pulled(backup: nil))
        #expect(try f.read(f.local) == one)
    }

    @Test func anAgentCommandIsAskedAboutToo() throws {
        let agent = "[general]\nagents = [\"claude\"]\n[agent.claude]\ncommand = \"claude --dangerously-skip-permissions\"\n"
        let f = try machine(folder: agent); defer { f.cleanUp() }
        let changes = try #require(refusal { try f.sync.pull() })
        // The command is listed, and so is what it comes to: the agent is in the menu and starts without its prompts (the flag is typed in its command, and the config does not set the switch).
        #expect(changes.map(\.line) == [#"[agent.claude] command = "claude --dangerously-skip-permissions" (was "claude")"#,
                                        #"[agent.claude] offered with its permission prompts switched off (it is in the menu or the Quick Actions) = "--dangerously-skip-permissions""#])
    }

    @Test func aFirstPullOnAMachineWithoutAConfigAsksOnlyAboutWhatIsCustom() throws {
        // The usual second Mac: nothing local yet. A config that only picks built-in apps and agents pulls without a flag.
        let plain = try Fixture(); defer { plain.cleanUp() }
        try plain.write("[general]\nterminal = \"ghostty\"\neditor = \"vscode\"\nagents = [\"claude\", \"codex\"]\n", to: plain.remoteFile)
        try plain.sync.enable(folder: plain.remote.path)
        #expect(try plain.sync.pull() == .pulled(backup: nil))
        // One with a program of its own asks, even though there is nothing to overwrite.
        let custom = try Fixture(); defer { custom.cleanUp() }
        try custom.write(withCommands, to: custom.remoteFile)
        try custom.sync.enable(folder: custom.remote.path)
        #expect(refusal { try custom.sync.pull() } != nil)
        #expect(!FileManager.default.fileExists(atPath: custom.local.path))
    }

    @Test func statusAndEnableSayWhatAPullWouldAsk() throws {
        let f = try machine(folder: withCommands); defer { f.cleanUp() }
        let report = try f.sync.status()
        #expect(report.status == .remoteAhead)
        #expect(report.pendingCommands.count == 4)
        // `enable` on a machine that has nothing yet reports the same.
        let fresh = try Fixture(); defer { fresh.cleanUp() }
        try fresh.write(withCommands, to: fresh.remoteFile)
        #expect(try fresh.sync.enable(folder: fresh.remote.path).pendingCommands.count == 4)
    }

    @Test func aConfigThatIsNotValidIsRefusedBeforeCommandsAreWeighed() throws {
        let f = try machine(folder: withCommands + "\n[agent.x]\napi_key = \"k\"\n"); defer { f.cleanUp() }
        #expect(throws: ConfigSyncError.self) { try f.sync.pull(allowCommands: true) }
        #expect(try f.read(f.local) == one)
    }
}

@Suite("ConfigSync: a file past the size limit is never read")
struct ConfigSyncOversizeTests {
    /// A valid config with an agent command in it, padded with a comment past the limit: whatever parsed it would list the
    /// command, so the command not being listed shows the file was not parsed.
    private var oversize: String {
        "[agent.mine]\nname = \"Mine\"\ncommand = \"mine --yes\"\n# " + String(repeating: "x", count: ConfigParser.maxBytes) + "\n"
    }

    @Test func aCopyPastTheLimitIsNotReadOrParsed() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.write(oversize, to: f.remoteFile)
        let report = try f.sync.enable(folder: f.remote.path)
        #expect(report.remote == .tooLarge(bytes: oversize.utf8.count))
        #expect(report.remoteHash == nil, "it was hashed, so it was read")
        #expect(report.pendingCommands.isEmpty, "it was parsed: \(report.pendingCommands.map(\.line))")
        #expect(report.status == .remoteEvicted)
        #expect(report.remoteProblems == [.tooLarge(bytes: oversize.utf8.count)])
        #expect(try f.sync.status() == report)
    }

    @Test func aCopyPastTheLimitIsNeverPulledOrReplaced() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.write(oversize, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        let size = oversize.utf8.count
        #expect(throws: ConfigSyncError.remoteTooLarge(file: f.remoteFile.path, bytes: size)) { try f.sync.pull(force: true, allowCommands: true) }
        #expect(throws: ConfigSyncError.remoteTooLarge(file: f.remoteFile.path, bytes: size)) { try f.sync.push(force: true) }
        #expect(try f.read(f.local) == one)
        #expect(try f.read(f.remoteFile) == oversize)
        #expect(f.names(in: f.paths.configDirectory) == ["config.toml", "sync.toml"], "a copy of a huge file was made")
        #expect(f.names(in: f.remote) == ["config.toml"])
        #expect(ConfigSyncError.remoteTooLarge(file: "/x/config.toml", bytes: size).description.contains("is never replaced"))
    }

    @Test func theDoctorSaysTheCopyIsTooLargeAndAsksNothingAboutIt() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.write(oversize, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        let checks = f.sync.doctorChecks()
        let remote = try #require(checks.first { $0.id == .syncRemote })
        #expect(remote.status == .fail)
        #expect(remote.detail?.english().contains("KB") == true && remote.detail?.english().contains("limit") == true)
        #expect(remote.fix?.english().contains("Move the file out of it") == true)
        #expect(!checks.contains { $0.id == .syncCommands }, "the copy was parsed for launch commands")
    }

    @Test func aCopyOfEightMegabytesIsAnsweredAtOnce() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write("[general]\nagents = []\n", to: f.local)
        // Valid config, expensive to parse: eight megabytes of [[app]] tables took ten seconds and hundreds of MB.
        var text = "[general]\nagents = []\n"
        var number = 0
        while text.utf8.count < 8 * 1024 * 1024 {
            text += "[[app]]\nid = \"a-\(number)\"\nname = \"x\"\nbundle_id = \"y\"\n"
            number += 1
        }
        try f.write(text, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        let started = ContinuousClock.now
        let report = try f.sync.status()
        let elapsed = ContinuousClock.now - started
        #expect(report.folderReachable && report.remote == .tooLarge(bytes: text.utf8.count))
        #expect(elapsed < .seconds(3), "status took \(elapsed) for a copy past the limit")
    }

    @Test func aLocalConfigPastTheLimitIsNotReadEither() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(oversize, to: f.local)
        try f.write(one, to: f.remoteFile)
        let report = try f.sync.enable(folder: f.remote.path)
        #expect(report.localHash == nil)
        #expect(report.localProblems == [.tooLarge(bytes: oversize.utf8.count)])
        #expect(report.status != .remoteAhead, "a file that is there reads as one that is not, and a pull writes over it")
        #expect(throws: ConfigSyncError.invalid([.tooLarge(bytes: oversize.utf8.count)], file: f.local.path)) { try f.sync.push(force: true) }
        let why = "is \(oversize.utf8.count / 1024) KB, over the \(ConfigParser.maxBytes / 1024) KB limit for a config"
        #expect(throws: ConfigSyncError.localNotRead(file: f.local.path, why: why)) { try f.sync.pull(force: true, allowCommands: true) }
        #expect(try f.read(f.local) == oversize)
        #expect(f.names(in: f.paths.configDirectory) == ["config.toml", "sync.toml"], "a copy of a huge file was made")
        #expect(try f.read(f.remoteFile) == one)
    }

    @Test func aLocalConfigThatCannotBeReadIsNotAMissingOne() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.write(two, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: f.local.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: f.local.path) }
        try #require(!FileManager.default.isReadableFile(atPath: f.local.path), "running as a user that ignores permissions")
        let report = try f.sync.status()
        #expect(report.status != .remoteAhead, "an unreadable file read as a missing one, which a plain pull writes over with no backup")
        #expect(report.localProblems == [.unreadable(reason: "Permission denied")])
        #expect(throws: ConfigSyncError.self) { try f.sync.pull() }
        #expect(throws: ConfigSyncError.self) { try f.sync.pull(force: true) }
        #expect(throws: ConfigSyncError.self) { try f.sync.push(force: true) }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: f.local.path)
        #expect(try f.read(f.local) == one, "the file this Mac could not read was written over")
        #expect(f.names(in: f.paths.configDirectory) == ["config.toml", "sync.toml"])
    }
}

@Suite("ConfigSync: the folder, as it is typed and as it is made")
struct ConfigSyncFolderTests {
    @Test("an empty folder is refused, whatever it is made of", arguments: ["", " ", "\t", "  \n"])
    func aBlankFolderIsRefused(text: String) throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        // `--folder "$UNSET_VARIABLE"` is the empty string, which was taken for the current folder.
        #expect(throws: ConfigSyncError.self) { try f.sync.enable(folder: text) }
        #expect(f.sync.settings() == nil)
        #expect(f.names(in: f.paths.configDirectory) == ["config.toml"])
        do { try f.sync.enable(folder: text); Issue.record("enabled") } catch let error as ConfigSyncError {
            #expect(error.description.contains("The folder is empty (is a shell variable unset?)"), "\(error.description)")
        }
    }

    @Test func aFolderUnderTheHomeFolderIsOfferedAMakeParent() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        let home = f.paths.home
        let target = home.appendingPathComponent("Sync/rh")
        try f.sync.enable(folder: "~/Sync/rh")
        let parent = home.appendingPathComponent("Sync").path
        do { try f.sync.push(); Issue.record("pushed") } catch let error as ConfigSyncError {
            #expect(error == .folderUnreachable(target.path, makeParent: parent), "\(error)")
            let text = error.description
            #expect(text.contains("creates the last folder of the path only"), "\(text)")
            #expect(text.contains("`mkdir -p \(ShellQuoting.quote(parent, for: .posix))`"), "\(text)")
        }
        #expect(!FileManager.default.fileExists(atPath: parent), "push made the parent")
        // Once the parent is there, the push makes the last folder.
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: parent), withIntermediateDirectories: true)
        #expect(try f.sync.push() == .pushed(backup: nil, createdFolder: true))
        #expect(try f.read(target.appendingPathComponent("config.toml")) == one)
    }

    @Test func theReportSaysThePushCannotMakeTheFolderBeforeAnyoneTriesIt() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        let parent = f.paths.home.appendingPathComponent("Sync").path
        #expect(try f.sync.enable(folder: "~/Sync/rh").missingParent == .init(makeParent: parent))
        #expect(try f.sync.status().missingParent == .init(makeParent: parent))
        // Outside the home folder there is no `mkdir` to suggest; a folder that is there, or whose parent is, has no problem.
        #expect(try f.sync.enable(folder: f.root.appendingPathComponent("no/such/rh").path).missingParent == .init(makeParent: nil))
        #expect(try f.sync.enable(folder: f.root.appendingPathComponent("new-folder").path).missingParent == nil, "its parent is there: push makes it")
        #expect(try f.sync.enable(folder: f.remote.path).missingParent == nil)
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: parent), withIntermediateDirectories: true)
        #expect(try f.sync.enable(folder: "~/Sync/rh").missingParent == nil)
    }

    @Test func noMakeParentIsOfferedOutsideTheHomeFolderOrInICloudDrivesOwnTree() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        let outside = f.root.appendingPathComponent("elsewhere/rh")
        try f.sync.enable(folder: outside.path)
        do { try f.sync.push(); Issue.record("pushed") } catch let error as ConfigSyncError {
            #expect(error == .folderUnreachable(outside.path, makeParent: nil))
            #expect(!error.description.contains("mkdir") && error.description.contains("Is iCloud Drive on, or the drive mounted?"), "\(error.description)")
        }
        // iCloud Drive's folder is switched on in System Settings, not made by hand.
        try f.sync.enable(folder: nil)
        do { try f.sync.push(); Issue.record("pushed") } catch let error as ConfigSyncError {
            #expect(error == .folderUnreachable(f.sync.defaultFolder.path, makeParent: nil), "\(error)")
        }
    }

    @Test("a folder prints as it was typed", arguments: [
        ("/private/tmp/rh-sync/x", "/private/tmp/rh-sync/x"), ("/private/var/folders/a/../b", "/private/var/folders/b"), ("/tmp/rh-sync//x/./y/", "/tmp/rh-sync/x/y"),
        ("/a/b/../../c", "/c"), ("/..", "/"),
    ])
    func noPrivatePrefixIsRewritten(typed: String, printed: String) throws {
        let f = try Fixture(); defer { f.cleanUp() }
        #expect(f.sync.resolve(folder: typed).path == printed)
        let home = f.paths.home.path
        #expect(f.sync.resolve(folder: "~").path == home)
        #expect(f.sync.resolve(folder: "~/a/../b/").path == home + "/b")
        let relative = f.sync.resolve(folder: "some/where/../else").path
        #expect(relative == FileManager.default.currentDirectoryPath + "/some/else", "\(relative)")
    }

    @Test func aFolderThatExistsKeepsItsPrivatePrefixInTheReport() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        // `resolvingSymlinksInPath` takes `/private` off again, so the real path is asked of the system.
        let real = try #require(realpath(f.remote.path, nil).map { String(cString: $0) })
        try #require(real.hasPrefix("/private/"), "the temporary folder is not under /private here: \(real)")
        try f.write(one, to: f.local)
        let report = try f.sync.enable(folder: real)
        #expect(report.folder.path == real, "typed \(real), reported \(report.folder.path)")
        #expect(f.sync.settings()?.folder == real)
        #expect(try f.sync.status().folder.path == real)
    }
}

@Suite("ConfigSync: what status reports about a config that would be refused")
struct ConfigSyncProblemTests {
    private func withCommand(_ general: String = "") -> String {
        "[general]\n" + general + "agents = [\"mine\"]\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine --yes\"\n"
    }

    @Test func aLocalConfigWithASyntaxErrorRunsWithTheDefaults() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write("[general\n" + withCommand(), to: f.local)
        try f.write(withCommand(), to: f.remoteFile)
        let report = try f.sync.enable(folder: f.remote.path)
        #expect(report.localRunsWithDefaults)
        // The gate is unchanged: against the defaults the folder's agent command is new, and a pull asks.
        #expect(report.pendingCommands.map(\.line) == ["[agent.mine] command = \"mine --yes\""], "\(report.pendingCommands)")
        #expect(throws: ConfigSyncError.self) { try f.sync.pull(force: true) }
        // A config that reads, with a semantic error, runs as it says; and one that does not exist or is fine is not "defaults".
        try f.write(withCommand("terminal = \"nope\"\n"), to: f.local)
        let semantic = try f.sync.status()
        #expect(!semantic.localRunsWithDefaults && semantic.pendingCommands.isEmpty)
        try FileManager.default.removeItem(at: f.local)
        #expect(!(try f.sync.status().localRunsWithDefaults))
    }
}

@Suite("ConfigSync: a pull is made under the lock of the config")
struct ConfigSyncLockTests {
    /// A Mac whose config is behind the copy in the folder: a pull takes it.
    private func behind() throws -> Fixture {
        let f = try Fixture()
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(two, to: f.remoteFile)
        return f
    }

    @Test func aPullDoesNotReplaceTheConfigWhileAnEditHoldsItsLock() throws {
        let f = try behind(); defer { f.cleanUp() }
        let edit = try FileLock.acquireNow(f.paths.configLockFile, timeout: .zero)
        #expect(edit.isHeld)
        let sync = ConfigSync(paths: f.paths, lockTimeout: .milliseconds(50))
        #expect(throws: ConfigSyncError.configBusy(file: f.paths.configLockFile.path)) { try sync.pull() }
        #expect(try f.read(f.local) == one, "the config was replaced under the edit")
        #expect(f.sync.settings()?.lastSynced == (try f.sync.status().localHash), "nothing was recorded either")
        edit.release()
        #expect(try sync.pull() == .pulled(backup: nil))
        #expect(try f.read(f.local) == two)
    }

    @Test func aPullWaitsForAnEditThatEndsAndThenLooksAtTheFileAsTheEditLeftIt() throws {
        let f = try behind(); defer { f.cleanUp() }
        let edit = try FileLock.acquireNow(f.paths.configLockFile, timeout: .zero)
        // The edit changes the config before it lets go, as an edit of the window or of an assistant does.
        try f.write(three, to: f.local)
        // A thread of its own: the queues of the system are shared with the other tests, which run at the same time and may keep them busy for longer than a pull waits.
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 0.15)
            edit.release()
        }
        let started = ContinuousClock.now
        #expect(throws: ConfigSyncError.refused(.localChanged, folder: f.remote.path)) { try f.sync.pull() }
        #expect(ContinuousClock.now - started >= .milliseconds(100), "it did not wait for the lock")
        #expect(try f.read(f.local) == three, "the edit was written over")
    }

    @Test func aLockThatCannotBeTakenStopsThePull() throws {
        let f = try behind(); defer { f.cleanUp() }
        let elsewhere = f.root.appendingPathComponent("not-a-lock")
        try f.write("", to: elsewhere)
        try FileManager.default.createSymbolicLink(at: f.paths.configLockFile, withDestinationURL: elsewhere)
        #expect(throws: ConfigSyncError.lockUnavailable(file: f.paths.configLockFile.path)) { try f.sync.pull() }
        #expect(try f.read(f.local) == one)
    }

    /// What a test of the lock sees from inside the write, in a hook that runs on the thread of the pull.
    private final class Seen: @unchecked Sendable { var lockWasTaken: Bool? }

    @Test func aPullHoldsTheLockUntilTheConfigIsReplaced() throws {
        let f = try behind(); defer { f.cleanUp() }
        let seen = Seen()
        let lock = f.paths.configLockFile
        let sync = ConfigSync(paths: f.paths, beforeRename: { _ in
            do { try FileLock.acquireNow(lock, timeout: .zero).release(); seen.lockWasTaken = true } catch { seen.lockWasTaken = false }
        })
        #expect(try sync.pull() == .pulled(backup: nil))
        #expect(seen.lockWasTaken == false, "another process could take the lock in the middle of the write")
        #expect(try FileLock.acquireNow(lock, timeout: .zero).isHeld, "the lock was kept after the pull")
    }

    @Test func aMacWithoutAConfigHasNothingToLockAndMakesNoLock() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        #expect(try f.sync.pull() == .pulled(backup: nil))
        #expect(try f.read(f.local) == one)
        #expect(!FileManager.default.fileExists(atPath: f.paths.configLockFile.path), "a lock was made for a config that was not there")
    }

    @Test func theLockIsLetGoOfWhenThePullEndsInEitherWay() throws {
        let f = try behind(); defer { f.cleanUp() }
        try f.write(three, to: f.local)
        #expect(throws: ConfigSyncError.self) { try f.sync.pull() }
        let after = try FileLock.acquireNow(f.paths.configLockFile, timeout: .zero)
        #expect(after.isHeld, "a refused pull kept the lock")
        after.release()
        let outcome = try f.sync.pull(force: true)
        if case .pulled = outcome {} else { Issue.record("not pulled: \(outcome)") }
        let again = try FileLock.acquireNow(f.paths.configLockFile, timeout: .zero)
        #expect(again.isHeld, "a pull that was made kept the lock")
        again.release()
    }
}

@Suite("ConfigSync: a process that a test started cannot change the real home")
struct ConfigSyncRealHomeTests {
    /// A home that the test names as the real one, a config in it, and a folder elsewhere to sync with.
    private struct Machine {
        let root: URL
        let home: URL
        let paths: RHPaths
        let elsewhere: URL
        var local: URL { paths.configFile }
        var tester: [String: String] { ["RH_NO_UI": "1"] }

        init() throws {
            root = try makeTemporaryDirectory()
            home = root.appendingPathComponent("home")
            elsewhere = root.appendingPathComponent("elsewhere")
            paths = RHPaths(environment: [:], home: home)
            try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
        func sync(_ environment: [String: String]) -> ConfigSync { ConfigSync(paths: paths, environment: environment, realHome: home) }
        /// The same sync as a person runs it, for what the test sets up.
        var person: ConfigSync { sync([:]) }
        func write(_ text: String, to file: URL) throws { try text.write(to: file, atomically: true, encoding: .utf8) }
        func read(_ file: URL) throws -> String { try String(contentsOf: file, encoding: .utf8) }
        var syncStateExists: Bool { FileManager.default.fileExists(atPath: paths.syncStateFile.path) }

        func refused(_ body: () throws -> Void) -> String? {
            do { try body() } catch ConfigSyncError.writeFailed(let reason) { return reason } catch { Issue.record("a different error: \(error)") }
            return nil
        }
    }

    @Test func enableAndDisableChangeNothingInTheRealHome() throws {
        let m = try Machine(); defer { m.cleanUp() }
        let reason = try #require(m.refused { try m.sync(m.tester).enable(folder: m.elsewhere.path) })
        #expect(reason.contains("RH_NO_UI") && reason.contains("RH_HOME"), Comment(rawValue: reason))
        #expect(!m.syncStateExists)
        try m.person.enable(folder: m.elsewhere.path)
        #expect(m.refused { try m.sync(m.tester).disable() } != nil)
        #expect(m.syncStateExists, "the settings were removed from the real home")
    }

    @Test func aPullChangesNothingInTheRealHome() throws {
        let m = try Machine(); defer { m.cleanUp() }
        try m.write(one, to: m.local)
        try m.person.enable(folder: m.elsewhere.path)
        try m.person.push()
        try m.write(two, to: m.elsewhere.appendingPathComponent("config.toml"))
        let settings = try m.read(m.paths.syncStateFile)
        #expect(m.refused { try m.sync(m.tester).pull() } != nil)
        #expect(try m.read(m.local) == one && (try m.read(m.paths.syncStateFile)) == settings)
        #expect(!FileManager.default.fileExists(atPath: m.paths.configLockFile.path), "the lock was made in the real home")
    }

    @Test func aPullOfAMacWithoutAConfigChangesNothingEither() throws {
        let m = try Machine(); defer { m.cleanUp() }
        try m.write(one, to: m.elsewhere.appendingPathComponent("config.toml"))
        try m.person.enable(folder: m.elsewhere.path)
        #expect(m.refused { try m.sync(m.tester).pull() } != nil)
        #expect(!FileManager.default.fileExists(atPath: m.local.path))
    }

    @Test func aConfigThatIsALinkOutOfTheHomeDoesNotLetAPullChangeTheRealHome() throws {
        let m = try Machine(); defer { m.cleanUp() }
        let kept = m.elsewhere.appendingPathComponent("dotfiles-config.toml")
        try m.write(one, to: kept)
        try FileManager.default.createSymbolicLink(at: m.local, withDestinationURL: kept)
        let remote = m.root.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try m.person.enable(folder: remote.path)
        try m.person.push()
        try m.write(two, to: remote.appendingPathComponent("config.toml"))
        #expect(m.refused { try m.sync(m.tester).pull() } != nil)
        #expect(try m.read(kept) == one, "the file the link leads to was replaced")
    }

    @Test func aPushChangesNothingInTheRealHomeAndSendsNoCopyBeforeTheRecordOfItCanBeKept() throws {
        let m = try Machine(); defer { m.cleanUp() }
        try m.write(one, to: m.local)
        let theirs = m.root.appendingPathComponent("theirs")
        try m.person.enable(folder: theirs.path)
        #expect(m.refused { try m.sync(m.tester).push() } != nil)
        #expect(!FileManager.default.fileExists(atPath: theirs.path), "the folder was made before the record could be kept")
    }

    /// The folder to sync with is in the home that the test names as the real one, and the config is not.
    @Test func aPushDoesNotMakeAFolderOrWriteACopyInTheRealHome() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        let guarded = ConfigSync(paths: f.paths, environment: ["RH_NO_UI": "1"], realHome: f.remote)
        let made = f.remote.appendingPathComponent("new", isDirectory: true)
        try f.sync.enable(folder: made.path)
        #expect(throws: ConfigSyncError.self) { try guarded.push() }
        #expect(!FileManager.default.fileExists(atPath: made.path), "the folder was made in the real home")
        try f.sync.enable(folder: f.remote.path)
        #expect(throws: ConfigSyncError.self) { try guarded.push() }
        #expect(!FileManager.default.fileExists(atPath: f.remoteFile.path), "the copy was written in the real home")
    }

    /// The config is a link into the home that the test names as the real one: replacing the file it leads to changes that home.
    @Test func aPullDoesNotReplaceTheFileAConfigLinkLeadsToInTheRealHome() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        let home = f.root.appendingPathComponent("home")
        let kept = home.appendingPathComponent("dotfiles/config.toml")
        try FileManager.default.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
        try f.write(one, to: kept)
        try FileManager.default.createSymbolicLink(at: f.local, withDestinationURL: kept)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(two, to: f.remoteFile)
        let guarded = ConfigSync(paths: f.paths, environment: ["RH_NO_UI": "1"], realHome: home)
        #expect(throws: ConfigSyncError.self) { try guarded.pull() }
        #expect(try f.read(kept) == one, "the file in the real home was replaced")
    }

    @Test func aTrialHomeAHomeThatIsNotTheRealOneAndAPersonAreNotStopped() throws {
        let m = try Machine(); defer { m.cleanUp() }
        try m.write(one, to: m.local)
        // A test that means to write has a trial home.
        let trial = m.tester.merging(["RH_HOME": m.home.path]) { $1 }
        try m.sync(trial).enable(folder: m.elsewhere.path)
        try m.sync(trial).push()
        try m.write(two, to: m.elsewhere.appendingPathComponent("config.toml"))
        #expect(try m.sync(trial).pull() == .pulled(backup: nil))
        #expect(try m.read(m.local) == two)
        // A person has no RH_NO_UI.
        #expect(try m.sync([:]).disable())
        // A config folder that is not in the real home is the test's own.
        let other = try Fixture(); defer { other.cleanUp() }
        try other.write(one, to: other.local)
        let guarded = ConfigSync(paths: other.paths, environment: m.tester, realHome: m.home)
        try guarded.enable(folder: other.remote.path)
        try guarded.push()
        #expect(try other.read(other.remoteFile) == one)
    }
}
