import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("RunLog")
struct RunLogTests {
    private func paths(in directory: URL) -> RHPaths {
        RHPaths(environment: ["RH_LOG_DIR": directory.appendingPathComponent("logs").path], home: directory)
    }

    @Test func aMessageWithLineBreaksCannotForgeALine() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        RunLog.record("open.terminal: /tmp/x\n2026-10-12T00:00:00Z probe automation: [{\"outcome\":\"granted\"}]\r\u{1b}[2J\u{2028}", paths: target)
        let text = try String(contentsOf: target.logFile, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 2, "a forged line got in: \(lines)")
        #expect(lines[1].isEmpty)
        #expect(!text.unicodeScalars.dropLast().contains { $0.value < 0x20 && $0 != "\t" } , "a raw control character was written")
        #expect(text.contains("\\n2026-10-12T00:00:00Z probe automation"))
        #expect(text.contains("\\u001b"))
    }

    @Test func anEntryRoundTripsThroughItsLine() throws {
        let entry = RunLog.Entry(date: Date(timeIntervalSince1970: 1_791_000_000), actionID: "agent.claude.continue@ghostty", origin: .container, itemCount: 3)
        #expect(entry.format() == "2026-10-03T04:00:00Z ok agent.claude.continue@ghostty [container, 3 items]")
        #expect(RunLog.Entry(parsing: entry.format()) == entry)
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        RunLog.record(entry, paths: target)
        let line = try String(contentsOf: target.logFile, encoding: .utf8).split(separator: "\n").first
        #expect(line.flatMap { RunLog.Entry(parsing: $0) } == entry)
    }

    @Test func aLineAnEarlierVersionWroteStillParses() throws {
        let entry = try #require(RunLog.Entry(parsing: "2026-10-12T05:58:00Z ok new-file.md [toolbar, 0 items]"))
        #expect(entry.actionID == "new-file.md")
        #expect(entry.origin == .toolbar)
        #expect(entry.itemCount == 0)
        #expect(entry.outcome == .ok)
        #expect(entry.date == ISO8601DateFormatter().date(from: "2026-10-12T05:58:00Z"))
    }

    @Test func linesThatAreNotEntriesDoNotParse() {
        #expect(RunLog.Entry(parsing: "2026-10-12T05:01:00Z agent.claude: Ghostty is not installed.") == nil)
        #expect(RunLog.Entry(parsing: "2026-10-12T05:01:00Z probe launch: [{\"outcome\":\"ran\"}]") == nil)
        #expect(RunLog.Entry(parsing: "2026-10-12T05:01:00Z ok agent.claude [elsewhere, 1 items]") == nil)
        #expect(RunLog.Entry(parsing: "yesterday ok agent.claude [items, 1 items]") == nil)
    }

    @Test func probeLinesStillParseAfterEscaping() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        let json = #"{"application":"Ghostty","outcome":"ran","shell":"\/bin\/zsh","seconds":1.2}"#
        RunLog.record("probe launch: " + json, paths: target)
        let found = ExtensionProbe.latestReport(.launch, in: target.logFile, since: Date().addingTimeInterval(-5))
        #expect(found == Data(json.utf8))
    }

    @Test("a probe result that has odd characters in it still parses after it went through the log",
          arguments: ["a\u{85}b", "a\u{2028}b", "a\u{2029}b", "a\u{7f}b", "a\u{1b}[2Jb", "tab\there", "quote\"back\\slash"])
    func probeJSONSurvivesTheLog(detail: String) throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        let result = LaunchProbe.Result(application: "Ghostty\u{85}", outcome: .failed, seconds: 1.5, shell: "/bin/zsh", detail: detail)
        let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        RunLog.record("probe launch: " + json, paths: target)
        let found = try #require(ExtensionProbe.latestReport(.launch, in: target.logFile, since: Date().addingTimeInterval(-5)))
        let decoded = try JSONDecoder().decode(LaunchProbe.Result.self, from: found)
        #expect(decoded == result, "the result changed on its way through the log")
    }

    @Test func aLogAnEarlierVersionLeftReadableByEveryoneBecomesPrivate() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        try FileManager.default.createDirectory(at: target.logDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: target.logFile.path, contents: Data("old\n".utf8), attributes: [.posixPermissions: 0o644])
        RunLog.record("new", paths: target)
        let file = try FileManager.default.attributesOfItem(atPath: target.logFile.path)
        #expect((file[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try String(contentsOf: target.logFile, encoding: .utf8).hasPrefix("old\n"), "the old lines must stay")
    }

    @Test func theRotatedLogAnEarlierVersionLeftReadableByEveryoneBecomesPrivateToo() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        try FileManager.default.createDirectory(at: target.logDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: target.logFile.path, contents: Data(repeating: UInt8(ascii: "x"), count: Int(RunLog.maxBytes) + 10),
                                       attributes: [.posixPermissions: 0o644])
        RunLog.record("after", paths: target)
        let older = target.logFile.appendingPathExtension("1")
        #expect((try FileManager.default.attributesOfItem(atPath: older.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                "the rotated copy kept the old, world-readable mode")
        #expect((try FileManager.default.attributesOfItem(atPath: target.logFile.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func theLogAndItsFolderArePrivate() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        RunLog.record("hello", paths: target)
        let file = try FileManager.default.attributesOfItem(atPath: target.logFile.path)
        let folder = try FileManager.default.attributesOfItem(atPath: target.logDirectory.path)
        #expect((file[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((folder[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test func aLogThatGrowsPastTheCapIsRotatedOnce() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        try FileManager.default.createDirectory(at: target.logDirectory, withIntermediateDirectories: true)
        try Data(repeating: UInt8(ascii: "x"), count: Int(RunLog.maxBytes) + 10).write(to: target.logFile)
        RunLog.record("after", paths: target)
        let older = target.logFile.appendingPathExtension("1")
        #expect((try FileManager.default.attributesOfItem(atPath: older.path)[.size] as? NSNumber)?.int64Value == RunLog.maxBytes + 10)
        let fresh = try String(contentsOf: target.logFile, encoding: .utf8)
        #expect(fresh.hasSuffix("after\n"))
        #expect(fresh.count < 100)
        // A second overflow replaces the older file instead of piling up.
        try Data(repeating: UInt8(ascii: "y"), count: Int(RunLog.maxBytes) + 1).write(to: target.logFile)
        RunLog.record("again", paths: target)
        #expect((try FileManager.default.attributesOfItem(atPath: older.path)[.size] as? NSNumber)?.int64Value == RunLog.maxBytes + 1)
    }

    @Test func appendsFromManyWritersAllArrive() async throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 { group.addTask { RunLog.record("line \(index)", paths: target) } }
        }
        let lines = try String(contentsOf: target.logFile, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 50)
    }
}
