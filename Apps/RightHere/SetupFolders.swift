import Foundation
import RightHereCore
import RightHereKit
import SwiftUI

struct FoldersPage: View {
    @Bindable var model: SetupModel
    @FocusState private var searchFocused: Bool
    @State private var searchSelection: TextSelection?
    @Environment(\.setupPalette) private var palette
    private let l10n = Localizer.system

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if model.snapshot == nil {
                ProgressRow(message: .appLoading)
            } else if let problem = model.folders.problem {
                failure(problem)
            } else {
                savedFolders
                Text(l10n.string(.appFoldersNote))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var savedFolders: some View {
        let query = FolderSearch(model.folderQuery, locale: Locale(identifier: l10n.resolvedLanguage))
        let pins = query.filter(model.folders.pins, home: model.homePath)
        let recents = query.filter(model.folders.recents, home: model.homePath)
        if model.showsFolderSearch {
            HStack(spacing: 12) {
                searchField
                    .frame(minWidth: 160)
                pinButton
            }
        }
        if !query.isEmpty && pins.isEmpty && recents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(l10n.string(.appNoMatchingFolders))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(l10n.string(.appFindFoldersHint))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(l10n.string(.appClearSearch), action: clearSearch)
                    .buttonStyle(.bordered)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
            .accessibilityElement(children: .contain)
        } else {
            if query.isEmpty || !pins.isEmpty { pinned(pins) }
            if query.isEmpty || !recents.isEmpty { recent(recents, searching: !query.isEmpty) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            searchInput
            if !model.folderQuery.isEmpty {
                Button(action: clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.string(.appClearSearch))
                .help(l10n.string(.appClearSearch))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(minHeight: 28)
        .background(palette.canvas, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(searchFocused ? palette.accent : palette.rule, lineWidth: searchFocused ? 2 : 1))
        .task(id: model.folderSearchRequest) {
            guard model.folderSearchRequest > 0 else { return }
            // A fast section switch can request focus before the native field has joined the window.
            await Task.yield()
            guard !Task.isCancelled, model.canFindFolders else { return }
            searchFocused = true
            searchSelection = TextSelection(range: model.folderQuery.startIndex..<model.folderQuery.endIndex)
        }
    }

    @ViewBuilder private var searchInput: some View {
        #if PREVIEW
        // ImageRenderer cannot draw the native text field. Its static value occupies the same place in a canned preview.
        Text(verbatim: model.folderQuery.isEmpty ? l10n.string(.appFindFolders) : model.folderQuery)
            .foregroundStyle(model.folderQuery.isEmpty ? .secondary : .primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        #else
        TextField(l10n.string(.appFindFolders), text: $model.folderQuery, selection: $searchSelection)
            .textFieldStyle(.plain)
            .focused($searchFocused)
            .help(l10n.string(.appFindFoldersHint))
            .onExitCommand {
                if model.folderQuery.isEmpty { searchFocused = false }
                else { clearSearch() }
            }
        #endif
    }

    private func clearSearch() {
        searchSelection = nil
        model.folderQuery = ""
        searchFocused = true
    }

    private var pinButton: some View {
        Button {
            Task { await model.choosePinnedFolder() }
        } label: {
            Label(l10n.string(.appPinFolder), systemImage: "folder.badge.plus")
        }
        .buttonStyle(.bordered)
        .fixedSize()
        .disabled(model.isWorking || model.isRefreshing)
    }

    private func failure(_ problem: LocalizedMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(l10n.string(.appFoldersLoadFailed), systemImage: "exclamationmark.triangle")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            MessageViewportLayout(maximumHeight: 180) {
                ViewThatFits(in: .vertical) {
                    problemText(problem)
                    ScrollViewReader { proxy in
                        SetupPage(clipPreview: true) { problemText(problem).id("folder-problem") }
                            .onChange(of: problem) { proxy.scrollTo("folder-problem", anchor: .top) }
                    }
                    .frame(height: 180)
                }
            }
            .accessibilityRepresentation { Text(l10n.render(problem, isolatingValues: true)) }
            ViewThatFits(in: .horizontal) {
                HStack { recoveryActions }
                VStack(alignment: .leading) { recoveryActions }
            }
            .buttonStyle(.bordered)
            .disabled(model.isWorking || model.isRefreshing)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        .accessibilityElement(children: .contain)
    }

    private func problemText(_ problem: LocalizedMessage) -> some View {
        Text(verbatim: l10n.render(problem, isolatingValues: true))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var recoveryActions: some View {
        Button(l10n.string(.appTryAgain)) { Task { await model.retryFolders() } }
        Button(l10n.string(.actionReveal)) { Task { await model.revealSavedFolders() } }
    }

    private func pinned(_ paths: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(l10n.string(.appPinnedFolders))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if !model.showsFolderSearch { pinButton }
                else if !paths.isEmpty {
                    Text(paths.count.formatted())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if paths.isEmpty {
                Prose(key: .appNoPinned, home: model.homePath)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
            } else {
                rows(paths)
            }
        }
    }

    private func recent(_ paths: [String], searching: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(l10n.string(.appRecentFolders))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if !searching && !paths.isEmpty {
                    Button(l10n.string(.appClearRecents)) { Task { await model.clearRecents() } }
                        .font(.system(size: 11))
                        .frame(minHeight: 28)
                        .buttonStyle(SetupQuietButtonStyle())
                        .foregroundStyle(.secondary)
                        .controlSize(.small)
                        .disabled(model.isWorking || model.isRefreshing)
                }
            }
            if paths.isEmpty {
                Text(l10n.string(.appNoRecents))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                rows(paths)
            }
        }
    }

    private func rows(_ paths: [String]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(paths.enumerated()), id: \.element) { index, path in
                SavedFolderRow(path: path, home: model.homePath, pinned: model.folders.pins.contains(path),
                               disabled: model.isWorking || model.isRefreshing,
                               reveal: { Task { await model.revealFolder(path) } },
                               togglePin: {
                    Task {
                        if model.folders.pins.contains(path) { await model.unpin(path) }
                        else { await model.pin(path) }
                    }
                })
                if index < paths.count - 1 {
                    Divider().padding(.leading, 46).padding(.trailing, 14)
                }
            }
        }
        .panel()
    }
}

private struct SavedFolderRow: View {
    let path: String
    let home: String
    let pinned: Bool
    let disabled: Bool
    let reveal: () -> Void
    let togglePin: () -> Void
    @Environment(\.setupPalette) private var palette
    private let l10n = Localizer.system

    private var displayedPath: String { PathDisplay.abbreviatingHome(path.withControlCharactersEscaped, home: home) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 18))
                .foregroundStyle(palette.folder)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: (path as NSString).lastPathComponent.withControlCharactersEscaped)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: PathDisplay.folder(path.withControlCharactersEscaped, home: home))
                    .font(.system(size: 11))
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
                    .frame(width: 26, height: 28)
            }
            .labelStyle(.iconOnly)
            .help(l10n.string(.actionReveal))
            .accessibilityValue(displayedPath)

            Button(action: togglePin) {
                Label(l10n.string(pinned ? .appUnpin : .appPin), systemImage: pinned ? "pin.fill" : "pin")
                    .frame(width: 26, height: 28)
            }
            .labelStyle(.iconOnly)
            .help(l10n.string(pinned ? .appUnpin : .appPin))
            .accessibilityValue(displayedPath)
        }
        .buttonStyle(SetupQuietButtonStyle())
        .controlSize(.small)
        .disabled(disabled)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
