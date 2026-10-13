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

    public static func parse(_ text: String) -> ConfigLoadResult {
        let sink = ConfigSink()
        guard let root = readTable(text, sink: sink) else {
            return ConfigLoadResult(config: .default, diagnostics: sink.items)
        }
        let config = ConfigBuilder(sink: sink).build(ConfigReader(table: root, path: [], schema: ConfigSchema.root, sink: sink))
        return ConfigLoadResult(config: config, diagnostics: sink.items)
    }

    /// The text as a table, or `nil` with the reason in the sink.
    static func readTable(_ text: String, sink: ConfigSink) -> TOMLTable? {
        // The TOML library recurses once per level and a deep enough file overflowed the stack and killed `rh`.
        if NestingDepth.tomlExceeds(text, limit: maxNesting) {
            sink.syntaxError("arrays or tables nested more than \(maxNesting) levels deep")
            return nil
        }
        do {
            // A text that ends right after an empty quoted key inside an open bracket (`[""`, `[ ''`, `[[""`) makes the
            // library trap on reading past the end of its input, which killed every `rh` command and the Finder
            // menu. A final line break is harmless to a valid file and turns those into the ordinary syntax error.
            return try TOMLTable(source: text + "\n")
        } catch {
            sink.syntaxError((error.description.hasSuffix(".") ? String(error.description.dropLast()) : error.description) + ". Usual causes: text without \"quotes\", a missing = or ], the same [table] twice. Defaults apply until it is fixed.")
            return nil
        }
    }

    /// The text as plain values, for merging; or the problem that stops it from being read.
    static func readTree(_ text: String) -> (tree: [String: TOMLValue]?, diagnostics: [ConfigDiagnostic]) {
        let sink = ConfigSink()
        guard let table = readTable(text, sink: sink) else { return (nil, sink.items) }
        guard let tree = TOMLValue.read(table) else {
            sink.error([], "contains a value of a kind this build cannot read")
            return (nil, sink.items)
        }
        return (tree, sink.items)
    }
}
