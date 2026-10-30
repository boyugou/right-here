import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// The Agents page (ADR 0026): the AI coding agents the Finder menu offers, in the order it lists them, and the switch that starts them without their permission prompts. Each change is
// written to the config file at once, in the smallest way, and can be undone from the note below the list.

/// The height of a line of the list of agents: its name, and under it what is typed to start it.
private let agentLineHeight: CGFloat = 46

struct AgentsPage: View {
    let model: SetupModel
    /// The place (from 0, in the list as it is) a dragged agent would go to, while one is over the list.
    @State private var dropTarget: Int?
    /// The person's own click on the line of the agents the shell does not have; `nil` until then, and the model's answer is used.
    @State private var missingShown: Bool?
    @Environment(\.localizer) private var l10n

    var body: some View {
        // Which page of one thing is in front is the model's answer, the one the header names too.
        if case .variant(let open)? = model.openDetailPage {
            VariantPage(model: model, agent: open.agent, id: open.id)
        } else if case .agent(let open)? = model.openDetailPage {
            AgentOptionsPage(model: model, id: open)
        } else if case .preset(let open)? = model.openDetailPage {
            PresetPage(model: model, id: open)
        } else {
            VStack(alignment: .leading, spacing: PageRhythm.section) {
                if model.snapshot == nil {
                    note(.appAgentsCaption)
                    ProgressRow(message: .appChecking)
                } else if let general = model.general {
                    editor(general)
                } else {
                    note(.appAgentsCaption)
                    note(model.configIsThere ? .appSettingsNeedValidConfig : .appConfigNone, secondary: false)
                }
            }
        }
    }

