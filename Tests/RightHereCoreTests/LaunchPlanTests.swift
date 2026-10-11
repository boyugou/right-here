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
