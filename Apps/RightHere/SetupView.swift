import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

/// The setup window: a sidebar of its sections and the section the person chose. It is for setup and status: the Finder
/// extension, the command line and the Shortcuts actions all work without it.
struct SetupView: View {
    @Bindable var model: SetupModel
    private var l10n: Localizer { model.localizer }

    init(model: SetupModel) {
        self.model = model
    }

    /// The window has no title bar of its own (`hiddenTitleBar`): the sidebar runs to the top, with the window's buttons in its corner, and the
    /// page's header stands where a title bar would.
    static let headerHeight: CGFloat = 32

    /// The widest the header and the page get, their margins included. In a wider window they stand in the middle of the space beside the sidebar,
    /// where a setting's name and its control are still read as one line.
    static let widestPage: CGFloat = 780

    static let sidebarWidth: CGFloat = 232

    /// The width of the space beside the sidebar, which says how far a header that a wide window centres stands from the window's buttons.
    @State private var columnWidth: CGFloat = 0
    /// Whether the page is scrolled, so that what scrolls under the header is cut at a line, as a title bar draws its separator then.
    @State private var pageIsScrolled = false

    /// Which way the window's title bar runs, and so on which side its close, minimize and zoom buttons stand. The Mac's language decides it
    /// (`NSWindow.windowTitlebarLayoutDirection`), not the window's; the window reads it from itself once it is in one.
    @State private var titlebarRightToLeft = NSApplication.shared.userInterfaceLayoutDirection == .rightToLeft
    #if PREVIEW
    @Environment(\.previewTitlebarRightToLeft) private var previewTitlebarRightToLeft
    @Environment(\.previewWindowWidth) private var previewWindowWidth
    #endif

    /// The window's buttons stand over the end of the header when the window's language runs the other way from the Mac's (Arabic on an
    /// English Mac, English on a Hebrew one): the sidebar is then on the other side, and the header leaves the buttons room.
    private var windowButtonsOverHeader: Bool {
        #if PREVIEW
        let titlebar = previewTitlebarRightToLeft ?? titlebarRightToLeft
        #else
        let titlebar = titlebarRightToLeft
        #endif
        return SetupModel.windowButtonsOverHeader(titlebarRightToLeft: titlebar, windowRightToLeft: model.localizer.isRightToLeft)
    }

    /// The width of the space beside the sidebar. The renderer lays the window out once, so the preview is given the width it draws rather than
    /// measuring it.
    private var columnWidthNow: CGFloat {
        #if PREVIEW
        previewWindowWidth.map { $0 - Self.sidebarWidth } ?? columnWidth
        #else
        columnWidth
        #endif
    }

    private var headerRoomForWindowButtons: CGFloat {
        SetupModel.headerRoomForWindowButtons(over: windowButtonsOverHeader, columnWidth: columnWidthNow, widestHeader: Self.widestPage)
    }

