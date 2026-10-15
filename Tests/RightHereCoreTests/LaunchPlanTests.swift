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

    @Test func textIsNeverCutOff() throws {
        // A plan that says "see exactly what would happen" cannot end in an ellipsis where the interesting part is.
        let text = String(repeating: "a", count: 500) + "THE END"
        let detail = try #require(Step.copyToPasteboard(text).details.first)
        #expect(detail == "text: \"" + text + "\"")
        let typed = String(repeating: "x", count: 600) + " && claude --dangerously-skip-permissions"
        let line = try #require(Step.appleScript(AppleScriptStep(source: "x", arguments: [typed], controls: "Terminal")).details.first)
        #expect(line.hasSuffix("--dangerously-skip-permissions\""))
        #expect(!line.contains("…"))
    }

    @Test func oneCharacterIsNotSomeCharacters() {
        #expect(Step.copyToPasteboard("a").heading == "copy 1 character to the clipboard")
        #expect(Step.copyToPasteboard("ab").heading == "copy 2 characters to the clipboard")
        #expect(Step.copyToPasteboard("").heading == "copy 0 characters to the clipboard")
    }

    @Test func everyTargetIsOnALineOfItsOwnAndReadsBackAsExactlyThatPath() throws {
        let paths = ["/tmp/Café d'été \"x\"/naïve file.txt", "/tmp/back\\slash/report.md", "/tmp/two\nlines.txt"]
        for step in [Step.open(OpenStep(bundleID: "com.microsoft.VSCode", targets: paths)), .reveal(paths)] {
            #expect(step.details.count == paths.count, "\(step.details)")
            for (line, path) in zip(step.details, paths) {
                #expect(line.hasPrefix("target: "))
                #expect(try Self.valueRead(from: String(line.dropFirst("target: ".count))) == path, "\(line)")
            }
            // The heading names the step and has none of the paths: they are below it.
            #expect(paths.allSatisfy { !step.heading.contains($0) })
        }
        #expect(Step.open(OpenStep(bundleID: "com.microsoft.VSCode", targets: paths)).heading == "open com.microsoft.VSCode")
        #expect(Step.open(OpenStep(bundleID: nil, targets: paths)).heading == "open default app")
        #expect(Step.reveal(paths).heading == "reveal")
    }

    @Test func theOneLineFormKeepsEveryTargetAndQuotesEach() {
        // `summary` is what failure messages and the run report say: one line, so every value in it is quoted too.
        #expect(Step.open(OpenStep(bundleID: "x", targets: ["/Users/me/my code/日本語 é", "/b"])).summary == "open x \"/Users/me/my code/日本語 é\" \"/b\"")
        #expect(Step.reveal(["/a b"]).summary == "reveal \"/a b\"")
        #expect(Step.run(ProcessStep(executable: "/usr/bin/touch", arguments: ["/tmp/a b"])).summary == "run \"/usr/bin/touch\" \"/tmp/a b\"")
        #expect(Step.createFile(CreateFileStep(path: "/tmp/x y/untitled.md")).summary == "create \"/tmp/x y/untitled.md\"")
        #expect(Step.openURL("claude://code/new?folder=%2Ftmp").summary == "open URL \"claude://code/new?folder=%2Ftmp\"")
    }

    @Test func aValueWithABackslashIsNotMistakenForAnEscape() {
        // `Café\ d\'été` is a real copy-path.shell-escaped text: printing it with only the quote escaped made
        // `\\"x\\"` mean two different things depending on who read it.
        let text = "Café\\ d\\'été\\ \\\"x\\\""
        #expect(Step.copyToPasteboard(text).details == ["text: \"Café\\\\ d\\\\'été\\\\ \\\\\\\"x\\\\\\\"\""])
    }

    @Test func controlCharactersInNamesNeverReachATerminal() {
        let hostile = "/tmp/\u{1b}[2Jevil\nname\u{9b}31m\u{202E}"
        for step in [Step.open(OpenStep(bundleID: "x", targets: [hostile])), .reveal([hostile]), .createFile(CreateFileStep(path: hostile)),
                     .run(ProcessStep(executable: "/bin/echo", arguments: [hostile])), .openURL("x://" + hostile)] {
            for shown in [step.summary, step.heading] + step.details {
                #expect(!shown.unicodeScalars.contains { $0.value < 0x20 || (0x7f...0x9f).contains($0.value) || $0.value == 0x202E }, "\(shown.debugDescription)")
            }
            #expect(step.summary.contains("\\u001b"))
        }
        let copy = Step.copyToPasteboard(hostile)
        #expect(copy.details.allSatisfy { !$0.unicodeScalars.contains { $0.value < 0x20 } })
    }

    @Test func ordinaryNamesAreJustQuoted() {
        #expect(Step.open(OpenStep(bundleID: "x", targets: ["/Users/me/my code/日本語 é"])).details == ["target: \"/Users/me/my code/日本語 é\""])
    }

    /// What a JSON reader makes of a quoted value: the text it stands for.
    private static func valueRead(from literal: String) throws -> String? {
        let array = try JSONSerialization.jsonObject(with: Data(("[" + literal + "]").utf8)) as? [String]
        return array?.first
    }
}

