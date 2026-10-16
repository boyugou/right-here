import Foundation

/// A sentence of the String Catalog and the values that go into it: what a menu, an alert or the doctor says, before it
/// is written in a language.
///
/// `LocalizedMessage.menuOpenIn("Ghostty")` is how one is made: there is a constructor per catalog key (generated, in
/// `LocalizedMessage.generated.swift`), so a wrong number of values does not compile. `Localizer.render` writes it in a
/// language; `english()` writes it in English, which is what the command line and the MCP server print.
public struct LocalizedMessage: Sendable, Equatable {
    public let key: LocalizationKey
    public let arguments: [String]

    init(_ key: LocalizationKey, _ arguments: [String] = []) {
        assert(arguments.count == key.arity, "\(key.rawValue) takes \(key.arity) values, not \(arguments.count)")
        self.key = key
        self.arguments = arguments
    }

    /// The sentence in English, as the command line and the MCP server print it: its values with their control and invisible characters shown as escapes.
    public func english() -> String {
        Localizer.english.render(self, escapingValues: true)
    }

    /// The sentence in English with each of its values (a name, a command, a path or a message that something other than Right Here wrote) fenced as data
    /// (`Fence`), and Right Here's own words outside the fences. A number is not a value in that sense, and neither is a value at one of the `own` positions (the
    /// message's own file, say). For a report an AI agent is told to pass on.
    public func englishMarkingValues(except own: Set<Int> = []) -> String {
        let marked = arguments.enumerated().map { index, value in
            own.contains(index) || (!value.isEmpty && value.utf8.allSatisfy { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }) ? value.withControlCharactersEscaped : Fence.wrap(value)
        }
        return Localizer.english.render(LocalizedMessage(key, marked))
    }

    /// The sentence with its values left out (shown as `…`), except the numbers and the values at the positions named: Right Here's own
    /// wording and nothing a config or a file put into it. For a report that is pasted where everyone reads it.
    public func english(showingOnly positions: Set<Int> = []) -> String {
        let shown = arguments.enumerated().map { index, value in
            positions.contains(index) || (!value.isEmpty && value.utf8.allSatisfy { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }) ? value : "…"
        }
        return Localizer.english.render(LocalizedMessage(key, shown), escapingValues: true)
    }
}

/// `{"code": "doctor.config.missing", "args": ["/path"], "text": "none at /path; defaults apply"}`: the code and the values
/// identify the sentence for a program, and the text is its English wording for a person or an AI agent.
extension LocalizedMessage: Encodable {
    private enum CodingKeys: String, CodingKey {
        case code, args, text
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key.rawValue, forKey: .code)
        try container.encode(arguments, forKey: .args)
        try container.encode(english(), forKey: .text)
    }
}