    private var pageInset: CGFloat { SetupModel.pageInset(columnWidth: columnWidthNow, widestPage: Self.widestPage) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth)
                .background(SidebarPanel())

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 28)
                    .modifier(PageColumn(inset: pageInset))
                    // The band of a title bar moves the window, and a double-click in it does what one in a title bar does, across the whole width.
                    .background(alignment: .top) {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(height: Self.headerHeight)
                            .windowDrag()
                    }
                    // Across the column, only while the page is scrolled: without it, scrolled text was cut off bare under the header's buttons. The system's
                    // separator, as a title bar draws it then; the lighter line of a group's rows (`GroupLine`) all but vanished on the page's white.
                    .overlay(alignment: .bottom) {
                        if pageIsScrolled { Divider() }
                    }

                SetupPage(scrolled: $pageIsScrolled) {
                    page
                        .padding(.horizontal, 28)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                        .modifier(PageColumn(inset: pageInset))
                }
            }
            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columnWidth = $0 }
        }
        .frame(minWidth: 800, minHeight: 560)
        .background(WindowBackground())
        // Every bordered button of the window is a capsule, as the buttons of macOS 26 are.
        .buttonBorderShape(.capsule)
        .ignoresSafeArea(.container, edges: .top)
        .background {
            #if !PREVIEW
            TitlebarDirectionReader { titlebarRightToLeft = $0 }
                .frame(width: 0, height: 0)
            #endif
        }
        .task {
            await model.refresh()
            await model.watchExtension()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refreshOnActivation() }
        }
        // Whichever control a change comes from, one that would make an agent start without its permission prompts waits for the person's yes.
        .alert(looseningTitle(model.pendingLoosening), isPresented: Binding(get: { model.pendingLoosening != nil }, set: { if !$0 { model.cancelLoosening() } }), presenting: model.pendingLoosening) { held in
            Button(l10n.string(.appBypassConfirmButton), role: .destructive) { Task { await model.confirmLoosening(held) } }
            Button(l10n.string(.appCancel), role: .cancel) { model.declineLoosening() }
        } message: { held in
            Text(looseningMessage(held))
        }
        // The config can name a language other than the system's: the pages are written in it, and laid out in its direction.
        .environment(\.localizer, model.localizer)
        .environment(\.layoutDirection, model.localizer.isRightToLeft ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: model.localizer.resolvedLanguage))
        .environment(\.fieldAnswerToken, model.fieldAnswerToken)
        .environment(\.changeIsHeld, { [model] in model.pendingLoosening != nil })
    }

    private func looseningTitle(_ held: PendingLoosening?) -> String {
        guard let held, held.agents.count == 1, let only = held.agents.first else { return l10n.string(.appBypassConfirmTitle) }
        return l10n.render(.appAgentBypassConfirmTitle(only.name))
    }

    /// What each agent would be started with, as the question of the general switch says it.
    private func looseningMessage(_ held: PendingLoosening) -> String {
        if held.agents.count == 1, let only = held.agents.first { return l10n.render(.appAgentBypassConfirmMessage(only.name, only.flag)) }
        return l10n.render(.appBypassConfirmMessage(held.agents.map { "\($0.name)  \($0.flag)" }.joined(separator: "\n")))
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The window's close, minimize and zoom buttons stand in this corner (14-point circles, centred 16 points from the top).
            Color.clear
                .frame(height: 34)
                .contentShape(Rectangle())
                .windowDrag()

            brand
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 16)

            VStack(spacing: 1) {
                ForEach(SetupTab.allCases) { tab in
                    SidebarRow(tab: tab, selected: model.selectedTab == tab, badge: model.badge(for: tab)) {
                        model.select(tab)
                    }
                    // ⌘1 to ⌘8, in the order of the sidebar, as the sections of most Mac apps' windows go; a tenth section would have none.
                    .keyboardShortcut(Self.shortcut(for: tab))
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 8)

            footer
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: AppIdentity.productName)
                    .font(.system(size: 14, weight: .semibold))
                Text(verbatim: AppIdentity.version)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(l10n.render(.appVersion(AppIdentity.version)))
            }
        }
        .help(l10n.string(.appSubtitle))
        .accessibilityElement(children: .combine)
    }

    /// A section of the sidebar, as System Settings draws its own: the section's symbol on a tile of its colour, and the chosen one on the
    /// system's colour of a selection.
    private struct SidebarRow: View {
        let tab: SetupTab
        let selected: Bool
        let badge: SetupBadge?
        let select: () -> Void
        @Environment(\.localizer) private var l10n
        @Environment(\.appearsActive) private var appearsActive

        /// A window in the background marks its section in grey, as the sidebars of the system do.
        private var windowIsActive: Bool {
            #if PREVIEW
            true
            #else
            appearsActive
            #endif
        }

        /// The system's colours of a chosen row, which hold white text whatever accent colour the person chose.
        private static let chosen = Color(nsColor: .selectedContentBackgroundColor)
        private static let chosenInBackground = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)

        var body: some View {
            var attention = ""
            if case .attention(let count)? = badge {
                attention = l10n.render(.appNeedAttentionCount(String(count)))
            }
            let highlighted = selected && windowIsActive
            return Button(action: select) {
                HStack(spacing: 9) {
                    SectionTile(symbol: tab.symbol, tint: tab.tint)

                    Text(l10n.string(tab.titleKey))
                        .font(.system(size: 13))
                        .foregroundStyle(highlighted ? Color.white : Color.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if case .attention(let count)? = badge {
                        Text(verbatim: String(count))
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(highlighted ? Color.white : Color.orange, in: Capsule())
                            .foregroundStyle(highlighted ? Self.chosen : Color.white)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(selected ? (windowIsActive ? Self.chosen : Self.chosenInBackground) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue(attention)
        }
    }

    private static func shortcut(for tab: SetupTab) -> KeyboardShortcut? {
        guard let index = SetupTab.allCases.firstIndex(of: tab), index < 9 else { return nil }
        return KeyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(l10n.string(model.needsFirstRunChoice ? .appNotSetUpYet : statusTitle(model.summary.state)))
                    .font(.caption.weight(.medium))
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
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isRefreshing)
            }

            if model.isRefreshing {
                ProgressRow(message: .appRefreshing)
                    .font(.caption2)
            } else if let notice = model.notice {
                NoticeLine(notice: notice)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        if model.needsFirstRunChoice { return .secondary }
        return switch model.summary.state {
        case .checking: .secondary
        case .allSet: .green
        case .needsAttention: .orange
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerBar
                .frame(height: Self.headerHeight)
                .padding(.trailing, headerRoomForWindowButtons)
            if let newer = model.newerCopy { OlderCopyStrip(running: model.runningCopy, newer: newer, home: model.homePath) }
            // A repair takes seconds (the Finder extension is given time to settle, the checks start the login shell): what it does now is said while it runs, and how it came out
            // when it ends, on whichever page the button was pressed. The first run's card says the same next to its own button.
            if !model.needsFirstRunChoice, let phase = model.setupPhase {
                ProgressRow(message: phase.messageKey)
                    .accessibilityAddTraits(.updatesFrequently)
            } else if let outcome = model.repairOutcome {
                RepairOutcome(notice: outcome, changed: model.setupReport.map(SetupModel.changedPieces) ?? [], home: model.homePath,
                              extensionIsOn: !model.summary.extensionNeedsSetup)
            }
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            if let detail = model.detailHeader(l10n) {
                // The page of one thing in place of a section's list: a button back to the list, and the thing's name, which a long name may cut.
                Button(action: model.closeDetail) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .keyboardShortcut("[", modifiers: .command)
                .help(detail.parent)
                .accessibilityLabel(detail.parent)
                Text(verbatim: detail.title)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            } else {
                // A section's name is short and is never cut: when the window is narrow the buttons give up their words first.
                Text(l10n.string(model.selectedTab.titleKey))
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer(minLength: 12)

            // On the first run the card of the first section is the way in: it makes the config file from what is chosen. These two act on a
            // config that is there, and are not offered before the first look has found out whether it is.
            if model.configIsThere {
                ViewThatFits(in: .horizontal) {
                    headerButtons(repairInWords: true)
                    headerButtons(repairInWords: false)
                }
                .layoutPriority(1)
            }
        }
    }

    /// The two buttons of the header. Open Config is its symbol, with its words as its tooltip and for VoiceOver; Install or Repair, which a
    /// person looks for when something is wrong, keeps its words unless the window is too narrow for them.
    private func headerButtons(repairInWords: Bool) -> some View {
        HStack(spacing: 8) {
            // On the Config page the file is already in front of the person; there the button says where it opens it.
            let open = l10n.string(model.selectedTab == .config ? .appOpenInTextEditor : .appOpenConfig)
            Button {
                Task { await model.openConfig() }
            } label: {
                Label(open, systemImage: "square.and.pencil")
                    .labelStyle(.iconOnly)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .help(open)
            .disabled(model.isWorking)

            Button {
                Task { await model.repair() }
            } label: {
                // While it runs, the button that was pressed turns: the line under the header says what it does now, but it is at the other end of the
                // header from the button, and a person who looked at the button saw only that it went grey.
                Label {
                    Text(l10n.string(.appInstallOrRepair))
                } icon: {
                    if model.isRepairing {
                        Spinner()
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "wrench.and.screwdriver")
                    }
                }
                .labelStyle(InWords(inWords: repairInWords))
            }
            // The main button (blue, and Return presses it) only when a check asks for what it does.
            .buttonStyle(.bordered)
            .help(l10n.string(.appInstallOrRepair), when: !repairInWords)
            .keyboardShortcut(model.repairIsWanted ? .defaultAction : nil)
            .disabled(model.isWorking || !model.canSetUp)
        }
        // Small, as the buttons of a title bar: the header is the band of one, 32 points tall, and a button of the regular size touched its edges.
        .controlSize(.small)
    }

    /// A label with its title and icon, or with its icon alone.
    private struct InWords: LabelStyle {
        let inWords: Bool

        func makeBody(configuration: Configuration) -> some View {
            if inWords {
                Label(configuration)
            } else {
                Label(configuration).labelStyle(.iconOnly)
            }
        }
    }

    /// This copy is older than one that is installed: which, where, and a way to it.
    private struct OlderCopyStrip: View {
        let running: AppCopy
        let newer: AppCopy
        let home: String
        @Environment(\.localizer) private var l10n

        var body: some View {
            let version = newer.version ?? "?"
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    // An older copy, or one of the same version that is not the one to keep (outside the Mac's Applications folder).
                    let isOlder = AppCopies.newer(newer.version, than: running.version)
                    Text(isOlder ? l10n.render(.appOlderCopyTitle(running.version ?? "?")) : l10n.string(.appOtherCopyTitle))
                        .font(.callout.weight(.semibold))
                    let folder = PathDisplay.abbreviatingHome((newer.path as NSString).deletingLastPathComponent, home: home)
                    Text(isOlder ? l10n.render(.appOlderCopyBody(version, folder), isolatingValues: true) : l10n.render(.appOtherCopyBody(folder), isolatingValues: true))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button(l10n.render(.appOlderCopyOpen(version))) {
                            // Both copies have one bundle identifier. Without a new instance, macOS might bring this one to the front instead (not measured;
                            // MANUAL_CHECKS section 9), and quitting it would then leave none: it quits only when the copy that opened is the newer one.
                            let configuration = NSWorkspace.OpenConfiguration()
                            configuration.createsNewApplicationInstance = true
                            let target = URL(fileURLWithPath: newer.path).standardizedFileURL.path
                            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: newer.path), configuration: configuration) { app, error in
                                guard error == nil, app?.bundleURL?.standardizedFileURL.path == target else { return }
                                Task { @MainActor in NSApplication.shared.terminate(nil) }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        Button(l10n.string(.appOlderCopyReveal)) {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: running.path)])
                        }
                        .controlSize(.small)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .callout(.orange)
            .accessibilityElement(children: .contain)
        }
    }

    /// How the last Install or Repair came out: done, with the parts it made or changed, or why it did not finish.
    private struct RepairOutcome: View {
        let notice: SetupNotice
        let changed: [SetupStep]
        let home: String
        let extensionIsOn: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                NoticeLine(notice: notice, font: .callout)
                if !notice.isProblem, !changed.isEmpty {
                    FlowLayout(spacing: 12) {
                        ForEach(changed, id: \.piece) { step in
                            SetupStepMark(step: step, home: home, extensionIsOn: extensionIsOn)
                        }
                    }
                    .padding(.leading, 22)
                }
            }
        }
    }

    @ViewBuilder private var page: some View {
        switch model.selectedTab {
        case .overview: OverviewPage(model: model)
        case .menu: MenuPage(model: model)
        case .agents: AgentsPage(model: model)
        case .config: ConfigPage(model: model)
        case .checks: ChecksPage(model: model)
        case .ai: AIPage(model: model)
        case .worktrees: WorktreesPage(model: model)
        case .folders: FoldersPage(model: model)
        }
    }

}

