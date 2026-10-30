import Foundation

/// Which edits an AI agent may make by itself and which wait for the person (ADR 0026, D5).
///
/// A setting that decides which program starts when the person clicks, or that switches an agent's permission prompts off, is not changed on an agent's say-so: a
/// prompt-injected agent could otherwise make the next click run what it likes. The agent proposes it, and the person looks at the change and applies it. Everything else
/// is a menu, a title, a prompt or a list the person can see and undo, and an agent may change it.
///
/// Every setting of the schema is named in one of the two lists, and a test fails for one that is in neither: a setting added to the schema has to be decided here.
public enum ConfigTrust {
    /// The settings an agent may only propose (when a value is written to them).
    static let programKeys: [String: String] = [
        "app.*.bundle_id": "it decides which app is opened",
        "app.*.bundle_ids": "it decides which app is opened",
        "app.*.role": "it decides how an app is started",
        "app.*.open_args": "it is the program that opens a folder",
        "app.*.run_args": "it is the program that starts a command",
        "agent.*.command": "it is the program that starts the agent",
        "agent.*.args": "it is part of the command that starts the agent",
        "agent.*.prompt_arg": "it is part of the command that starts the agent",
        "agent.*.bypass_permission_arg": "it is part of the command that starts the agent",
        "agent.*.variant.*.arguments": "it is part of the command that starts the agent",
        "agent.*.bypass_permissions": "it switches the agent's permission prompts off",
        "general.bypass_permissions": "it switches the agents' permission prompts off",
        // The tool that makes a new file takes the folder from whoever asks, so what a template holds can be put in any folder: a script, or a login item in a folder that starts programs.
        "new_file.template.*.contents": "it becomes a file that something on this Mac may run (a script, a login item)"
    ]

    /// What a change can do without writing a program key: the effect checks (`approvals(changingFrom:to:)`) name these, and they are not settings of the schema.
    static let effectKeys: [String: String] = [
        "terminal.*.template": "it makes a click start through a command template, a program of your own"
    ]

    /// The settings that were looked at and that an agent may change: they pick among things the person has (a terminal, an agent, an app that is defined), arrange or
    /// name them, or are text for an agent that asks before it acts.
    static let plainKeys: Set<String> = [
        "version", "disabled",
        "general.terminal", "general.editor", "general.terminal_placement", "general.agents", "general.language",
        "menu.items", "services.items",
        "copy_path.title", "copy_path.styles",
        "new_file.then", "new_file.hidden", "new_file.template.*.id", "new_file.template.*.title", "new_file.template.*.base_name", "new_file.template.*.extension",
        "new_file.template.*.open_with", "new_file.template.*.format",
        "app.*.id", "app.*.name",
        "agent.*.name", "agent.*.launcher", "agent.*.terminal", "agent.*.variant.*.id", "agent.*.variant.*.title",
        "preset.*.id", "preset.*.title", "preset.*.agent", "preset.*.prompt", "preset.*.max_files"
    ]

    /// One setting an agent may not change on its own.
    public struct Approval: Sendable, Equatable, Codable {
        /// The setting, spelled generally (`agent.*.command`).
        public var key: String
        /// Why, in English: what the MCP server and the command line say.
        public var reason: String
        /// For the switch of the permission prompts: which agents would start without asking, and with which flag, as names and flags only ("Claude Code --x"),
        /// so that the window can put them after its own words in any language.
        public var effect: String?

        public init(key: String, reason: String, effect: String? = nil) {
            self.key = key
            self.reason = reason
            self.effect = effect
        }

        /// Why, as the window says it in its language: the catalog's text for the setting, with the effect after it.
        public var reasonKey: LocalizationKey? { ConfigTrust.reasonKeys[key] }
    }

    /// The window's words for each reason, by the setting (the English ones are `programKeys` and `effectKeys`).
    static let reasonKeys: [String: LocalizationKey] = [
        "app.*.bundle_id": .trustAppOpened, "app.*.bundle_ids": .trustAppOpened, "app.*.role": .trustAppStarted,
        "app.*.open_args": .trustOpensFolder, "app.*.run_args": .trustStartsCommand,
        "agent.*.command": .trustStartsAgent, "agent.*.args": .trustPartOfAgent, "agent.*.prompt_arg": .trustPartOfAgent,
        "agent.*.bypass_permission_arg": .trustPartOfAgent, "agent.*.variant.*.arguments": .trustPartOfAgent,
        "agent.*.bypass_permissions": .trustPromptsOff, "general.bypass_permissions": .trustPromptsOffAll,
        "new_file.template.*.contents": .trustFileRuns, "terminal.*.template": .trustTemplate, "*": .trustWholeFile
    ]

    /// Whether a value that is written to a setting can start nothing: `false` for a permission setting that is off by default, a list with nothing in it, and an empty text for the contents of a
    /// new file (an empty file starts nothing). An empty text for any other setting is not one of these: `bypass_permission_arg = ""` takes away the flag that the guard of a preset looks for.
    private static func startsNothing(_ value: ConfigDocument.Value, at path: String) -> Bool {
        switch value {
        case .boolean(false), .strings([]): return true
        case .string(""): return ConfigSchema.genericKey(of: path) == "new_file.template.*.contents"
        default: return false
        }
    }

