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

    public func english() -> String {
        Localizer.english.render(self)
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
