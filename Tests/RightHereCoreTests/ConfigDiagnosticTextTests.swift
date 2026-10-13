import Foundation
import Testing
@testable import RightHereCore

/// Scalars a terminal acts on: C0 and C1 controls (ESC, BEL, U+009B), line and paragraph separators, and the marks
/// that reorder how text is shown.
private func actsOnATerminal(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .control, .lineSeparator, .paragraphSeparator: return true
    default: return ["\u{061C}", "\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}"].contains(scalar)
    }
}

private func everyString(of diagnostic: ConfigDiagnostic) -> [String] {
    [diagnostic.path, diagnostic.message, diagnostic.suggestion ?? "", diagnostic.replacement ?? "", diagnostic.summary(file: URL(fileURLWithPath: "/tmp/config.toml"))]
}

@Suite("Config problems quote the file as data")
struct ConfigDiagnosticTextTests {
    /// What a config from the sync folder can put where a key, a value or an id goes.
    static let hostile: [String] = [
        #""token\u001b]52;c;ZWNobyBwd25lZA==\u0007" = 1"#,
        "[general]\nterminal = \"x\\u001b[2J\"",
        "[general]\neditor = \"\\u009b31m\"",
        "[general]\nagents = [\"a\\u001bb\"]",
        "[menu]\nitems = [\"agent.\\u001b[31m\", \"open.terminal@\\u0007\", \"\\u2028\"]",
        "[services]\nitems = [\"\\u001b]0;pwned\\u0007\"]",
        "[agent.\"bad\\u001bid\"]\nname = \"X\"\ncommand = \"x\"",
        "[copy_path]\nstyles = [\"\\u001b\"]",
        "[new_file]\nthen = \"\\u0085\"",
        "[[app]]\nid = \"x\\u001b\"\nname = \"X\"\nbundle_id = \"a.b\"",
        "[general]\ntermnial\\u001b = \"ghostty\"",
        "[general]\nterminal = \"\\u202Egnp.exe\"",
    ]

    @Test("a control character in the config never reaches a message", arguments: hostile)
    func nothingActsOnATerminal(text: String) {
        let results = [
            ConfigParser.parse(text),
            ConfigLayers.load(base: .text(text), local: .text("# overlay\n")),
            ConfigLayers.load(base: .text("[general]\nterminal = \"ghostty\"\n"), local: .text(text)),
        ]
        for result in results {
            for diagnostic in result.diagnostics {
                for string in everyString(of: diagnostic) {
                    #expect(!string.unicodeScalars.contains(where: actsOnATerminal), "\(string.debugDescription) would act on a terminal")
                }
            }
        }
        #expect(results.contains { !$0.diagnostics.isEmpty }, "the input produced no problem at all, so it tested nothing")
    }

    @Test func theEscapedSpellingIsStillReadable() {
        let result = ConfigParser.parse(#""token\u001b]52;c;ZWNobyBwd25lZA==\u0007" = 1"#)
        let shown = result.diagnostics.map { $0.path + " " + $0.message }.joined(separator: " ")
        #expect(shown.contains(#"token\u001b]52;c;ZWNobyBwd25lZA==\u0007"#), "\(shown)")
    }

    @Test func aProblemInAnOverlayKeyIsStillNamedForTheOverlay() {
        // Origins are looked up by the path as a diagnostic spells it, which is the escaped spelling. The base has an
        // [agent] table too, so the tables merge and the overlay's key is the only thing that says where its problem is.
        let result = ConfigLayers.load(base: .text("[general]\nagents = [\"claude\"]\n[agent.claude]\ncommand = \"claude --x\"\n"),
                                       local: .text("[agent.\"bad\\u001bid\"]\nname = \"X\"\ncommand = \"x\"\n"))
        let about = result.diagnostics.filter { $0.path.hasPrefix("agent.bad") }
        #expect(!about.isEmpty)
        #expect(about.allSatisfy { $0.file == ConfigLayers.overlayFileName }, "\(about)")
    }

    @Test func aDiagnosticThatIsBuiltByHandIsEscapedToo() {
        let diagnostic = ConfigDiagnostic(severity: .error, path: "a\u{1b}b", message: "m\u{7}", suggestion: "s\u{9b}", replacement: "r\u{85}")
        #expect(everyString(of: diagnostic).allSatisfy { !$0.unicodeScalars.contains(where: actsOnATerminal) })
        #expect(diagnostic.message == #"m\u0007"#)
    }
}

@Suite("SyncValidation: messages")
struct SyncValidationMessageTests {
    @Test func aMessageEndsWithoutAPeriodSoTheSentenceThatJoinsThemCanClose() {
        let reasons = ["error: config.toml:3: TOML syntax error: x. Usual causes: y. Defaults apply until it is fixed.", "error: config.toml: bad"]
        let problems: [SyncValidation.Problem] = reasons.map { .invalid($0) } + [.secretKeys(["a.token"]), .tooLarge(bytes: 4_000_000), .notUTF8]
        for problem in problems {
            #expect(!problem.message.hasSuffix("."), "\(problem.message)")
            #expect(!problem.message.contains(".."), "\(problem.message)")
        }
    }

    @Test func aSecretLookingKeyIsListedEscaped() {
        let problems = SyncValidation.check(Data(#""token\u001b]52;c;ZWNobyBwd25lZA==\u0007" = "x""#.utf8))
        guard case .secretKeys(let keys)? = problems.first(where: { if case .secretKeys = $0 { true } else { false } }) else { Issue.record("no secret key found: \(problems)"); return }
        #expect(keys == [#"token\u001b]52;c;ZWNobyBwd25lZA==\u0007"#])
        #expect(!problems.map(\.message).joined().unicodeScalars.contains(where: actsOnATerminal))
    }
}
