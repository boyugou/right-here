import Foundation

public struct NewFileTemplate: Sendable, Equatable, Identifiable {
    public var id: String
    /// Menu title, for example "Text Document".
    public var title: String
    /// File name without extension; numbered on collision (`untitled`, `untitled 2`).
    public var baseName: String
    public var fileExtension: String
    public var contents: String
    /// A blank document of an Office format that the file is made as, in place of `contents` (ADR 0032).
    public var format: OfficeFormat?
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
        format: OfficeFormat? = nil,
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
        self.format = format
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
        if let newTitleKey { return localizer.string(newTitleKey) }
        // A built-in template that was written out as the config's own (the window's "Customize Templates") says what it said, for as long as its title is the built-in one.
        if let builtIn = Self.builtIn.first(where: { $0.id == id }), let phrase = builtIn.newTitleKey, title == builtIn.localizedTitle(localizer) { return localizer.string(phrase) }
        return localizer.newFile(localizedTitle(localizer))
    }

    public func localizedBaseName(_ localizer: Localizer) -> String {
        baseNameKey.map { localizer.string($0) } ?? baseName
    }

    public static let text = NewFileTemplate(id: "txt", title: "Text Document", fileExtension: "txt", titleKey: .templateText, newTitleKey: .menuNewText, baseNameKey: .newFileBaseName)
    public static let markdown = NewFileTemplate(id: "md", title: "Markdown Document", fileExtension: "md", titleKey: .templateMarkdown, newTitleKey: .menuNewMarkdown, baseNameKey: .newFileBaseName)
    public static let word = NewFileTemplate(id: "docx", title: "Word Document", fileExtension: "docx", format: .docx, titleKey: .templateWord, newTitleKey: .menuNewWord, baseNameKey: .newFileBaseName)
    public static let excel = NewFileTemplate(id: "xlsx", title: "Excel Workbook", fileExtension: "xlsx", format: .xlsx, titleKey: .templateExcel, newTitleKey: .menuNewExcel, baseNameKey: .newFileBaseName)
    public static let powerPoint = NewFileTemplate(id: "pptx", title: "PowerPoint Presentation", fileExtension: "pptx", format: .pptx, titleKey: .templatePowerPoint, newTitleKey: .menuNewPowerPoint, baseNameKey: .newFileBaseName)
    public static let builtIn: [NewFileTemplate] = [.text, .markdown, .word, .excel, .powerPoint]
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
}