@Suite("Quoting a value for display")
struct JSONQuotedTests {
    @Test("the quoted form is a JSON string literal", arguments: [
        ("plain", "\"plain\""), ("Café d'été \"x\"", "\"Café d'été \\\"x\\\"\""), ("a\\b", "\"a\\\\b\""), ("a\nb", "\"a\\nb\""),
        ("a\tb", "\"a\\tb\""), ("a\rb", "\"a\\rb\""), ("日本語 🚀", "\"日本語 🚀\""), ("", "\"\""), ("\u{1b}[2J", "\"\\u001b[2J\""),
        ("a\u{9b}b", "\"a\\u009bb\""), ("a\u{7f}b", "\"a\\u007fb\""), ("a\u{2028}b", "\"a\\u2028b\""), ("a\u{202E}b", "\"a\\u202eb\"")
    ])
    func quotes(input: String, expected: String) {
        #expect(input.jsonQuoted == expected)
    }

    @Test("a quoted value reads back as exactly the text, whatever it holds")
    func roundTripsRandomText() throws {
        let alphabet: [Unicode.Scalar] = ["a", "Z", "0", " ", "/", "\\", "\"", "'", "\n", "\r", "\t", "\u{0}", "\u{1}", "\u{1b}", "\u{7}", "\u{7f}", "\u{80}", "\u{85}", "\u{9b}",
                                          "\u{9f}", "\u{2028}", "\u{2029}", "\u{202E}", "\u{2066}", "\u{2069}", "\u{200D}", "\u{301}", "é", "日", "🚀", "{", "}", "[", "]", "u"]
        var state: UInt64 = 0x1234_5678_9ABC_DEF0
        func next() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state >> 33)
        }
        for _ in 0..<2000 {
            var text = String.UnicodeScalarView()
            for _ in 0..<(next() % 12) { text.append(alphabet[next() % alphabet.count]) }
            let original = String(text)
            let quoted = original.jsonQuoted
            let decoded = try #require(try JSONSerialization.jsonObject(with: Data(("[" + quoted + "]").utf8)) as? [String], "\(original.debugDescription) became \(quoted.debugDescription)")
            #expect(decoded == [original], "\(original.debugDescription) became \(quoted.debugDescription)")
            // And what is printed holds nothing a terminal would act on.
            #expect(!quoted.unicodeScalars.contains { $0.value < 0x20 || (0x7f...0x9f).contains($0.value) || [0x2028, 0x2029, 0x202E, 0x2066, 0x2069].contains($0.value) }, "\(quoted.debugDescription)")
        }
    }
}

@Suite("Escaping control characters")
struct ControlCharacterEscapingTests {
    @Test("control characters become visible escapes", arguments: [
        ("a\nb", "a\\nb"), ("a\rb", "a\\rb"), ("a\tb", "a\\tb"), ("\u{1b}[2J", "\\u001b[2J"),
        ("\u{7}", "\\u0007"), ("a\u{2028}b", "a\\u2028b"), ("a\u{85}b", "a\\u0085b"), ("a\u{0}b", "a\\u0000b"),
        ("a\u{7f}b", "a\\u007fb"), ("a\u{2029}b", "a\\u2029b"),
        ("a\u{202E}b", "a\\u202eb"), ("a\u{2066}b", "a\\u2066b"), ("a\u{200F}b", "a\\u200fb")
    ])
    func escapes(input: String, expected: String) {
        #expect(input.withControlCharactersEscaped == expected)
    }

    @Test("ordinary text is untouched, backslashes and unicode included", arguments: ["plain", "back\\slash", "日本語 é 🚀", "a b/c.d", "e\u{301}"])
    func leavesTheRest(input: String) {
        #expect(input.withControlCharactersEscaped == input)
    }
}