extension View {
    /// Where a title bar would be, the mouse does what it does on one: a drag moves the window, and a double-click does what the person chose
    /// for a title bar in System Settings › Desktop & Dock.
    func windowDrag() -> some View {
        gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
            .simultaneousGesture(TapGesture(count: 2).onEnded { TitleBarDoubleClick.perform() })
    }

    /// A tooltip, when the view does not already say it.
    @ViewBuilder func help(_ text: String, when shown: Bool) -> some View {
        if shown { help(text) } else { self }
    }
}

/// What a double-click on a title bar does (`AppleActionOnDoubleClick`): minimize, nothing, or zoom (which "Fill" and the default also do here).
@MainActor
enum TitleBarDoubleClick {
    static func perform() {
        guard let window = NSApplication.shared.keyWindow else { return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.performMiniaturize(nil)
        case "None": break
        default: window.performZoom(nil)
        }
    }
}

/// Says which way the title bar of the window it is in runs (`NSWindow.windowTitlebarLayoutDirection`), once it is in one.
private struct TitlebarDirectionReader: NSViewRepresentable {
    let report: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> Probe { Probe(report: report) }
    func updateNSView(_ view: Probe, context: Context) {}

    final class Probe: NSView {
        let report: @MainActor (Bool) -> Void

        init(report: @escaping @MainActor (Bool) -> Void) {
            self.report = report
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            let rightToLeft = window.windowTitlebarLayoutDirection == .rightToLeft
            // Not while SwiftUI is placing its views: a change of state then is dropped.
            Task { @MainActor [report] in report(rightToLeft) }
        }
    }
}

