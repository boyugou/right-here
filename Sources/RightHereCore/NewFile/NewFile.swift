import Foundation

public struct NewFileTemplate: Sendable, Equatable, Identifiable {
    public var id: String
    /// Menu title, for example "Text Document".
    public var title: String
    /// File name without extension; numbered on collision (`untitled`, `untitled 2`).
    public var baseName: String
    public var fileExtension: String
    public var contents: String
    /// Localized title and file name of a built-in template; custom templates use their own text.
    public var titleKey: LocalizationKey?
    public var baseNameKey: LocalizationKey?

    public init(
        id: String,
        title: String,
        baseName: String = "untitled",
        fileExtension: String,
        contents: String = "",
        titleKey: LocalizationKey? = nil,
        baseNameKey: LocalizationKey? = nil
    ) {
        self.id = id
        self.title = title
        self.baseName = baseName
        self.fileExtension = fileExtension
        self.contents = contents
        self.titleKey = titleKey
        self.baseNameKey = baseNameKey
    }

    public func localizedTitle(_ localizer: Localizer) -> String {
        titleKey.map { localizer.string($0) } ?? title
    }

    public func localizedBaseName(_ localizer: Localizer) -> String {
        baseNameKey.map { localizer.string($0) } ?? baseName
    }

    public static let text = NewFileTemplate(id: "txt", title: "Text Document", fileExtension: "txt", titleKey: .templateText, baseNameKey: .newFileBaseName)
    public static let markdown = NewFileTemplate(id: "md", title: "Markdown Document", fileExtension: "md", titleKey: .templateMarkdown, baseNameKey: .newFileBaseName)
    public static let builtIn: [NewFileTemplate] = [.text, .markdown]
}

public enum NewFileNamer {
    private static let attemptLimit = 10_000

    /// The first free name in `directory`: `untitled.txt`, then `untitled 2.txt`, `untitled 3.txt`, and so on.
    public static func uniqueName(for template: NewFileTemplate, in directory: URL, facts: any SystemFacts, localizer: Localizer = .english) -> String? {
        let suffix = template.fileExtension.isEmpty ? "" : "." + template.fileExtension
        let baseName = template.localizedBaseName(localizer)
        for number in 1...attemptLimit {
            let stem = number == 1 ? baseName : "\(baseName) \(number)"
            let name = stem + suffix
            if !facts.fileExists(directory.appendingPathComponent(name)) { return name }
        }
        return nil
    }
}
