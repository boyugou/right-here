import Foundation
import Testing
@testable import RightHereKit

@Suite("Doctor probe checks")
struct DoctorProbeChecksTests {
    private func launch(_ outcome: LaunchProbe.Outcome, detail: String? = nil) -> DoctorCheck {
        Doctor.launchCheck(for: LaunchProbe.Result(application: "Ghostty", outcome: outcome, seconds: 1.1, accepted: 0.3, shell: "/bin/zsh", detail: detail))
    }

    @Test func aCommandThatRanIsOkAndSaysHowLongItTook() {
        let check = launch(.ran)
        #expect(check.status == .ok)
        #expect(check.id == .finderLaunch)
        #expect(check.detail?.english().contains("1.1 s") == true)
        #expect(check.detail?.english().contains("accepted after 0.3 s") == true)
        #expect(check.detail?.english().contains("/bin/zsh") == true)
        #expect(check.fix == nil)
    }

    @Test("each failed outcome has a status and a fix", arguments: [
        (LaunchProbe.Outcome.timedOut, DoctorCheck.Status.needsUser),
        (.denied, .fail),
        (.noReply, .fail),
        (.wrongFolder, .fail),
        (.failed, .fail),
        (.notInstalled, .warn),
        (.unsupported, .warn)
    ])
    func outcomes(outcome: LaunchProbe.Outcome, status: DoctorCheck.Status) {
        let check = launch(outcome, detail: "some detail")
        #expect(check.status == status)
        #expect(check.fix?.english().isEmpty == false)
    }

    @Test func aPermissionPromptNamesTheTerminal() {
        #expect(launch(.timedOut).fix?.english().contains("Ghostty") == true)
        #expect(launch(.denied).fix?.english().contains("Automation") == true)
    }

    @Test func noReportMeansTheExtensionNeverAnswered() {
        let check = Doctor.launchCheck(for: nil)
        #expect(check.status == .fail)
        #expect(check.detail?.english().contains("did not report back") == true)
        #expect(check.fix?.english().contains("rh setup") == true)
    }

    @Test func theAutomationChainIsOkWhenEveryAppAllowedIt() {
        let granted = AutomationProbe.Result(application: "Ghostty", bundleID: "com.mitchellh.ghostty", outcome: .granted)
        let idle = AutomationProbe.Result(application: "Terminal", bundleID: "com.apple.Terminal", outcome: .notRunning)
        #expect(Doctor.chainCheck(for: [granted, idle]).status == .ok)
    }

    @Test func theAutomationChainReportsTheWorstOutcome() {
        let granted = AutomationProbe.Result(application: "Ghostty", bundleID: "a", outcome: .granted)
        let denied = AutomationProbe.Result(application: "Terminal", bundleID: "b", outcome: .denied)
        let waiting = AutomationProbe.Result(application: "Terminal", bundleID: "b", outcome: .timedOut)
        #expect(Doctor.chainCheck(for: [granted, denied]).status == .fail)
        #expect(Doctor.chainCheck(for: [granted, waiting]).status == .needsUser)
        #expect(Doctor.chainCheck(for: nil).status == .fail)
    }
}

@Suite("Doctor services check")
struct DoctorServicesCheckTests {
    private let a = "Right Here - Open in Ghostty.workflow"
    private let b = "Right Here - Codex Here.workflow"

    @Test func noServicesIsAWarningWithTheCommand() {
        let check = Doctor.servicesCheck(installed: [], expected: [a])
        #expect(check.status == .warn)
        #expect(check.fix?.english().contains("rh setup") == true)
    }

    @Test func servicesMatchingTheConfigAreOk() {
        let check = Doctor.servicesCheck(installed: [a, b], expected: [a, b])
        #expect(check.status == .ok)
        #expect(check.detail?.english() == "2 installed")
    }

    @Test func servicesThatDifferFromTheConfigAreFlagged() {
        let missing = Doctor.servicesCheck(installed: [a], expected: [a, b])
        #expect(missing.status == .warn)
        #expect(missing.detail?.english() == "1 installed, but they differ from the config (1 missing, 0 stale)")
        let extra = Doctor.servicesCheck(installed: [a, b], expected: [a])
        #expect(extra.status == .warn)
        #expect(extra.detail?.english() == "2 installed, but they differ from the config (0 missing, 1 stale)")
    }
}

@Suite("Doctor activity check")
struct DoctorActivityCheckTests {
    private func log(_ lines: [String]) throws -> (URL, URL) {
        let directory = try makeTemporaryDirectory()
        let file = directory.appendingPathComponent("rh.log")
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        return (directory, file)
    }

    private let now = ISO8601DateFormatter().date(from: "2026-10-12T06:00:00Z")!

    @Test func theNewestActionFromFinderIsReported() throws {
        let (directory, file) = try log([
            "2026-10-12T05:00:00Z ok agent.claude [cli, 0 items]",
            "2026-10-12T05:30:00Z ok copy-path.name [items, 2 items]",
            "2026-10-12T05:50:00Z ok agent.codex [container, 0 items]",
            "2026-10-12T05:55:00Z ok open.terminal [cli, 1 items]",
            "2026-10-12T05:56:00Z probe automation: []"
        ])
        defer { try? FileManager.default.removeItem(at: directory) }
        let check = Doctor.activityCheck(logFile: file, now: now)
        #expect(check.status == .ok)
        #expect(check.detail?.english().contains("agent.codex from the container menu") == true)
        #expect(check.detail?.english().contains("ago") == true, "English on a Mac of any language: the command line's sentences are English")
        let german = Doctor.activityCheck(logFile: file, now: now, language: "de")
        #expect(german.detail?.arguments.last?.hasPrefix("vor") == true, "the window writes the time in its own language: \(german.detail?.arguments ?? [])")
    }

    @Test func commandLineRunsAndProbesDoNotCount() throws {
        let (directory, file) = try log(["2026-10-12T05:00:00Z ok agent.claude [cli, 0 items]", "2026-10-12T05:01:00Z agent.claude: Ghostty is not installed."])
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(Doctor.activityCheck(logFile: file, now: now).detail?.english().hasPrefix("none yet") == true)
    }

    @Test func noLogMeansNoneYetNotAnError() {
        let check = Doctor.activityCheck(logFile: URL(fileURLWithPath: "/nonexistent/rh.log"), now: now)
        #expect(check.status == .ok)
        #expect(check.detail?.english().hasPrefix("none yet") == true)
    }

    @Test func theRotatedLogIsReadToo() throws {
        let (directory, file) = try log(["2026-10-12T05:58:00Z ok agent.claude [cli, 0 items]"])
        defer { try? FileManager.default.removeItem(at: directory) }
        try "2026-10-11T12:00:00Z ok new-file.md [toolbar, 0 items]\n".write(to: file.appendingPathExtension("1"), atomically: true, encoding: .utf8)
        #expect(Doctor.activityCheck(logFile: file, now: now).detail?.english().contains("new-file.md from the toolbar menu") == true)
    }
}
