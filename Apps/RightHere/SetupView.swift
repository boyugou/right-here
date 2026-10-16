import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

/// The setup window: a sidebar of its sections and the section the person chose. It is for setup and status: the Finder
/// extension, the command line and the Shortcuts actions all work without it.
struct SetupView: View {
    @Bindable var model: SetupModel
    private let l10n = Localizer.system

    init(model: SetupModel) {
        self.model = model
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(.ultraThinMaterial)

            Divider()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)

                Divider()

                SetupPage {
                    page
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minWidth: 580, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 800, minHeight: 560)
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
    }

    private func sidebarRow(_ tab: SetupTab) -> some View {
        let selected = model.selectedTab == tab
        let badge = model.summary.badge(for: tab)
        var attention = ""
        if case .attention(let count)? = badge {
            attention = l10n.render(.appNeedAttentionCount(String(count)))
        }
        return Button {
            model.select(tab)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol(for: tab))
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)

                Text(l10n.string(title(for: tab)))
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)

                Spacer(minLength: 4)

                if case .attention(let count)? = badge {
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
                Text(l10n.string(statusTitle(model.summary.state)))
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
                .disabled(model.isRefreshing)
            }

            if model.isRefreshing {
                ProgressRow(message: .appRefreshing)
                    .font(.caption2)
            } else if let notice = model.notice {
                NoticeLine(notice: notice)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        switch model.summary.state {
        case .checking: .secondary
        case .allSet: .green
        case .needsAttention: .orange
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(l10n.string(title(for: model.selectedTab)))
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 12)

            // On the first run the card of the first section is the way in: it makes the config file from what is chosen. These two act on a
            // config that is there, and are not offered before the first look has found out whether it is.
            if model.configIsThere {
                Button {
                    Task { await model.openConfig() }
                } label: {
                    Label(l10n.string(.appOpenConfig), systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isWorking)

                Button {
                    Task { await model.repair() }
                } label: {
                    Label(l10n.string(.appInstallOrRepair), systemImage: "wrench.and.screwdriver")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isWorking || model.locationProblem != nil)
            }
        }
    }

    @ViewBuilder private var page: some View {
        switch model.selectedTab {
        case .overview: OverviewPage(model: model)
        case .menu: MenuPage(model: model)
        case .checks: ChecksPage(model: model)
        case .ai: AIPage(model: model)
        case .worktrees: WorktreesPage(model: model)
        case .folders: FoldersPage(model: model)
        }
    }

    // MARK: Names

    /// The catalog text that names a section, in the sidebar and above its page.
    private func title(for tab: SetupTab) -> LocalizationKey {
        switch tab {
        case .overview: .appTabOverview
        case .menu: .appMenuTitle
        case .checks: .appTabChecks
        case .ai: .appTabAI
        case .worktrees: .appTabWorktrees
        case .folders: .appTabFolders
        }
    }

    private func symbol(for tab: SetupTab) -> String {
        switch tab {
        case .overview: "house"
        case .menu: "contextualmenu.and.cursorarrow"
        case .checks: "checklist"
        case .ai: "sparkles"
        case .worktrees: "arrow.triangle.branch"
        case .folders: "folder"
        }
    }
}

/// A page of the window. The app scrolls it; the preview draws it whole, because ImageRenderer draws nothing inside a ScrollView.
struct SetupPage<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        #if PREVIEW
        content()
        #else
        ScrollView(.vertical) {
            content()
        }
        #endif
    }
}
