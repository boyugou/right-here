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
    private let l10n = Localizer.system

    init(model: SetupModel, expandCheckDetails: Bool = false, previewViewport: Bool = false) {
        self.model = model
        self.expandCheckDetails = expandCheckDetails
        self.previewViewport = previewViewport
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(.ultraThinMaterial)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(l10n.string(.appNavigation))

            Divider()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)

                Divider()

                if model.isWorking && !model.isChoosingFolder {
                    ProgressRow(message: model.isTestingLaunch ? .appTesting : model.isSettingUp ? .appSettingUp : .appLoading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 14)
                } else if let notice = model.notice, !model.isWorking {
                    NoticeBanner(notice: notice, model: model)
                        .padding(.horizontal, 24)
                        .padding(.top, 14)
                }

                ScrollViewReader { proxy in
                    SetupPage(clipPreview: previewViewport) {
                        page
                            .padding(24)
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
            .frame(minWidth: 580, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(l10n.string(model.selectedTab.title))
        }
        .frame(minWidth: 800, minHeight: 560)
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
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 12)

            VStack(spacing: 2) {
                ForEach(SetupTab.allCases) { tab in
                    sidebarRow(tab)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)

            Spacer(minLength: 8)

            Divider()
                .padding(.horizontal, 12)

            footer
                .padding(12)
        }
    }

    private var brand: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(verbatim: AppIdentity.productName)
                        .font(.headline.weight(.bold))
                    Text(verbatim: AppIdentity.version)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(l10n.render(.appVersion(AppIdentity.version)))
                }
                Text(l10n.string(.appSubtitle))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)

                Text(l10n.string(tab.title))
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)

                Spacer(minLength: 4)

                if count > 0 {
                    Text(verbatim: String(count))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.3), in: Capsule())
                        .foregroundStyle(Color.primary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(attention)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(l10n.string(model.statusTitle))
                    .font(.caption.weight(.medium))
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
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        if model.needsFirstRunChoice { return .accentColor }
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
            .font(.title2.weight(.bold))
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
            .buttonStyle(.bordered)
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
