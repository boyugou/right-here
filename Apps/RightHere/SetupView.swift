import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

struct SetupView: View {
    let model: SetupModel
    private let l10n = Localizer.system
    @State private var detailsExpanded: Bool

    init(model: SetupModel) {
        self.model = model
        _detailsExpanded = State(initialValue: model.detailsStartOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            summary
            if model.extensionNeedsSetup { onboarding }
            details
            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            actions
        }
        .padding(24)
        .frame(width: 560)
        .task {
            await model.refresh()
            await model.watchExtension()
        }
        .onChange(of: model.needsAttention) { _, attention in
            // The first-run card already says what to do; the long list would push it off a small screen.
            if attention, !model.extensionNeedsSetup { detailsExpanded = true }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Right Here").font(.title2.weight(.semibold))
                Text(l10n.string(.appSubtitle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One line that says whether anything needs the person, so a healthy setup stays quiet.
    private var summary: some View {
        HStack(spacing: 10) {
            if model.checks.isEmpty {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: model.needsAttention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(model.needsAttention ? Color.orange : Color.green)
                    // The sentence beside it says the same; VoiceOver would read the symbol's name first.
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.string(model.needsAttention ? .appNeedsAttention : .appAllSet)).font(.body.weight(.medium))
                    // Which checks, so the banner is not a puzzle with the answer further down.
                    let open = model.checks.filter { $0.status != .ok }.map { $0.title(in: l10n) }
                    if !open.isEmpty {
                        Text(open.formatted(.list(type: .and, width: .narrow))).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    /// First run: three steps in order, and a way around the extension. Shown until the extension is on.
    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.string(.appOnboardTitle)).font(.headline)
            step(1, title: l10n.string(.appStepOneTitle), body: l10n.string(.appStepOneBody),
                 done: model.check(.terminalDefault)?.status == .ok && model.check(.editorDefault)?.status == .ok) {
                ForEach([CheckID.terminalDefault, .editorDefault], id: \.self) { id in
                    if let detail = model.check(id)?.detail {
                        Text(CheckRow.styled(l10n.render(detail, isolatingValues: true))).font(.callout).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button(l10n.string(.appOpenConfig)) { Task { await model.openConfig() } }
            }
            step(2, title: l10n.string(.appStepTwoTitle), body: l10n.string(.appStepTwoBody), done: false) {
                Button(l10n.string(.appExtensionSettings)) { model.showExtensionSettings() }
            }
            step(3, title: l10n.string(.appStepThreeTitle), body: l10n.string(.appStepThreeBody), done: false) {
                Button(l10n.string(.appTestLaunch)) { Task { await model.testTerminalLaunch() } }
                    .disabled(model.isWorking)
            }
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.string(.appQuickActionsTitle)).font(.callout.weight(.medium))
                Text(l10n.string(.appQuickActionsBody)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func step(_ number: Int, title: String, body: String, done: Bool, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.accentColor)
                if done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text(number.formatted()).font(.caption.weight(.bold)).foregroundStyle(.white)
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.body.weight(.medium))
                Text(body).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                content()
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l10n.render(.appStepLabel(number.formatted(), title)))
    }

    private var details: some View {
        DisclosureGroup(l10n.string(.appDetails), isExpanded: $detailsExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.checks.enumerated()), id: \.element.id) { index, check in
                    CheckRow(check: check)
                    if index < model.checks.count - 1 { Divider() }
                }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 8)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(l10n.string(.appInstallOrRepair)) { Task { await model.installOrRepair() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isWorking)
                Button(l10n.string(.appTestLaunch)) { Task { await model.testTerminalLaunch() } }
                    .disabled(model.isWorking)
                if model.isWorking && !model.checks.isEmpty { ProgressView().controlSize(.small) }
                Spacer()
            }
            HStack {
                // The first-run card has its own buttons for these two.
                if !model.extensionNeedsSetup { Button(l10n.string(.appOpenConfig)) { Task { await model.openConfig() } } }
                Button(l10n.string(.appCopySetupPrompt)) { model.copySetupPrompt() }
                Spacer()
            }
        }
    }
}

private struct CheckRow: View {
    let check: DoctorCheck
    private let l10n = Localizer.system

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title(in: l10n)).font(.body.weight(.medium))
                if let detail = check.detail {
                    line(detail, .secondary).textSelection(.enabled)
                }
                ForEach(Array(check.notes.enumerated()), id: \.offset) { _, note in
                    line(note, .secondary).textSelection(.enabled)
                }
                if let fix = check.fix {
                    line(fix, .primary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        // One stop for VoiceOver per check (title, detail and fix read together) instead of three.
        .accessibilityElement(children: .combine)
        .accessibilityValue(l10n.string(statusKey))
    }

    /// One line of what the doctor says, in the system language, as long as it needs to be. A path or a command in it
    /// stays in one piece in a right-to-left sentence.
    private func line(_ message: LocalizedMessage, _ style: HierarchicalShapeStyle) -> some View {
        Text(Self.styled(l10n.render(message, isolatingValues: true))).font(.callout).foregroundStyle(style).fixedSize(horizontal: false, vertical: true)
    }

    private var statusKey: LocalizationKey {
        switch check.status {
        case .ok: return .appStatusOK
        case .warn: return .appStatusWarning
        case .fail: return .appStatusProblem
        case .needsUser: return .appStatusNeedsYou
        }
    }

    /// The doctor writes commands between backticks (it prints for a terminal too): show them as
    /// code instead of with the backticks.
    static func styled(_ text: String) -> AttributedString {
        var result = AttributedString()
        for (index, part) in abbreviatingHome(text).split(separator: "`", omittingEmptySubsequences: false).enumerated() {
            var piece = AttributedString(String(part))
            if index % 2 == 1 { piece.font = .system(.callout, design: .monospaced) }
            result += piece
        }
        return result
    }

    /// Paths read as `~/...`: shorter, and a screenshot of the window does not show the account name.
    static func abbreviatingHome(_ text: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard home.count > 1 else { return text }
        return text.replacingOccurrences(of: home + "/", with: "~/")
    }

    private var symbol: String {
        switch check.status {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        case .needsUser: return "hand.raised.fill"
        }
    }

    private var color: Color {
        switch check.status {
        case .ok: return .green
        case .warn: return .orange
        case .fail: return .red
        case .needsUser: return .blue
        }
    }
}
