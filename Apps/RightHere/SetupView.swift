import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

/// The setup window: a sidebar of its sections and the section the person chose. It is for setup and status: the Finder
/// extension, the command line and the Shortcuts actions all work without it.
struct SetupView: View {
    @Bindable var model: SetupModel
    let expandCheckDetails: Bool
    let previewViewport: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    private let l10n = Localizer.system
    private var palette: SetupPalette { SetupPalette(dark: colorScheme == .dark, increasedContrast: contrast == .increased) }

    init(model: SetupModel, expandCheckDetails: Bool = false, previewViewport: Bool = false) {
        self.model = model
        self.expandCheckDetails = expandCheckDetails
        self.previewViewport = previewViewport
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 196)
                .background(palette.sidebar)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(l10n.string(.appNavigation))

            Divider()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 28)
                    .padding(.vertical, 15)

                Divider()

                if model.isWorking && !model.isChoosingFolder {
                    ProgressRow(message: model.isTestingLaunch ? .appTesting : model.isSettingUp ? .appSettingUp : .appLoading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28)
                        .padding(.top, 14)
                } else if let notice = model.notice, !model.isWorking {
                    NoticeBanner(notice: notice, model: model)
                        .padding(.horizontal, 28)
                        .padding(.top, 14)
                }

                ScrollViewReader { proxy in
                    SetupPage(clipPreview: previewViewport) {
                        page
                            .padding(28)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("setup-page-start")
                    }
                    // A different section starts at its introduction, not at the previous section's scroll offset.
                    .id(model.selectedTab)
                    .onChange(of: model.folderSearchRequest) {
                        if model.selectedTab == .folders { proxy.scrollTo("setup-page-start", anchor: .top) }
                    }
                }
            }
            .frame(minWidth: 604, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(palette.canvas)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(l10n.string(model.selectedTab.title))
        }
        .frame(minWidth: 800, minHeight: 560)
        .environment(\.setupPalette, palette)
        .tint(palette.accent)
        // The catalog can choose a different language from macOS's layout locale, including an English fallback.
        .environment(\.layoutDirection, l10n.isRightToLeft ? .rightToLeft : .leftToRight)
        .task {
            await model.refresh()
            await model.watchExtension()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refreshOnActivation() }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 24)

            VStack(spacing: 2) {
                ForEach([SetupTab.overview, .menu, .ai]) { tab in
                    sidebarRow(tab)
                }
                Divider().padding(.horizontal, 10).padding(.vertical, 16)
                ForEach([SetupTab.folders, .worktrees]) { tab in
                    sidebarRow(tab)
                }
                Divider().padding(.horizontal, 10).padding(.vertical, 16)
                sidebarRow(.checks)
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 8)

            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            Text(verbatim: AppIdentity.productName)
                .font(.system(size: 14, weight: .semibold))
        }
        .accessibilityElement(children: .combine)
    }

    private func sidebarRow(_ tab: SetupTab) -> some View {
        let selected = model.selectedTab == tab
        let count = tab == .checks ? model.attentionCount : 0
        var attention = ""
        if count > 0 {
            attention = l10n.render(.appNeedAttentionCount(String(count)))
        }
        return Button {
            model.select(tab)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 18)
                    .foregroundStyle(selected ? palette.accent : Color.secondary)
                    .accessibilityHidden(true)

                Text(l10n.string(tab.title))
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                if count > 0 {
                    Text(verbatim: String(count))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color.primary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected ? palette.selection : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(attention)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
                Text(l10n.string(model.statusTitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(l10n.string(.appRefresh))
                .accessibilityLabel(l10n.string(.appRefresh))
                .disabled(model.isRefreshing || model.isWorking)
            }

            if model.isRefreshing {
                ProgressRow(message: .appRefreshing)
                    .font(.caption2)
            }

            Text(verbatim: AppIdentity.version)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityLabel(l10n.render(.appVersion(AppIdentity.version)))
        }
    }

    private var statusColor: Color {
        if model.needsFirstRunChoice { return palette.accent }
        switch model.summary.state {
        case .checking: return .secondary
        case .allSet: return .green
        case .needsAttention: return .orange
        }
    }

    // MARK: Header

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                heading
                Spacer(minLength: 12)
                headerActions
            }
            VStack(alignment: .leading, spacing: 10) {
                heading
                headerActions
            }
        }
    }

    private var heading: some View {
        Text(l10n.string(model.selectedTab.title))
            .font(.system(size: 16, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var headerActions: some View {
        if model.configIsThere {
            Button {
                Task { await model.openConfig() }
            } label: {
                Label(l10n.string(.appOpenConfig), systemImage: "square.and.pencil")
            }
            .buttonStyle(SetupQuietButtonStyle())
            .foregroundStyle(.secondary)
            .controlSize(.small)
            .disabled(model.isWorking)
        }
    }

    @ViewBuilder private var page: some View {
        switch model.selectedTab {
        case .overview: OverviewPage(model: model)
        case .menu: MenuPage(model: model)
        case .checks: ChecksPage(model: model, expandDetails: expandCheckDetails)
        case .ai: AIPage(model: model)
        case .worktrees: WorktreesPage(model: model)
        case .folders: FoldersPage(model: model)
        }
    }

}

/// A page of the window. The app scrolls it; the preview draws it whole, because ImageRenderer draws nothing inside a ScrollView.
struct SetupPage<Content: View>: View {
    let content: () -> Content
    let clipPreview: Bool

    init(clipPreview: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.clipPreview = clipPreview
    }

    var body: some View {
        #if PREVIEW
        if clipPreview {
            GeometryReader { geometry in
                content()
                    .frame(width: geometry.size.width, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .clipped()
        } else {
            content()
        }
        #else
        ScrollView(.vertical) {
            content()
        }
        #endif
    }
}
