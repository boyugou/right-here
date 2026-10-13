import Foundation
import Testing
@testable import RightHereCore

/// A deterministic generator, so a failing case can be replayed from its seed.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func pick<T>(_ items: [T], _ random: inout SplitMix64) -> T { items[Int(random.next() % UInt64(items.count))] }

/// Random TOML documents: mostly well-formed pieces of the real schema, with wrong types, odd keys and
/// out-of-place tables, so the semantic checks run; now and then a line of garbage for the syntax errors.
/// Keys never repeat inside a table and plain tables never repeat, since TOML forbids both.
/// `count` random documents from one seed, for the tests of the config layers.
func randomConfigTexts(seed: UInt64, count: Int) -> [String] {
    var random = SplitMix64(state: seed)
    return (0..<count).map { _ in randomConfigText(&random) }
}

private func randomConfigText(_ random: inout SplitMix64) -> String {
    let tables = ["[general]", "[menu]", "[services]", "[copy_path]", "[new_file]", "[agent.claude]", "[agent.codex]", "[agent.mine]",
                  "[agent.\"Bad Id\"]", "[nope]", "[agent]"]
    let arrayTables = ["[[new_file.template]]", "[[app]]", "[[agent.claude.variant]]", "[[agent.mine.variant]]", "[[preset]]", "[[preset]]"]
    let keys = ["terminal", "editor", "agents", "terminal_placement", "items", "styles", "then", "id", "title", "extension", "base_name",
                "contents", "open_with", "prompt", "agent", "max_files", "prompt_arg", "name", "bundle_id", "bundle_ids", "role", "command", "launcher", "arguments", "a.b", "\"quoted key\"", "\"日本語\"", "unknown"]
    let values = ["\"ghostty\"", "\"tab\"", "\"window\"", "\"open\"", "\"claude\"", "\"mine\"", "\"x\"", "1", "-3", "2.5", "true", "false", "[]", "[1, 2]", "[\"a\", \"b\"]", "[[\"x\"]]",
                  "{ a = 1 }", "\"\"", "\"multi\\nline\"", "\'\'\'raw\nstring\'\'\'", "1979-05-27T07:32:00Z", "\"\\u0000\"", "\"a/b\"", "\"../x\"", "\"💥\"",
                  "[\"claude\", \"codex\", \"nope\"]", "\"terminal\"", "\"typora\"", "\"md\"", "\"X Y\"", "\"com.a.b\"", "\"link\"", "\"desktop\"", "[\"open-terminal\", \"-\", \"agents\"]", "\"Review {files} in {folder}\"", "\"{nope} {name}\"", "\"-x\"", "\"positional\"", "\"--prompt\"", "20", "99"]

    func chunk(header: String) -> [String] {
        var available = keys
        var lines = [header]
        for _ in 0..<Int(random.next() % 5) where !available.isEmpty {
            let key = available.remove(at: Int(random.next() % UInt64(available.count)))
            lines.append("\(key) = \(pick(values, &random))")
        }
        return lines
    }

    var lines: [String] = []
    if random.next() % 4 == 0 { lines.append("version = \(pick(["1", "1", "2", "\"1\"", "0"], &random))") }
    var plain = tables.shuffled(using: &random)
    for _ in 0..<Int(random.next() % 6) {
        if random.next() % 2 == 0, let header = plain.popLast() { lines += chunk(header: header) }
        else { lines += chunk(header: pick(arrayTables, &random)) }
        if random.next() % 25 == 0 { lines.append(String((0..<Int(random.next() % 20)).map { _ in pick(Array("=[]{}\"',.# \t\nabc"), &random) })) }
    }
    return lines.joined(separator: "\n")
}

