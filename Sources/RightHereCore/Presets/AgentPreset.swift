import Foundation

/// How an agent's command line takes a first prompt.
public enum PromptArgument: Sendable, Equatable, Hashable {
    /// `claude "prompt"`.
    case positional
    /// `tool --flag "prompt"`; the flag is typed as its own word before the prompt.
    case flag(String)

    /// The word the config spells for the positional form.
    public static let positionalWord = "positional"
    /// What a config value has to look like: `positional`, or a flag such as `--prompt` or `-i`.
    public static let pattern = "^(positional|--?[A-Za-z0-9][A-Za-z0-9-]*)$"

    public init?(configValue: String) {
        if configValue == Self.positionalWord { self = .positional; return }
        guard configValue.range(of: Self.pattern, options: .regularExpression) != nil else { return nil }
        self = .flag(configValue)
    }

    public var configValue: String {
        switch self {
        case .positional: return Self.positionalWord
        case .flag(let flag): return flag
        }
    }
}

/// A prompt template that an agent starts with, filled in from the selection. Built-ins are read-only in wording only:
/// the agent decides what it does with the words.
public struct AgentPreset: Sendable, Equatable, Identifiable {
    public static let defaultMaxFiles = 20
    public static let maxFilesLimit = 50
    /// A prompt is typed as one shell word; this keeps it a sentence or two, not a document. Counted in UTF-8 bytes, what
    /// is typed: a `Character` can be any number of scalars (a letter with a thousand combining marks is one), so a count
    /// of them says nothing about how much text reaches the terminal.
    public static let maxPromptBytes = 4000

    public var id: String
    public var title: String
    /// The agent that runs it; `nil` means the first agent in `general.agents`.
    public var agent: String?
    public var prompt: String
    public var maxFiles: Int
    /// The localized title of a built-in preset; presets from the config use `title` as written.
    public var titleKey: LocalizationKey?

    public init(id: String, title: String, agent: String? = nil, prompt: String, maxFiles: Int = AgentPreset.defaultMaxFiles, titleKey: LocalizationKey? = nil) {
        self.id = id
        self.title = title
        self.agent = agent
        self.prompt = prompt
        self.maxFiles = maxFiles
        self.titleKey = titleKey
    }

    public func localizedTitle(_ localizer: Localizer) -> String {
        titleKey.map { localizer.string($0) } ?? title
    }

    /// Whether the prompt names the selected files, which makes the preset need some.
    public var needsFiles: Bool {
        PresetTemplate.segments(of: prompt).contains(.files)
    }

    /// Why a selection of `count` files does not suit this preset, or `nil`. The count alone, so the menu can decide
    /// without looking at the files.
    public func refusal(forFileCount count: Int) -> String? {
        guard needsFiles else { return nil }
        if count == 0 { return "\"\(title)\" works on selected files; select one or more files (folders do not count)." }
        if count > maxFiles { return "\(count) files are selected and \"\(title)\" takes at most \(maxFiles) (max_files)." }
        return nil
    }

    /// Why a launcher word that only an agent entry understands cannot follow `preset.<id>@`, or `nil`. A preset is
    /// always typed into a terminal; the agent's own deep link and its desktop app do not take a prompt this way.
    public static func launcherRefusal(_ terminal: String?) -> String? {
        guard let terminal, terminal == AgentLauncher.linkWord || terminal == AgentLauncher.desktopWord else { return nil }
        return "A preset is typed into a terminal, so @\(terminal) does not apply. Name a terminal from `rh apps` (preset.<id>@<terminal>) or leave the suffix out."
    }

    public static let builtIn: [AgentPreset] = [
        AgentPreset(
            id: "review", title: "Review",
            prompt: "Review {files} for bugs, unclear code and risky changes. Do not modify any files; reply with your findings, most serious first.",
            titleKey: .presetReview),
        AgentPreset(
            id: "explain", title: "Explain",
            prompt: "Explain what {files} does and how it fits into the rest of {folder}. Do not modify any files.",
            titleKey: .presetExplain),
        AgentPreset(
            id: "tests", title: "Write Tests",
            prompt: "Read {files} and propose a test plan: the behaviors and edge cases that need tests, and where the tests would live. Write the plan only; do not create or modify any files.",
            titleKey: .presetTests)
    ]
}

/// The `{files}`, `{folder}` and `{name}` placeholders of a preset prompt, read in a single pass so text that came
/// from a file name (`{files}.md`) is never read as a placeholder itself.
public enum PresetTemplate {
    public enum Segment: Sendable, Equatable {
        case text(String)
        case files
        case folder
        case name
    }

    public static let placeholders = ["files", "folder", "name"]

