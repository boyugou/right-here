import Foundation
import RightHereCore

/// Matches the path the person knows and the abbreviated, escaped path the window shows. It never reads the filesystem.
public struct FolderSearch: Sendable {
    private let terms: [String]
    private let locale: Locale

    public init(_ query: String, locale: Locale) {
        self.locale = locale
        terms = query.split(whereSeparator: \.isWhitespace).map {
            String($0).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
        }
    }

    public var isEmpty: Bool { terms.isEmpty }

    public func filter(_ paths: [String], home: String) -> [String] {
        guard !isEmpty else { return paths }
        return paths.filter { path in
            let displayed = PathDisplay.abbreviatingHome(path.withControlCharactersEscaped, home: home.withControlCharactersEscaped)
            let text = (path + "\n" + displayed).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
            return terms.allSatisfy(text.contains)
        }
    }
}
