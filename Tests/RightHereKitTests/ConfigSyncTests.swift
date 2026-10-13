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

    @Test func anEvictedStubIsNeitherMissingNorOverwritten() throws {
        let f = try Fixture(); defer { f.cleanUp() }
        try f.write(one, to: f.local)
        try f.sync.enable(folder: f.remote.path)
        try f.write("stub", to: f.remote.appendingPathComponent(".config.toml.icloud"))
        #expect(try f.sync.status().status == .remoteEvicted)
        #expect(throws: ConfigSyncError.refused(.remoteEvicted, folder: f.remote.path)) { try f.sync.push() }
        #expect(throws: ConfigSyncError.refused(.remoteEvicted, folder: f.remote.path)) { try f.sync.push(force: true) }
        #expect(throws: ConfigSyncError.refused(.remoteEvicted, folder: f.remote.path)) { try f.sync.pull(force: true) }
        #expect(!FileManager.default.fileExists(atPath: f.remoteFile.path))
        #expect(try f.read(f.local) == one)
    }

    @Test func aFileThatCannotBeReadCountsAsEvicted() throws {
        let f = try prepared(one); defer { f.cleanUp() }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: f.remoteFile.path)
        try #require(!FileManager.default.isReadableFile(atPath: f.remoteFile.path), "running as a user that ignores permissions")
        #expect(try f.sync.status().status == .remoteEvicted)
        #expect(throws: ConfigSyncError.refused(.remoteEvicted, folder: f.remote.path)) { try f.sync.push(force: true) }
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
        try f.sync.enable(folder: f.remote.path)
        try f.write("stub", to: f.remote.appendingPathComponent(".config.toml.icloud"))
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
}
