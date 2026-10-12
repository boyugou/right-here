import Foundation
import Testing
@testable import RightHereCore

@Suite("NestingDepth")
struct NestingDepthTests {
    private func nested(_ open: String, _ close: String, _ depth: Int, _ inner: String = "1") -> String {
        String(repeating: open, count: depth) + inner + String(repeating: close, count: depth)
    }

    @Test("JSON: the limit is on levels, not on brackets", arguments: [(5, false), (32, false), (33, true), (500, true)])
    func jsonLevels(depth: Int, exceeds: Bool) {
        #expect(NestingDepth.jsonExceeds(nested("[", "]", depth).utf8, limit: 32) == exceeds)
        #expect(NestingDepth.jsonExceeds(("{\"k\":" + nested("{\"k\":", "}", depth - 1) + "}").utf8, limit: 32) == exceeds)
    }

    @Test func jsonBracketsInsideStringsAreNotLevels() {
        let text = #"{"a":"[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[","b":"\"[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[","c":[1]}"#
        #expect(!NestingDepth.jsonExceeds(text.utf8, limit: 3))
    }

    @Test func jsonSiblingsDoNotAddUp() {
        #expect(!NestingDepth.jsonExceeds(("[" + String(repeating: "[1],", count: 1_000) + "[1]]").utf8, limit: 3))
    }

    @Test("TOML: arrays and inline tables count, headers are two levels at most", arguments: [(5, false), (64, false), (65, true), (5_000, true)])
    func tomlLevels(depth: Int, exceeds: Bool) {
        #expect(NestingDepth.tomlExceeds("x = " + nested("[", "]", depth), limit: 64) == exceeds)
        #expect(NestingDepth.tomlExceeds("x = " + nested("{ a = ", " }", depth), limit: 64) == exceeds)
    }

    @Test func tomlStringsAndCommentsAreNotLevels() {
        let brackets = String(repeating: "[", count: 200)
        let text = """
        a = "\(brackets)"
        b = '\(brackets)'
        c = \"\"\"
        \(brackets)
        \"\"\"
        d = '''
        \(brackets)
        '''
        e = "an escaped quote \\" then \(brackets)"
        # \(brackets)
        [[agent.claude.variant]]
        id = "x"
        """
        #expect(!NestingDepth.tomlExceeds(text, limit: 8))
    }

    @Test("a multiline string may close with up to two extra quotes, and the brackets after it still count",
          arguments: ["\"\"\"a\"\"\"\"", "\"\"\"a\"\"\"\"\"", "'''a''''", "'''a'''''"])
    func extraClosingQuotes(closing: String) {
        #expect(NestingDepth.tomlExceeds("x = [\(closing), \(nested("[", "]", 200))]", limit: 64), "\(closing)")
        #expect(!NestingDepth.tomlExceeds("x = [\(closing), [1]]", limit: 64), "\(closing)")
    }

    @Test func aRealConfigIsFarFromTheLimit() {
        #expect(!NestingDepth.tomlExceeds(ConfigTemplate.render(DetectedEnvironment(terminal: "ghostty", editor: "vscode", agents: ["claude", "codex"])), limit: 8))
    }
}
