import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// The first run of the setup window: the choice of terminal, editor and agents before any config file exists, and the list of what
// setup did. The words are catalog entries (`Localizer`); a name of an app or an agent is `Text(verbatim:)`.

/// Lays its children out in rows that wrap, starting at the leading edge: from the right in a right-to-left language.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let mirrored = subviews.layoutDirection == .rightToLeft
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            let left = mirrored ? bounds.maxX - x - size.width : bounds.minX + x
            view.place(at: CGPoint(x: left, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// One thing to choose: a round mark when exactly one can be chosen, a square one when several can. What it is called is a name.
struct ChoiceChip: View {
    let title: String
    let selected: Bool
    let multiple: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: mark)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(.callout)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var mark: String {
        switch (multiple, selected) {
        case (true, true): "checkmark.square.fill"
        case (true, false): "square"
        case (false, true): "largecircle.fill.circle"
        case (false, false): "circle"
        }
    }
}

/// The app runs from a disk image, another volume or the temporary copy macOS makes of a download. Said before anything is tried, with what to do: the
/// buttons that would set up are off until the app is somewhere that stays.
struct LocationCard: View {
    private let l10n = Localizer.system

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.string(.appLocationTitle))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(l10n.string(.appLocationBody))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.5), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
}

/// The card of a first run: the terminals and editors installed on this Mac, the agents Right Here knows (the ones found are checked),
/// and the button that sets everything up with what is chosen. It is shown only while there is no config file: the choice is written
/// because the file does not exist yet, and nothing here ever changes a file that is there.
struct FirstRunChooser: View {
    @Bindable var model: SetupModel
    private let l10n = Localizer.system

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.string(.appSetupTitle))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(l10n.string(.appSetupBody))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let offer = model.offer {
                choice(.appCheckTerminal) {
                    FlowLayout(spacing: 8) {
                        ForEach(offer.terminals) { option in
                            ChoiceChip(title: option.name, selected: model.selectedTerminal == option.id, multiple: false) {
                                model.selectedTerminal = option.id
                            }
                        }
                    }
                }
                choice(.appCheckEditor) {
                    FlowLayout(spacing: 8) {
                        ForEach(offer.editors) { option in
                            ChoiceChip(title: option.name, selected: model.selectedEditor == option.id, multiple: false) {
                                model.selectedEditor = option.id
                            }
                        }
                    }
                }
                choice(.appSetupAgents, hint: .appSetupAgentsHint) {
                    VStack(alignment: .leading, spacing: 10) {
                        agentChips(offer.agents.filter(\.available))
                        let missing = offer.agents.filter { !$0.available }
                        if !missing.isEmpty {
                            Text(l10n.string(.appSetupNotFound))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            agentChips(missing)
                        }
                    }
                }
            } else {
                ProgressRow(message: .appChecking)
            }

            HStack(spacing: 12) {
                Button(l10n.string(.appSetupButton)) { Task { await model.setUp() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isWorking || model.offer == nil || model.locationProblem != nil)
                if model.isSettingUp {
                    ProgressRow(message: .appSettingUp)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1.5))
    }

    private func agentChips(_ agents: [SetupOffer.Option]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(agents) { agent in
                ChoiceChip(title: agent.name, selected: model.selectedAgents.contains(agent.id), multiple: true) {
                    if !model.selectedAgents.insert(agent.id).inserted { model.selectedAgents.remove(agent.id) }
                }
            }
        }
    }

    private func choice<Content: View>(_ title: LocalizationKey, hint: LocalizationKey? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.string(title))
                .font(.callout.weight(.medium))
            content()
            if let hint {
                Text(l10n.string(hint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l10n.string(title))
    }
}