    @ViewBuilder private func editor(_ general: GeneralSettingsState) -> some View {
        let enabled = general.enabledAgents
        // The ones a terminal would find come first: those are the ones to put in the menu. The ones the login shell said it does not have
        // are a list of their own under them, which says so once instead of on each line.
        let (others, missing) = model.agentsOutOfMenu(general)
        let locked = model.isWorking || !general.agentsAreExact
        // The list of the menu with what is said of it, then what is not in the menu with the way to add one, each a section of the page.
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            note(.appAgentsCaption)
            if model.agentsAreMachineOwn { note(.appAgentsMachineNote) }
            if !general.agentsAreExact { note(.appAgentsInexactNote) }
            if !enabled.isEmpty {
                // The check, the drag and the menu change the list, which waits for a change that is being written and is left alone when it is not what the window shows. The chevron opens
                // the agent's own options, which have nothing to do with the list's places.
                LinedRows {
                    ForEach(Array(enabled.enumerated()), id: \.element.id) { index, agent in
                        AgentRow(model: model, agent: agent, index: index, count: enabled.count, locked: locked, dropTarget: $dropTarget)
                    }
                }
            }
            // A move, a check or a new agent is said under the list it changed: at the end of the page it was out of sight.
            ConfigEditBanner(model: model, tab: .agents, concerning: Self.concernsTheList)
        }
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            outOfMenu(others: others, missing: missing, listsMissingAtFirst: model.listsMissingAgentsAtFirst(general), locked: locked)
            NewAgentForm(model: model, general: general)
        }
        if let presets = model.presets { PresetsPanel(model: model, presets: presets) }
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            BypassPanel(model: model, general: general)
            // The switch's change, and any other of this page, under the switch.
            ConfigEditBanner(model: model, tab: .agents, concerning: { !Self.concernsTheList($0) && !PresetsPanel.concerns($0) })
        }
    }

    /// The changes of the list of agents: its order and which are in it, an agent added or taken out.
    static func concernsTheList(_ key: String) -> Bool { key == GeneralSettingsState.agentsKey || key.hasPrefix("agent.") }

    @ViewBuilder private func outOfMenu(others: [GeneralSettingsState.Agent], missing: [GeneralSettingsState.Agent], listsMissingAtFirst: Bool, locked: Bool) -> some View {
        if !others.isEmpty || !missing.isEmpty {
            // What the menu could offer and does not: a check puts it in, as a check on a line above takes it out.
            Text(l10n.string(.appMenuHiddenHeading))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if !others.isEmpty {
                LinedRows {
                    ForEach(others) { agent in
                        OtherAgentRow(model: model, agent: agent, locked: locked)
                    }
                }
            }
            if !missing.isEmpty {
                let shown = missingShown ?? listsMissingAtFirst
                VStack(alignment: .leading, spacing: 6) {
                    // Nearer the list it names than the group above it. Two symbols rather than one turned: a turned chevron.forward
                    // points up in a right-to-left language.
                    PlainButton(action: { withAnimation(.snappy(duration: 0.2)) { missingShown = !shown } }) {
                        HStack(spacing: 6) {
                            Image(systemName: shown ? "chevron.down" : "chevron.forward")
                                .font(.caption.weight(.semibold))
                                .frame(width: 12)
                                .accessibilityHidden(true)
                            Text(l10n.string(.appAgentNotFound))
                            Tag(text: missing.count.formatted())
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 14)
                        .padding(.top, 8)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(l10n.string(.appAgentNotFound))
                    .accessibilityValue(missing.count.formatted())
                    if shown {
                        LinedRows {
                            ForEach(missing) { agent in
                                MissingAgentRow(model: model, agent: agent, locked: locked)
                            }
                        }
                    }
                }
            }
        }
    }

    private func note(_ key: LocalizationKey, secondary: Bool = true) -> some View {
        Text(l10n.string(key))
            .font(.callout)
            .foregroundStyle(secondary ? .secondary : .primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One agent of the menu: a grip, a check that takes it out, its icon, its name and the command that starts it, and what the doctor says if the command is not there. Dragging it
/// moves it; a right click, VoiceOver's actions and Option with the arrow keys move it up and down.
private struct AgentRow: View {
    let model: SetupModel
    let agent: GeneralSettingsState.Agent
    let index: Int
    let count: Int
    let locked: Bool
    @Binding var dropTarget: Int?
    @Environment(\.localizer) private var l10n

    private var position: Int { index + 1 }
    private var removeText: String { l10n.render(.appMenuRemoveItem(agent.name)) }
    /// The doctor's word on the command, when it is not as it should be.
    private var warning: LocalizedMessage? {
        guard let check = model.check(.agent(agent.id)), check.status != .ok else { return nil }
        return check.detail
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                RowGrip()
                RowCheck(isOn: true, label: removeText) { Task { await model.setAgent(agent.id, enabled: false) } }
                RowIcon(image: model.image(for: agent.icon))
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: agent.name)
                        .font(.body)
                    if let warning {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.orange)
                                .accessibilityHidden(true)
                            Text(DoctorText.styled(l10n.render(warning), home: model.homePath))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        AgentCommandLine(command: agent.command, state: model.commandState(of: agent), dimmed: false)
                    }
                }
                Spacer(minLength: 8)
                if model.commandState(of: agent) == .missing, let page = agent.installPage {
                    InstallLink(page: page)
                }
            }
            .disabled(locked)
            OptionsButton(model: model, agent: agent)
        }
        .padding(.horizontal, 14)
        .frame(height: agentLineHeight)
        .overlay(alignment: .top) { if dropTarget == index { DropLine() } }
        .overlay(alignment: .bottom) { if dropTarget == index + 1, index == count - 1 { DropLine() } }
        .contentShape(Rectangle())
        .reorderable(model: model, token: "agent:\(agent.id)", scope: "agents", row: position, index: index, height: agentLineHeight, dropTarget: $dropTarget, enabled: !locked,
                     move: { from, destination in await model.moveAgents(from: IndexSet(integer: from - 1), to: destination) },
                     moveBy: { offset in await model.moveAgent(position, by: offset) })
        .contextMenu {
            Button(l10n.string(.appMenuMoveUp)) { Task { await model.moveAgent(position, by: -1) } }.disabled(index == 0 || locked)
            Button(l10n.string(.appMenuMoveDown)) { Task { await model.moveAgent(position, by: 1) } }.disabled(index == count - 1 || locked)
            Divider()
            Button(removeText) { Task { await model.setAgent(agent.id, enabled: false) } }.disabled(locked)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(agent.name)
        // The row is one element for VoiceOver: what the login shell said is its value, and the install page an action of it.
        .accessibilityValue(warning.map { l10n.render($0) } ?? AgentCommandLine.describe(model.commandState(of: agent), l10n) ?? "")
        .modifier(InstallAction(page: model.commandState(of: agent) == .missing ? agent.installPage : nil))
        .accessibilityAction(named: Text(l10n.string(.appMenuMoveUp))) { if index > 0, !locked { Task { await model.moveAgent(position, by: -1) } } }
        .accessibilityAction(named: Text(l10n.string(.appMenuMoveDown))) { if index < count - 1, !locked { Task { await model.moveAgent(position, by: 1) } } }
        .accessibilityAction(named: Text(removeText)) { if !locked { Task { await model.setAgent(agent.id, enabled: false) } } }
        .accessibilityAction(named: Text(l10n.render(.appAgentOptionsFor(agent.name)))) { model.openAgentOptions(agent.id) }
    }
}

