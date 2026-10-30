import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// The page of one agent's own options (ADR 0026), which the Agents page opens: the command that starts it, how and in which terminal, whether its permission prompts are off, and the
// arguments it is given. A change is written to the config file at once, in the smallest way, and can be undone from the note below.

struct AgentOptionsPage: View {
    let model: SetupModel
    let id: String
    @Environment(\.localizer) private var l10n

    var body: some View {
        // The way back and the agent's name stand in the window's header (`SetupModel.detailHeader`).
        VStack(alignment: .leading, spacing: PageRhythm.section) {
            if let options = model.agentOptions(id), let general = model.general {
                // Off while something that is not a change of the config runs (an install): a change would wait for it, and a field that went off for every change would lose the focus.
                Group {
                    commandPanel(options, general)
                    promptsPanel(options, general)
                    arguments(options)
                    startOptions(options)
                    if !options.isBuiltIn {
                        RemoveButton(title: l10n.string(.appAgentRemove)) { await model.removeAgent(id) }
                            .disabled(!general.agentsAreExact)
                    }
                }
                .disabled(model.isWorking && !model.isEditingConfig)
                ConfigEditBanner(model: model, tab: .agents, concerning: { $0.hasPrefix("agent.") })
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)
            caption(text)
        }
    }

    // MARK: The command, how it starts, where

    private func launcherTitle(_ launcher: AgentOptionsState.Launcher) -> String {
        switch launcher {
        case .terminal: l10n.string(.appAgentStartsTerminal)
        case .link: l10n.string(.appAgentStartsLink)
        case .desktop: l10n.string(.appAgentStartsDesktop)
        }
    }

    private func terminalTitle(_ app: GeneralSettingsState.App) -> String {
        app.installed ? app.name : l10n.render(.appChooseNotInstalled(app.name))
    }

