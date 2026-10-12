import Foundation
import Testing
@testable import RightHereCore

@Suite("LaunchPlan")
struct LaunchPlanTests {
    private let steps: [Step] = [
        .open(OpenStep(bundleID: "com.apple.Terminal", targets: ["/tmp/a b"], activate: true)),
        .openURL("claude://code/new?folder=%2Ftmp"),
        .run(ProcessStep(executable: "/usr/bin/open", arguments: ["-a", "Ghostty"], environment: ["A": "1"])),
        .appleScript(AppleScriptStep(source: "on run argv\nend run", arguments: ["/tmp"], controls: "com.mitchellh.ghostty")),
        .copyToPasteboard("hello"),
        .createFile(CreateFileStep(path: "/tmp/untitled.txt", contents: "")),
        .reveal(["/tmp/untitled.txt"]),
        .pause(milliseconds: 150)
    ]

    @Test func everyStepSurvivesAJSONRoundTrip() throws {
        let plan = LaunchPlan(action: "test", summary: "all steps", steps: steps, notices: ["note"])
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(LaunchPlan.self, from: data)
        #expect(decoded == plan)
    }

    @Test func stepsEncodeWithAFlatKindDiscriminator() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try String(decoding: encoder.encode(Step.open(OpenStep(bundleID: "x.y", targets: ["/a"]))), as: UTF8.self)
        #expect(json == #"{"activate":true,"bundleID":"x.y","kind":"open","targets":["\/a"]}"#)
        let pause = try String(decoding: encoder.encode(Step.pause(milliseconds: 5)), as: UTF8.self)
        #expect(pause == #"{"kind":"pause","milliseconds":5}"#)
    }

    @Test func unknownKindIsRejected() {
        let data = Data(#"{"kind":"explode"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Step.self, from: data) }
    }
}

@Suite("Step summaries")
struct StepSummaryTests {
    @Test func aCopyShowsWhatIsCopied() {
        #expect(Step.copyToPasteboard("@/tmp").details == ["text: \"@/tmp\""])
        #expect(Step.copyToPasteboard("a\nb").details == ["text: \"a\\nb\""])
    }

    @Test func anAppleScriptShowsItsArguments() {
        let step = Step.appleScript(AppleScriptStep(source: "x", arguments: ["/tmp", "codex", "window"], controls: "Ghostty"))
        #expect(step.details == ["arguments: \"/tmp\", \"codex\", \"window\""])
        #expect(Step.appleScript(AppleScriptStep(source: "x")).details.isEmpty)
    }

    @Test func longTextIsCutOff() throws {
        let detail = try #require(Step.copyToPasteboard(String(repeating: "a", count: 500)).details.first)
        #expect(detail.count < 260)
        #expect(detail.hasSuffix("…\""))
    }

    @Test func controlCharactersInNamesNeverReachATerminal() {
        let hostile = "/tmp/\u{1b}[2Jevil\nname"
        for step in [Step.open(OpenStep(bundleID: "x", targets: [hostile])), .reveal([hostile]), .createFile(CreateFileStep(path: hostile)),
                     .run(ProcessStep(executable: "/bin/echo", arguments: [hostile])), .openURL("x://" + hostile)] {
            let shown = step.summary
            #expect(!shown.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f }, "\(shown.debugDescription)")
            #expect(shown.contains("\\u{1b}"))
        }
        let copy = Step.copyToPasteboard(hostile)
        #expect(copy.details.allSatisfy { !$0.unicodeScalars.contains { $0.value < 0x20 } })
    }

    @Test func ordinaryNamesAreUnchanged() {
        #expect(Step.open(OpenStep(bundleID: "x", targets: ["/Users/me/my code/日本語 é"])).summary == "open x /Users/me/my code/日本語 é")
    }
}
