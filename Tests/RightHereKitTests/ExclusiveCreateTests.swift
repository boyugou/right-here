import Foundation
import Synchronization
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("Creating a file only when it is not there")
struct ExclusiveCreateTests {
    private func names(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    @Test func createsTheFileWithItsContentAndLeavesNothingElseBehind() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("config.toml")
        #expect(try AtomicFile.createExclusively(Data("one".utf8), at: file) == .created)
        #expect(try String(contentsOf: file, encoding: .utf8) == "one")
        #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o644)
        #expect(names(in: folder) == ["config.toml"])
    }

    @Test func aFileThatIsThereIsLeftAloneAndNothingElseIsLeftBehind() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("config.toml")
        try "mine".write(to: file, atomically: true, encoding: .utf8)
        #expect(try AtomicFile.createExclusively(Data("theirs".utf8), at: file) == .exists)
        #expect(try String(contentsOf: file, encoding: .utf8) == "mine")
        #expect(names(in: folder) == ["config.toml"])
    }

    @Test func aLinkThatPointsNowhereIsAFileThatIsThere() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("config.toml")
        try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: "/nonexistent/dotfiles/config.toml")
        #expect(try AtomicFile.createExclusively(Data("theirs".utf8), at: file) == .exists)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: file.path) == "/nonexistent/dotfiles/config.toml")
    }

    @Test func aFileThatAppearsAtTheLastMomentIsNotReplaced() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("config.toml")
        let outcome = try AtomicFile.createExclusively(Data("late".utf8), at: file) { _ in
            try "somebody else's".write(to: file, atomically: true, encoding: .utf8)
        }
        #expect(outcome == .exists)
        #expect(try String(contentsOf: file, encoding: .utf8) == "somebody else's")
        #expect(names(in: folder) == ["config.toml"])
    }

    @Test func ofManyCallersAtOnceExactlyOneCreatesTheFileAndItsContentIsTheWinners() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        for round in 0..<60 {
            let file = folder.appendingPathComponent("round-\(round).toml")
            let winners = Mutex<[Int]>([])
            DispatchQueue.concurrentPerform(iterations: 8) { caller in
                if (try? AtomicFile.createExclusively(Data("caller \(caller)".utf8), at: file)) == .created {
                    winners.withLock { $0.append(caller) }
                }
            }
            let won = winners.withLock { $0 }
            #expect(won.count == 1, "round \(round): \(won.count) callers created the file")
            if let winner = won.first {
                #expect(try String(contentsOf: file, encoding: .utf8) == "caller \(winner)", "round \(round)")
            }
        }
        #expect(names(in: folder).allSatisfy { !$0.contains(".tmp-") }, "temporary files were left behind: \(names(in: folder))")
    }

    // MARK: The config

    private func paths(in folder: URL) -> RHPaths {
        RHPaths(environment: ["RH_CONFIG_DIR": folder.appendingPathComponent("config").path], home: folder)
    }

    @Test func aConfigThatAppearsWhileTheOneOfSetupIsBeingMadeIsKept() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let paths = paths(in: folder)
        let outcome = try ConfigStore.initialize(paths: paths, detected: DetectedEnvironment(terminal: "ghostty")) { _ in
            try "[general]\nterminal = \"terminal\"\n".write(to: paths.configFile, atomically: true, encoding: .utf8)
        }
        #expect(outcome == .kept)
        #expect(try String(contentsOf: paths.configFile, encoding: .utf8) == "[general]\nterminal = \"terminal\"\n")
    }

    @Test func twoSetupsThatCreateTheConfigTogetherLeaveOneOfThemAndTheOtherIsToldItWasKept() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        for round in 0..<30 {
            let paths = paths(in: folder.appendingPathComponent("round-\(round)"))
            let outcomes = Mutex<[ConfigStore.InitializeOutcome]>([])
            let first = DetectedEnvironment(terminal: "ghostty", editor: "vscode", agents: ["claude"])
            let second = DetectedEnvironment(terminal: "terminal", editor: "zed", agents: ["codex"])
            DispatchQueue.concurrentPerform(iterations: 2) { caller in
                if let outcome = try? ConfigStore.initialize(paths: paths, detected: caller == 0 ? first : second) { outcomes.withLock { $0.append(outcome) } }
            }
            let got = outcomes.withLock { $0 }
            #expect(got.filter { $0 == .created }.count == 1 && got.filter { $0 == .kept }.count == 1, "round \(round): \(got)")
            let text = try String(contentsOf: paths.configFile, encoding: .utf8)
            #expect(text == ConfigTemplate.render(first) || text == ConfigTemplate.render(second), "round \(round): the file is neither one that was made")
        }
    }
}
