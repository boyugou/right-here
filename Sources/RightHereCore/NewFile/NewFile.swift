import Foundation

public struct NewFileTemplate: Sendable, Equatable, Identifiable {
    public var id: String
    /// Menu title, for example "Text Document".
    public var title: String
    /// File name without extension; numbered on collision (`untitled`, `untitled 2`).
    public var baseName: String
    public var fileExtension: String
    public var contents: String

    public init(id: String, title: String, baseName: String = "untitled", fileExtension: String, contents: String = "") {
        self.id = id
        self.title = title
        self.baseName = baseName
        self.fileExtension = fileExtension
        self.contents = contents
    }

    public static let text = NewFileTemplate(id: "txt", title: "Text Document", fileExtension: "txt")
    public static let markdown = NewFileTemplate(id: "md", title: "Markdown Document", fileExtension: "md")
    public static let builtIn: [NewFileTemplate] = [.text, .markdown]
}

public enum NewFileNamer {
    private static let attemptLimit = 10_000

    /// The first free name in `directory`: `untitled.txt`, then `untitled 2.txt`, `untitled 3.txt`, and so on.
    public static func uniqueName(for template: NewFileTemplate, in directory: URL, facts: any SystemFacts) -> String? {
        let suffix = template.fileExtension.isEmpty ? "" : "." + template.fileExtension
        for number in 1...attemptLimit {
            let stem = number == 1 ? template.baseName : "\(template.baseName) \(number)"
            let name = stem + suffix
            if !facts.fileExists(directory.appendingPathComponent(name)) { return name }
        }
        return nil
    }
}
