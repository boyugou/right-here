import Foundation
import Testing
@testable import RightHereCore

@Suite("SyncValidation")
struct SyncValidationTests {
    private func check(_ text: String) -> [SyncValidation.Problem] { SyncValidation.check(Data(text.utf8)) }

    @Test func aPlainConfigPasses() {
        #expect(check("[general]\nterminal = \"ghostty\"\n").isEmpty)
        #expect(check("").isEmpty)
    }

    @Test func aSyntaxErrorIsRefused() {
        let problems = check("[general\n")
        #expect(problems.count == 1)
        if case .invalid(let reason)? = problems.first { #expect(reason.contains("TOML syntax error")) } else { Issue.record("expected .invalid") }
    }

    @Test func aSemanticErrorIsRefused() {
        #expect(check("[general]\nterminal = 3\n").contains { if case .invalid = $0 { true } else { false } })
    }

    @Test func aWarningAloneIsAccepted() {
        #expect(check("[general]\ntermnial = \"x\"\n").isEmpty)
    }

    @Test func tooLargeIsRefusedBeforeParsing() {
        let big = Data(("# " + String(repeating: "x", count: ConfigParser.maxBytes)).utf8)
        #expect(SyncValidation.check(big) == [.tooLarge(bytes: big.count)])
    }

    @Test func invalidUTF8IsRefused() {
        #expect(SyncValidation.check(Data([0xFF, 0xFE, 0x00])) == [.notUTF8])
    }

    @Test("key names that look like secrets", arguments: ["api_key", "API-KEY", "github_token", "my_Secret", "password", "tokens"])
    func secretKeysAreRefused(name: String) {
        let problems = check("[agent.mine]\nname = \"M\"\ncommand = \"m\"\n\(name) = \"x\"\n")
        #expect(problems.contains(.secretKeys(["agent.mine.\(name)"])))
    }

    @Test func aSecretInAnArrayOfTablesIsFoundToo() {
        let problems = check("[[app]]\nid = \"x\"\nname = \"X\"\nbundle_id = \"a.b\"\napi_key = \"k\"\n")
        #expect(problems.contains(.secretKeys(["app.api_key"])))
    }

    @Test func aValueThatMentionsATokenIsNotAKey() {
        #expect(check("[agent.mine]\nname = \"token tool\"\ncommand = \"mine --token-file x\"\n").isEmpty)
    }

    @Test func everyProblemHasAReadableMessage() {
        #expect(SyncValidation.Problem.secretKeys(["a.token"]).message.contains("a.token"))
        #expect(SyncValidation.Problem.tooLarge(bytes: 2_097_152).message.contains("2048 KB"))
    }
}
