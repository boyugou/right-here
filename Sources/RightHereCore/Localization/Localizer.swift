import Foundation

/// Picks the best available translation for a list of preferred languages and fills in arguments.
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

    public func string(_ key: LocalizationKey, _ arguments: CVarArg...) -> String {
        format(key, arguments)
    }

    func format(_ key: LocalizationKey, _ arguments: [CVarArg]) -> String {
        let translations = Localizations.table[key.rawValue]
        let template = translations?[resolvedLanguage] ?? translations?["en"] ?? key.rawValue
        return arguments.isEmpty ? template : String(format: template, arguments: arguments)
    }

    /// Maps a language tag such as `zh-Hans-US` or `pt-PT` to a language the catalog carries.
    static func match(_ tag: String) -> String? {
        let parts = tag.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let primary = parts.first?.lowercased() else { return nil }
        let supported = Localizations.languages
        let lowered = parts.map { $0.lowercased() }

        if primary == "zh" {
            let traditionalRegions: Set<String> = ["tw", "hk", "mo"]
            if lowered.contains("hant") || !traditionalRegions.isDisjoint(with: lowered) { return supported.contains("zh-Hant") ? "zh-Hant" : nil }
            return supported.contains("zh-Hans") ? "zh-Hans" : nil
        }
        if let exact = supported.first(where: { $0.lowercased() == lowered.prefix(2).joined(separator: "-") }) { return exact }
        return supported.first { $0.lowercased() == primary || $0.lowercased().hasPrefix(primary + "-") }
    }
}
