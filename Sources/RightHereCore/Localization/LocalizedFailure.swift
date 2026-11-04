import Foundation

/// A failure whose sentences are in the catalog, so the alert after a click in Finder, a Shortcuts action and the window say it in the
/// person's language. The command line and the MCP server print its English (`localizedDescription`).
public protocol LocalizedFailure: Error {
    /// What went wrong, one sentence after another, with its values as they are.
    var sentences: [LocalizedMessage] { get }
    /// The same with the values as a person is shown them: their control and invisible characters as escapes (a name can carry a direction
    /// override that would turn the sentence around), except what a value is meant to keep (the line breaks of what a program wrote).
    var shownSentences: [LocalizedMessage] { get }
    /// The shown sentences in the localizer's language, the values in an isolate in a right-to-left sentence.
    func text(in localizer: Localizer) -> String
}

extension LocalizedFailure {
    public var shownSentences: [LocalizedMessage] {
        sentences.map { $0.escapingValues() }
    }

    public func text(in localizer: Localizer) -> String {
        localizer.render(sentences: shownSentences, isolatingValues: true)
    }
}

extension Localizer {
    /// Sentences one after another as the language writes them: Chinese and Japanese put no space between two.
    public func render(sentences: [LocalizedMessage], isolatingValues: Bool = false, escapingValues: Bool = false) -> String {
        let separator = ["zh-Hans", "zh-Hant", "ja"].contains(resolvedLanguage) ? "" : " "
        return sentences.map { render($0, isolatingValues: isolatingValues, escapingValues: escapingValues) }.joined(separator: separator)
    }

    /// What went wrong, in this language when the failure's sentences are in the catalog, else in the failure's own words.
    public func describe(_ error: any Error) -> String {
        (error as? any LocalizedFailure)?.text(in: self) ?? error.localizedDescription
    }
}