    public static func segments(of template: String) -> [Segment] {
        var result: [Segment] = []
        var text = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            text += rest[..<open]
            let after = rest[rest.index(after: open)...]
            guard let close = after.firstIndex(of: "}") else { rest = rest[open...]; break }
            let segment: Segment?
            switch after[..<close] {
            case "files": segment = .files
            case "folder": segment = .folder
            case "name": segment = .name
            default: segment = nil
            }
            if let segment {
                if !text.isEmpty { result.append(.text(text)); text = "" }
                result.append(segment)
                rest = after[after.index(after: close)...]
            } else {
                text += "{"
                rest = after
            }
        }
        text += rest
        if !text.isEmpty { result.append(.text(text)) }
        return result
    }

    /// Words in braces that look like placeholders but are not one (`{file}`, `{path}`): almost always a typo, and
    /// they would reach the agent as literal text.
    public static func unknownPlaceholders(in template: String) -> [String] {
        var unknown: [String] = []
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            let after = rest[rest.index(after: open)...]
            guard let close = after.firstIndex(of: "}") else { break }
            let word = String(after[..<close])
            if !word.isEmpty, word.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }), !placeholders.contains(word), !unknown.contains(word) {
                unknown.append(word)
            }
            rest = after[after.index(after: close)...]
        }
        return unknown
    }

    public static func expand(_ template: String, files: String, folder: String, name: String) -> String {
        segments(of: template).map { segment in
            switch segment {
            case .text(let text): return text
            case .files: return files
            case .folder: return folder
            case .name: return name
            }
        }.joined()
    }

    /// Why a prompt cannot be typed into a terminal as one argument. A line break would press Return in the middle of it;
    /// a backslash is read differently inside single quotes by fish than by the other shells, and no quoting is right for
    /// every shell (the person's login shell is not what the terminal runs); a leading dash would be read by the agent as
    /// an option.
    public enum TypingProblem: Sendable, Equatable {
        case empty, controlCharacter, misleadingCharacter, backslash, leadingDash, tooLong

        /// The sentence about the prompt as a whole.
        public var refusal: String {
            switch self {
            case .empty: return "the prompt is empty"
            case .controlCharacter: return "it has a line break or another control character"
            case .misleadingCharacter: return "it has a character that shows nothing or changes how the text reads (a direction override, a zero-width space, a tag character)"
            case .backslash: return "it has a backslash, which shells do not all read the same way inside quotes"
            case .leadingDash: return "it starts with a dash, which the agent would read as an option"
            case .tooLong: return "it is longer than \(AgentPreset.maxPromptBytes) bytes"
            }
        }

        /// The sentence about one name the prompt carries that causes this, or `nil` when no single name does.
        var aboutAName: String? {
            switch self {
            case .controlCharacter: return "its name has a line break or another control character"
            case .misleadingCharacter: return "its name has a character that shows nothing or changes how it reads (a direction override, a zero-width space, a tag character), and the agent would read what the person cannot see"
            case .backslash: return "naming it would put a backslash in the prompt (its name has one, or a quote and a space), which shells do not all read the same way inside quotes"
            case .leadingDash: return "its name would start the prompt with a dash, which the agent would read as an option"
            case .empty, .tooLong: return nil
            }
        }
    }

    public static func typingProblem(_ prompt: String) -> TypingProblem? {
        if prompt.allSatisfy(\.isWhitespace) { return .empty }
        if ShellQuoting.containsControlCharacter(prompt) { return .controlCharacter }
        // The tag characters spell ASCII that a language model reads and a person does not see, and so does a run of variation selectors: a file named with them would carry an instruction to the agent.
        if prompt.hasMisleadingCharacter() { return .misleadingCharacter }
        if prompt.unicodeScalars.contains("\\") { return .backslash }
        if prompt.unicodeScalars.first == "-" { return .leadingDash }
        if prompt.utf8.count > AgentPreset.maxPromptBytes { return .tooLong }
        return nil
    }

    /// Why a prompt cannot be typed into a terminal as one argument, or `nil`.
    public static func typingRefusal(_ prompt: String) -> String? {
        typingProblem(prompt)?.refusal
    }

    /// A name from the selection that the prompt would carry: what the person calls it, and the text that goes into the prompt.
    public struct Carried: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case file, folder, item }

        public var kind: Kind
        public var name: String
        public var text: String

        public init(kind: Kind, name: String, text: String) {
            self.kind = kind
            self.name = name
            self.text = text
        }

        /// How a message names it: the file, the folder, the selected item.
        public var subject: String {
            switch kind {
            case .file: return "the file " + name.jsonQuoted
            case .folder: return "the folder " + name.jsonQuoted
            case .item: return "the selected item " + name.jsonQuoted
            }
        }
    }

    /// The prompt with each placeholder filled from what the selection carries (`{files}` takes every file, one space between).
    public static func expand(_ template: String, carried: [Carried]) -> String {
        func text(_ kind: Carried.Kind) -> [String] { carried.filter { $0.kind == kind }.map(\.text) }
        return expand(template, files: text(.file).joined(separator: " "), folder: text(.folder).first ?? "", name: text(.item).first ?? "")
    }

    /// The name that makes `template`, filled in, impossible to type, when one does by itself: the first of those the template
    /// uses whose own text holds the problem (a line break, a backslash) or, for a leading dash, whose text begins the prompt.
    /// Names the person did not choose to put in the prompt (`{files}` is not in the template) are never blamed.
    public static func carriedNameBehind(_ problem: TypingProblem, template: String, carried: [Carried]) -> Carried? {
        let segments = segments(of: template)
        func used(_ kind: Carried.Kind) -> Bool {
            segments.contains { segment in
                switch (segment, kind) {
                case (.files, .file), (.folder, .folder), (.name, .item): return true
                default: return false
                }
            }
        }
        let candidates = carried.filter { used($0.kind) }
        switch problem {
        case .controlCharacter:
            return candidates.first { ShellQuoting.containsControlCharacter($0.text) }
        case .misleadingCharacter:
            return candidates.first { $0.text.hasMisleadingCharacter() }
        case .backslash:
            return candidates.first { $0.text.unicodeScalars.contains("\\") }
        case .leadingDash:
            let first: Carried.Kind?
            switch segments.first {
            case .files?: first = .file
            case .folder?: first = .folder
            case .name?: first = .item
            default: first = nil
            }
            return candidates.first { $0.kind == first && $0.text.unicodeScalars.first == "-" }
        case .empty, .tooLong:
            return nil
        }
    }
}