    @ViewBuilder private func commandPanel(_ options: AgentOptionsState, _ general: GeneralSettingsState) -> some View {
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            let chosen = options.terminal.flatMap { terminal in options.terminals.first { $0.id == terminal } }
            VStack(spacing: 0) {
                if !options.isBuiltIn {
                    OptionRow(label: l10n.string(.appAgentName)) {
                        EditableText(label: l10n.string(.appAgentName), prompt: l10n.string(.appAgentName), current: { model.agentOptions(id)?.name ?? "" },
                                     commit: { typed, _ in await model.setAgentName(id, typed) })
                    }
                    RowDivider()
                }
                OptionRow(label: l10n.string(.appAgentCommand), help: l10n.string(.appAgentCommandHelp)) {
                    HStack(spacing: 6) {
                        EditableText(label: l10n.string(.appAgentCommand), prompt: options.builtInCommand ?? l10n.string(.appAgentCommand), monospaced: true,
                                     current: { model.agentOptions(id)?.command ?? "" }, commit: { typed, _ in await model.setAgentCommand(id, typed) })
                        if let builtIn = options.builtInCommand, builtIn != options.command {
                            PlainButton(action: { Task { await model.setAgentCommand(id, builtIn) } }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .foregroundStyle(.secondary)
                            }
                            .help(l10n.string(.appAgentCommandReset))
                            .accessibilityLabel(l10n.string(.appAgentCommandReset))
                        }
                    }
                }
                if options.launchers.count > 1 {
                    RowDivider()
                    OptionRow(label: l10n.string(.appAgentStarts)) {
                        ChoiceMenu(shown: launcherTitle(options.launcher), font: .body, accessibilityLabel: l10n.string(.appAgentStarts)) {
                            Picker(selection: Binding(get: { options.launcher }, set: { launcher in Task { await model.setAgentLauncher(id, launcher) } })) {
                                ForEach(options.launchers, id: \.self) { launcher in
                                    Text(launcherTitle(launcher)).tag(launcher)
                                }
                            } label: {
                                EmptyView()
                            }
                            .pickerStyle(.inline)
                        }
                    }
                }
                if options.launcher == .terminal {
                    RowDivider()
                    OptionRow(label: l10n.string(.appAgentTerminal)) {
                        ChoiceMenu(shown: chosen.map(terminalTitle) ?? automaticTerminal(options), font: .body, accessibilityLabel: l10n.string(.appAgentTerminal)) {
                            Picker(selection: Binding(get: { options.terminal ?? "" }, set: { terminal in Task { await model.setAgentTerminal(id, terminal.isEmpty ? nil : terminal) } })) {
                                Text(automaticTerminal(options)).tag("")
                                ForEach(options.terminals) { app in
                                    Text(terminalTitle(app)).tag(app.id)
                                }
                            } label: {
                                EmptyView()
                            }
                            .pickerStyle(.inline)
                        }
                    }
                }
                RowDivider()
                OptionRow(label: l10n.string(.appAgentPromptArg), help: l10n.string(.appAgentPromptArgHelp)) {
                    EditableText(label: l10n.string(.appAgentPromptArg), prompt: options.builtInPromptArgument ?? "", monospaced: true,
                                 current: { model.agentOptions(id)?.promptArgument ?? "" }, commit: { typed, _ in await model.setAgentPromptArgument(id, typed) })
                }
            }
            .panel()
            // Empty means "the built-in way" for an agent that has one; for the others it means that the agent takes no first prompt, which is why no preset can name it.
            if options.builtInPromptArgument == nil, (options.promptArgument ?? "").isEmpty { caption(l10n.string(.appAgentPromptArgNone)) }
            // The terminal the agent would be typed into, chosen or not, and it cannot run an agent.
            if options.launcher == .terminal, let used = chosen ?? options.automaticTerminal, !used.runsCommands {
                warning(l10n.render(.appTerminalNoAgents(used.name)))
            }
        }
    }

    /// "Automatic (X)": X is the terminal an agent that names none is typed into, which is the default one when it is installed (not the first that is installed, as the Overview's menu says).
    private func automaticTerminal(_ options: AgentOptionsState) -> String {
        options.automaticTerminal.map { l10n.render(.appTerminalAutomatic($0.name)) } ?? l10n.string(.appNoneFound)
    }

    // MARK: The permission prompts

    /// The flag the agent is started with to skip its prompts; `nil` when it has none.
    private func skipFlag(_ options: AgentOptionsState) -> String? {
        let flag = options.bypassArgument ?? options.builtInBypassArgument
        return flag.flatMap { $0.isEmpty ? nil : $0 }
    }

    private func promptsTitle(_ override: Bool?) -> String {
        switch override {
        case nil: l10n.string(.appAgentPromptsFollow)
        case true?: l10n.string(.appAgentPromptsOff)
        case false?: l10n.string(.appAgentPromptsAsk)
        }
    }

    @ViewBuilder private func promptsPanel(_ options: AgentOptionsState, _ general: GeneralSettingsState) -> some View {
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            let flag = skipFlag(options)
            // Whether a click starts this agent without its prompts now: its own setting, or the switch for all agents, and a flag that does it.
            let startsWithout = (options.bypassOverride ?? general.bypassPermissions) && flag != nil
            let wantsToStartWithout = options.bypassOverride ?? general.bypassPermissions
            VStack(spacing: 0) {
                OptionRow(label: l10n.string(.appAgentPrompts)) {
                    ChoiceMenu(shown: promptsTitle(options.bypassOverride), font: .body, accessibilityLabel: l10n.string(.appAgentPrompts)) {
                        Picker(selection: Binding<Bool?>(get: { options.bypassOverride }, set: { override in Task { await model.setAgentBypass(id, override) } })) {
                            Text(promptsTitle(nil)).tag(Bool?.none)
                            // Starting without prompts needs a flag that does it.
                            Text(promptsTitle(true)).tag(Bool?.some(true)).disabled(flag == nil)
                            Text(promptsTitle(false)).tag(Bool?.some(false))
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.inline)
                    }
                }
                RowDivider()
                OptionRow(label: l10n.string(.appAgentSkipFlag)) {
                    EditableText(label: l10n.string(.appAgentSkipFlag), prompt: options.builtInBypassArgument ?? "", monospaced: true,
                                 current: { model.agentOptions(id)?.bypassArgument ?? "" }, commit: { typed, _ in await model.setAgentBypassArgument(id, typed) })
                }
            }
            .panel()
            if startsWithout, let flag { caption(l10n.render(.appAgentStartsWithoutAsking(flag))) }
            if flag == nil, wantsToStartWithout { warning(l10n.render(.appBypassNoFlag(options.name))) }
        }
    }

    // MARK: The arguments

    @ViewBuilder private func arguments(_ options: AgentOptionsState) -> some View {
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            Text(l10n.string(.appAgentArguments))
                .font(.headline)
            ArgumentListPanel(model: model, owner: .agent(id), list: options.argumentList)
            caption(l10n.string(.appAgentArgumentsHelp))
            if !options.argsAreExact { warning(l10n.string(.appAgentArgumentsInexactNote)) }
        }
    }

    // MARK: The start options

    /// The extra ways to start the agent: the ones it has built in, and the config's own, each a line that opens its page.
    @ViewBuilder private func startOptions(_ options: AgentOptionsState) -> some View {
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            Text(l10n.string(.appAgentVariants))
                .font(.headline)
            caption(l10n.string(.appAgentVariantsCaption))
            if !options.fixedVariants.isEmpty || !options.variants.isEmpty {
                LinedRows {
                    ForEach(options.fixedVariants) { variant in
                        VariantLine(model: model, agent: id, title: variant.titleKey.map { l10n.string($0) } ?? variant.title, arguments: variant.arguments, tag: variant.isBuiltIn ? l10n.string(.appVariantTagBuiltIn) : nil, opens: nil)
                    }
                    ForEach(options.variants) { variant in
                        VariantLine(model: model, agent: id, title: variant.title, arguments: variant.arguments.items, tag: nil, opens: VariantRef(agent: id, id: variant.id))
                    }
                }
            }
            NewVariantForm(model: model, agent: id)
        }
    }
}
