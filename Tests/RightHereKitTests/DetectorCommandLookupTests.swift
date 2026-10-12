import Foundation
import Testing
@testable import RightHereCore
@testable import RightHereKit

@Suite("Detector command lookup")
struct DetectorCommandLookupTests {
    /// A plain POSIX login shell keeps the test quick and independent of anyone's startup files.
    private let facts = FakeSystemFacts(loginShell: "/bin/sh")

    @Test func findsCommandsTheShellKnowsAndNotOthers() async {
        let found = await Detector(facts: facts).commandsFound(["ls", "definitely-not-a-command-xyz", "printf"])
        #expect(found == ["ls", "printf"])
    }

    @Test func noCommandsAsksNothing() async {
        #expect(await Detector(facts: facts).commandsFound([]).isEmpty)
    }

    @Test("a command from the config is a name to look up, never shell syntax",
          arguments: ["$(touch CANARY)", "`touch CANARY`", "ls; touch CANARY", "ls && touch CANARY", "ls\ttouch CANARY", "a\nb", "'; touch CANARY; '"])
    func hostileNamesAreNotExecuted(name: String) async throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let canary = directory.appendingPathComponent("CANARY")
        // The canary is an absolute path, so it cannot be created by accident anywhere else.
        let hostile = name.replacingOccurrences(of: "CANARY", with: canary.path)
        let found = await Detector(facts: facts).commandsFound([hostile, "ls"])
        #expect(!FileManager.default.fileExists(atPath: canary.path), "the name ran as shell code: \(hostile.debugDescription)")
        #expect(found == ["ls"])
    }

    @Test func aNameThatLooksLikeAnOptionIsStillOnlyAName() async {
        let found = await Detector(facts: facts).commandsFound(["-x", "--version", "ls"])
        #expect(found == ["ls"])
    }
}
