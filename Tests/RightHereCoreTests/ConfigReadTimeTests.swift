import Foundation
import Testing
@testable import RightHereCore

/// From an independent review of the Finder click path (2026-11-04). The Finder extension reads the config on its main thread inside `menu(for:)`
/// (`FinderSyncExtension.currentConfigWithStamp`, through `ConfigStore.load`, which is `ConfigParser.parse` plus `locate`), and every
/// `rh run` a click starts reads it again. `ConfigParser.maxBytes` (1 MiB) is meant to keep that to milliseconds. These texts are far
/// below the limit and are not: the cost grows faster than the text.
/// Timed: the limits are three seconds for what took between six and twenty-six before, and takes a third of a second at most now.
@Suite("What a hostile config costs the Finder menu (timed)", .serialized)
struct ConfigReadTimeTests {
    private func seconds(_ body: () -> Void) -> Double {
        let start = ContinuousClock.now
        body()
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    /// `TOMLOutline.resolved` joins the first 1, 2, ... n segments of a table header to look each prefix up in `entryCounts`: n²/2 work for a
    /// header of n segments. `locate` builds the outline whenever there is any diagnostic, and the nesting check's own refusal is one, so a
    /// text that is refused as a syntax error still pays it. 32 KB here (16,000 segments); a 1 MiB header is hours.
    @Test func aLongTableHeaderIsReadInTimeThatGrowsWithTheText() {
        let text = "[" + Array(repeating: "a", count: 16_000).joined(separator: ".") + "]\nx = 1\n"
        #expect(text.utf8.count < ConfigParser.maxBytes / 30)
        var result: ConfigLoadResult?
        let elapsed = seconds { result = ConfigParser.parse(text) }
        #expect(result?.diagnostics.contains { $0.severity == .error } == true, "the text is refused, as it should be")
        #expect(elapsed < 3.0, "parsing \(text.utf8.count) bytes took \(elapsed) s")
    }

    /// `Suggestion.distance` is a full edit distance between the unknown key and each key of the table, however long the key is, although a
    /// word that is longer than a candidate by more than the threshold (`max(2, count / 3)`) can never be suggested. An unknown key is only a
    /// warning, so `rh config sync pull` copies such a config without `--allow-commands`.
    @Test func aLongUnknownKeyIsReadInTimeThatGrowsWithTheText() {
        let text = "[general]\n" + String(repeating: "a", count: 600_000) + " = 1\n"
        var result: ConfigLoadResult?
        let elapsed = seconds { result = ConfigParser.parse(text) }
        #expect(result?.diagnostics.allSatisfy { $0.severity == .warning } == true, "only a warning")
        #expect(elapsed < 3.0, "parsing \(text.utf8.count) bytes took \(elapsed) s")
    }

    /// The same edit distance when both words are long: a preset id (no length limit, and a preset is text, not a program, so a pull takes it
    /// without `--allow-commands`) and a `menu.items` entry that names another long preset id. 20 KB; quadratic in the ids' length.
    @Test func aLongIdNextToALongReferenceIsReadInTimeThatGrowsWithTheText() {
        let text = "[menu]\nitems = [\"preset.\(String(repeating: "b", count: 10_000))\"]\n\n[[preset]]\nid = \"\(String(repeating: "a", count: 10_000))\"\ntitle = \"x\"\nprompt = \"look\"\n"
        var result: ConfigLoadResult?
        let elapsed = seconds { result = ConfigParser.parse(text) }
        #expect(result?.diagnostics.allSatisfy { $0.severity == .warning } == true, "only warnings: a sync pull copies it")
        #expect(elapsed < 3.0, "parsing \(text.utf8.count) bytes took \(elapsed) s")
    }

    /// Nothing bounds `menu.items`: a list that repeats groups is only a warning ("listed twice, so the menu shows it twice"), so a plain
    /// `rh config sync pull` accepts it, and the menu grows with it (16,000 entries here make 12,000 top-level items and 76,000 in all). On top,
    /// `MenuBuilder.assembleEntries` asks `entries.contains("presets")` (and `contains("agents")` per agent) for every `agents-more` entry, which
    /// makes the build quadratic in the list. A selection of files is not served from the extension's cache: every right-click on files builds it.
    @Test func theMenuForFilesFromALongMenuListIsBuiltQuickly() {
        let facts = FakeSystemFacts(
            directories: ["/Users/tester/code"],
            files: ["/Users/tester/code/a.txt"],
            applications: Dictionary(uniqueKeysWithValues: ["com.mitchellh.ghostty", "com.apple.Terminal", "com.microsoft.VSCode", "dev.zed.Zed"].map {
                ($0, URL(fileURLWithPath: "/Applications/\($0).app"))
            })
        )
        let files = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/a.txt")], container: URL(fileURLWithPath: "/Users/tester/code"))
        // 212 KB, a fifth of what a config may hold; the Finder menu of a normal config is built in milliseconds.
        let text = "[menu]\nitems = [" + Array(repeating: "\"agents-more\", \"open-with\", \"copy-path\", \"new-file\"", count: 4_000).joined(separator: ", ") + "]\n"
        let config = ConfigParser.parse(text).config
        var menu: [MenuNode] = []
        let elapsed = seconds { menu = MenuBuilder(config: config, facts: facts).build(for: files) }
        #expect(elapsed < 3.0, "building the menu for a selection of files took \(elapsed) s, for \(menu.count) entries")
    }
}

@Suite("What a config may hold, so that reading it stays quick")
struct ConfigBoundsTests {
    /// The decoder's cost grows with the square of a table's keys, so a config that sets thousands of keys is refused before it is decoded; one
    /// that sets fewer is read. What is inside a string (a template's contents) or a comment is not a key.
    @Test func aConfigThatSetsThousandsOfKeysIsRefusedAndOneThatSetsFewerIsRead() {
        let many = "[general]\n" + (0..<ConfigParser.maxEntries).map { "k\($0) = 1\n" }.joined()
        #expect(ConfigParser.parse(many).hasErrors && ConfigParser.parse(many).config == .default)
        let fewer = "[general]\n" + (0..<(ConfigParser.maxEntries - 2)).map { "k\($0) = 1\n" }.joined()
        #expect(!ConfigParser.parse(fewer).hasErrors)
        let lines = (0..<(ConfigParser.maxEntries * 2)).map { "x\($0) = [y]" }.joined(separator: "\n")
        let template = "# a = 1\n[[new_file.template]]\nid = \"ini\"\ntitle = \"INI\"\nextension = \"ini\"\ncontents = \"\"\"\n\(lines)\n\"\"\"\n"
        #expect(!ConfigParser.parse(template).hasErrors, "the lines of a template's contents are not keys of the config")
    }

    @Test func theMenuTakesTheFirstEntriesOfAListThatIsTooLong() {
        let text = "[menu]\nitems = [" + Array(repeating: "\"copy-path\"", count: 300).joined(separator: ", ") + "]\n"
        let result = ConfigParser.parse(text)
        #expect(result.config.menuItems?.count == 256)
        #expect(result.diagnostics.contains { $0.severity == .warning && $0.path == "menu.items" && $0.message.contains("the menu takes the first 256") })
    }

    /// A word far longer than any id is not a typo of one, and comparing it with every candidate costs the square of its length.
    @Test func aLongWordIsNotComparedForASuggestion() {
        let long = String(repeating: "a", count: 65)
        #expect(Suggestion.closest(to: long, in: [long]) == nil)
        #expect(Suggestion.closest(to: "termnial", in: ["terminal", "editor"]) == "terminal")
    }
}