@Suite("Fuzz: config")
struct ConfigFuzzTests {
    @Test("random documents never crash the parser and always leave a usable config", arguments: Array(1...8))
    func parserSurvives(seed: Int) {
        var random = SplitMix64(state: UInt64(seed))
        for _ in 0..<250 {
            let text = randomConfigText(&random)
            let result = ConfigParser.parse(text)
            let config = result.config
            // Whatever was wrong, what remains is internally consistent.
            for id in config.enabledAgents { #expect(config.agent(id: id) != nil, "unknown enabled agent \(id) from \(text.debugDescription)") }
            if let terminal = config.terminal { #expect(config.app(id: terminal)?.role == .terminal, "bad terminal \(terminal) from \(text.debugDescription)") }
            if let editor = config.editor { #expect(config.app(id: editor) != nil) }
            let ids = config.allApps.map(\.id)
            #expect(Set(ids).count == ids.count, "duplicate app ids from \(text.debugDescription)")
            #expect(!config.newFile.templates.isEmpty)
            #expect(Set(config.newFile.templates.map(\.id)).count == config.newFile.templates.count)
            for template in config.newFile.templates {
                #expect(!template.baseName.unicodeScalars.contains("/"), "base_name with a slash from \(text.debugDescription)")
                #expect(!template.fileExtension.unicodeScalars.contains("/"))
            }
            for diagnostic in result.diagnostics { #expect(!diagnostic.message.isEmpty) }
            // Planning with the result must not crash either.
            _ = ActionRegistry(config: config, facts: FakeSystemFacts()).catalog()
            _ = MenuBuilder(config: config, facts: FakeSystemFacts()).build(for: HereContext(origin: .cli))
        }
    }
}

@Suite("Fuzz: action ids")
struct ActionRefFuzzTests {
    @Test("an id that parses writes back as the same id", arguments: Array(1...6))
    func roundTrip(seed: Int) {
        var random = SplitMix64(state: UInt64(seed) &+ 100)
        let words = ["copy-path", "open", "terminal", "editor", "app", "agent", "claude", "new-file", "reveal", "user", "md", "continue", "ghostty", "preset", "review",
                     "default", "link", "desktop", "absolute", "git-relative", "", "A", "a b", "é", "a_b", "-", "1"]
        let separators = [".", "@", ".", ".", "@@", ".@", ""]
        for _ in 0..<600 {
            let text = (0..<Int(1 + random.next() % 6)).map { _ in pick(words, &random) + pick(separators, &random) }.joined()
            guard let ref = ActionRef(parsing: text) else { continue }
            #expect(ActionRef(parsing: ref.id) == ref, "\(text.debugDescription) parsed as \(ref) but its id \(ref.id.debugDescription) parses differently")
        }
    }
}

@Suite("Fuzz: paths and languages")
struct PathAndLanguageFuzzTests {
    @Test("every path style renders any name without crashing", arguments: Array(1...4))
    func renderers(seed: Int) {
        var random = SplitMix64(state: UInt64(seed) &+ 200)
        let pieces = ["a", " ", "'", "\"", "\\", "$", "`", "\n", "\t", "\u{301}", "\u{200D}", "é", "日本", "🚀", "..", ".", "/", "%", "~", "-", "\u{0}", "\u{1b}"]
        let renderer = PathRenderer(facts: FakeSystemFacts(gitRoots: ["/Users/tester/repo"]))
        for _ in 0..<400 {
            let name = (0..<Int(1 + random.next() % 12)).map { _ in pick(pieces, &random) }.joined()
            let url = URL(fileURLWithPath: "/Users/tester/repo/" + name.replacingOccurrences(of: "\u{0}", with: ""))
            for style in PathStyle.allCases { _ = renderer.render([url, url], style: style) }
        }
    }

    @Test func languageTagsOfAnyShapeResolveToSomethingSupported() {
        var random = SplitMix64(state: 300)
        let pieces = ["en", "zh", "Hans", "Hant", "TW", "pt", "BR", "PT", "xx", "", "-", "_", "x", "1", "é", "日本"]
        for _ in 0..<500 {
            let tag = (0..<Int(random.next() % 5)).map { _ in pick(pieces, &random) }.joined(separator: pick(["-", "_", ""], &random))
            let resolved = Localizer(languages: [tag]).resolvedLanguage
            #expect(Localizations.languages.contains(resolved), "\(tag.debugDescription) resolved to \(resolved)")
            _ = Localizer(languages: [tag]).render(.menuOpenIn("X"))
        }
    }
}