/// What is typed to start an agent, and whether a new terminal window would find it: where, or that it is not installed. Nothing is said before the checks have asked the login shell.
struct AgentCommandLine: View {
    let command: String
    let state: AgentCommandState?
    let dimmed: Bool
    @Environment(\.localizer) private var l10n

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: command)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(dimmed ? .tertiary : .secondary)
            if let state {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Image(systemName: symbol(state))
                        .font(.caption2)
                        .foregroundStyle(color(state))
                        .accessibilityHidden(true)
                    Text(verbatim: text(state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .help(l10n.string(.appAgentLookupHelp))
            }
        }
        .lineLimit(1)
    }

    private func text(_ state: AgentCommandState) -> String { Self.describe(state, l10n) ?? "" }

    /// What the login shell said of the command, as a sentence; `nil` when it was not asked.
    static func describe(_ state: AgentCommandState?, _ l10n: Localizer) -> String? {
        switch state {
        case .found(let path?): l10n.render(.appAgentFoundAt(path), isolatingValues: true)
        case .found(nil): l10n.string(.appAgentFound)
        case .missing: l10n.string(.appAgentNotFound)
        case .unknown: l10n.string(.appAgentNotChecked)
        case nil: nil
        }
    }

    private func symbol(_ state: AgentCommandState) -> String {
        switch state {
        case .found: "checkmark.circle.fill"
        case .missing: "minus.circle"
        case .unknown: "questionmark.circle"
        }
    }

    private func color(_ state: AgentCommandState) -> Color {
        switch state {
        case .found: .green
        case .missing, .unknown: .secondary
        }
    }
}

/// "How to Install": the agent's own page, in the browser.
private struct InstallLink: View {
    let page: URL
    @Environment(\.localizer) private var l10n

    var body: some View {
        // A plain button drawn as a link: SwiftUI's Link and the link button style are not drawn by the renderer the screenshots come from.
        PlainButton(action: { NSWorkspace.shared.open(page) }) {
            Text(l10n.string(.appAgentInstallLink))
                .font(.caption)
                .foregroundStyle(Color.accentColor)
        }
        .help(page.absoluteString)
        .accessibilityAddTraits(.isLink)
    }
}

/// The chevron at the right end of an agent's line, which opens that agent's own options.
private struct OptionsButton: View {
    let model: SetupModel
    let agent: GeneralSettingsState.Agent
    @Environment(\.localizer) private var l10n

    var body: some View {
        PlainButton(action: { model.openAgentOptions(agent.id) }) {
            Image(systemName: "chevron.forward")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .help(l10n.render(.appAgentOptionsFor(agent.name)))
        .accessibilityLabel(l10n.render(.appAgentOptionsFor(agent.name)))
    }
}

/// An agent the menu does not offer, as a line with an empty check: checking it puts it at the end of the list.
private struct OtherAgentRow: View {
    let model: SetupModel
    let agent: GeneralSettingsState.Agent
    let locked: Bool
    @Environment(\.localizer) private var l10n

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                // The grip's place, so that the checks and the icons of these lines stand under those of the lines above.
                RowGripSpace()
                RowCheck(isOn: false, label: agent.name) { Task { await model.setAgent(agent.id, enabled: true) } }
                RowIcon(image: model.image(for: agent.icon))
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    // In the text's colour: a grey name looked switched off, and a tick puts the agent in the menu.
                    Text(verbatim: agent.name)
                        .font(.body)
                    AgentCommandLine(command: agent.command, state: model.commandState(of: agent), dimmed: true)
                }
                Spacer(minLength: 8)
                if model.commandState(of: agent) == .missing, let page = agent.installPage {
                    InstallLink(page: page)
                }
            }
            .disabled(locked)
            OptionsButton(model: model, agent: agent)
        }
        .padding(.horizontal, 14)
        .frame(height: agentLineHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !locked { Task { await model.setAgent(agent.id, enabled: true) } } }
        .accessibilityAction(named: Text(l10n.render(.appAgentOptionsFor(agent.name)))) { model.openAgentOptions(agent.id) }
        .modifier(InstallAction(page: model.commandState(of: agent) == .missing ? agent.installPage : nil))
    }
}

/// An agent the login shell does not have, as one line: its name and its command, and where to get it. The list says once that they were not found,
/// and they have no icon, which would be the same on every line.
private struct MissingAgentRow: View {
    let model: SetupModel
    let agent: GeneralSettingsState.Agent
    let locked: Bool
    @Environment(\.localizer) private var l10n

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                RowGripSpace()
                RowCheck(isOn: false, label: agent.name) { Task { await model.setAgent(agent.id, enabled: true) } }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: agent.name)
                        .font(.body)
                    Text(verbatim: agent.command)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                if let page = agent.installPage {
                    InstallLink(page: page)
                }
            }
            .disabled(locked)
            OptionsButton(model: model, agent: agent)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(l10n.string(.appAgentNotFound))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !locked { Task { await model.setAgent(agent.id, enabled: true) } } }
        .accessibilityAction(named: Text(l10n.render(.appAgentOptionsFor(agent.name)))) { model.openAgentOptions(agent.id) }
        .modifier(InstallAction(page: agent.installPage))
    }
}

