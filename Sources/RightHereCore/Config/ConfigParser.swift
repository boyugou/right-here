import Foundation
import TOMLDecoder

public enum ConfigParser {
    /// Parses config text. A file with a syntax error yields the default config plus the error;
    /// semantic problems are reported while everything valid is still applied.
    /// The deepest nesting of arrays and inline tables a config may have; real ones nest a few levels.
    static let maxNesting = 64

    /// The most a config file may hold. A config is a few kilobytes; the menu is built from it on every right-click, so a
    /// file far past that (a wrong path, a log pasted over it) is refused instead of read: parsing 60 MB took four
    /// seconds. The config store, the overlay and the sync folder's copy all keep to it.
    public static let maxBytes = 1_048_576

    /// What a file that cannot be read means for the config, said after the problem: with one file, the defaults apply.
    static let defaultsApply = "Defaults apply until it is fixed."
    /// With an overlay, a file that cannot be read is left out and the other one still applies.
    static let fileLeftOut = "This file is left out until it is fixed."

    /// Parses config text, and says where in it each problem is (`locate`).
    public static func parse(_ text: String) -> ConfigLoadResult {
        var result = parseUnlocated(text)
        result.diagnostics = locate(result.diagnostics, in: text)
        return result
    }

    /// `parse` without the lines: a problem names a path, and the merge of two files finds its line in the file it came
    /// from, which is not this text.
    static func parseUnlocated(_ text: String, consequence: String = defaultsApply) -> ConfigLoadResult {
        let sink = ConfigSink(source: text)
        guard let root = readTable(text, sink: sink, consequence: consequence) else {
            return ConfigLoadResult(config: .default, diagnostics: sink.items)
        }
        let config = ConfigBuilder(sink: sink).build(ConfigReader(table: root, path: [], schema: ConfigSchema.root, sink: sink))
        return ConfigLoadResult(config: config, diagnostics: sink.items)
    }

    /// Puts each problem at the line of its key or table in `text`, and the problems in the order of the file: what is
    /// about the file as a whole first, then by line. Problems with the same line keep the order they were found in.
    static func locate(_ diagnostics: [ConfigDiagnostic], in text: String) -> [ConfigDiagnostic] {
        guard !diagnostics.isEmpty else { return diagnostics }
        let outline = TOMLOutline(text)
        let located = diagnostics.map { diagnostic -> ConfigDiagnostic in
            guard diagnostic.line == nil, !diagnostic.path.isEmpty, let line = outline.line(of: diagnostic.path) else { return diagnostic }
            var diagnostic = diagnostic
            diagnostic.line = line
            return diagnostic
        }
        return located.enumerated().sorted {
            ($0.element.line ?? 0, $0.offset) < ($1.element.line ?? 0, $1.offset)
        }.map(\.element)
    }

    /// Whether the text is TOML at all: a text with a syntax error is not read, and the config built from it is the defaults.
    public static func canBeRead(_ text: String) -> Bool {
        readTable(text, sink: ConfigSink()) != nil
    }

    /// The text as a table, or `nil` with the reason in the sink.
    static func readTable(_ text: String, sink: ConfigSink, consequence: String = defaultsApply) -> TOMLTable? {
        // The TOML library recurses once per level and a deep enough file overflowed the stack and killed `rh`.
        if NestingDepth.tomlExceeds(text, limit: maxNesting) {
            sink.syntaxError("arrays or tables nested more than \(maxNesting) levels deep. \(consequence)")
            return nil
        }
        do {
            // A text that ends right after an empty quoted key inside an open bracket (`[""`, `[ ''`, `[[""`) makes the
            // library trap on reading past the end of its input, which killed every `rh` command and the Finder
            // menu. A final line break is harmless to a valid file and turns those into the ordinary syntax error.
            return try TOMLTable(source: text + "\n")
        } catch {
            let explained = TOMLSyntax.explain(error.description, outline: TOMLOutline(text))
            sink.syntaxError("\(explained.message). \(consequence)", line: explained.line)
            return nil
        }
    }

    /// The text as plain values, for merging; or the problem that stops it from being read.
    static func readTree(_ text: String, consequence: String = defaultsApply) -> (tree: [String: TOMLValue]?, diagnostics: [ConfigDiagnostic]) {
        let sink = ConfigSink()
        guard let table = readTable(text, sink: sink, consequence: consequence) else { return (nil, sink.items) }
        var outline: TOMLOutline?
        let tree = TOMLValue.read(table) { path in
            if outline == nil { outline = TOMLOutline(text) }
            return outline?.rawValue(of: path.map(\.withControlCharactersEscaped).joined(separator: "."))
        }
        guard let tree else {
            sink.error([], "contains a value of a kind this build cannot read")
            return (nil, sink.items)
        }
        return (tree, sink.items)
    }
}
