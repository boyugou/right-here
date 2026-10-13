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
        _detailsExpanded = State(initialValue: model.needsAttention)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            summary
            details
            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            actions
        }
        .padding(24)
        .frame(width: 560)
        .task { await model.refresh() }
        .onChange(of: model.needsAttention) { _, attention in
            if attention { detailsExpanded = true }
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
                    let open = model.checks.filter { $0.status != .ok }.map(CheckRow.localizedTitle(of:))
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
                Button(l10n.string(.appOpenConfig)) { Task { await model.openConfig() } }
                Button(l10n.string(.appCopySetupPrompt)) { model.copySetupPrompt() }
                Spacer()
                if model.checks.contains(where: { $0.id == "finder.extension" && $0.status != .ok }) {
                    Button(l10n.string(.appExtensionSettings)) { model.showExtensionSettings() }
                }
            }
        }
    }
}

private struct CheckRow: View {
    let check: DoctorCheck

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.localizedTitle(of: check)).font(.body.weight(.medium))
                if let detail = check.detail {
                    Text(Self.styled(detail)).font(.callout).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                }
                if let fix = check.fix {
                    Text(Self.styled(fix)).font(.callout).foregroundStyle(.primary).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        // One stop for VoiceOver per check (title, detail and fix read together) instead of three.
        .accessibilityElement(children: .combine)
        .accessibilityValue(Localizer.system.string(statusKey))
    }

    /// The doctor's titles are English (the command line is); the checks with a fixed title are translated here.
    /// Agent checks carry the agent's own name, and the detail and fix lines stay as the doctor wrote them.
    static func localizedTitle(of check: DoctorCheck) -> String {
        let keys: [String: LocalizationKey] = [
            "config": .appCheckConfig, "terminal.default": .appCheckTerminal, "editor.default": .appCheckEditor,
            "agents": .appCheckAgents, "claude.link": .appCheckClaudeLink, "finder.runner": .appCheckRunner,
            "services": .appCheckServices, "cli.link": .appCheckCLI, "finder.extension": .appCheckExtension,
            "finder.activity": .appCheckLastAction, "finder.chain": .appCheckChain, "finder.launch": .appCheckLaunch
        ]
        return keys[check.id].map { Localizer.system.string($0) } ?? check.title
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
