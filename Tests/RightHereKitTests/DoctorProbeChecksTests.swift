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
        #expect(check.id == "finder.launch")
        #expect(check.detail?.contains("1.1 s") == true)
        #expect(check.detail?.contains("accepted after 0.3 s") == true)
        #expect(check.detail?.contains("/bin/zsh") == true)
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
        #expect(check.fix?.isEmpty == false)
    }

    @Test func aPermissionPromptNamesTheTerminal() {
        #expect(launch(.timedOut).fix?.contains("Ghostty") == true)
        #expect(launch(.denied).fix?.contains("Automation") == true)
    }

    @Test func noReportMeansTheExtensionNeverAnswered() {
        let check = Doctor.launchCheck(for: nil)
        #expect(check.status == .fail)
        #expect(check.detail?.contains("did not report back") == true)
        #expect(check.fix?.contains("rh install --finder") == true)
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
