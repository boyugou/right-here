import RightHereKit
import SwiftUI

struct SetupView: View {
    let model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.checks.enumerated()), id: \.element.id) { index, check in
                    CheckRow(check: check)
                    if index < model.checks.count - 1 { Divider() }
                }
                if model.checks.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            actions
        }
        .padding(24)
        .frame(width: 560)
        .task { await model.refresh() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "contextualmenu.and.cursorarrow")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.tint)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("Right Here").font(.title2.weight(.semibold))
                Text("Send a folder or selection to your terminals, editors and AI agents.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        HStack {
            Button("Install or Repair") { Task { await model.installOrRepair() } }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isWorking)
            Button("Open Config") { Task { await model.openConfig() } }
            Button("Copy Setup Prompt for AI") { model.copySetupPrompt() }
            Spacer()
            if model.checks.contains(where: { $0.id == "finder.extension" && $0.status != .ok }) {
                Button("Finder Extension Settings") { model.showExtensionSettings() }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title).font(.body.weight(.medium))
                if let detail = check.detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                }
                if let fix = check.fix {
                    Text(fix).font(.callout).foregroundStyle(color).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
