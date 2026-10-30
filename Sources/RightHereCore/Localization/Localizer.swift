import Foundation

/// Picks the best available translation for a list of preferred languages and fills in values.
///
/// Human-facing surfaces (the Finder menu, the app, alerts, files created from Finder) use the
/// system languages; the command line and the MCP server stay in English so their output is
/// stable for scripts and agents.
public struct Localizer: Sendable, Equatable {
    public static let english = Localizer(languages: ["en"])

    /// The person's preferred languages, most preferred first.
    public static var system: Localizer {
        Localizer(languages: Locale.preferredLanguages)
    }

    /// The language a config names, or the system's when it names none (`Config.language`).
    public static func preferring(_ language: String?) -> Localizer {
        language.map { Localizer(languages: [$0]) } ?? .system
    }

    public let languages: [String]

    public init(languages: [String]) {
        self.languages = languages
    }

    /// The language of the catalog that will be used, for example `zh-Hans`.
    public var resolvedLanguage: String {
        for tag in languages {
            if let match = Self.match(tag) { return match }
        }
        return "en"
    }

    /// The text of a key that takes no values. A key that does is made with its `LocalizedMessage` constructor.
    public func string(_ key: LocalizationKey) -> String {
        render(LocalizedMessage(key))
    }

    /// Whether the language of the catalog that will be used is written right to left.
    public var isRightToLeft: Bool {
        Locale.Language(identifier: resolvedLanguage).characterDirection == .rightToLeft
    }

    /// The message in the best language the catalog has for this localizer, with its values filled in.
    ///
    /// `isolatingValues` is for text shown in a window that quotes things written left to right (a path, a command, a
    /// name) inside a right-to-left sentence: each value is put in a Unicode isolate (U+2068 ... U+2069), so the
    /// sentence around it cannot reorder it, which would otherwise show the leading slash of a path at its wrong end.
    /// It changes nothing in a left-to-right language, and nothing for a text that is only its value (it has no
    /// sentence around it). Not for a title that becomes a file name or a menu command's name.
    ///
    /// `escapingValues` is for text that goes to a terminal or to an AI agent (`LocalizedMessage.english()`): the values (a name, a path or a message
    /// that a file, a config or git wrote) are shown with their control and invisible characters as escapes, whoever built the message. A menu title or the
    /// setup window shows a name as it is: a terminal escape cannot act there, and a name written right to left may need its marks.
    public func render(_ message: LocalizedMessage, isolatingValues: Bool = false, escapingValues: Bool = false) -> String {
        let translations = Localizations.table[message.key.rawValue]
        let template = translations?[resolvedLanguage] ?? translations?["en"] ?? message.key.rawValue
        // A count that is not the text's own would make String(format:) read values that are not there.
        guard message.key.arity > 0, message.arguments.count == message.key.arity else { return template }
        var values = escapingValues ? message.arguments.map(\.withControlCharactersEscaped) : message.arguments
        if isolatingValues, isRightToLeft, template != "%@" {
            values = values.map { "\u{2068}" + $0 + "\u{2069}" }
        }
        return String(format: template, arguments: values.map { $0 as CVarArg })
    }

    /// The languages the catalog carries.
    public static var supportedLanguages: [String] { Localizations.languages }

    /// Maps a language tag such as `zh-Hans-US` or `pt-PT` to a language the catalog carries.
    public static func match(_ tag: String) -> String? {
        let parts = tag.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let primary = parts.first?.lowercased() else { return nil }
        let supported = Localizations.languages
        let lowered = parts.map { $0.lowercased() }

        if primary == "zh" {
            // The script says which Chinese is written. macOS names a Simplified Chinese preference with the region of the Mac
            // (`zh-Hans-HK` on a Hong Kong Mac), so the region only decides when there is no script: zh-TW, zh-HK and zh-MO are
            // Traditional, any other region (and none) Simplified.
            let traditionalRegions: Set<String> = ["tw", "hk", "mo"]
            let traditional: Bool
            if let script = lowered.first(where: { $0 == "hans" || $0 == "hant" }) {
                traditional = script == "hant"
            } else {
                traditional = !traditionalRegions.isDisjoint(with: lowered)
            }
            let chinese = traditional ? "zh-Hant" : "zh-Hans"
            return supported.contains(chinese) ? chinese : nil
        }
        if let exact = supported.first(where: { $0.lowercased() == lowered.prefix(2).joined(separator: "-") }) { return exact }
        return supported.first { $0.lowercased() == primary || $0.lowercased().hasPrefix(primary + "-") }
    }
}
