import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// MARK: Checks

/// Every check of the doctor, with what it found and what to do. The launch test is here, where its answer goes.
struct ChecksPage: View {
    let model: SetupModel
    @State private var showPassed: Bool
    @State private var showOptional: Bool
    private let l10n = Localizer.system

    init(model: SetupModel, expandDetails: Bool = false) {
        self.model = model
        _showPassed = State(initialValue: expandDetails)
        _showOptional = State(initialValue: expandDetails)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.checks.isEmpty {
                ProgressRow(message: .appChecking)
            } else {
                Text(l10n.string(model.statusTitle))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                if model.needsFirstRunChoice {
                    Button(l10n.string(.appSetupButton)) { model.select(.overview) }
                        .buttonStyle(.borderedProminent)
                }

                if !model.summary.attentionChecks.isEmpty {
                    checkList(model.summary.attentionChecks)
                        .panel()
                }

                if !model.summary.optionalChecks.isEmpty {
                    DisclosureGroup(isExpanded: $showOptional) {
                        checkList(model.summary.optionalChecks)
                    } label: {
                        groupTitle(.appChecksOptional, count: model.summary.optionalChecks.count)
                    }
                    .padding(14)
                    .panel()
                }

                if !model.summary.passedChecks.isEmpty {
                    DisclosureGroup(isExpanded: $showPassed) {
                        checkList(model.summary.passedChecks)
                    } label: {
                        groupTitle(.appChecksPassed, count: model.summary.passedChecks.count)
                    }
                    .padding(14)
                    .panel()
                }

                if model.configIsThere {
                    VStack(alignment: .leading, spacing: 12) {
                        Prose(key: .appTestLaunchHint, home: model.homePath)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) { maintenanceActions }
                                .fixedSize(horizontal: true, vertical: false)
                            VStack(alignment: .leading, spacing: 10) { maintenanceActions }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
                }
            }
        }
    }

    @ViewBuilder private var maintenanceActions: some View {
        Button {
            Task { await model.testLaunch() }
        } label: {
            Label(l10n.string(.appTestLaunch), systemImage: "play.circle")
        }
        .buttonStyle(.bordered)
        .disabled(model.isWorking || model.isRefreshing || model.summary.extensionNeedsSetup)

        Button {
            Task { await model.repair() }
        } label: {
            Label(l10n.string(.appInstallOrRepair), systemImage: "wrench.and.screwdriver")
        }
        .buttonStyle(.bordered)
        .disabled(model.isWorking || model.isRefreshing || model.locationProblem != nil)
    }

    private func groupTitle(_ key: LocalizationKey, count: Int) -> some View {
        HStack {
            Text(l10n.string(key))
                .font(.body.weight(.medium))
            Spacer()
            Text(verbatim: count.formatted())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func checkList(_ checks: [DoctorCheck]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                let action = check.setupAction(firstRun: model.needsFirstRunChoice)
                CheckRow(check: check, home: model.homePath, firstRun: model.needsFirstRunChoice,
                         action: action, disabled: model.isWorking || model.isRefreshing || (action == .repair && model.locationProblem != nil)) {
                    if let action { Task { await model.perform(action) } }
                }
                if index < checks.count - 1 {
                    Divider().padding(.horizontal, 14)
                }
            }
        }
    }
}

/// One check: its title, status, findings, notes and fix, with a separate recovery button.
struct CheckRow: View {
    let check: DoctorCheck
    let home: String
    /// There is no config file yet: the way in is the Set Up button of the first page, not Install or Repair.
    let firstRun: Bool
    let action: SetupCheckAction?
    let disabled: Bool
    let perform: () -> Void
    private let l10n = Localizer.system

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(check.title(in: l10n))
                        .font(.body.weight(.medium))
                    if let detail = check.detail {
                        line(detail, .secondary)
                    }
                    ForEach(Array(check.notes.enumerated()), id: \.offset) { _, note in
                        line(note, .secondary)
                    }
                    if let fix = check.fix {
                        line(inTheWindow(fix), .primary)
                    }
                }
                // Combining selectable text and overriding its value loses the detail, notes and fix on macOS.
                .accessibilityRepresentation {
                    Text(verbatim: accessibleDescription)
                }
                if let action {
                    Button(l10n.string(action.title), action: perform)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(disabled)
                        .padding(.top, 5)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    /// The fixes of the doctor are written for a terminal ("Run `rh setup`"); in the window the same thing is a button, and the person has no command to run.
    private func inTheWindow(_ fix: LocalizedMessage) -> LocalizedMessage {
        switch fix.key {
        case .doctorFixRunSetup, .doctorFixExtensionInstall: firstRun ? .appFixSetUp : .appFixRepair
        case .doctorFixExtensionClean: firstRun ? .appFixSetUp : .appFixExtensionClean
        case .doctorFixExtensionEnable: .appFixExtensionEnable
        default: fix
        }
    }

    /// One line of what the doctor says, in the system language, as long as it needs to be. A path or a command in a right-to-left
    /// sentence stays in one piece, and the text stays selectable (a fix is a command a person copies).
    private func line(_ message: LocalizedMessage, _ style: HierarchicalShapeStyle) -> some View {
        Text(styled(message))
            .font(.callout)
            .foregroundStyle(style)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func styled(_ message: LocalizedMessage) -> AttributedString {
        DoctorText.styled(l10n.render(message, isolatingValues: true), home: home)
    }

    /// The same localized words and abbreviated paths as the visible row, without its command-formatting marks.
    private var accessibleDescription: String {
        let messages = [check.detail].compactMap { $0 } + check.notes + [check.fix.map(inTheWindow)].compactMap { $0 }
        let lines = [check.title(in: l10n), l10n.string(statusKey)] + messages.map { String(styled($0).characters) }
        return lines.joined(separator: "\n")
    }

    private var statusKey: LocalizationKey {
        switch check.status {
        case .ok: .appStatusOK
        case .warn: .appStatusWarning
        case .fail: .appStatusProblem
        case .needsUser: .appStatusNeedsYou
        }
    }

    private var symbol: String {
        switch check.status {
        case .ok: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.octagon.fill"
        case .needsUser: "hand.raised.fill"
        }
    }

    private var color: Color {
        switch check.status {
        case .ok: .green
        case .warn: .orange
        case .fail: .red
        case .needsUser: .blue
        }
    }
}
