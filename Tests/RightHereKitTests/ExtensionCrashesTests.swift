import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("ExtensionCrashes: a crashing Finder extension is not a healthy one (ADR 0019)")
struct ExtensionCrashesTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-15T20:00:00Z")!

    /// A folder of crash reports, each written `hoursAgo` hours before `now`.
    private func reports(_ named: [String: Double]) throws -> URL {
        let folder = try makeTemporaryDirectory()
        for (name, hoursAgo) in named {
            let file = folder.appendingPathComponent(name)
            try "report".write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-hoursAgo * 3600)], ofItemAtPath: file.path)
        }
        return folder
    }

    @Test func countsTheExtensionsReportsAndNamesTheNewest() throws {
        let folder = try reports(["FinderExtension-2026-10-15-120000.ips": 8, "FinderExtension-2026-10-15-150000.ips": 5, "FinderExtension-2026-10-15-180000.ips": 2])
        defer { try? FileManager.default.removeItem(at: folder) }
        let found = try #require(ExtensionCrashes.scan(in: folder, installedAfter: nil, now: now))
        #expect(found.count == 3)
        #expect(found.latestFile == "FinderExtension-2026-10-15-180000.ips")
        #expect(found.latest == now.addingTimeInterval(-2 * 3600))
    }

    @Test func otherProgramsReportsAndOtherFilesAreNotTheExtensions() throws {
        let folder = try reports(["Finder-2026-10-15-120000.ips": 1, "rh-2026-10-15-120000.ips": 1, "FinderExtensionHelper-2026-10-15-120000.ips": 1,
                                  "FinderExtension-2026-10-15-120000.txt": 1, "FinderExtension-2026-10-15-120000.diag": 1])
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(ExtensionCrashes.scan(in: folder, installedAfter: nil, now: now) == nil)
    }

    @Test func aReportFromBeforeThisCopyWasInstalledIsAboutAnotherCopy() throws {
        let folder = try reports(["FinderExtension-old.ips": 30, "FinderExtension-new.ips": 3])
        defer { try? FileManager.default.removeItem(at: folder) }
        let installed = now.addingTimeInterval(-10 * 3600)
        let found = try #require(ExtensionCrashes.scan(in: folder, installedAfter: installed, now: now))
        #expect(found.count == 1)
        #expect(found.latestFile == "FinderExtension-new.ips")
        #expect(ExtensionCrashes.scan(in: folder, installedAfter: now.addingTimeInterval(-1 * 3600), now: now) == nil)
    }

    @Test func aReportOlderThanAWeekSaysNothingAboutTheExtensionAsItIsNow() throws {
        let folder = try reports(["FinderExtension-week-old.ips": 24 * 8])
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(ExtensionCrashes.scan(in: folder, installedAfter: nil, now: now) == nil)
    }

    @Test func aFolderThatCannotBeReadIsNoEvidence() {
        #expect(ExtensionCrashes.scan(in: URL(fileURLWithPath: "/nonexistent/DiagnosticReports"), installedAfter: nil, now: now) == nil)
    }

    @Test func theInstallDateIsWhenTheExtensionsCodeWasWritten() throws {
        let appex = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: appex) }
        #expect(ExtensionCrashes.installDate(ofExtensionAt: appex.path + "/nope") == nil)
        let executable = appex.appendingPathComponent("Contents/MacOS/FinderExtension")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "binary".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: executable.path)
        #expect(ExtensionCrashes.installDate(ofExtensionAt: appex.path) == now)
    }

    private let enabled = "+    \(AppIdentity.extensionBundleID)(1.0)\tU1\t2026-10-11 23:29:41 +0000\t/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex\n"

    @Test func aSwitchedOnExtensionThatCrashedIsAWarningWithTheReportToLookAt() async throws {
        let folder = try reports(["FinderExtension-2026-10-15-180000.ips": 2, "FinderExtension-2026-10-15-170000.ips": 3])
        defer { try? FileManager.default.removeItem(at: folder) }
        let check = await Doctor.extensionCheck(runner: FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: enabled)]), crashReports: folder, now: now)
        #expect(check.status == .warn)
        let detail = try #require(check.detail?.english())
        #expect(detail.contains("crashed 2 times"), "\(detail)")
        #expect(detail.contains("FinderExtension-2026-10-15-180000.ips"), "\(detail)")
        #expect(check.fix?.english().contains("DiagnosticReports") == true)
    }

    @Test func oneCrashSaysOnce() async throws {
        let folder = try reports(["FinderExtension-2026-10-15-180000.ips": 2]); defer { try? FileManager.default.removeItem(at: folder) }
        let check = await Doctor.extensionCheck(runner: FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: enabled)]), crashReports: folder, now: now)
        #expect(check.detail?.english().contains("crashed once") == true)
    }

    @Test func aHealthyExtensionStaysOkAndTheWindowsLookNeverReadsTheFolder() async throws {
        let empty = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: empty) }
        let healthy = await Doctor.extensionCheck(runner: FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: enabled)]), crashReports: empty, now: now)
        #expect(healthy.status == .ok)
        let crashed = try reports(["FinderExtension-2026-10-15-180000.ips": 2]); defer { try? FileManager.default.removeItem(at: crashed) }
        let withoutTheFolder = await Doctor.extensionCheck(runner: FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: enabled)]))
        #expect(withoutTheFolder.status == .ok, "no folder given: only pluginkit is asked")
    }

    @Test func aSwitchedOffExtensionIsStillForThePersonToSwitchOn() async throws {
        let folder = try reports(["FinderExtension-2026-10-15-180000.ips": 2]); defer { try? FileManager.default.removeItem(at: folder) }
        let off = enabled.replacingOccurrences(of: "+    ", with: "-    ")
        let check = await Doctor.extensionCheck(runner: FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: off)]), crashReports: folder, now: now)
        #expect(check.status == .needsUser)
    }
}
