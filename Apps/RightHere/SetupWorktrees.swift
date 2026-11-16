import Foundation
import RightHereCore
import RightHereKit
import SwiftUI

/// The git worktrees Right Here made for agents, in one repository. Only those can be removed here, never forced.
struct WorktreesPage: View {
    let model: SetupModel
    @State private var pending: SetupModel.WorktreeRemovalRequest?
    private let l10n = Localizer.system

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Prose(key: .appWorktreesIntro, home: model.homePath)

            repositoryBar

            listing
        }
        .confirmationDialog(l10n.string(.appRemoveWorktreeTitle), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button(l10n.string(.appRemoveWorktreeConfirm), role: .destructive) {
                if let request = pending { Task { await model.remove(request) } }
                pending = nil
            }
            Button(l10n.string(.appCancel), role: .cancel) {
                pending = nil
            }
        } message: {
            if let request = pending {
                Text(verbatim: request.row.removalMessage(in: l10n, home: model.homePath))
            }
        }
    }

    private var repositoryBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(l10n.string(.appWorktreesRepository))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button {
                    Task { await model.chooseRepository() }
                } label: {
                    Label(l10n.string(.appWorktreesChoose), systemImage: "folder.badge.plus")
                }
                .disabled(model.isWorking || model.isRefreshing)
                if model.repository != nil {
                    Button {
                        Task { await model.refreshWorktrees() }
                    } label: {
                        Label(l10n.string(.appRefresh), systemImage: "arrow.clockwise")
                    }
                    .labelStyle(.iconOnly)
                    .help(l10n.string(.appRefresh))
                    .disabled(model.isWorking || model.isRefreshing || model.isLoadingWorktrees)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if let repository = model.repository {
                HStack(spacing: 10) {
                    if model.repositories.count > 1 {
                        Menu {
                            ForEach(model.repositories, id: \.path) { root in
                                Button { model.selectRepository(root) } label: {
                                    if root == repository {
                                        Label(displayPath(root), systemImage: "checkmark")
                                    } else {
                                        Text(verbatim: displayPath(root))
                                    }
                                }
                            }
                        } label: {
                            repositoryName(repository)
                        }
                        .disabled(model.isWorking || model.isRefreshing)
                        .accessibilityLabel(l10n.string(.appWorktreesRepository))
                        .accessibilityValue(displayPath(repository))
                    } else {
                        repositoryName(repository)
                    }
                    Spacer(minLength: 8)
                }
                .help(displayPath(repository))
                Text(verbatim: displayPath(repository))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .environment(\.layoutDirection, .leftToRight)
                    .help(displayPath(repository))
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private func repositoryName(_ root: URL) -> some View {
        Text(verbatim: root.lastPathComponent.withControlCharactersEscaped)
            .font(.body.weight(.medium))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func displayPath(_ root: URL) -> String {
        PathDisplay.folder(root.path.withControlCharactersEscaped, home: model.homePath)
    }

    @ViewBuilder private var listing: some View {
        switch model.worktrees {
        case .idle:
            Text(l10n.string(.appWorktreesNoRepository))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .loading:
            ProgressRow(message: .appLoading)
        case .failed(let text):
            VStack(alignment: .leading, spacing: 12) {
                Label(l10n.string(.appWorktreesLoadFailed), systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Button(l10n.string(.appTryAgain)) { Task { await model.refreshWorktrees() } }
                    .buttonStyle(.bordered)
                    .disabled(model.isWorking || model.isRefreshing)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
            .accessibilityElement(children: .contain)
        case .loaded(let rows) where rows.isEmpty:
            Text(l10n.string(.appWorktreesEmpty))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .loaded(let rows):
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    WorktreeLine(row: row, home: model.homePath, disabled: model.isWorking || model.isRefreshing,
                                 onReveal: { Task { await model.revealFolder(row.entry.path) } },
                                 onRemove: { pending = model.removalRequest(for: row) })
                    if index < rows.count - 1 {
                        Divider().padding(.leading, 46).padding(.trailing, 14)
                    }
                }
            }
            .panel()
        }
    }
}

/// One worktree: its branch, location, Finder reveal, and removal when Right Here made it.
struct WorktreeLine: View {
    let row: WorktreeRow
    let home: String
    let disabled: Bool
    let onReveal: () -> Void
    let onRemove: () -> Void
    @Environment(\.setupPalette) private var palette
    private let l10n = Localizer.system

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: row.isMainWorkingCopy ? "house" : "arrow.triangle.branch")
                .foregroundStyle(palette.folder)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(verbatim: row.branchTitle ?? l10n.string(.appWorktreeDetached))
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if row.isMainWorkingCopy {
                        tag(.appWorktreeMain)
                    } else if row.canBeRemoved {
                        tag(.appWorktreeMadeHere)
                    }
                }
                Text(verbatim: PathDisplay.folder(row.entry.path.withControlCharactersEscaped, home: home))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .accessibilityElement(children: .combine)
            .help(row.identity(in: l10n, home: home))

            Spacer(minLength: 8)

            Button(action: onReveal) {
                Label(l10n.string(.actionReveal), systemImage: "arrow.up.forward.square")
                    .frame(width: 26, height: 28)
            }
            .labelStyle(.iconOnly)
            .help(l10n.string(.actionReveal))
            .accessibilityValue(PathDisplay.abbreviatingHome(row.entry.path.withControlCharactersEscaped, home: home))

            if row.canBeRemoved {
                Button(l10n.string(.appRemoveWorktree), action: onRemove)
                    .accessibilityLabel(l10n.render(.appRemoveWorktreeNamed((row.entry.path as NSString).lastPathComponent.withControlCharactersEscaped), isolatingValues: true))
            }
        }
        .buttonStyle(SetupQuietButtonStyle())
        .controlSize(.small)
        .disabled(disabled)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func tag(_ key: LocalizationKey) -> some View {
        Text(l10n.string(key))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 4))
    }
}
