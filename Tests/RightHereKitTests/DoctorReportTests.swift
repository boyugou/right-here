import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("rh doctor --report")
struct DoctorReportTests {
    private let privacy = DoctorReport.Privacy(homes: ["/Users/fakeperson", "/Volumes/Trial/home"], account: "fakeperson")

    @Test func theHomeFolderIsShownAsTildeAndTheAccountNameIsTakenOutAsWholeWordsOnly() {
        let text = "/Users/fakeperson/code, /Users/fakeperson2/x, fakeperson's folder, -fakeperson-, myfakeperson, /Volumes/Trial/home/.config, application"
        #expect(privacy.apply(text) == "~/code, /Users/fakeperson2/x, <account>'s folder, -<account>-, myfakeperson, ~/.config, application")
        // The home folder by itself, at the end of a line, and in quotes.
        #expect(privacy.apply("\"/Users/fakeperson\"\n/Users/fakeperson") == "\"~\"\n~")
    }

    @Test func aReportHoldsNoHomeFolderNoAccountNameAndNoTextOfTheConfig() {
        let check = DoctorCheck(
            .config, status: .fail,
            detail: .doctorVerbatim("error: /Users/fakeperson/.config/right-here/config.toml:3 [general.terminal]: unknown terminal \"fakeperson\""),
            fix: .doctorVerbatim("Run `rh config validate` and fix the errors.")
        )
        let runner = DoctorCheck(.finderRunner, status: .warn, detail: .doctorVerbatim("the runner script is in /Users/fakeperson/Library/Application Support/x"))
        let report = DoctorReport.markdown(
            identity: DoctorReport.Identity(rhVersion: "0.2.0", appVersion: nil, macOS: "26.0.0", architecture: "arm64"),
            configCheck: "1 error, 0 warnings", checks: [check, runner], privacy: privacy
        )
        #expect(!report.contains("fakeperson"), Comment(rawValue: report))
        #expect(!report.contains("/Volumes/Trial/home"))
        #expect(report.contains("~/.config/right-here/config.toml:3"))
        #expect(report.contains("- Right Here.app: not found"))
        #expect(report.contains("- Config check (`rh config validate --strict`): 1 error, 0 warnings"))
        #expect(report.contains("```text\n[fail] Config file"), Comment(rawValue: report))
    }

    @Test func theBlockStaysClosedWhenTheChecksHoldBackticks() {
        let check = DoctorCheck(.config, status: .warn, detail: .doctorVerbatim("a ``` fence inside the text"))
        let report = DoctorReport.markdown(
            identity: DoctorReport.Identity(rhVersion: "0.2.0", appVersion: "0.2.0", macOS: "26.0.0", architecture: "arm64"),
            configCheck: "ok", checks: [check], privacy: privacy
        )
        #expect(report.contains("````text\n") && report.hasSuffix("````\n"), Comment(rawValue: report))
    }
}
