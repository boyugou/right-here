import Foundation

public enum PlanError: Error, Equatable, Sendable {
    /// Nothing is selected and there is no folder to act on.
    case noTarget
    /// A path that was named does not exist, for example a typo on the command line.
    case pathNotFound(String)
    /// A path the system will not let `rh` look at (a privacy-protected folder, say), so what it is cannot be told.
    case unreadable(String)
    case unknownApp(String)
    /// A terminal id (or an agent's launcher) that names no terminal.
    case unknownTerminal(String)
    case appNotInstalled(String)
    /// None of the apps of a role is installed, so there is no default to pick.
    case noDefaultApp(AppDescriptor.Role)
    case unknownAgent(String, choices: [String])
    case unknownVariant(agent: String, variant: String, choices: [String])
    case unknownTemplate(String, choices: [String])
    case unknownPreset(String, choices: [String])
    /// The prompt of a preset, once filled in, cannot be typed into a terminal as one argument (the problem says why).
    case unsafePrompt(preset: String, problem: PresetTemplate.TypingProblem)
    /// A name the prompt of a preset carries from the selection is what makes it impossible to type, so it is named instead of blaming
    /// the prompt.
    case unsafePresetName(preset: String, name: PresetTemplate.Carried, problem: PresetTemplate.TypingProblem)
    /// The target exists but cannot do what was asked, for example a terminal that cannot run a command: the sentence says why.
    case refused(LocalizedMessage)
    /// Text that would be typed into a terminal (a command line) contains line breaks or control characters.
    case unsafeText(String)
    /// A folder whose path a terminal would have to type (`cd …`) has a line break or another control character in it.
    case unsafeFolder(String)
    case nameExhausted
}

extension PlanError {
    /// An app that is no terminal was named where a terminal is needed.
    static func notATerminal(_ app: AppDescriptor) -> PlanError {
        .refused(.refusalNotATerminal(app.name, "open.app.\(app.id)"))
    }
}

extension PlanError: LocalizedError, LocalizedFailure {
    /// Messages name paths, which are whatever somebody called them, so control characters are shown as escapes.
    public var errorDescription: String? {
        text(in: .english)
    }

    public var sentences: [LocalizedMessage] {
        switch self {
        case .noTarget: [.refusalNoTarget]
        case .pathNotFound(let path): [.refusalPathNotFound(path)]
        case .unreadable(let path): [.refusalUnreadable(path)]
        case .unknownApp(let id): [.refusalUnknownApp(id)]
        case .unknownTerminal(let id): [.refusalUnknownTerminal(id)]
        case .appNotInstalled(let name): [.doctorAppNotInstalled(name)]
        case .noDefaultApp(.terminal): [.doctorTerminalNone]
        case .noDefaultApp(.editor): [.refusalNoEditor]
        case .noDefaultApp(.general): [.refusalNoApp]
        case .unknownAgent(let id, let choices): [.refusalUnknownAgent(id)] + Self.hint(id, choices) + [.refusalAgentsListed]
        case .unknownVariant(let agent, let variant, let choices): [.refusalUnknownVariant(agent, variant)] + Self.hint(variant, choices)
        case .unknownTemplate(let id, let choices): [.refusalUnknownTemplate(id)] + Self.hint(id, choices) + [.refusalTemplatesReplace("`[[new_file.template]]`")]
        case .unknownPreset(let id, let choices): [.refusalUnknownPreset(id)] + Self.hint(id, choices) + [.refusalPresetsAdd("`[[preset]]`")]
        case .unsafePrompt(let preset, let problem): [.refusalPresetPrompt(preset), problem.sentence]
        case .unsafePresetName(let preset, let name, let problem): [name.cannotBeNamed(inPreset: preset), problem.aboutAName ?? problem.sentence]
        case .refused(let sentence): [sentence]
        case .unsafeText(let text): [.refusalUnsafeText(text.jsonQuoted)]
        case .unsafeFolder(let path): [.refusalUnsafeFolder(path.jsonQuoted)]
        case .nameExhausted: [.refusalNameExhausted]
        }
    }

    /// The refusal as one sentence, for a place that shows one (why an action is unavailable): every refusal such a place meets is one.
    var sentence: LocalizedMessage {
        sentences.count == 1 ? sentences[0] : .doctorVerbatim(text(in: .english))
    }

    /// "Did you mean "x"?" when one is close, then what exists (so a typo is fixed without a second command).
    private static func hint(_ word: String, _ choices: [String]) -> [LocalizedMessage] {
        var sentences: [LocalizedMessage] = []
        if let close = Suggestion.closest(to: word, in: choices) { sentences.append(.refusalDidYouMean(close)) }
        if !choices.isEmpty { sentences.append(.refusalKnown(choices.joined(separator: ", "))) }
        return sentences
    }
}
