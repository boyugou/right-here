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
    @Test func theLoginShellsPathIsAskedForInTheSameStart() async {
        let facts = await Detector(facts: facts, runner: EmptyHomeRunner()).probe(commands: ["ls", "definitely-not-a-command-xyz"], wantPath: true)
        #expect(facts.found == ["ls"])
        let path = facts.path ?? []
        #expect(path.contains("/usr/bin") && path.contains("/bin"), "\(path)")
        #expect(!path.contains(""), "an empty entry is not a folder")
    }

    @Test func thePathCanBeAskedForAlone() async {
        let facts = await Detector(facts: facts, runner: EmptyHomeRunner()).probe(commands: [], wantPath: true)
        #expect(facts.found.isEmpty)
        #expect(facts.path?.contains("/usr/bin") == true)
    }

    @Test func noPathIsReturnedWhenNoneWasAskedFor() async {
        let result = await Detector(facts: facts, runner: EmptyHomeRunner()).probe(commands: ["ls"])
        #expect(result == LoginShellFacts(found: ["ls"], path: nil, answered: true))
    }

    @Test func aCommandCalledLikeTheMarkerCannotPassForThePath() async {
        let forged = "\u{01}rh-path\u{01}/evil"
        let result = await Detector(facts: facts, runner: EmptyHomeRunner()).probe(commands: [forged, "ls"], wantPath: false)
        #expect(result.path == nil)
        #expect(result.found == ["ls"])
    }

    @Test func aStartupFileThatPrintsAnUnfinishedLineDoesNotHideTheAnswer() async throws {
        // `printf Welcome` ends no line: without a line feed of their own the names and the last line would be glued to it, and a shell that did answer would read as silent.
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rh-welcome-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try "printf Welcome\n".write(to: home.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        struct Welcome: ProcessRunner {
            let home: URL
            func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
                var step = step
                step.environment.merge(["HOME": home.path, "ZDOTDIR": home.path, "ENV": "", "BASH_ENV": ""]) { $1 }
                return try await LiveProcessRunner().run(step, timeout: timeout)
            }
        }
        let detector = Detector(facts: FakeSystemFacts(loginShell: "/bin/zsh"), runner: Welcome(home: home))
        let shell = await detector.probe(commands: ["ls", "definitely-not-a-command-xyz"], wantPath: true)
        #expect(shell.found == ["ls"], "the word the startup file printed is not a command that was asked about: \(shell.found)")
        #expect(shell.answered, "a shell that printed a word before the script was taken for a silent one")
        #expect(shell.path?.contains("/usr/bin") == true)
        // With nothing found, the path line and the last line come right after the startup file's word.
        let none = await detector.probe(commands: ["definitely-not-a-command-xyz"], wantPath: true)
        #expect(none.found.isEmpty)
        #expect(none.answered, "the last line was glued to the word the startup file printed")
        #expect(none.path?.contains("/usr/bin") == true, "the path line was glued to the word the startup file printed")
        #expect(await detector.probe(commands: ["definitely-not-a-command-xyz"]).answered)
    }

    @Test func aShellThatDidNotGetToTheEndOfTheScriptHasNotAnswered() {
        // A startup file that exits, or a shell that was stopped for being slow, prints nothing of the script: "no agent" is then not what it said.
        #expect(!Detector.parse("").answered)
        #expect(!Detector.parse("claude\n").answered, "what it printed before it was stopped is not an answer")
        let whole = Detector.parse("claude\n\u{01}rh-done\u{01}\n")
        #expect(whole.answered && whole.found == ["claude"], "the marker is not a command")
    }

    @Test func startupNoiseBeforeThePathLineIsNotAFolder() {
        let parsed = Detector.parse("last login: today\nclaude\n\u{01}rh-path\u{01}/a:/b::/c\n")
        #expect(parsed.path == ["/a", "/b", "/c"])
        #expect(parsed.found.contains("claude"))
    }

    @Test func aShellThatPrintsNoPathLineLeavesThePathUnknown() {
        #expect(Detector.parse("claude\n").path == nil)
        #expect(Detector.parse("").path == nil)
    }
}
