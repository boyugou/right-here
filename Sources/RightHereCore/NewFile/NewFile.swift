import Foundation

public struct NewFileTemplate: Sendable, Equatable, Identifiable {
    public var id: String
    /// Menu title, for example "Text Document".
    public var title: String
    /// File name without extension; numbered on collision (`untitled`, `untitled 2`).
    public var baseName: String
    public var fileExtension: String
    public var contents: String
    /// An app id that opens this kind of file after creation when `new_file.then` is `open`; the default
    /// editor otherwise, or when this one is not installed.
    public var openWith: String?
    /// Localized title and file name of a built-in template; custom templates use their own text.
    public var titleKey: LocalizationKey?
    /// The whole "New …" phrase of a built-in template, so a language can capitalise it correctly; custom
    /// templates compose "New %@" from their title.
    public var newTitleKey: LocalizationKey?
    public var baseNameKey: LocalizationKey?

    public init(
        id: String,
        title: String,
        baseName: String = "untitled",
        fileExtension: String,
        contents: String = "",
        openWith: String? = nil,
        titleKey: LocalizationKey? = nil,
        newTitleKey: LocalizationKey? = nil,
        baseNameKey: LocalizationKey? = nil
    ) {
        self.id = id
        self.title = title
        self.baseName = baseName
        self.fileExtension = fileExtension
        self.contents = contents
        self.openWith = openWith
        self.titleKey = titleKey
        self.newTitleKey = newTitleKey
        self.baseNameKey = baseNameKey
    }

    public func localizedTitle(_ localizer: Localizer) -> String {
        titleKey.map { localizer.string($0) } ?? title
    }

    /// The menu text that creates this kind of file: "New Markdown Document".
    public func localizedNewTitle(_ localizer: Localizer) -> String {
        newTitleKey.map { localizer.string($0) } ?? localizer.newFile(localizedTitle(localizer))
    }

    public func localizedBaseName(_ localizer: Localizer) -> String {
        baseNameKey.map { localizer.string($0) } ?? baseName
    }

    public static let text = NewFileTemplate(id: "txt", title: "Text Document", fileExtension: "txt", titleKey: .templateText, newTitleKey: .menuNewText, baseNameKey: .newFileBaseName)
    public static let markdown = NewFileTemplate(id: "md", title: "Markdown Document", fileExtension: "md", titleKey: .templateMarkdown, newTitleKey: .menuNewMarkdown, baseNameKey: .newFileBaseName)
    public static let builtIn: [NewFileTemplate] = [.text, .markdown]
}

public enum NewFileNamer {
    private static let attemptLimit = 10_000

    public enum Name: Equatable, Sendable {
        case free(String)
        /// The system will not say whether a candidate exists (the folder cannot be searched), and ten thousand more
        /// lookups would not change that.
        case unreadable
        case exhausted
    }

    /// The first free name in `directory`: `untitled.txt`, then `untitled 2.txt`, `untitled 3.txt`, and so on.
    public static func firstFreeName(for template: NewFileTemplate, in directory: URL, facts: any SystemFacts, localizer: Localizer = .english) -> Name {
        let suffix = template.fileExtension.isEmpty ? "" : "." + template.fileExtension
        let baseName = template.localizedBaseName(localizer)
        for number in 1...attemptLimit {
            let stem = number == 1 ? baseName : "\(baseName) \(number)"
            let name = stem + suffix
            switch facts.itemState(directory.appendingPathComponent(name)) {
            case .missing: return .free(name)
            case .present: continue
            case .unreadable: return .unreadable
            }
        }
        return .exhausted
    }

    public static func uniqueName(for template: NewFileTemplate, in directory: URL, facts: any SystemFacts, localizer: Localizer = .english) -> String? {
        if case .free(let name) = firstFreeName(for: template, in: directory, facts: facts, localizer: localizer) { return name }
        return nil
    }
}
