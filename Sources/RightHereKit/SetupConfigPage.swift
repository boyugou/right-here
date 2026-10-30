import Foundation
import RightHereCore

/// A proposal an AI assistant made, with what applying it would do to the file as it is now.
public struct ProposalPreview: Sendable, Equatable, Identifiable {
    public var proposal: ConfigProposal
    /// The change as a dry run; `nil` when it can no longer be made (the file was edited since), with `problem` saying why.
    public var change: ConfigChange?
    public var problem: String?
    /// The digest of the text of the file the change was computed against, which applying it is held to.
    public var digest: String?

    public var id: String { proposal.id }

    public init(proposal: ConfigProposal, change: ConfigChange?, problem: String?, digest: String? = nil) {
        self.proposal = proposal
        self.change = change
        self.problem = problem
        self.digest = digest
    }
}

/// What the window's Config page shows for one file: its text, the proposals that wait, and the changes that can be taken back.
public struct ConfigPageState: Sendable, Equatable {
    public var target: ConfigTarget
    /// The file's text and the digest a save of it is guarded with; `nil` when there is no config yet or it cannot be read, with `problem` saying why.
    public var text: ConfigService.ConfigText?
    public var problem: String?
    public var proposals: [ProposalPreview]
    public var history: [ConfigService.HistoryItem]
    public var validation: ConfigDocument.Validation?
    /// The text above is the one a draft being typed started from, and the file has been changed by something else since: a save is refused until the person has seen it.
    public var fileMovedUnderDraft = false

    public init(target: ConfigTarget, text: ConfigService.ConfigText?, problem: String?, proposals: [ProposalPreview], history: [ConfigService.HistoryItem], validation: ConfigDocument.Validation?,
                fileMovedUnderDraft: Bool = false) {
        self.fileMovedUnderDraft = fileMovedUnderDraft
        self.target = target
        self.text = text
        self.problem = problem
        self.proposals = proposals
        self.history = history
        self.validation = validation
    }

    public static func == (left: ConfigPageState, right: ConfigPageState) -> Bool {
        left.target == right.target && left.text == right.text && left.problem == right.problem && left.proposals == right.proposals && left.history == right.history
            && left.fileMovedUnderDraft == right.fileMovedUnderDraft
    }
}

extension SetupActions {
    /// Reads what the Config page shows for the file of `target`, in one go: the text with the digest, the proposals with their previews, and the history.
    public func configPage(target: ConfigTarget) async -> ConfigPageState {
        let service = ConfigService(paths: paths)
        var text: ConfigService.ConfigText?
        var problem: String?
        var validation: ConfigDocument.Validation?
        do {
            text = try service.text(of: target)
            validation = try service.validation(for: target)
        } catch {
            problem = Self.describe(error)
        }
        let previews = service.pending().map { proposal -> ProposalPreview in
            do {
                let preview = try service.preview(proposal: proposal.id)
                return ProposalPreview(proposal: proposal, change: preview.change, problem: nil, digest: preview.digest)
            } catch {
                return ProposalPreview(proposal: proposal, change: nil, problem: Self.describe(error))
            }
        }
        return ConfigPageState(target: target, text: text, problem: problem, proposals: previews, history: service.history(of: target), validation: validation)
    }

    /// Saves the text the person edited for the file of `target`, when the file is still what they started from (`digest`); a text that does not read is refused, and said.
    public func saveConfigText(_ text: String, target: ConfigTarget, unchangedSince digest: String) async -> ConfigEditResult {
        let service = ConfigService(paths: paths)
        do {
            return ConfigEditResult(change: try service.apply([.replaceText(text)], target: target, actor: .window, unchangedSince: digest), notice: nil)
        } catch {
            return ConfigEditResult(change: nil, notice: .failed(Self.describe(error)))
        }
    }

    /// Takes back the last change of the file of `target`: the one the window made there (`ConfigChange.target`), not the file that decides a setting now, which an edit that took the setting
    /// out of this Mac's own file has changed. With `expecting`, the digest the change reported, only that change is taken back: when something else changed the file after it, nothing is.
    public func undoConfigEdit(target: ConfigTarget, expecting digest: String? = nil, replacing before: String? = nil) async -> ConfigEditResult {
        let service = ConfigService(paths: paths)
        do {
            return ConfigEditResult(change: try service.undo(target: target, expecting: digest, replacing: before), notice: nil)
        } catch ConfigService.Failure.notTheLast {
            return ConfigEditResult(change: nil, notice: .undoRefused)
        } catch {
            return ConfigEditResult(change: nil, notice: .failed(Self.describe(error)))
        }
    }

    /// Makes a proposal's change, as the person who has looked at it: the card showed it against the file whose digest this is, and a file that is not that any more is not changed.
    public func approveProposal(_ id: String, unchangedSince digest: String? = nil) async -> ConfigEditResult {
        do {
            return ConfigEditResult(change: try ConfigService(paths: paths).approve(id, actor: .window, unchangedSince: digest), notice: nil)
        } catch ConfigService.Failure.editedMeanwhile {
            return ConfigEditResult(change: nil, notice: .proposalStale)
        } catch {
            return ConfigEditResult(change: nil, notice: .failed(Self.describe(error)))
        }
    }

    /// Forgets a proposal without making it.
    public func dismissProposal(_ id: String) async -> SetupNotice? {
        do {
            try ConfigService(paths: paths).dismiss(id)
            return nil
        } catch {
            return .failed(Self.describe(error))
        }
    }
}