extension SetupTab {
    /// The symbol on the section's tile in the sidebar.
    var symbol: String {
        switch self {
        case .overview: "house.fill"
        case .menu: "contextualmenu.and.cursorarrow"
        case .agents: "terminal.fill"
        case .config: "doc.text.fill"
        case .checks: "checklist"
        case .ai: "sparkles"
        case .worktrees: "arrow.triangle.branch"
        case .folders: "folder.fill"
        }
    }

    /// The colour of the section's tile: one hue each, so a section is found by its colour as well as its name.
    var tint: Color {
        switch self {
        case .overview: .blue
        case .menu: .indigo
        case .agents: .purple
        case .config: .gray
        case .checks: .green
        case .ai: .pink
        case .worktrees: .orange
        case .folders: .teal
        }
    }
}

/// A white symbol on a rounded tile of one colour, like the icons of System Settings' sidebar.
struct SectionTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [tint.mix(with: .white, by: 0.18), tint], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The ground of the window: white, or near black, as the grouped settings pages of macOS 26 have it.
struct WindowBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        scheme == .dark ? Color(white: 0.11) : Color.white
    }
}

/// The sidebar's ground: a shade off the window's, from the top of the window to its bottom, with a hairline at its inner edge. (A panel inset
/// from the window's edges, as the sidebars of macOS 26 are, would put the window's buttons, 9 points from its edge, on the panel's border:
/// those sidebars come with a toolbar, which moves the buttons in.)
struct SidebarPanel: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        (scheme == .dark ? Color(white: 0.155) : Color(white: 0.96))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.primary.opacity(scheme == .dark ? 0.12 : 0.07))
                    .frame(width: 1)
            }
    }
}

