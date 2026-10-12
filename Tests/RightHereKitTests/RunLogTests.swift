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
        #expect(text.contains("\\u{1b}"))
    }

    @Test func probeLinesStillParseAfterEscaping() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        let json = #"{"application":"Ghostty","outcome":"ran","shell":"\/bin\/zsh","seconds":1.2}"#
        RunLog.record("probe launch: " + json, paths: target)
        let found = ExtensionProbe.latestReport(.launch, in: target.logFile, since: Date().addingTimeInterval(-5))
        #expect(found == Data(json.utf8))
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