/// What the first setup did: each thing it put in place, with a mark. The way it came out is said only when it is not simply "created",
/// and the reason when a step was skipped or failed, so that a setup that went well is one calm line. What the person chose that could
/// not be applied (the config was there, and a config is never rewritten) is said with the edits that would apply it, and every warning of
/// the report is said: both are English as the command line says them, since they are the report's own sentences.
struct SetupDonePanel: View {
    let report: SetupReport
    let home: String
    /// Whether the Finder extension is switched on now. Registering it is what setup does; the switch in System Settings is the person's, and the
    /// mark of the extension says so while it is off, directly above the step of the card that tells them where.
    let extensionIsOn: Bool
    private let l10n = Localizer.system

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.string(.appSetupDoneTitle))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 16) {
                ForEach(Array(report.steps.enumerated()), id: \.offset) { _, step in
                    SetupStepMark(step: step, home: home, extensionIsOn: extensionIsOn)
                }
            }
            ForEach(Array(report.steps.enumerated()), id: \.offset) { _, step in
                if let reason = SetupStepMark.reason(step) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(DoctorText.styled(l10n.string(SetupStepMark.title(step.piece)), home: home))
                            .font(.callout.weight(.medium))
                        Text(DoctorText.styled(l10n.render(reason, isolatingValues: true), home: home))
                            .font(.callout)
                            .foregroundStyle(step.outcome == .failed ? Color.red : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            if !report.configEdits.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    note(SetupReport.editsHeading, symbol: "pencil.line", color: .accentColor)
                    ForEach(Array(report.configEdits.enumerated()), id: \.offset) { _, edit in
                        Text(DoctorText.styled(l10n.render(.doctorVerbatim(Fence.withoutMarks(edit.instruction)), isolatingValues: true), home: home))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.leading, 22)
                    }
                }
            }
            ForEach(Array(report.warnings.enumerated()), id: \.offset) { _, warning in
                note(warning, symbol: "exclamationmark.triangle.fill", color: .orange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}

extension SetupDonePanel {
    /// A sentence of the report beside a mark, as it is: the report's own words, not the catalog's.
    private func note(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(DoctorText.styled(l10n.render(.doctorVerbatim(Fence.withoutMarks(text)), isolatingValues: true), home: home))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

/// One thing setup put in place: a mark, its name, and how it came out when that is worth saying.
struct SetupStepMark: View {
    let step: SetupStep
    let home: String
    let extensionIsOn: Bool
    private let l10n = Localizer.system

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(DoctorText.styled(l10n.string(Self.title(step.piece)), home: home))
                .font(.callout)
            if let remark {
                Text(remark)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        // One stop for VoiceOver: the name, then how it came out.
        .accessibilityElement(children: .combine)
    }

    /// How it came out, when "created" does not say it: updated, already in place, skipped, failed, or how many Quick Actions.
    private var remark: String? {
        if step.piece == .finderExtension, !extensionIsOn, step.outcome == .created || step.outcome == .updated || step.outcome == .unchanged {
            return l10n.render(.doctorExtensionDisabled)
        }
        switch step.outcome {
        case .created:
            guard step.piece == .services, let detail = step.detail else { return nil }
            return l10n.render(detail)
        case .updated: return l10n.string(.appSetupUpdated)
        case .unchanged: return l10n.string(.appSetupUnchanged)
        case .skipped: return l10n.string(.appSetupSkipped)
        case .failed: return l10n.string(.appSetupFailed)
        }
    }

    /// Why a step was skipped or failed, in its own words; nothing for a step that worked.
    static func reason(_ step: SetupStep) -> LocalizedMessage? {
        step.outcome == .skipped || step.outcome == .failed ? step.detail : nil
    }

    static func title(_ piece: SetupPiece) -> LocalizationKey {
        switch piece {
        case .config: .appCheckConfig
        case .runnerScript: .appCheckRunner
        case .cliLink: .appSetupCommandLink
        case .services: .appCheckServices
        case .finderExtension: .appCheckExtension
        }
    }

    private var symbol: String {
        switch step.outcome {
        case .created, .updated, .unchanged: "checkmark.circle.fill"
        case .skipped: "minus.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch step.outcome {
        case .created, .updated, .unchanged: .green
        case .skipped: .secondary
        case .failed: .red
        }
    }
}
