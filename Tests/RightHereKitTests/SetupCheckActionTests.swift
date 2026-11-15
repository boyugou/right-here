import Testing
import RightHereCore
@testable import RightHereKit

@Suite("Setup window: actionable checks")
struct SetupCheckActionTests {
    @Test func diagnosticsArePartitionedWithoutLosingOrDuplicatingARow() {
        let checks = [
            DoctorCheck(.config, status: .ok),
            DoctorCheck(.cliLink, status: .warn, detail: .doctorCliNotOnPath("~/.local/bin/rh")),
            DoctorCheck(.finderExtension, status: .needsUser, fix: .doctorFixExtensionEnable),
            DoctorCheck(.finderRunner, status: .fail, fix: .doctorFixRunSetup),
            DoctorCheck(.services, status: .ok),
            DoctorCheck(.agents, status: .warn, detail: .doctorAgentsNone)
        ]
        let summary = SetupSummary(checks: checks)
        #expect(summary.attentionChecks.map(\.id) == [.finderExtension, .finderRunner])
        #expect(summary.optionalChecks.map(\.id) == [.cliLink, .agents])
        #expect(summary.passedChecks.map(\.id) == [.config, .services])
        let shown = summary.attentionChecks + summary.optionalChecks + summary.passedChecks
        #expect(shown.count == checks.count && Set(shown.map(\.id)) == Set(checks.map(\.id)))
    }

    @Test func aFirstRunGoesToTheChooserInsteadOfStartingRepair() {
        let missing = DoctorCheck(.finderRunner, status: .fail, fix: .doctorFixRunSetup)
        #expect(missing.setupAction(firstRun: true) == .setup)
        #expect(missing.setupAction(firstRun: false) == .repair)
        let config = DoctorCheck(.config, status: .fail, fix: .doctorFixConfigErrors)
        #expect(config.setupAction(firstRun: true) == .setup)
        #expect(config.setupAction(firstRun: false) == .openConfig)
    }

    @Test func theFixDeterminesTheActionNotJustTheCheckID() {
        let disabled = DoctorCheck(.finderExtension, status: .needsUser, fix: .doctorFixExtensionEnable)
        let missing = DoctorCheck(.finderExtension, status: .fail, fix: .doctorFixExtensionInstall)
        let duplicate = DoctorCheck(.finderExtension, status: .warn, fix: .doctorFixExtensionClean)
        #expect(disabled.setupAction(firstRun: false) == .extensionSettings)
        #expect(missing.setupAction(firstRun: false) == .repair)
        #expect(duplicate.setupAction(firstRun: false) == .repair)
    }

    @Test func aSuccessfulCheckOrAFixWithoutAnAppActionOffersNoButton() {
        #expect(DoctorCheck(.config, status: .ok, fix: .doctorFixConfigErrors).setupAction(firstRun: false) == nil)
        #expect(DoctorCheck(.cliLink, status: .warn, fix: .doctorFixCliPath("~/.local/bin")).setupAction(firstRun: false) == nil)
        #expect(DoctorCheck(.syncState, status: .warn, fix: .doctorFixSyncCompare).setupAction(firstRun: false) == nil)
        #expect(DoctorCheck(.finderLaunch, status: .fail, fix: .doctorVerbatim("A future fix")).setupAction(firstRun: false) == nil)
    }

    @Test func anOptionalWarningThatBecomesAFailureMovesIntoAttention() {
        let warning = DoctorCheck(.cliLink, status: .warn, detail: .doctorCliNotOnPath("~/.local/bin/rh"))
        var failure = warning
        failure.status = .fail
        #expect(SetupSummary(checks: [warning]).optionalChecks == [warning])
        #expect(SetupSummary(checks: [failure]).attentionChecks == [failure])
        #expect(SetupSummary(checks: [failure]).optionalChecks.isEmpty)
    }

    @Test func theLaunchResultKeepsItsLocalizedMessageAndStatusInTheVisibleNotice() {
        let success = DoctorCheck(.finderLaunch, status: .ok, detail: .doctorVerbatim("The test completed."))
        let failure = DoctorCheck(.finderLaunch, status: .fail, detail: .doctorVerbatim("The terminal did not answer."))
        #expect(SetupNotice.launchFinished(success).message == success.detail)
        #expect(!SetupNotice.launchFinished(success).isProblem)
        #expect(SetupNotice.launchFinished(failure).message == failure.detail)
        #expect(SetupNotice.launchFinished(failure).isProblem)
    }
}
