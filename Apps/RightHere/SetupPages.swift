import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// The sections of the setup window. Each is written from the model's answers; the words are catalog entries (`Localizer`), and what
// is only a name, a path or a command is `Text(verbatim:)`, so that a literal that a translation would miss does not get in.

extension View {
    /// A panel of the window: a group of rows a shade off the window's ground, as the grouped settings of macOS 26 draw theirs.
    func panel(cornerRadius: CGFloat = 12) -> some View {
        modifier(Card(fill: Color.primary.opacity(0.035), edge: Color.primary, cornerRadius: cornerRadius))
    }

    /// A card that asks for something: the first steps, a change waiting for a yes, a copy of the app to leave. Its colour says which.
    func callout(_ tint: Color) -> some View {
        modifier(Card(fill: tint.opacity(0.09), edge: tint, cornerRadius: 12))
    }
}

/// The ground of a panel or a callout. It has no edge of its own, as the groups of macOS 26 have none, unless the person asked for more contrast.
private struct Card: ViewModifier {
    let fill: Color
    let edge: Color
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(fill, in: shape)
            .overlay {
                if contrast == .increased { shape.strokeBorder(edge.opacity(0.45), lineWidth: 1) }
            }
    }
}

extension View {
    /// At the trailing edge of the page, as the buttons under a group of macOS 26's settings stand (Add…, New…, Remove…).
    func atTrailingEdge() -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            self
        }
    }
}

/// A list that has nothing in it yet: the group it would fill, with what would be there said in its middle, so that the page keeps the shape it
/// has once there is something.
struct EmptyList<Message: View>: View {
    @ViewBuilder let message: Message

    var body: some View {
        message
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .panel()
    }
}

/// The button that takes a thing of the config away, under its page at the trailing edge: a button with a frame and its words in red, as macOS
/// draws one that deletes (a red word alone is how a phone lists it).
struct RemoveButton: View {
    let title: String
    /// Red for what deletes; the accent colour for what puts a built-in thing back.
    var tint: Color = .red
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Text(verbatim: title)
                .foregroundStyle(tint)
        }
        .buttonStyle(.bordered)
        .atTrailingEdge()
    }
}

/// Rows in one group with a hairline between two, as the grouped lists of macOS 26 have them (a row is not a card of its own).
struct RowGroup<Content: View>: View {
    /// Where the line between two rows starts: under the rows' text, past an icon or a tile.
    var inset: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        GroupLine()
                            .padding(.leading, inset)
                            .padding(.trailing, 14)
                    }
                    row
                }
            }
        }
        .panel()
    }
}

/// A word about a row (Built in, Customized, Main working copy): small and grey in a capsule, the same on every page.
struct Tag: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Color.primary.opacity(0.08), in: Capsule())
    }
}

/// The spacing of every page (ADR 0029, 13): 24 points between a page's sections, 8 inside one, between its heading, what it says and its group, as a settings pane
/// of macOS stacks them. The pages had five spacings of their own, from 14 to 28 points between sections and 8 to 10 inside them.
enum PageRhythm {
    static let section: CGFloat = 24
    static let inSection: CGFloat = 8
}

/// Rows in one group with a hairline between two, drawn over the foot of a row: the rows keep the heights that a drag counts places with.
struct LinedRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    row.overlay(alignment: .bottom) {
                        if index < rows.count - 1 {
                            GroupLine()
                                .padding(.horizontal, 14)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .panel()
    }
}

/// The sentence that says how the setup stands.
func statusTitle(_ state: SetupSummary.State) -> LocalizationKey { state.titleKey }

/// The language the window is written in: the config's `general.language`, or the system's (`SetupModel.localizer`). The window sets it at its root.
private struct LocalizerKey: EnvironmentKey {
    static let defaultValue = Localizer.system
}

extension EnvironmentValues {
    var localizer: Localizer {
        get { self[LocalizerKey.self] }
        set { self[LocalizerKey.self] = newValue }
    }
}