    /// What in `operations` waits for the person. Taking something out, moving it and putting a value that cannot start anything (a list with nothing in it, `false` for a
    /// permission setting that is off by default) never does.
    public static func approvals(for operations: [ConfigOperation]) -> [Approval] {
        var found: [Approval] = []
        func need(_ path: String) {
            guard let key = ConfigSchema.genericKey(of: path), let reason = programKeys[key], !found.contains(where: { $0.key == key }) else { return }
            found.append(Approval(key: key, reason: reason))
        }
        for operation in operations {
            switch operation {
            case .set(let path, let value):
                if startsNothing(value, at: path) { continue }
                need(path)
            case .insert(_, let path, _), .remove(_, let path), .replace(_, let path, _), .move(_, _, let path):
                // Not only what is put in: an argument that is taken out may be the one that keeps an agent in its sandbox, and the order of the arguments is what they mean.
                need(path)
            case .unset(let path):
                // Taking a setting out is not always taking power away: a per-agent `bypass_permissions = false` is what keeps one agent asking while the general switch is on, and
                // taking it out hands that agent to the switch. The general switch taken out is the one case that can only make agents ask.
                // An empty template is a file with nothing in it, which starts nothing.
                if let key = ConfigSchema.genericKey(of: path), key != "general.bypass_permissions", key != "new_file.template.*.contents" { need(path) }
            case .addEntry(let table, let fields, _):
                for field in fields where !startsNothing(field.value, at: "\(table).1.\(field.key)") { need("\(table).1.\(field.key)") }
            case .addTable(let path, let fields):
                for field in fields where !startsNothing(field.value, at: "\(path).\(field.key)") { need("\(path).\(field.key)") }
            case .replaceText:
                // Anything may be in it, programs included.
                if !found.contains(where: { $0.key == "*" }) { found.append(Approval(key: "*", reason: "it rewrites the whole file, and a program may be among what it says")) }
            case .removeTable(let path):
                // What is taken out may be the override that keeps a built-in agent asking.
                need("\(path).command")
            case .removeEntry, .moveEntry, .expect, .expectEntry:
                continue
            }
        }
        return found
    }

    /// What a change does to the agents, whatever the operations are that make it: operations can be spelled many ways and combined, and a change can come through the other file of the
    /// config, so what the files would say afterwards is the one thing that has no other way to be said.
    /// - What an agent is started with, once it exists before and after: another command, argument, first-prompt flag, or arguments of a variant, in either direction. The arguments that keep an
    ///   agent in its sandbox go as well by emptying the list as by taking them out one by one, or by a variant that the other file replaces by its id. An agent that is new starts a program the
    ///   person has not seen; one that is gone starts nothing.
    /// - An agent that starts with a flag that switches its prompts off and did not before, or with another one (whether or not the menu offers it: a built-in agent that the other file turns off
    ///   loses its own `bypass_permissions = false` with its table, and `rh run` and the MCP tool start any agent by its id).
    /// - An agent that a click can start without its prompts and could not before (`PromptEffects`): one that is put in the menu while the switch is on.
    public static func approvals(changingFrom before: Config, to after: Config) -> [Approval] {
        var found: [Approval] = []
        func need(_ key: String) {
            guard let reason = programKeys[key] ?? effectKeys[key], !found.contains(where: { $0.key == key }) else { return }
            found.append(Approval(key: key, reason: reason))
        }
        // An app that is defined otherwise than before (the entry of this Mac's own file that replaces the shared one taken out brings the shared one back; an id that another app takes over): what a
        // click hands it, and how it is started, changed.
        for app in after.allApps {
            guard let was = before.app(id: app.id) else {
                if case .template = app.driver { need("app.*.run_args") }
                continue
            }
            if app.bundleIDs != was.bundleIDs { need("app.*.bundle_ids") }
            if app.role != was.role { need("app.*.role") }
            if case .template(let launch) = app.driver {
                if case .template(let earlier) = was.driver {
                    if launch.open != earlier.open { need("app.*.open_args") }
                    if launch.run != earlier.run { need("app.*.run_args") }
                } else {
                    need("app.*.run_args")
                }
            }
        }
        // A terminal that starts through a command template is chosen where it was not (the default terminal, an agent's own, an item of the menu or of the Quick Actions), or is another program
        // under the choice that stays.
        let uses = Dictionary(before.templateTerminalUses.map { ($0.place, $0.program) }, uniquingKeysWith: { first, _ in first })
        if after.templateTerminalUses.contains(where: { uses[$0.place] != $0.program }) { need("terminal.*.template") }
        for agent in after.allAgents {
            guard let was = before.agent(id: agent.id) else {
                need("agent.*.command")
                continue
            }
            if agent.command != was.command { need("agent.*.command") }
            if agent.promptArgument?.configValue != was.promptArgument?.configValue { need("agent.*.prompt_arg") }
            if after.launchOptions(for: agent).arguments != before.launchOptions(for: was).arguments { need("agent.*.args") }
            for variant in agent.variants where was.variants.first(where: { $0.id == variant.id })?.arguments != variant.arguments { need("agent.*.variant.*.arguments") }
        }
        for agent in after.allAgents {
            let flag = after.launchOptions(for: agent).bypassFlag ?? after.bypassFlagTypedAnywhere(by: agent)
            let was = before.agent(id: agent.id).flatMap { before.launchOptions(for: $0).bypassFlag ?? before.bypassFlagTypedAnywhere(by: $0) }
            if let flag, flag != was { need("agent.*.bypass_permissions") }
        }
        if !PromptEffects.newlyWithoutAsking(from: before, to: after).isEmpty { need("agent.*.bypass_permissions") }
        for template in after.newFile.templates where !template.contents.isEmpty && template.contents != before.newFile.templates.first(where: { $0.id == template.id })?.contents {
            need("new_file.template.*.contents")
        }
        return found
    }
}