#if PREVIEW
/// The height of the part of a window that shows a page, when the preview draws a window of a fixed height (`script/preview_setup.sh --default-window`): a page taller than that shows its start, as
/// the app does before it is scrolled. Without it the preview draws the whole page.
private struct PreviewPageHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

/// The direction of the title bar the preview draws (`--titlebar-ltr`, `--titlebar-rtl`), when it is not the system language's: a window in
/// a language that runs the other way from the Mac's.
private struct PreviewTitlebarKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

/// The width of the window the preview draws, which the renderer lays out once without telling the window what it measured.
private struct PreviewWindowWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var previewWindowWidth: CGFloat? {
        get { self[PreviewWindowWidthKey.self] }
        set { self[PreviewWindowWidthKey.self] = newValue }
    }

    var previewPageHeight: CGFloat? {
        get { self[PreviewPageHeightKey.self] }
        set { self[PreviewPageHeightKey.self] = newValue }
    }

    var previewTitlebarRightToLeft: Bool? {
        get { self[PreviewTitlebarKey.self] }
        set { self[PreviewTitlebarKey.self] = newValue }
    }
}
#endif

/// The header and the page: at most `SetupView.widestPage` wide, `inset` from the sidebar.
private struct PageColumn: ViewModifier {
    let inset: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: SetupView.widestPage, alignment: .leading)
            .padding(.leading, inset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A page of the window. The app scrolls it; the preview draws it whole, because ImageRenderer draws nothing inside a ScrollView.
struct SetupPage<Content: View>: View {
    /// Set while the page is scrolled down from its top.
    @Binding var scrolled: Bool
    let content: () -> Content
    #if PREVIEW
    @Environment(\.previewPageHeight) private var pageHeight
    #endif

    init(scrolled: Binding<Bool> = .constant(false), @ViewBuilder content: @escaping () -> Content) {
        _scrolled = scrolled
        self.content = content
    }

    var body: some View {
        #if PREVIEW
        if let pageHeight {
            // At most the height under a header of one line: a header with a strip under it (an older copy, a repair's outcome) leaves the page less.
            // The page keeps its own height and is cut, as a scrolled page is; without `fixedSize` it was squeezed into the window instead.
            content().fixedSize(horizontal: false, vertical: true).frame(minHeight: 0, maxHeight: pageHeight, alignment: .top).clipped()
        } else {
            content()
        }
        #else
        ScrollView(.vertical) {
            content()
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 0.5
        } action: { _, isScrolled in
            scrolled = isScrolled
        }
        #endif
    }
}
