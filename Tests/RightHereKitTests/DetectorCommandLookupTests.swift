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

/// Runs the real login shell with a home folder of its own, so the one startup file a test writes is the only one it reads.
private struct StartupWordRunner: ProcessRunner {
    let home: URL
    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        var step = step
        step.environment.merge(["HOME": home.path, "ZDOTDIR": home.path, "XDG_CONFIG_HOME": home.appendingPathComponent(".config").path, "ENV": "", "BASH_ENV": ""]) { $1 }
        return try await LiveProcessRunner().run(step, timeout: timeout)
    }
}

private let fishForTheProbe: String? = ["/opt/homebrew/bin/fish", "/usr/local/bin/fish"].first(where: FileManager.default.isExecutableFile)

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
        #expect(result == LoginShellFacts(asked: ["ls"], found: ["ls"], locations: ["ls": "/bin/ls"], path: nil, answered: true))
    }

    @Test func eachCommandFoundComesWithWhereTheShellFindsIt() async {
        // The setup window says where a terminal would find each agent; an alias or a function has no path, and its name is what it gets.
        let result = await Detector(facts: facts, runner: EmptyHomeRunner()).probe(commands: ["ls", "cd", "definitely-not-a-command-xyz"])
        #expect(result.asked == ["ls", "cd", "definitely-not-a-command-xyz"])
        #expect(result.found == ["ls", "cd"] && result.locations == ["ls": "/bin/ls", "cd": "cd"], "\(result.locations)")
        // Only a name that was asked about counts, whatever a startup file prints.
        let parsed = Detector.parse("\nclaude\u{01}/opt/claude\n\(Detector.doneMarker)\n")
        #expect(parsed.locations == ["claude": "/opt/claude"] && parsed.answered)
    }

    @Test func aCommandCalledLikeTheMarkerCannotPassForThePath() async {
        let forged = "\u{01}rh-path\u{01}/evil"
        let result = await Detector(facts: facts, runner: EmptyHomeRunner()).probe(commands: [forged, "ls"], wantPath: false)
        #expect(result.path == nil)
        #expect(result.found == ["ls"])
    }

    /// `printf Welcome` ends no line: without a line feed of their own the names and the last line would be glued to it, and a shell that did answer would read as silent.
    private func checkTheProbeAfterAnUnfinishedLine(loginShell: String, startupFile: String) async throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(startupFile)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "printf Welcome\n".write(to: file, atomically: true, encoding: .utf8)
        let detector = Detector(facts: FakeSystemFacts(loginShell: loginShell), runner: StartupWordRunner(home: home))
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

    @Test func aStartupFileThatPrintsAnUnfinishedLineDoesNotHideTheAnswer() async throws {
        try await checkTheProbeAfterAnUnfinishedLine(loginShell: "/bin/zsh", startupFile: ".zshrc")
    }

    @Test("the same under fish, whose script is another one (skipped where fish is not installed)", .enabled(if: fishForTheProbe != nil))
    func aStartupFileOfFishThatPrintsAnUnfinishedLineDoesNotHideTheAnswer() async throws {
        try await checkTheProbeAfterAnUnfinishedLine(loginShell: try #require(fishForTheProbe), startupFile: ".config/fish/config.fish")
    }

    @Test func anAgentWhoseCommandCarriesAnArgumentIsFoundByItsFirstWord() async {
        // Goose's session is `goose session`; the login shell is asked about `goose`.
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: "\nclaude\u{01}/opt/claude\n\ngoose\u{01}/opt/goose\n\n\u{01}rh-done\u{01}\n")])
        let (environment, answered) = await Detector(facts: facts, runner: runner).look()
        #expect(answered)
        #expect(environment.agents.contains("goose") && environment.agents.contains("claude"), "\(environment.agents)")
        #expect(runner.recorded.first?.arguments.contains("goose") == true && runner.recorded.first?.arguments.contains("goose session") != true)
    }

    @Test func aShellThatDidNotGetToTheEndOfTheScriptHasNotAnswered() {
        // A startup file that exits, or a shell that was stopped for being slow, prints nothing of the script: "no agent" is then not what it said.
        #expect(!Detector.parse("").answered)
        #expect(!Detector.parse("claude\n").answered, "what it printed before it was stopped is not an answer")
        let whole = Detector.parse("\nclaude\u{01}/opt/claude\n\u{01}rh-done\u{01}\n")
        #expect(whole.answered && whole.found == ["claude"], "the marker is not a command")
    }

    @Test func startupNoiseBeforeThePathLineIsNotAFolder() {
        let parsed = Detector.parse("last login: today\n\nclaude\u{01}/opt/claude\n\u{01}rh-path\u{01}/a:/b::/c\n")
        #expect(parsed.path == ["/a", "/b", "/c"])
        #expect(parsed.found == ["claude"])
    }

    @Test func anAnswerForANameThatWasNotAskedAboutIsNotOne() async {
        // A startup file can print a line in the answer's own form; only the names the shell was asked about can be answers.
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: "\ncodex\u{01}/opt/evil\n\nclaude\u{01}/opt/claude\n\u{01}rh-done\u{01}\n")])
        let shell = await Detector(facts: facts, runner: runner).probe(commands: ["claude"])
        #expect(shell.found == ["claude"] && shell.locations == ["claude": "/opt/claude"], "\(shell)")
    }

    @Test func aLineAStartupFilePrintedIsNotAnAnswerEvenWhenItIsAName() {
        // Every answer carries the separator; a `.zshrc` that prints `amp` does not install Amp.
        #expect(Detector.parse("amp\ngoose\n\u{01}rh-done\u{01}\n").found.isEmpty)
    }

    @Test func aStartupFileThatEndsWithACarriageReturnDoesNotHideTheFirstAnswer() {
        // "\r\n" is one Character in Swift: split on line feeds alone, the startup file's last line and the first answer were one line.
        let parsed = Detector.parse("Loading...\r\nclaude\u{01}/opt/claude\n\n\u{01}rh-done\u{01}\n")
        #expect(parsed.found == ["claude"] && parsed.locations == ["claude": "/opt/claude"] && parsed.answered, "\(parsed)")
    }

    @Test("fish says where it finds each command as well (skipped where fish is not installed)", .enabled(if: fishForTheProbe != nil))
    func fishSaysWhereItFindsEachCommand() async throws {
        let detector = Detector(facts: FakeSystemFacts(loginShell: try #require(fishForTheProbe)), runner: EmptyHomeRunner())
        let result = await detector.probe(commands: ["ls", "definitely-not-a-command-xyz"])
        #expect(result.answered && result.found == ["ls"] && result.locations == ["ls": "/bin/ls"], "\(result)")
    }

    @Test func aNameThatStartsWithADashIsNotHandedToTheShell() async {
        // fish has no `$0` slot: the names follow `-c <script>`, and `--init-command=…` would be read as fish's own option.
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: "\u{01}rh-done\u{01}\n")])
        let shell = await Detector(facts: FakeSystemFacts(loginShell: "/opt/homebrew/bin/fish"), runner: runner).probe(commands: ["--init-command=touch /tmp/x", "claude"])
        #expect(runner.recorded.first?.arguments.contains { $0.hasPrefix("-") && $0 != "-lic" } == false, "\(runner.recorded.first?.arguments ?? [])")
        #expect(shell.asked == ["--init-command=touch /tmp/x", "claude"] && shell.found.isEmpty)
    }

    @Test func aShellThatPrintsNoPathLineLeavesThePathUnknown() {
        #expect(Detector.parse("claude\n").path == nil)
        #expect(Detector.parse("").path == nil)
    }
}
