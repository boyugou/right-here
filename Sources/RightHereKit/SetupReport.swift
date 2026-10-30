import Foundation
import RightHereCore

/// A piece of what `rh setup` puts in place, in the order it puts them there.
public enum SetupPiece: String, CaseIterable, Sendable, Encodable {
    case config
    case runnerScript
    case cliLink
    case services
    case finderExtension

    /// What the setup window calls it.
    public var titleKey: LocalizationKey {
        switch self {
        case .config: .appCheckConfig
        case .runnerScript: .appCheckRunner
        case .cliLink: .appSetupCommandLink
        case .services: .appCheckServices
        case .finderExtension: .appCheckExtension
        }
    }

    /// What the window says while it is being put in place.
    public var progressKey: LocalizationKey {
        switch self {
        case .config: .appSetupPhaseConfig
        case .runnerScript: .appSetupPhaseRunner
        case .cliLink: .appSetupPhaseLink
        case .services: .appSetupPhaseServices
        case .finderExtension: .appSetupPhaseExtension
        }
    }

    /// What the command line calls it, in English. (The setup window names the same pieces from its String Catalog, `titleKey`.)
    public var englishTitle: String {
        switch self {
        case .config: "Config file"
        case .runnerScript: "Runner script"
        case .cliLink: "Command link"
        case .services: "Quick Actions"
        case .finderExtension: "Finder extension"
        }
    }
}

/// What one piece came to.
public struct SetupStep: Sendable, Equatable {
    public enum Outcome: String, Sendable {
        /// It was not there and was made.
        case created
        /// It was there and was changed to be right.
        case updated
        /// It was there and right: nothing was done.
        case unchanged
        /// It was left out on purpose; the detail says why.
        case skipped
        /// It could not be done; the detail says why.
        case failed

        /// The word of the report's JSON. A dry run does nothing, so what it would do is not said as if it had been done: `would-create`,
        /// `would-update` and `would-fail`. What was not going to change anything (`unchanged`, `skipped`) is true of a dry run as it is.
        public func word(dryRun: Bool) -> String {
            guard dryRun else { return rawValue }
            switch self {
            case .created: return "would-create"
            case .updated: return "would-update"
            case .failed: return "would-fail"
            case .unchanged, .skipped: return rawValue
            }
        }
    }

    public var piece: SetupPiece
    public var outcome: Outcome
    /// A path, a count, or why it was skipped or failed. A sentence of the catalog where one fits, else the text as it is.
    public var detail: LocalizedMessage?

    public init(_ piece: SetupPiece, _ outcome: Outcome, detail: LocalizedMessage? = nil) {
        self.piece = piece
        self.outcome = outcome
        self.detail = detail
    }

    /// The step as one line of the command line's output. A dry run says what would happen.
    public func english(dryRun: Bool = false) -> String {
        let word: String
        switch outcome {
        case .created: word = dryRun ? "would be created" : "created"
        case .updated: word = dryRun ? "would be updated" : "updated"
        case .unchanged: word = "already in place"
        case .skipped: word = "skipped"
        case .failed: word = dryRun ? "would fail" : "failed"
        }
        return "\(piece.englishTitle): \(word)" + (detail.map { " (\($0.english()))" } ?? "")
    }
}

/// Something only the person can do, and exactly how.
public struct SetupNeed: Sendable, Equatable, Encodable {
    public enum Kind: String, Sendable, Encodable {
        /// Switch the Finder extension on in System Settings.
        case finderExtension
        /// Put `~/.local/bin` on the PATH of the terminal.
        case path
        /// Click Allow when macOS asks whether Right Here may control the terminal.
        case automation
        /// Fix the config file, which cannot be used (it is not TOML, cannot be read, or is a link to nowhere): setup never rewrites a config.
        case config
    }

    public var id: Kind
    /// What it is, in a sentence.
    public var text: String
    /// What to do, one step to a line, with the exact words and clicks.
    public var how: [String]

    public init(_ id: Kind, text: String, how: [String]) {
        self.id = id
        self.text = text
        self.how = how
    }
}

/// A command worth running next, and why.
public struct SetupNext: Sendable, Equatable, Encodable {
    public var command: String
    public var why: String

    public init(_ command: String, why: String) {
        self.command = command
        self.why = why
    }
}

/// What setting Right Here up did and what is left, as data and as text from one value: `rh setup --json` prints the data, the
/// command line prints `english()`, and the setup window reads the steps. A person and an AI agent therefore read the same thing.
public struct SetupReport: Sendable, Equatable, Encodable {
    /// One thing the person chose or the machine found, by the id the config uses.
    public struct Pick: Sendable, Equatable, Encodable {
        public enum Source: String, Sendable, Encodable {
            /// The person said it (a flag, or the first-run choice).
            case you
            /// Right Here found it on this Mac.
            case found
        }

        public var id: String
        public var name: String
        public var source: Source

        public init(id: String, name: String, source: Source) {
            self.id = id
            self.name = name
            self.source = source
        }
    }

    /// What the config that was written says.
    public struct Chosen: Sendable, Equatable, Encodable {
        public var terminal: Pick?
        public var editor: Pick?
        public var agents: [Pick]

        public init(terminal: Pick? = nil, editor: Pick? = nil, agents: [Pick] = []) {
            self.terminal = terminal
            self.editor = editor
            self.agents = agents
        }
    }

