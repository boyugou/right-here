import Foundation
import Testing
@testable import RightHereCore
@testable import RightHereKit

/// Runs every process with an empty home and no startup variables, so a login shell reads none of the person's files.
private struct EmptyHomeRunner: ProcessRunner {
    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rh-empty-home", isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var step = step
        step.environment.merge(["HOME": home.path, "ZDOTDIR": home.path, "ENV": "", "BASH_ENV": ""]) { $1 }
        return try await LiveProcessRunner().run(step, timeout: timeout)
    }
}

@Suite("Detector command lookup")
struct DetectorCommandLookupTests {
    /// A plain POSIX login shell keeps the test quick and independent of anyone's startup files.
    private let facts = FakeSystemFacts(loginShell: "/bin/sh")

    @Test func findsCommandsTheShellKnowsAndNotOthers() async {
        let found = await Detector(facts: facts, runner: EmptyHomeRunner()).commandsFound(["ls", "definitely-not-a-command-xyz", "printf"])
        #expect(found == ["ls", "printf"])
    }

    @Test func noCommandsAsksNothing() async {
        #expect(await Detector(facts: facts, runner: EmptyHomeRunner()).commandsFound([]).isEmpty)
    }

    @Test("a command from the config is a name to look up, never shell syntax",
          arguments: ["$(touch CANARY)", "`touch CANARY`", "ls; touch CANARY", "ls && touch CANARY", "ls\ttouch CANARY", "a\nb", "'; touch CANARY; '"])
    func hostileNamesAreNotExecuted(name: String) async throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let canary = directory.appendingPathComponent("CANARY")
        // The canary is an absolute path, so it cannot be created by accident anywhere else.
        let hostile = name.replacingOccurrences(of: "CANARY", with: canary.path)
        let found = await Detector(facts: facts, runner: EmptyHomeRunner()).commandsFound([hostile, "ls"])
        #expect(!FileManager.default.fileExists(atPath: canary.path), "the name ran as shell code: \(hostile.debugDescription)")
        #expect(found == ["ls"])
    }

    @Test func aNameThatLooksLikeAnOptionIsStillOnlyAName() async {
        let found = await Detector(facts: facts, runner: EmptyHomeRunner()).commandsFound(["-x", "--version", "ls"])
        #expect(found == ["ls"])
    }
}