/// "How to Install" as an action of a row for VoiceOver, which reads the row as one element and would not reach the link inside it.
private struct InstallAction: ViewModifier {
    let page: URL?
    @Environment(\.localizer) private var l10n

    func body(content: Content) -> some View {
        if let page {
            content.accessibilityAction(named: Text(l10n.string(.appAgentInstallLink))) { NSWorkspace.shared.open(page) }
        } else {
            content
        }
    }
}

// MARK: An agent of one's own

/// A program of one's own (lazygit, aider, a script) offered in the menu like the built-in agents: a button that opens a small form for its name and its command.
private struct NewAgentForm: View {
    let model: SetupModel
    let general: GeneralSettingsState
    @State private var isOpen = false
    @State private var name = ""
    @State private var command = ""
    @Environment(\.localizer) private var l10n

    private var canAdd: Bool { AgentOptions.operations(creating: name, command: command, in: general) != nil }

    private func close() {
        isOpen = false
        name = ""
        command = ""
    }

    var body: some View {
        if isOpen {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 0) {
                    OptionRow(label: l10n.string(.appAgentName)) {
                        DraftField(label: l10n.string(.appAgentName), prompt: l10n.string(.appAgentName), text: $name)
                    }
                    RowDivider()
                    OptionRow(label: l10n.string(.appAgentCommand)) {
                        DraftField(label: l10n.string(.appAgentCommand), prompt: "lazygit", text: $command, monospaced: true)
                    }
                }
                .panel()
                Text(l10n.string(.appAgentNewCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(l10n.string(.appCancel)) { close() }
                        .keyboardShortcut(.cancelAction)
                    Button(l10n.string(.appAgentNewAdd)) { Task { if await model.createAgent(name: name, command: command) { close() } } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canAdd || model.isWorking)
                }
            }
        } else {
            Button(l10n.string(.appAgentNew)) { isOpen = true }
                .disabled(model.isWorking || !general.agentsAreExact)
                .atTrailingEdge()
        }
    }
}

// MARK: The permission prompts

/// The switch that starts agents without their permission prompts. Switching it on asks first, through the question that every change of this kind goes through (`SetupModel.edit`), which says
/// what each agent would be started with; switching it off does not.
private struct BypassPanel: View {
    let model: SetupModel
    let general: GeneralSettingsState
    @Environment(\.localizer) private var l10n

    private func sentence(_ line: GeneralSettingsState.BypassLine) -> String {
        switch line.outcome {
        case .flag(let flag): "\(line.agent)  \(flag)"
        case .noFlag: l10n.render(.appBypassNoFlag(line.agent))
        case .keepsAsking: l10n.render(.appBypassKeepsAsking(line.agent))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(l10n.string(.appBypassTitle))
                        .font(.body.weight(.semibold))
                    Text(l10n.string(.appBypassHelp))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                SwitchControl(isOn: general.bypassPermissions, label: l10n.string(.appBypassTitle)) { on in
                    Task { await model.setBypassPermissions(on) }
                }
                .disabled(model.isWorking)
            }
            if general.bypassPermissions {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(general.bypassLines.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: sentence(line))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                // The switch is off, and an agent whose own setting says "start without asking" still starts without its prompts.
                let own = general.enabledAgents.filter { $0.bypassOverride == true && $0.bypassFlag != nil }
                if !own.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(own) { agent in
                            Text(l10n.render(.appBypassOwnSetting(agent.name)))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}

/// A switch. In the preview, which draws nothing for a control that AppKit draws, a capsule and a knob stand for it, with the switch's own measures: on
/// macOS 27.2 the track is 54 by 24 points and the knob a pill of 32 by 20, 2 points in (`preview_setup.sh --real-controls`, measured in pixels).
private struct SwitchControl: View {
    let isOn: Bool
    let label: String
    let set: (Bool) -> Void

    var body: some View {
        #if STANDINS
        Capsule()
            .fill(isOn ? Color.accentColor : Color.primary.opacity(0.13))
            .frame(width: 54, height: 24)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.18), radius: 1.5, y: 1)
                    .frame(width: 32, height: 20)
                    .padding(2)
            }
            .accessibilityLabel(label)
        #else
        Toggle(isOn: Binding(get: { isOn }, set: set)) { EmptyView() }
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel(label)
        #endif
    }
}
