import Foundation
import TOMLDecoder

public enum ConfigParser {
    /// Lowercase letters, digits and dashes, not starting with a dash (it would read as an option on a command
    /// line). `ConfigSchema.identifierPattern` says the same in the JSON Schema, and a test holds them together.
    static func isIdentifier(_ text: String) -> Bool {
        guard let first = text.utf8.first, first != UInt8(ascii: "-") else { return false }
        return text.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == UInt8(ascii: "-") }
    }

    /// Parses config text. A file with a syntax error yields the default config plus the error;
    /// semantic problems are reported while everything valid is still applied.
    /// The deepest nesting of arrays and inline tables a config may have; real ones nest a few levels.
    static let maxNesting = 64

    public static func parse(_ text: String) -> ConfigLoadResult {
        let sink = ConfigSink()
        // The TOML library recurses once per level and a deep enough file overflowed the stack and killed `rh`.
        if NestingDepth.tomlExceeds(text, limit: maxNesting) {
            sink.syntaxError("arrays or tables nested more than \(maxNesting) levels deep")
            return ConfigLoadResult(config: .default, diagnostics: sink.items)
        }
        let root: TOMLTable
        do {
            // A text that ends right after an empty quoted key inside an open bracket (`[""`, `[ ''`, `[[""`) makes the
            // library trap on reading past the end of its input, which killed every `rh` command and the Finder
            // menu. A final line break is harmless to a valid file and turns those into the ordinary syntax error.
            root = try TOMLTable(source: text + "\n")
        } catch {
            sink.syntaxError((error.description.hasSuffix(".") ? String(error.description.dropLast()) : error.description) + ". Usual causes: text without \"quotes\", a missing = or ], the same [table] twice. Defaults apply until it is fixed.")
            return ConfigLoadResult(config: .default, diagnostics: sink.items)
        }
        let config = ConfigBuilder(sink: sink).build(ConfigReader(table: root, path: [], schema: ConfigSchema.root, sink: sink))
        return ConfigLoadResult(config: config, diagnostics: sink.items)
    }
}
