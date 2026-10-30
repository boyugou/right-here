import Foundation
import Testing
@testable import RightHereCore

/// Random text, made of the pieces TOML is built from and a few it is not, is parsed: the parser has to come back (a trap would take the Finder
/// extension with it, which reads the config for every menu) and say the same thing twice. `ConfigDocumentFuzzTests` edits valid configs; this
/// is the other side, text that was never valid.
@Suite("ConfigParser: random text never traps, and parses the same way twice")
struct ConfigParserFuzzTests {
    private struct Generator {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    private static let pieces: [String] = [
        "[", "]", "[[", "]]", "=", "\"", "'", "\"\"\"", "'''", "\\", "\n", "\r\n", "\r", "#", " ", "\t", ".", ",", "{", "}", "true", "false",
        "1", "-", "+", "0x", "1e9", "inf", "nan", "1979-05-27T07:32:00Z", "general", "terminal", "editor", "agents", "menu", "items", "app",
        "agent", "preset", "new_file", "template", "version", "ghostty", "claude", "id", "name", "command", "args", "é", "\u{301}", "中",
        "\u{0}", "\u{7F}", "\u{2028}", "\u{FEFF}", "🙂", "\\u00", "\\U0010FFFF", "\\n", "\\x", "\\", "\"\\\"", "''", "\"\"",
    ]

    /// The text of one case: the seed decides it, so a case that fails can be read back by its seed.
    static func text(seed: Int) -> String {
        var generator = Generator(state: UInt64(seed) &* 2_654_435_761 &+ 7)
        let count = 1 + generator.next(seed % 7 == 0 ? 600 : 120)
        return (0..<count).map { _ in pieces[generator.next(pieces.count)] }.joined()
    }

    @Test("random text is parsed without a trap, and the same way twice", arguments: Array(1...400))
    func randomText(seed: Int) {
        let text = Self.text(seed: seed)
        let first = ConfigParser.parse(text)
        let second = ConfigParser.parse(text)
        #expect(String(describing: first.diagnostics) == String(describing: second.diagnostics))
        #expect(String(describing: first.config) == String(describing: second.config))
    }

    @Test func aSeedAlwaysMakesTheSameTextAndTwoSeedsDiffer() {
        #expect(Self.text(seed: 3) == Self.text(seed: 3))
        #expect(Self.text(seed: 3) != Self.text(seed: 4))
    }
}
