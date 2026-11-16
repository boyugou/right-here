import Testing
import RightHereCore
@testable import RightHereKit

@Suite("Setup results distinguish installation from readiness")
struct SetupStepSummaryTests {
    @Test(arguments: [SetupStep.Outcome.created, .updated, .unchanged])
    func registeringAnExtensionDoesNotSayItIsReady(outcome: SetupStep.Outcome) {
        let check = DoctorCheck(.finderExtension, status: .needsUser, detail: .doctorExtensionDisabled)
        let summary = SetupStepSummary(SetupStep(.finderExtension, outcome), extensionCheck: check)
        #expect(summary.state == .needsUser)
        #expect(summary.remark == .doctorExtensionDisabled)
    }

    @Test func turningTheExtensionOnCompletesTheSameInstallation() {
        let step = SetupStep(.finderExtension, .created)
        let off = DoctorCheck(.finderExtension, status: .needsUser)
        let on = DoctorCheck(.finderExtension, status: .ok)
        #expect(SetupStepSummary(step, extensionCheck: off).state == .needsUser)
        #expect(SetupStepSummary(step, extensionCheck: on).state == .complete)
        #expect(SetupStepSummary(step, extensionCheck: on).remark == nil)
    }

    @Test func aMissingOrUnansweredExtensionIsNotReportedAsSwitchedOff() {
        let step = SetupStep(.finderExtension, .created)
        let missing = SetupStepSummary(step, extensionCheck: DoctorCheck(.finderExtension, status: .fail))
        #expect(missing.state == .failed)
        #expect(missing.remark == .appStatusProblem)
        let unknown = SetupStepSummary(step, extensionCheck: DoctorCheck(.finderExtension, status: .warn))
        #expect(unknown.state == .warning)
        #expect(unknown.remark == .appStatusWarning)
    }

    @Test func noExtensionCheckCannotProduceACompletedMark() {
        let step = SetupStep(.finderExtension, .created)
        #expect(SetupStepSummary(step, extensionCheck: nil).state == .checking)
        #expect(SetupStepSummary(step, extensionCheck: DoctorCheck(.config, status: .ok)).state == .checking)
    }

    @Test func aFailedOrSkippedStepKeepsItsOutcomeEvenWhenTheExtensionIsOn() {
        let check = DoctorCheck(.finderExtension, status: .ok)
        #expect(SetupStepSummary(SetupStep(.finderExtension, .failed), extensionCheck: check).state == .failed)
        #expect(SetupStepSummary(SetupStep(.finderExtension, .skipped), extensionCheck: check).state == .skipped)
    }

    @Test func otherPiecesKeepTheirInstallationOutcomeAndDetails() {
        let check = DoctorCheck(.finderExtension, status: .needsUser)
        let services = SetupStepSummary(SetupStep(.services, .created, detail: .doctorServicesOk("7")), extensionCheck: check)
        #expect(services.state == .complete)
        #expect(services.remark == .doctorServicesOk("7"))
        let updated = SetupStepSummary(SetupStep(.runnerScript, .updated), extensionCheck: check)
        #expect(updated.state == .complete)
        #expect(updated.remark == .appSetupUpdated)
    }
}