    /// No step failed; in a dry run, none would. (A check of the doctor that is not ok is not a failure of setup: it is in `checks`, and what
    /// the person has to do about it is in `needsUser`.)
    public var ok: Bool { !steps.contains { $0.outcome == .failed } }
    public var dryRun: Bool
    /// The folder `RH_HOME` names, when this was a trial.
    public var trialHome: String?
    public var steps: [SetupStep]
    /// Only when a config was written (or would be).
    public var chosen: Chosen?
    /// The edits that would make an existing config say what was asked for, which setup does not make itself.
    public var configEdits: [ConfigEdit]
    public var warnings: [String]
    public var needsUser: [SetupNeed]
    public var next: [SetupNext]
    /// The doctor's rows after the steps; `nil` when it was not asked, or in a dry run.
    public var checks: [DoctorCheck]?
    /// What the doctor's login shell said of the agents' commands, for the setup window (not in `rh setup --json`).
    public var shell: LoginShellFacts?

    public init(dryRun: Bool = false, trialHome: String? = nil, steps: [SetupStep] = [], chosen: Chosen? = nil, configEdits: [ConfigEdit] = [],
                warnings: [String] = [], needsUser: [SetupNeed] = [], next: [SetupNext] = [], checks: [DoctorCheck]? = nil) {
        self.dryRun = dryRun
        self.trialHome = trialHome
        self.steps = steps
        self.chosen = chosen
        self.configEdits = configEdits
        self.warnings = warnings
        self.needsUser = needsUser
        self.next = next
        self.checks = checks
    }

    public func step(_ piece: SetupPiece) -> SetupStep? {
        steps.first { $0.piece == piece }
    }

    /// Whether there is more to say of this report than that every step worked: a step failed, there is a warning, or what the person chose
    /// could not be applied (the config was there, so setup left it alone and listed the edits). The setup window shows the list of what
    /// setup did only when this is so, or when the checks are not all ok.
    public var hasNews: Bool { !ok || !warnings.isEmpty || !configEdits.isEmpty }

    /// What stands before the edits in the text, and in the setup window.
    public static let editsHeading = "The config file was left as it is, so this was not applied. To apply it, make exactly these edits and nothing else:"

    private enum CodingKeys: String, CodingKey {
        case ok, dryRun, trialHome, steps, chosen, configEdits, warnings, needsUser, next, checks
    }

    /// A step as the JSON has it. Whether it was done is the report's to say, not the step's: in a dry run the outcome and the text are
    /// the ones of what would be done, so a program that reads a step cannot take a plan for a result.
    private struct StepJSON: Encodable {
        var step: SetupStep
        var dryRun: Bool

        init(_ step: SetupStep, dryRun: Bool) {
            self.step = step
            self.dryRun = dryRun
        }

        private enum CodingKeys: String, CodingKey {
            case id, outcome, detail, text
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(step.piece, forKey: .id)
            try container.encode(step.outcome.word(dryRun: dryRun), forKey: .outcome)
            try container.encodeIfPresent(step.detail, forKey: .detail)
            try container.encode(step.english(dryRun: dryRun), forKey: .text)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ok, forKey: .ok)
        try container.encode(dryRun, forKey: .dryRun)
        try container.encodeIfPresent(trialHome, forKey: .trialHome)
        try container.encode(steps.map { StepJSON($0, dryRun: dryRun) }, forKey: .steps)
        try container.encodeIfPresent(chosen, forKey: .chosen)
        try container.encode(configEdits, forKey: .configEdits)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(needsUser, forKey: .needsUser)
        try container.encode(next, forKey: .next)
        try container.encodeIfPresent(checks, forKey: .checks)
    }

    // MARK: Text

    /// The report as the command line prints it, in English: the steps, what was chosen, what was not applied, what to know, what
    /// is left for the person, what to run next and the checks that are not ok.
    public func english() -> [String] {
        var lines = [dryRun ? "Right Here setup (a dry run: nothing was changed)" : "Right Here setup"]
        lines += steps.map { "  " + $0.english(dryRun: dryRun) }
        if let chosen {
            lines.append("")
            lines.append(dryRun ? "The config file would say:" : "The config file says:")
            lines.append("  terminal: " + (chosen.terminal.map { Self.describe($0, foundIn: "found on this Mac") } ?? "none found"))
            lines.append("  editor: " + (chosen.editor.map { Self.describe($0, foundIn: "found on this Mac") } ?? "none found"))
            lines.append("  agents: " + (chosen.agents.isEmpty ? "none" : chosen.agents.map { Self.describe($0, foundIn: "found in your login shell") }.joined(separator: ", ")))
        }
        if !configEdits.isEmpty {
            lines.append("")
            lines.append(Self.editsHeading)
            lines += configEdits.map { "  " + $0.instruction }
        }
        if !warnings.isEmpty {
            lines.append("")
            lines += warnings.map { "note: " + $0 }
        }
        if !needsUser.isEmpty {
            lines.append("")
            lines.append("Only you can do this:")
            for (index, need) in needsUser.enumerated() {
                lines.append("  \(index + 1). \(need.text)")
                lines += need.how.map { "     " + $0 }
            }
        }
        if let checks {
            let open = checks.filter { $0.status != .ok }
            lines.append("")
            if open.isEmpty {
                lines.append("Checks: all \(checks.count) ok.")
            } else {
                lines.append("Checks: \(checks.count - open.count) ok, \(open.count) to look at (`rh doctor` lists them all):")
                lines += open.flatMap { $0.englishLines().map { "  " + $0 } }
            }
        }
        if !next.isEmpty {
            lines.append("")
            lines.append("Next:")
            for item in next {
                lines.append("  " + item.command)
                lines.append("      " + item.why)
            }
        }
        return lines
    }

    private static func describe(_ pick: Pick, foundIn: String) -> String {
        "\(pick.name) (\(pick.id), " + (pick.source == .you ? "you chose it)" : "\(foundIn))")
    }
}
