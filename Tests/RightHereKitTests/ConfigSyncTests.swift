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
    func names(in folder: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() }
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
        #expect(throws: ConfigSyncError.folderUnreachable(target.path)) { try f.sync.push() }
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
        let big = "# " + String(repeating: "x", count: SyncValidation.maxBytes + 1) + "\n"
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
        let remote = f.sync.doctorChecks().first { $0.id == "sync.remote" }
        #expect(remote?.status == .fail)
        #expect(remote?.detail?.unicodeScalars.contains { $0.properties.generalCategory == .control } == false)
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
        let conflict = f.sync.doctorChecks().first { $0.id == "sync.conflict" }
        #expect(conflict?.status == .warn)
        #expect(conflict?.detail?.contains("config 2.toml") == true)
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
        #expect(checks.map(\.id) == ["sync.folder", "sync.remote", "sync.state"])
        #expect(checks.allSatisfy { $0.status == .ok })
    }

    @Test func anUnreachableFolderIsAWarning() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.sync.enable(folder: f.root.appendingPathComponent("gone").path)
        let checks = f.sync.doctorChecks()
        #expect(checks.map(\.id) == ["sync.folder"])
        #expect(checks.first?.status == .warn)
    }

    @Test func anEvictedCopyIsAWarningWithAFix() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.write(one, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: f.remoteFile.path)
        try #require(!FileManager.default.isReadableFile(atPath: f.remoteFile.path), "running as a user that ignores permissions")
        let remote = f.sync.doctorChecks().first { $0.id == "sync.remote" }
        #expect(remote?.status == .warn)
        #expect(remote?.detail?.contains("not downloaded") == true)
    }

    @Test func aRemoteThatDoesNotValidateFails() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.write("[general\n", to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        #expect(f.sync.doctorChecks().first { $0.id == "sync.remote" }?.status == .fail)
    }

    @Test func divergenceIsAWarning() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(two, to: f.local)
        try f.write(three, to: f.remoteFile)
        let state = f.sync.doctorChecks().first { $0.id == "sync.state" }
        #expect(state?.status == .warn)
        #expect(state?.detail?.contains("both changed") == true)
    }

    @Test func aBrokenStateFileIsReported() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write("folder = 3\n", to: f.paths.syncStateFile)
        #expect(f.sync.doctorChecks().first?.id == "sync.state")
    }

    @Test func launchCommandsAreOneRowAndOnlyWhenThereAreSome() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(withCommands, to: f.local)
        try f.write(withCommands, to: f.remoteFile)
        try f.sync.enable(folder: f.remote.path)
        let row = try #require(f.sync.doctorChecks().filter { $0.id == "sync.commands" }.first)
        #expect(row.status == .ok)
        #expect(row.detail?.contains("/usr/bin/id") == true && row.detail?.contains("/bin/sh") == true)
        // Without any, no row (the healthy-folder test above has none).
        try f.write(one, to: f.local)
        try f.write(one, to: f.remoteFile)
        #expect(f.sync.doctorChecks().filter { $0.id == "sync.commands" }.isEmpty)
    }

    @Test func aFolderCopyThatWouldAddCommandsIsAWarningBeforeAnyPull() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.sync.push()
        try f.write(withCommands, to: f.remoteFile)
        let rows = f.sync.doctorChecks().filter { $0.id == "sync.commands" }
        #expect(rows.count == 1)
        #expect(rows.first?.status == .warn)
        #expect(rows.first?.fix?.contains("--allow-commands") == true)
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
        #expect(changes.map(\.line) == [#"[agent.claude] command = "claude --dangerously-skip-permissions" (was "claude")"#])
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
