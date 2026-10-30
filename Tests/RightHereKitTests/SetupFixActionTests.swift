import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("SetupFixAction: the button under a check's fix in the window")
struct SetupFixActionTests {
    @Test func aFixThatNamesSomethingTheWindowDoesHasItsButton() {
        #expect(SetupFixAction(fix: .doctorFixRunSetup, firstRun: false) == .repair)
        #expect(SetupFixAction(fix: .doctorFixRunSetup, firstRun: true) == nil, "on the first run the way in is Set Up, on the first page")
        #expect(SetupFixAction(fix: .doctorFixExtensionEnable, firstRun: false) == .extensionSettings)
        #expect(SetupFixAction(fix: .doctorFixTerminal, firstRun: false) == .page(.overview))
        #expect(SetupFixAction(fix: .doctorFixAgentRemove("claude"), firstRun: false) == .page(.agents))
        #expect(SetupFixAction(fix: .doctorFixPending, firstRun: false) == .page(.config))
        #expect(SetupFixAction(fix: .doctorFixCliPath("~/.local/bin"), firstRun: false) == nil, "a shell profile is the person's to edit")
        #expect(SetupFixAction(fix: .doctorFixAppCopies("/Applications/Right Here.app"), firstRun: false) == .revealOtherCopies)
    }
}
