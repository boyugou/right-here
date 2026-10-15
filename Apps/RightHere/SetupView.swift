import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

struct SetupView: View {
    @Bindable var model: SetupModel
    private let l10n = Localizer.system

    init(model: SetupModel) {
        self.model = model
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebarSection
                .frame(width: 220)
                .background(.ultraThinMaterial)

            Divider()

            detailSection
                .frame(minWidth: 580, maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 800, minHeight: 560)
        .task {
            await model.refresh()
            await model.watchExtension()
        }
    }

    // MARK: - Sidebar

    private var sidebarSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand header
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Right Here")
                            .font(.headline.weight(.bold))
                        Text("v0.2.0")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(.quaternary.opacity(0.6), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    Text(l10n.string(.appSubtitle))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 12)

            // Navigation List
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    sidebarItem(.overview, title: tabTitle(.overview), icon: "sparkles")
                    sidebarItem(.menu, title: tabTitle(.menu), icon: "menubar.dock.rectangle")
                    sidebarItem(.ai, title: tabTitle(.ai), icon: "cpu")
                    sidebarItem(.worktrees, title: tabTitle(.worktrees), icon: "arrow.triangle.branch", badge: model.worktrees.count > 0 ? "\(model.worktrees.count)" : nil)
                    sidebarItem(.bookmarks, title: tabTitle(.bookmarks), icon: "bookmark", badge: model.pins.count > 0 ? "\(model.pins.count)" : nil)
                    sidebarItem(.diagnostics, title: tabTitle(.diagnostics), icon: "stethoscope", badge: model.needsAttention ? "!" : nil, badgeColor: .orange)
                    sidebarItem(.config, title: tabTitle(.config), icon: "gearshape")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }

            Spacer(minLength: 8)

            Divider()
                .padding(.horizontal, 12)

            // Sidebar Footer Status Card
            sidebarFooterCard
                .padding(12)
        }
    }

    private func sidebarItem(_ tab: SetupTab, title: String, icon: String, badge: String? = nil, badgeColor: Color = .blue) -> some View {
        let isSelected = model.selectedTab == tab
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                model.selectedTab = tab
            }
        }) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                Spacer(minLength: 4)

                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(isSelected ? 0.2 : 0.12), in: Capsule())
                        .foregroundStyle(badgeColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sidebarFooterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.needsAttention ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
                Text(l10n.string(model.needsAttention ? .appNeedsAttention : .appAllSet))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(model.needsAttention ? Color.orange : Color.green)
                Spacer()
                Button(action: { Task { await model.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if model.isWorking {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Refreshing…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let message = model.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func tabTitle(_ tab: SetupTab) -> String {
        switch tab {
        case .overview:
            switch l10n.resolvedLanguage {
            case "zh-Hans", "zh-Hant": return "概览"
            case "ja": return "概要"
            case "ko": return "개요"
            case "de": return "Übersicht"
            case "fr": return "Aperçu"
            case "es": return "Resumen"
            case "it": return "Panoramica"
            default: return "Overview"
            }
        case .menu:
            return l10n.string(.appMenuTitle)
        case .ai:
            return "AI & MCP"
        case .worktrees:
            switch l10n.resolvedLanguage {
            case "zh-Hans", "zh-Hant": return "Git 工作区"
            case "ja": return "Git ワークツリー"
            default: return "Git Worktrees"
            }
        case .bookmarks:
            switch l10n.resolvedLanguage {
            case "zh-Hans", "zh-Hant": return "书签与最近"
            default: return "Bookmarks"
            }
        case .diagnostics:
            return l10n.string(.appDetails)
        case .config:
            switch l10n.resolvedLanguage {
            case "zh-Hans", "zh-Hant": return "配置"
            default: return "Configuration"
            }
        }
    }

    // MARK: - Detail Content Section

    private var detailSection: some View {
        VStack(spacing: 0) {
            detailToolbar
                .padding(.horizontal, 24)
                .padding(.vertical, 14)

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    switch model.selectedTab {
                    case .overview:
                        overviewTab
                    case .menu:
                        menuTab
                    case .ai:
                        aiTab
                    case .worktrees:
                        worktreesTab
                    case .bookmarks:
                        bookmarksTab
                    case .diagnostics:
                        diagnosticsTab
                    case .config:
                        configTab
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var detailToolbar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(tabTitle(model.selectedTab))
                .font(.title2.weight(.bold))

            Spacer()

            Button(action: { Task { await model.openConfig() } }) {
                Label(l10n.string(.appOpenConfig), systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(action: { Task { await model.installOrRepair() } }) {
                Label(l10n.string(.appInstallOrRepair), systemImage: "wrench.and.screwdriver")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(model.isWorking)
        }
    }

    // MARK: - Tab 1: Overview

    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            if model.extensionNeedsSetup {
                onboardingCard
            } else {
                statusHeroCard
            }

            appsConfiguredRow

            quickActionsCard
        }
    }

    private var statusHeroCard: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(model.needsAttention ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: model.needsAttention ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(model.needsAttention ? Color.orange : Color.green)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.string(model.needsAttention ? .appNeedsAttention : .appAllSet))
                    .font(.headline.weight(.semibold))
                Text(model.needsAttention
                     ? "Some settings or permissions need adjustment. Open Diagnostics for details."
                     : "Right Here is registered in Finder. Right-click any folder or file to act on it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if model.extensionNeedsSetup {
                Button(l10n.string(.appExtensionSettings)) {
                    model.showExtensionSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "1.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text(l10n.string(.appStepOneTitle))
                    .font(.headline.weight(.semibold))
            }

            Text("Right Here needs to be enabled under macOS System Settings so its actions appear in Finder.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button(action: { model.showExtensionSettings() }) {
                Label(l10n.string(.appExtensionSettings), systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1.5)
        )
    }

    private var appsConfiguredRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Configured Applications")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                appSummaryCard(title: "Default Terminal", name: model.defaultTerminalName, icon: "terminal.fill", role: "Splits & Tabs Supported")
                appSummaryCard(title: "Default Editor", name: model.defaultEditorName, icon: "chevron.left.forwardslash.chevron.right", role: "IDE & Text Editor")
            }
        }
    }

    private func appSummaryCard(title: String, name: String, icon: String, role: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.body.weight(.semibold))
                Text(role)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                actionButton(title: l10n.string(.appTestLaunch), icon: "play.circle") {
                    Task { await model.testTerminalLaunch() }
                }
                actionButton(title: l10n.string(.appCopySetupPrompt), icon: "doc.on.doc") {
                    model.copySetupPrompt()
                }
                actionButton(title: l10n.string(.appOpenConfig), icon: "gearshape") {
                    Task { await model.openConfig() }
                }
            }
        }
    }

    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 2: Menu Preview

    private var menuTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Finder Context Menu Preview")
                .font(.headline.weight(.semibold))
            Text("Shows the actions that appear when right-clicking a folder in Finder.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(model.menuRows) { row in
                    MenuLine(row: row, image: model.image(for: row.icon)) {
                        model.toggleSubmenu(row.id)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }

    // MARK: - Tab 3: AI & MCP

    private var aiTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Agents Showcase
            VStack(alignment: .leading, spacing: 12) {
                Text("Supported AI Agents & Harnesses")
                    .font(.headline.weight(.semibold))
                Text("Launch coding agents in your authenticated login shell with PATH, nvm, and aliases:")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
                    ForEach(model.knownAgents) { agent in
                        agentCard(agent)
                    }
                }
            }

            // MCP Configuration
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Model Context Protocol (MCP)", systemImage: "point.3.filled.connected.trianglepath.dotted")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    badgePill("stdio", color: .blue)
                }
                Text("Connect Claude Desktop, Cursor, Zed, or Windsurf directly via stdio:")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                codeBlock("""
{
  "mcpServers": {
    "right-here": {
      "command": "rh",
      "args": ["mcp"]
    }
  }
}
""")
                Button("Copy MCP Configuration") {
                    model.copyMCPConfig()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

            // Claude Code Plugin
            VStack(alignment: .leading, spacing: 10) {
                Label("Claude Code Plugin", systemImage: "puzzlepiece.extension")
                    .font(.headline.weight(.semibold))
                Text("Install the Right Here workspace plugin in Claude Code:")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                codeBlock("/plugin marketplace add boyugou/right-here\n/plugin install right-here@right-here")

                Button("Copy Plugin Install Command") {
                    model.copyClaudePluginCommand()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }

    private func agentCard(_ agent: AgentDescriptor) -> some View {
        let iconName: String = {
            switch agent.id {
            case "claude": return "brain.head.profile"
            case "codex": return "terminal"
            case "agy": return "sparkles"
            case "gemini": return "sparkle"
            case "opencode": return "chevron.left.forwardslash.chevron.right"
            case "kimi": return "moon.stars"
            case "muse": return "music.note.list"
            case "goose": return "bird"
            case "copilot": return "airplane"
            case "cody": return "curlybraces"
            default: return "command"
            }
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(Color.accentColor)
                Text(agent.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
            }
            Text(agent.command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            if let guide = agent.instructionFile {
                Text(guide)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Tab 4: Git Worktrees

    private var worktreesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Isolated Git Worktrees")
                    .font(.headline.weight(.semibold))
                Text("Run AI agents and experimental tasks in an isolated git branch without touching your working tree or uncommitted files.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("CLI Usage:")
                    .font(.caption.weight(.semibold))
                Text("`rh run agent.agy --worktree` or `rh run agent.claude --worktree my-feature`")
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            }

            if model.worktrees.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No active Right Here worktrees found in the current repository.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            } else {
                VStack(spacing: 8) {
                    ForEach(model.worktrees, id: \.path) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(entry.branch ?? "detached")
                                        .font(.body.weight(.semibold))
                                    if entry.isRightHere {
                                        badgePill("rh", color: .purple)
                                    }
                                }
                                Text(entry.path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Remove") {
                                Task { await model.removeWorktree(entry.path) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                }
            }
        }
    }

    // MARK: - Tab 5: Bookmarks

    private var bookmarksTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Pinned Folders
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Pinned Folders")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Text("\(model.pins.count)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(.blue)
                }
                Text("Folders pinned for instant Finder menu access (`rh pin <path>`).")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if model.pins.isEmpty {
                    Text("No pinned folders. Pin any directory using `rh pin <path>`.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(12)
                } else {
                    VStack(spacing: 6) {
                        ForEach(model.pins, id: \.self) { pin in
                            HStack(spacing: 10) {
                                Image(systemName: "pin.fill")
                                    .foregroundStyle(.blue)
                                    .frame(width: 16)
                                Text(pin)
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                                Button(action: { model.unpinFolder(pin) }) {
                                    Image(systemName: "trash")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                        }
                    }
                }
            }

            Divider()

            // Recent Folders
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent Folders")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    if !model.recents.isEmpty {
                        Button("Clear Recents") {
                            model.clearRecents()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                Text("Directories recently acted on by Right Here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if model.recents.isEmpty {
                    Text("No recent folders recorded yet.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(12)
                } else {
                    VStack(spacing: 6) {
                        ForEach(model.recents, id: \.self) { recent in
                            HStack(spacing: 10) {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(recent)
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tab 6: Diagnostics

    private var diagnosticsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(l10n.string(.appDetails))
                    .font(.headline.weight(.semibold))
                Spacer()
                Button(action: { Task { await model.testTerminalLaunch() } }) {
                    Label(l10n.string(.appTestLaunch), systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 0) {
                ForEach(model.checks) { check in
                    CheckRow(check: check)
                    if check.id != model.checks.last?.id {
                        Divider().padding(.horizontal, 14)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }

    // MARK: - Tab 7: Configuration

    private var configTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Configuration File")
                    .font(.headline.weight(.semibold))
                Spacer()
                badgePill(model.configValid ? "Valid TOML" : "Has Errors", color: model.configValid ? .green : .red)
            }

            if !model.configDiagnostics.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.configDiagnostics, id: \.self) { diag in
                        Text("• " + diag)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            codeBlock(model.configContent)

            HStack {
                Button("Open in Default Editor") {
                    Task { await model.openConfig() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    // MARK: - UI Helpers

    private func badgePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            .textSelection(.enabled)
    }
}

// MARK: - MenuLine & CheckRow

private struct MenuLine: View {
    let row: MenuPreviewRow
    let image: NSImage?
    let toggle: () -> Void
    private let l10n = Localizer.system

    var body: some View {
        switch row.kind {
        case .separator:
            Divider().padding(.horizontal, 14).accessibilityHidden(true)
        case .submenu where row.hasChildren:
            Button(action: toggle) { line }
                .buttonStyle(.plain)
                .accessibilityValue(l10n.string(row.isExpanded ? .appMenuSubmenuExpanded : .appMenuSubmenuCollapsed))
        case .action, .submenu:
            line.accessibilityElement(children: .combine)
        }
    }

    private var line: some View {
        HStack(spacing: 10) {
            icon.frame(width: 18, height: 18).accessibilityHidden(true)
            Text(row.title).font(.body)
            Spacer(minLength: 8)
            if row.hasChildren {
                Image(systemName: row.isExpanded ? "chevron.down" : "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 14 + CGFloat(row.level) * 24)
        .padding(.trailing, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var icon: some View {
        if let image {
            Image(nsImage: image)
                .renderingMode(image.isTemplate ? .template : .original)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary)
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
            VStack(alignment: .leading, spacing: 4) {
                Text(check.title(in: l10n)).font(.body.weight(.medium))
                if let detail = check.detail {
                    line(detail, .secondary).textSelection(.enabled)
                }
                ForEach(Array(check.notes.enumerated()), id: \.offset) { _, note in
                    line(note, .secondary).textSelection(.enabled)
                }
                if let fix = check.fix {
                    line(fix, .primary).textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityValue(l10n.string(statusKey))
    }

    private func line(_ message: LocalizedMessage, _ style: HierarchicalShapeStyle) -> some View {
        Text(Self.styled(l10n.render(message, isolatingValues: true)))
            .font(.callout)
            .foregroundStyle(style)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusKey: LocalizationKey {
        switch check.status {
        case .ok: return .appStatusOK
        case .warn: return .appStatusWarning
        case .fail: return .appStatusProblem
        case .needsUser: return .appStatusNeedsYou
        }
    }

    static func styled(_ text: String) -> AttributedString {
        var result = AttributedString()
        for (index, part) in abbreviatingHome(text).split(separator: "`", omittingEmptySubsequences: false).enumerated() {
            var piece = AttributedString(String(part))
            if index % 2 == 1 { piece.font = .system(.callout, design: .monospaced) }
            result += piece
        }
        return result
    }

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