/// What the doctor says, written for the window: a command between backticks is code, and a path starts from `~`.
enum DoctorText {
    static func styled(_ text: String, home: String) -> AttributedString {
        var result = AttributedString()
        for (index, part) in PathDisplay.abbreviatingHome(text, home: home).split(separator: "`", omittingEmptySubsequences: false).enumerated() {
            var piece = AttributedString(String(part))
            // A point smaller than the sentence: a monospaced word of the same size looks larger and wider than the words around it.
            if index % 2 == 1 { piece.font = .system(size: 11, design: .monospaced) }
            result += piece
        }
        return result
    }
}

/// A sentence of the catalog that may name a command between backticks: the command is written as code, as the doctor's are.
struct Prose: View {
    let key: LocalizationKey
    let home: String
    @Environment(\.localizer) private var l10n

    var body: some View {
        Text(DoctorText.styled(l10n.string(key), home: home))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The small spinner of something under way. The preview draws one of its own: ImageRenderer draws a `ProgressView` as a "prohibited"
/// sign, which the pictures of the window (the website's among them) would show. The stand-in has the small spinner's measures on macOS 27.2
/// (`preview_setup.sh --real-controls`): 16 points across, twelve thin spokes.
struct Spinner: View {
    var body: some View {
        #if STANDINS
        ZStack {
            ForEach(0..<12) { index in
                Capsule()
                    .fill(Color.secondary.opacity(0.2 + 0.8 * Double(index) / 11))
                    .frame(width: 1.4, height: 4)
                    .offset(y: -5.5)
                    .rotationEffect(.degrees(Double(index) * 30))
            }
        }
        .frame(width: 16, height: 16)
        #else
        ProgressView()
            .controlSize(.small)
        #endif
    }
}

/// A line that says what is happening, with a spinner.
struct ProgressRow: View {
    let message: LocalizationKey
    @Environment(\.localizer) private var l10n

    var body: some View {
        HStack(spacing: 8) {
            Spinner()
            Text(l10n.string(message))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// What the last action said: a confirmation, or why it did not work (with the symbol that says which).
struct NoticeLine: View {
    let notice: SetupNotice
    var font: Font = .caption2
    @Environment(\.localizer) private var l10n

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: notice.isProblem ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isProblem ? Color.orange : Color.green)
                .accessibilityHidden(true)
            Text(l10n.render(notice.message, isolatingValues: true))
                .font(font)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

/// The button under a check's fix, as a named action of the row for VoiceOver.
private struct FixActionForVoiceOver: ViewModifier {
    let title: String?
    let act: () -> Void

    func body(content: Content) -> some View {
        if let title { content.accessibilityAction(named: Text(title), act) } else { content }
    }
}

/// A button of a row that is its symbol alone: what it does is its tooltip, and what VoiceOver calls it.
struct RowIconButton: View {
    let symbol: String
    let help: String
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        PlainButton(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .help(help)
        .accessibilityLabel(accessibilityLabel ?? help)
    }
}

/// A small button that shows a folder in Finder.
struct RevealButton: View {
    let path: String
    @Environment(\.localizer) private var l10n

    var body: some View {
        RowIconButton(symbol: "magnifyingglass", help: l10n.string(.actionReveal)) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }
}

/// A block of text that a person can copy: a JSON snippet or the commands of a plugin.
struct CodeBlock: View {
    let code: String

    var body: some View {
        Text(verbatim: code)
            .font(.system(size: 11, design: .monospaced))
            .multilineTextAlignment(.leading)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
            .textSelection(.enabled)
            // JSON and commands are written left to right in every language; a right-to-left window put their indentation at the wrong end.
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// A path, as one left-to-right run: a folder named in Arabic or Hebrew made the line right to left, with `~` at its far end. It is in the
/// window's own font, as Finder and System Settings write paths: a monospaced one joined no Arabic letters, and stood beside the same path
/// in the proportional font elsewhere on a page.
struct PathText: View {
    let path: String
    var size: CGFloat = 12

    var body: some View {
        Text(verbatim: "\u{2066}" + path + "\u{2069}")
            .font(.system(size: size))
    }
}

// MARK: Overview

/// How the setup stands, and the first steps while the Finder extension is off.
struct OverviewPage: View {
    let model: SetupModel
    @Environment(\.localizer) private var l10n

    private static let resultID = "setup-result"

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: PageRhythm.section) {
                if model.locationProblem != nil {
                    LocationCard()
                }
                if model.needsFirstRunChoice {
                    // A Set Up that did not come out leaves no config, so the chooser stays: what went wrong is said above it, where the person is
                    // looking, and not only in the footnote of the sidebar. A refusal that started nothing has no report, only the notice.
                    if let report = model.setupReport {
                        SetupDonePanel(report: report, home: model.homePath, extensionIsOn: !model.summary.extensionNeedsSetup)
                            .id(Self.resultID)
                    } else if let notice = model.notice, notice.isProblem {
                        NoticeLine(notice: notice, font: .callout)
                            .id(Self.resultID)
                    }
                    // No config file yet: what is installed, to choose from, before anything is written.
                    FirstRunChooser(model: model)
                } else if case .app(let app)? = model.openDetailPage {
                    AppPage(model: model, id: app)
                } else {
                    if model.proposalsWaiting > 0 {
                        ProposalsNotice(model: model)
                    }
                    if let report = model.setupReport, model.summary.state != .allSet || report.hasNews {
                        SetupDonePanel(report: report, home: model.homePath, extensionIsOn: !model.summary.extensionNeedsSetup)
                            .id(Self.resultID)
                    }

                    if model.summary.extensionNeedsSetup {
                        FirstRunCard(model: model)
                    } else {
                        StatusCard(model: model)
                    }

                    VStack(alignment: .leading, spacing: PageRhythm.inSection) {
                        // The lines between the rows start where their names do, past the tiles.
                        RowGroup(inset: 14 + SettingRow<EmptyView, EmptyView>.tileSize + 12) {
                            DefaultAppRow(model: model, role: .terminal)
                            if let general = model.general, general.placements.count > 1 {
                                PlacementRow(model: model, general: general)
                            }
                            DefaultAppRow(model: model, role: .editor)
                            if model.general != nil { LanguageRow(model: model) }
                        }
                        ConfigEditBanner(model: model, tab: .overview, concerning: { !AppsPanel.concerns($0) })
                    }
                    if let apps = model.apps {
                        AppsPanel(model: model, apps: apps)
                    }
                }
            }
            // The button that was pressed may be far down the page; the answer is at the top.
            .onChange(of: model.setupAttempt) {
                proxy.scrollTo(Self.resultID, anchor: .top)
            }
        }
    }
}

/// The status once the Finder extension is on: a line that says whether anything needs the person, and which checks.
struct StatusCard: View {
    let model: SetupModel
    @Environment(\.localizer) private var l10n

    var body: some View {
        let state = model.summary.state
        HStack(alignment: .top, spacing: 16) {
            symbol(state)
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.string(statusTitle(state)))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if state == .allSet {
                    Text(l10n.string(.appAllSetHint))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if state == .needsAttention {
                    Text(model.summary.openTitles(in: l10n).formatted(.list(type: .and, width: .narrow)))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(l10n.string(.appOpenChecksHint))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(l10n.string(.appShowChecks)) { model.select(.checks) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    @ViewBuilder private func symbol(_ state: SetupSummary.State) -> some View {
        switch state {
        case .checking:
            Spinner()
                .frame(width: 40, height: 40)
        case .allSet:
            Image(systemName: "checkmark.seal.fill")
                .font(.title)
                .foregroundStyle(Color.green)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
        case .needsAttention:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(Color.orange)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
        }
    }
}

/// The three steps of a first run, in order, and a way around the extension. Shown until the extension is switched on.
struct FirstRunCard: View {
    let model: SetupModel
    @Environment(\.localizer) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(l10n.string(.appOnboardTitle))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            step(1, title: .appStepOneTitle, body: .appStepOneBody,
                 done: model.check(.terminalDefault)?.status == .ok && model.check(.editorDefault)?.status == .ok) {
                ForEach([CheckID.terminalDefault, .editorDefault], id: \.self) { id in
                    if let detail = model.check(id)?.detail {
                        Text(DoctorText.styled(l10n.render(detail, isolatingValues: true), home: model.homePath))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

            step(2, title: .appStepTwoTitle, body: .appStepTwoBody, done: false) {
                Button(l10n.string(.appExtensionSettings)) { model.showExtensionSettings() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            step(3, title: .appStepThreeTitle, body: .appStepThreeBody, done: false) {
                Button(l10n.string(.appShowChecks)) { model.select(.checks) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.string(.appQuickActionsTitle))
                    .font(.callout.weight(.medium))
                Text(l10n.string(.appQuickActionsBody))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .callout(.accentColor)
    }

    private func step<Actions: View>(_ number: Int, title: LocalizationKey, body: LocalizationKey, done: Bool,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color.accentColor)
                if done {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text(number.formatted())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.string(title))
                    .font(.body.weight(.medium))
                Text(l10n.string(body))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l10n.render(.appStepLabel(number.formatted(), l10n.string(title))))
        .accessibilityValue(done ? l10n.string(.appStatusOK) : "")
    }
}

// MARK: Finder menu

/// The menu Finder shows for a folder, built by the code the extension runs: the lines it would show, with the submenus that open
/// in place. With Edit, the lines become rows that can be dragged, removed and added to (`MenuEditorView`).
struct MenuPage: View {
    let model: SetupModel
    @Environment(\.localizer) private var l10n

    var body: some View {
        if case .template(let open)? = model.openDetailPage {
            TemplatePage(model: model, id: open)
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: PageRhythm.section) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.string(model.isEditingMenu ? .appMenuEditCaption : .appMenuCaption))
                    if !model.isEditingMenu, model.menuEditor != nil { Text(l10n.string(.appMenuEditHint)) }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if model.menuEditor != nil {
                    // The preview above looks like a picture of a menu; the button that makes it rows to change has to read as one.
                    Button {
                        model.setEditingMenu(!model.isEditingMenu)
                    } label: {
                        Label(l10n.string(model.isEditingMenu ? .appMenuEditDone : .appMenuEdit), systemImage: model.isEditingMenu ? "checkmark" : "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isWorking)
                }
            }

            if model.snapshot == nil {
                ProgressRow(message: .appChecking)
            } else if model.isEditingMenu, let editor = model.menuEditor {
                MenuEditorView(model: model, editor: editor)
            } else if model.menuRows.isEmpty {
                Text(l10n.string(.appMenuEmpty))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // A picture of the menu as Finder shows it, as wide as its lines, so that it does not read as one more list of settings. A line
                // longer than the page (a title of the person's own) cuts it at the page's width instead of widening the page.
                let menu = VStack(spacing: 0) {
                    ForEach(model.menuRows) { row in
                        MenuLine(row: row, image: model.image(for: row.icon)) {
                            model.toggleSubmenu(row.id)
                        }
                    }
                }
                .padding(.vertical, 5)
                .frame(minWidth: 280)
                // On a stage of the group's colour across the page, the menu in its middle: a menu on the bare page, at its leading edge, floated
                // there with the right half of the page empty (a design review of 0.3.21).
                ViewThatFits(in: .horizontal) {
                    menu.fixedSize(horizontal: true, vertical: false)
                    menu
                }
                .background(MenuCard())
                .padding(24)
                .frame(maxWidth: .infinity)
                .panel()
            }
            if let state = model.newFile { NewFilePanel(model: model, state: state) }
            if let state = model.copyPath { CopyPathPanel(model: model, state: state) }
            if let state = model.quickActions { QuickActionsPanel(model: model, state: state) }
        }
    }
}

/// The ground of the menu's picture: a menu's light sheet with a hairline edge and a soft shadow, as macOS draws a context menu.
struct MenuCard: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        shape
            .fill(scheme == .dark ? Color(white: 0.19) : Color(white: 0.985))
            .overlay(shape.strokeBorder(Color.primary.opacity(scheme == .dark ? 0.16 : 0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.14), radius: 12, y: 5)
    }
}

/// One line of the Finder menu preview: what Finder's menu line looks like, and nothing that acts. A submenu opens and closes in
/// place; an entry does nothing when it is clicked.
struct MenuLine: View {
    let row: MenuPreviewRow
    let image: NSImage?
    let toggle: () -> Void
    @Environment(\.localizer) private var l10n

    var body: some View {
        switch row.kind {
        case .separator:
            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .accessibilityHidden(true)
        case .submenu where row.hasChildren:
            Button(action: toggle) { line }
                .buttonStyle(.plain)
                .accessibilityValue(l10n.string(row.isExpanded ? .appMenuSubmenuExpanded : .appMenuSubmenuCollapsed))
        case .action, .submenu:
            line.accessibilityElement(children: .combine)
        }
    }

    private var line: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(row.title)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 24)
            if row.hasChildren {
                // Not a rotated chevron: the forward one is drawn mirrored in a right-to-left language, the down one is not.
                Image(systemName: row.isExpanded ? "chevron.down" : "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 12 + CGFloat(row.level) * 20)
        .padding(.trailing, 12)
        .frame(height: 24)
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

// MARK: Checks

/// Every check of the doctor, with what it found and what to do. The launch test is here, where its answer goes.
struct ChecksPage: View {
    let model: SetupModel
    @Environment(\.localizer) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            HStack(alignment: .center, spacing: 12) {
                Text(l10n.string(statusTitle(model.summary.state)))
                    .font(.body.weight(.medium))
                Spacer(minLength: 12)
                Button {
                    Task { await model.testLaunch() }
                } label: {
                    Label(l10n.string(.appTestLaunch), systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
                // The test goes through the extension: with it off it would wait its 75 seconds and say the extension did not answer.
                .disabled(model.isWorking || model.isRefreshing || model.summary.extensionNeedsSetup)
            }

            if model.isTestingLaunch {
                ProgressRow(message: .appTesting)
            }

            if model.checks.isEmpty {
                ProgressRow(message: .appChecking)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.checks.enumerated()), id: \.element.id) { index, check in
                        CheckRow(check: check, home: model.homePath, firstRun: model.needsFirstRunChoice, busy: model.isWorking || !model.canSetUp) { action in
                            switch action {
                            case .repair: Task { await model.repair() }
                            case .extensionSettings: model.showExtensionSettings()
                            case .page(let tab): model.select(tab)
                            case .revealOtherCopies: NSWorkspace.shared.activateFileViewerSelecting(model.otherCopies.map { URL(fileURLWithPath: $0.path) })
                            }
                        }
                        if index < model.checks.count - 1 {
                            // From where the check's text starts, past its symbol.
                            GroupLine()
                                .padding(.leading, 46)
                                .padding(.trailing, 14)
                        }
                    }
                }
                .panel()
            }
        }
    }
}

/// One check: its title, what was found, its notes and what to do. The status is spoken once, as the value of the row.
struct CheckRow: View {
    let check: DoctorCheck
    let home: String
    /// There is no config file yet: the way in is the Set Up button of the first page, not Install or Repair.
    let firstRun: Bool
    /// Something runs, or this copy cannot set anything up: the buttons are off.
    var busy = false
    var perform: (SetupFixAction) -> Void = { _ in }
    @Environment(\.localizer) private var l10n


    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(check.title(in: l10n))
                    .font(.body)
                if let detail = check.detail {
                    line(detail, .secondary)
                }
                ForEach(Array(check.notes.enumerated()), id: \.offset) { _, note in
                    line(note, .secondary)
                }
                if let fix = check.fix {
                    let action = SetupFixAction(fix: fix, firstRun: firstRun)
                    let sentence = inTheWindow(fix)
                    // "Press Install or Repair." above an Install or Repair button says twice what the button says.
                    if !(sentence.key == .appFixRepair && action == .repair) {
                        line(sentence, .primary)
                    }
                    if let action {
                        button(action)
                            .padding(.top, 3)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // One stop for VoiceOver per check (title, detail and fix read together) instead of three; the fix's button is an action of it.
        .accessibilityElement(children: .combine)
        .accessibilityValue(l10n.string(statusKey))
        .modifier(FixActionForVoiceOver(title: check.fix.flatMap { SetupFixAction(fix: $0, firstRun: firstRun) }.map(title(of:)), act: {
            if let action = check.fix.flatMap({ SetupFixAction(fix: $0, firstRun: firstRun) }) { perform(action) }
        }))
    }

    private func title(of action: SetupFixAction) -> String {
        switch action {
        case .repair: l10n.string(.appInstallOrRepair)
        case .extensionSettings: l10n.string(.appExtensionSettings)
        case .page(let tab): l10n.string(tab.titleKey)
        case .revealOtherCopies: l10n.string(.actionReveal)
        }
    }

    private func button(_ action: SetupFixAction) -> some View {
        let title = title(of: action)
        let symbol = switch action {
        case .repair: "wrench.and.screwdriver"
        case .extensionSettings: "gearshape"
        case .page: "arrow.right.circle"
        case .revealOtherCopies: "magnifyingglass"
        }
        return Button { perform(action) } label: { Label(title, systemImage: symbol) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(busy && action == .repair)
    }

    /// The fixes of the doctor are written for a terminal ("Run `rh setup`"); in the window the same thing is a button, and the person has no command to run.
    private func inTheWindow(_ fix: LocalizedMessage) -> LocalizedMessage {
        switch fix.key {
        case .doctorFixRunSetup, .doctorFixExtensionInstall: firstRun ? .appFixSetUp : .appFixRepair
        case .doctorFixExtensionClean: firstRun ? .appFixSetUp : .appFixExtensionClean
        case .doctorFixExtensionEnable: .appFixExtensionEnable
        // A setting the window has a control for is changed there, and the button under the sentence goes to it.
        case .doctorFixTerminal: .appFixTerminalWindow
        case .doctorFixEditor: .appFixEditorWindow
        case .doctorFixTerminalFallback, .doctorFixEditorFallback: .appFixFallbackWindow
        case .doctorFixAgentsAdd: .appFixAgentsAddWindow
        case .doctorFixAgentRemove: .appFixAgentRemoveWindow
        case .doctorFixAgentLauncher: .appFixAgentLauncherWindow
        case .doctorFixConfigErrors: .appFixConfigErrorsWindow
        case .doctorFixConfigWarnings: .appFixConfigWarningsWindow
        default: fix
        }
    }

    /// One line of what the doctor says, in the system language, as long as it needs to be. A path or a command in a right-to-left
    /// sentence stays in one piece, and the text stays selectable (a fix is a command a person copies).
    private func line(_ message: LocalizedMessage, _ style: HierarchicalShapeStyle) -> some View {
        Text(DoctorText.styled(l10n.render(message, isolatingValues: true), home: home))
            .font(.callout)
            .foregroundStyle(style)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private var statusKey: LocalizationKey {
        switch check.status {
        case .ok: .appStatusOK
        case .warn: .appStatusWarning
        case .fail: .appStatusProblem
        case .needsUser: .appStatusNeedsYou
        }
    }

    private var symbol: String {
        switch check.status {
        case .ok: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.octagon.fill"
        case .needsUser: "hand.raised.fill"
        }
    }

    private var color: Color {
        switch check.status {
        case .ok: .green
        case .warn: .orange
        case .fail: .red
        case .needsUser: .blue
        }
    }
}

// MARK: AI assistants

/// What to give an AI assistant: the prompt that sets Right Here up, the MCP server it can connect to, the Claude Code plugin.
struct AIPage: View {
    let model: SetupModel
    @Environment(\.localizer) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: PageRhythm.section) {
            section(.appAiPromptTitle) {
                Button(l10n.string(.appCopySetupPrompt)) { model.copySetupPrompt() }
                    .buttonStyle(.borderedProminent)
            } content: {
                Prose(key: .appAiPromptBody, home: model.homePath)
                copied(.promptCopied)
            }

            section(.appAiMCPTitle) {
                Button(l10n.string(.appCopyMCPConfig)) { model.copyMCPConfiguration() }
                    .buttonStyle(.bordered)
            } content: {
                Prose(key: .appAiMCPBody, home: model.homePath)
                CodeBlock(code: SetupSnippets.mcpConfiguration(command: model.mcpCommand))
                copied(.mcpConfigurationCopied)
            }

            section(.appAiPluginTitle) {
                Button(l10n.string(.appCopyPluginCommands)) { model.copyPluginCommands() }
                    .buttonStyle(.bordered)
            } content: {
                Prose(key: .appAiPluginBody, home: model.homePath)
                CodeBlock(code: SetupSnippets.pluginCommands)
                copied(.pluginCommandsCopied)
            }
        }
    }

    /// That the button above copied, said under it, where the person looks, and not only in the sidebar.
    @ViewBuilder private func copied(_ notice: SetupNotice) -> some View {
        if model.notice == notice { NoticeLine(notice: notice, font: .callout) }
    }

    /// A section with its button on the line of its heading, as Folders has "Pin a Folder…": the button is what the section is for.
    private func section<Action: View, Content: View>(_ title: LocalizationKey, @ViewBuilder action: () -> Action, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            HStack(alignment: .center, spacing: 12) {
                Text(l10n.string(title))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                action()
            }
            content()
        }
    }
}

// MARK: Worktrees

/// The git worktrees Right Here made for agents, in one repository. Only those can be removed here, never forced.
struct WorktreesPage: View {
    let model: SetupModel
    @State private var pending: WorktreeRow?
    @Environment(\.localizer) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            Prose(key: .appWorktreesIntro, home: model.homePath)

            repositoryBar

            listing
        }
        .confirmationDialog(l10n.string(.appRemoveWorktreeTitle), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button(l10n.string(.appRemoveWorktreeConfirm), role: .destructive) {
                if let row = pending { Task { await model.remove(row) } }
                pending = nil
            }
            Button(l10n.string(.appCancel), role: .cancel) {
                pending = nil
            }
        } message: {
            if let row = pending {
                Text(l10n.render(.appRemoveWorktreeMessage(PathDisplay.folder(row.entry.path, home: model.homePath)), isolatingValues: true))
            }
        }
    }

    private var repositoryBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(l10n.string(.appWorktreesRepository))
                .font(.callout.weight(.medium))

            if model.repositories.count > 1, let repository = model.repository {
                Menu {
                    ForEach(model.repositories, id: \.path) { root in
                        Button(PathDisplay.folder(root.path, home: model.homePath)) { model.selectRepository(root) }
                    }
                } label: {
                    PathText(path: PathDisplay.folder(repository.path, home: model.homePath))
                }
                .fixedSize()
            } else if let repository = model.repository {
                PathText(path: PathDisplay.folder(repository.path, home: model.homePath))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button {
                Task { await model.chooseRepository() }
            } label: {
                Label(l10n.string(.appWorktreesChoose), systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
            .disabled(model.isWorking)
        }
    }

    @ViewBuilder private var listing: some View {
        switch model.worktrees {
        case .idle:
            EmptyList { Text(l10n.string(.appWorktreesNoRepository)) }
        case .loading:
            ProgressRow(message: .appLoading)
        case .failed(let text):
            Text(verbatim: text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .loaded(let rows):
            RowGroup {
                ForEach(rows) { row in
                    WorktreeLine(row: row, home: model.homePath, disabled: model.isWorking) {
                        pending = row
                    }
                }
            }
        }
    }
}

/// One worktree of the list: its branch, where it is, and the one action the window offers for it.
struct WorktreeLine: View {
    let row: WorktreeRow
    let home: String
    let disabled: Bool
    let onRemove: () -> Void
    @Environment(\.localizer) private var l10n

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // In the secondary colour, as the leading symbols of the other lists: the accent colour says a thing can be clicked.
            Image(systemName: row.isMainWorkingCopy ? "house" : "arrow.triangle.branch")
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(verbatim: row.branchTitle ?? l10n.string(.appWorktreeDetached))
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if row.isMainWorkingCopy {
                        tag(.appWorktreeMain)
                    } else if row.canBeRemoved {
                        tag(.appWorktreeMadeHere)
                    }
                }
                PathText(path: PathDisplay.folder(row.entry.path, home: home), size: 11)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                .environment(\.layoutDirection, .leftToRight)
            }

            Spacer(minLength: 8)

            if row.canBeRemoved {
                Button(l10n.string(.appRemoveWorktree), action: onRemove)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(disabled)
                    .accessibilityLabel(l10n.render(.appRemoveWorktreeNamed(row.entry.path.split(separator: "/").last.map(String.init) ?? "")))
            }
            RevealButton(path: row.entry.path)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tag(_ key: LocalizationKey) -> some View {
        Tag(text: l10n.string(key))
    }
}

// MARK: Folders

/// The folders Right Here remembers: the pinned ones and the recent ones, kept on this Mac and readable only by its user.
struct FoldersPage: View {
    let model: SetupModel
    @Environment(\.localizer) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: PageRhythm.section) {
            Text(l10n.string(.appFoldersNote))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            pinned

            recent
        }
    }

    private var pinned: some View {
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            HStack(alignment: .center, spacing: 12) {
                Text(l10n.string(.appPinnedFolders))
                    .font(.headline)
                Spacer(minLength: 8)
                Button(l10n.string(.appPinChoose)) { Task { await model.choosePinnedFolder() } }
                    .buttonStyle(.bordered)
                    .disabled(model.isWorking || model.isRefreshing)
            }
            if model.folders.pins.isEmpty {
                EmptyList { Prose(key: .appNoPinned, home: model.homePath) }
            } else {
                RowGroup {
                    ForEach(model.folders.pins, id: \.self) { path in
                        folderLine(path, icon: "pin.fill") {
                            RowIconButton(symbol: "pin.slash", help: l10n.string(.appUnpin),
                                          accessibilityLabel: l10n.render(.appUnpinFolder(PathDisplay.folder(path, home: model.homePath)), isolatingValues: true)) {
                                Task { await model.unpin(path) }
                            }
                            .disabled(model.isWorking || model.isRefreshing)
                        }
                    }
                }
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            HStack(alignment: .center, spacing: 12) {
                Text(l10n.string(.appRecentFolders))
                    .font(.headline)
                Spacer(minLength: 8)
                if !model.folders.recents.isEmpty {
                    Button(l10n.string(.appClearRecents)) { Task { await model.clearRecents() } }
                        .buttonStyle(.bordered)
                        .disabled(model.isWorking || model.isRefreshing)
                }
            }
            if model.folders.recents.isEmpty {
                EmptyList { Text(l10n.string(.appNoRecents)) }
            } else {
                RowGroup {
                    ForEach(model.folders.recents, id: \.self) { path in
                        folderLine(path, icon: "clock") {
                            if !model.folders.pins.contains(path) {
                                RowIconButton(symbol: "pin", help: l10n.string(.appPin),
                                              accessibilityLabel: l10n.render(.appPinFolder(PathDisplay.folder(path, home: model.homePath)), isolatingValues: true)) {
                                    Task { await model.pin(path) }
                                }
                                .disabled(model.isWorking || model.isRefreshing)
                            }
                        }
                    }
                }
            }
        }
    }

    private func folderLine<Trailing: View>(_ path: String, icon: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            PathText(path: PathDisplay.folder(path, home: model.homePath))
                .lineLimit(1)
                .truncationMode(.middle)
                .environment(\.layoutDirection, .leftToRight)
            Spacer(minLength: 8)
            trailing()
            // Last, so that it stands in one column whatever the button before it says (Pin, Unpin, Remove…).
            RevealButton(path: path)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
