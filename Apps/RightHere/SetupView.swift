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
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 14)

            Divider()

            #if PREVIEW
            mainContent
                .padding(24)
                .frame(width: 640, alignment: .leading)
            #else
            ScrollView(.vertical) {
                mainContent
                    .padding(24)
                    .frame(width: 640, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .frame(minHeight: 460, maxHeight: 760)
            #endif

            Divider()

            footerSection
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(.quaternary.opacity(0.35))
        }
        .frame(width: 640)
        .task {
            await model.refresh()
            await model.watchExtension()
        }
    }

    // MARK: - Header & Tab Navigation

    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1.5)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Right Here")
                            .font(.title2.weight(.bold))
                        Text("v0.2.0")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary.opacity(0.6), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    Text(l10n.string(.appSubtitle))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                statusPill
            }

            segmentedTabBar
        }
    }

    private var segmentedTabBar: some View {
        HStack(spacing: 4) {
            tabButton(.overview, title: tabTitle(.overview), icon: "sparkles")
            tabButton(.menu, title: tabTitle(.menu), icon: "menubar.dock.rectangle")
            tabButton(.diagnostics, title: tabTitle(.diagnostics), icon: "stethoscope")
            tabButton(.ai, title: tabTitle(.ai), icon: "cpu")
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }

    private func tabButton(_ tab: SetupTab, title: String, icon: String) -> some View {
        let isSelected = model.selectedTab == tab
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                model.selectedTab = tab
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .shadow(color: isSelected ? Color.black.opacity(0.08) : Color.clear, radius: 2, y: 1)
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.needsAttention ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
                .shadow(color: (model.needsAttention ? Color.orange : Color.green).opacity(0.5), radius: 2)
            Text(l10n.string(model.needsAttention ? .appNeedsAttention : .appAllSet))
                .font(.caption.weight(.medium))
                .foregroundStyle(model.needsAttention ? Color.orange : Color.green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((model.needsAttention ? Color.orange : Color.green).opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder((model.needsAttention ? Color.orange : Color.green).opacity(0.25), lineWidth: 1))
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
            case "ru": return "Обзор"
            default: return "Overview"
            }
        case .menu:
            return l10n.string(.appMenuTitle)
        case .diagnostics:
            return l10n.string(.appDetails)
        case .ai:
            return "AI & MCP"
        }
    }

    // MARK: - Main Tab Switcher

    @ViewBuilder
    private var mainContent: some View {
        switch model.selectedTab {
        case .overview:
            overviewTab
        case .menu:
            menuTab
        case .diagnostics:
            diagnosticsTab
        case .ai:
            aiTab
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
                    .font(.headline)
                if model.needsAttention {
                    let open = model.checks.filter { $0.status != .ok }.map { $0.title(in: l10n) }
                    Text(open.formatted(.list(type: .and, width: .narrow)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("FinderSync extension is active. Right-click any folder or file to trigger actions.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)

            if model.needsAttention {
                Button(l10n.string(.appDetails)) {
                    model.selectedTab = .diagnostics
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }

    private var appsConfiguredRow: some View {
        HStack(spacing: 14) {
            appConfigCard(
                category: "Terminal",
                icon: "terminal.fill",
                accentColor: .blue,
                name: model.defaultTerminalName,
                actionTitle: l10n.string(.appTestLaunch),
                action: { Task { await model.testTerminalLaunch() } }
            )

            appConfigCard(
                category: "Editor",
                icon: "doc.text.fill",
                accentColor: .purple,
                name: model.defaultEditorName,
                actionTitle: l10n.string(.appOpenConfig),
                action: { Task { await model.openConfig() } }
            )
        }
    }

    private func appConfigCard(
        category: String,
        icon: String,
        accentColor: Color,
        name: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(accentColor)
                Text(category)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(name)
                .font(.body.weight(.medium))
                .lineLimit(1)

            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isWorking)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                Text(l10n.string(.appOnboardTitle))
                    .font(.headline)
            }

            stepRow(1, title: l10n.string(.appStepOneTitle), body: l10n.string(.appStepOneBody),
                    done: model.check(.terminalDefault)?.status == .ok && model.check(.editorDefault)?.status == .ok) {
                ForEach([CheckID.terminalDefault, .editorDefault], id: \.self) { id in
                    if let detail = model.check(id)?.detail {
                        Text(CheckRow.styled(l10n.render(detail, isolatingValues: true)))
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button(l10n.string(.appOpenConfig)) { Task { await model.openConfig() } }
                    .controlSize(.small)
            }

            stepRow(2, title: l10n.string(.appStepTwoTitle), body: l10n.string(.appStepTwoBody), done: !model.extensionNeedsSetup) {
                Button(l10n.string(.appExtensionSettings)) { model.showExtensionSettings() }
                    .controlSize(.small)
            }

            stepRow(3, title: l10n.string(.appStepThreeTitle), body: l10n.string(.appStepThreeBody), done: false) {
                Button(l10n.string(.appTestLaunch)) { Task { await model.testTerminalLaunch() } }
                    .controlSize(.small)
                    .disabled(model.isWorking)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func stepRow(_ number: Int, title: String, body: String, done: Bool, @ViewBuilder content: () -> some View) -> some View {
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

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                Text(l10n.string(.appQuickActionsTitle))
                    .font(.callout.weight(.medium))
            }
            Text(l10n.string(.appQuickActionsBody))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                commandPill("rh menu")
                commandPill("rh doctor")
                commandPill("rh config validate")
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    private func commandPill(_ cmd: String) -> some View {
        Text(cmd)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Tab 2: Finder Menu Preview

    private var menuTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(l10n.string(.appMenuTitle))
                        .font(.headline)
                    Text(l10n.string(.appMenuCaption))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 0) {
                let rows = model.menuRows
                if rows.isEmpty {
                    Text("No menu items configured or config has errors.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(20)
                } else {
                    ForEach(rows) { row in
                        MenuLine(row: row, image: model.image(for: row.icon)) {
                            model.toggleSubmenu(row.id)
                        }
                    }
                }
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        }
    }

    // MARK: - Tab 3: Diagnostics

    private var diagnosticsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(l10n.string(.appDetails))
                    .font(.headline)
                Spacer()
                HStack(spacing: 8) {
                    statPill("\(model.checks.count) total", color: .secondary)
                    if model.doctorStats.warn > 0 {
                        statPill("\(model.doctorStats.warn) warnings", color: .orange)
                    }
                    if model.doctorStats.fail > 0 {
                        statPill("\(model.doctorStats.fail) issues", color: .red)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.checks.enumerated()), id: \.element.id) { index, check in
                    CheckRow(check: check)
                    if index < model.checks.count - 1 {
                        Divider()
                    }
                }
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }

    private func statPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Tab 4: AI & MCP

    private var aiTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Hero
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Agent Automation & MCP")
                    .font(.headline)
                Text("Right Here connects macOS Finder actions, terminal sessions, and workspace automation to AI agents through Model Context Protocol (MCP) and direct plugins.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // Claude Code Plugin Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Claude Code Plugin", systemImage: "sparkle")
                        .font(.body.weight(.semibold))
                    Spacer()
                    badgePill("Official Plugin", color: .purple)
                }
                Text("Install the Right Here plugin in Claude Code for contextual file manipulation and automation:")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                codeBlock("""
/plugin marketplace add boyugou/right-here
/plugin install right-here@right-here
""")

                Button("Copy Install Command") {
                    model.copyClaudePluginCommand()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))

            // MCP Server Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Model Context Protocol (MCP)", systemImage: "point.3.filled.connected.trianglepath.dotted")
                        .font(.body.weight(.semibold))
                    Spacer()
                    badgePill("stdio", color: .blue)
                }
                Text("Add Right Here to Claude Desktop, Cursor, Zed, or Windsurf as an MCP tool server:")
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
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))

            // AI Setup Prompt Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("AI Setup Hand-off", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.body.weight(.semibold))
                    Spacer()
                }
                Text("Let your AI assistant configure, doctor-check, and customize Right Here for you automatically:")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button(action: { model.copySetupPrompt() }) {
                    Label(l10n.string(.appCopySetupPrompt), systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        }
    }

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
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
            .textSelection(.enabled)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            if model.isWorking {
                ProgressView().controlSize(.small)
            }
            if let message = model.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()

            Button(l10n.string(.appOpenConfig)) {
                Task { await model.openConfig() }
            }
            .buttonStyle(.bordered)

            Button(l10n.string(.appInstallOrRepair)) {
                Task { await model.installOrRepair() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(model.isWorking)
        }
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
