import Foundation
import RightHereCore
import RightHereKit
import SwiftUI

struct FoldersPage: View {
    let model: SetupModel
    private let l10n = Localizer.system

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if model.snapshot == nil {
                ProgressRow(message: .appLoading)
            } else {
                pinned
                recent
                Text(l10n.string(.appFoldersNote))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var pinned: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(l10n.string(.appPinnedFolders))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button {
                    Task { await model.choosePinnedFolder() }
                } label: {
                    Label(l10n.string(.appPinFolder), systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(model.isWorking || model.isRefreshing)
            }
            if model.folders.pins.isEmpty {
                Prose(key: .appNoPinned, home: model.homePath)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
            } else {
                rows(model.folders.pins)
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(l10n.string(.appRecentFolders))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if !model.folders.recents.isEmpty {
                    Button(l10n.string(.appClearRecents)) { Task { await model.clearRecents() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.isWorking || model.isRefreshing)
                }
            }
            if model.folders.recents.isEmpty {
                Text(l10n.string(.appNoRecents))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                rows(model.folders.recents)
            }
        }
    }

    private func rows(_ paths: [String]) -> some View {
        VStack(spacing: 8) {
            ForEach(paths, id: \.self) { path in
                SavedFolderRow(path: path, home: model.homePath, pinned: model.folders.pins.contains(path),
                               disabled: model.isWorking || model.isRefreshing,
                               reveal: { Task { await model.revealFolder(path) } },
                               togglePin: {
                    Task {
                        if model.folders.pins.contains(path) { await model.unpin(path) }
                        else { await model.pin(path) }
                    }
                })
            }
        }
    }
}

private struct SavedFolderRow: View {
    let path: String
    let home: String
    let pinned: Bool
    let disabled: Bool
    let reveal: () -> Void
    let togglePin: () -> Void
    private let l10n = Localizer.system

    private var displayedPath: String { PathDisplay.abbreviatingHome(path.withControlCharactersEscaped, home: home) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: (path as NSString).lastPathComponent.withControlCharactersEscaped)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: PathDisplay.folder(path.withControlCharactersEscaped, home: home))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .accessibilityElement(children: .combine)
            .help(displayedPath)

            Spacer(minLength: 8)

            Button(action: reveal) {
                Label(l10n.string(.actionReveal), systemImage: "arrow.up.forward.square")
            }
            .labelStyle(.iconOnly)
            .help(l10n.string(.actionReveal))
            .accessibilityValue(displayedPath)

            Button(action: togglePin) {
                Label(l10n.string(pinned ? .appUnpin : .appPin), systemImage: pinned ? "pin.fill" : "pin")
            }
            .labelStyle(.iconOnly)
            .help(l10n.string(pinned ? .appUnpin : .appPin))
            .accessibilityValue(displayedPath)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(disabled)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(cornerRadius: 8)
        .accessibilityElement(children: .contain)
    }
}
