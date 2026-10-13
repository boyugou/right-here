import Foundation

/// `[agent.<id>]` tables and `general.agents`.
extension ConfigBuilder {
    func readAgents(_ root: ConfigReader, into config: inout Config) {
        guard let agents = root.subtable("agent") else { return }
        for id in agents.table.keys.sorted() {
            guard isValidID(id, at: ["agent", id], noun: "agent ids") else { continue }
            guard let reader = agents.subtable(id) else { continue }
            agent(id: id, reader: ConfigReader(table: reader.table, path: reader.path, schema: agentSchema, sink: sink), into: &config)
        }
    }

    /// Fills `enabledAgents` from `general.agents`, and says so for an agent the config defines but does not enable.
    func enableAgents(_ choices: [String], into config: inout Config) {
        let agentIDs = (config.customAgents + KnownAgents.all).map(\.id)
        for id in choices {
            if agentIDs.contains(id) {
                if config.enabledAgents.contains(id) {
                    sink.warning(["general", "agents"], "\"\(id)\" is listed twice; the second is ignored")
                } else {
                    config.enabledAgents.append(id)
                }
            } else if !sink.rejectedAgents.contains(id) {
                sink.error(["general", "agents"], "unknown agent \"\(id)\"; known agents: " + agentIDs.joined(separator: ", "),
                           suggestion: Suggestion.didYouMean(id, in: agentIDs))
            }
        }
        // An agent the config defines is not in the menu until general.agents lists it, and nothing else says so.
        for agent in config.customAgents where !config.enabledAgents.contains(agent.id) {
            sink.warning(["agent", agent.id], "defined, but not in general.agents, so the menu does not offer it (it still runs as `rh run agent.\(agent.id)`); add \"\(agent.id)\" to general.agents")
        }
    }

    private var agentSchema: [SchemaNode] {
        ConfigSchema.root.first(where: { $0.key == "agent" })?.children ?? []
    }

    private func agent(id: String, reader: ConfigReader, into config: inout Config) {
        reader.checkKnownKeys()
        var command = reader.string("command")
        if let typed = command, typed.allSatisfy(\.isWhitespace) {
            sink.error(reader.path + ["command"], "the command is empty, so the agent would start nothing; name the program to run")
            command = nil
            sink.rejectedAgents.insert(id)
        } else if let typed = command, (try? ShellQuoting.validateForTyping(typed)) == nil {
            sink.error(reader.path + ["command"], "the command has a line break or control character, so it cannot be typed into a terminal")
            command = nil
            sink.rejectedAgents.insert(id)
        }
        let declaredVariants: [AgentDescriptor.Variant] = reader.tableArray("variant").compactMap { variant in
            variant.checkKnownKeys()
            guard let variantID = variant.string("id"), let title = variant.string("title") else {
                sink.error(variant.path, "a variant needs id and title")
                return nil
            }
            guard isValidID(variantID, at: variant.path + ["id"]) else { return nil }
            guard isPlainName(title, at: variant.path + ["title"], noun: "title") else { return nil }
            return AgentDescriptor.Variant(id: variantID, title: title, arguments: variant.stringArray("arguments") ?? [])
        }

        var takenVariants = Set((KnownAgents.agent(id: id)?.variants ?? []).map(\.id))
        let variants = declaredVariants.filter { variant in
            guard takenVariants.insert(variant.id).inserted else {
                sink.error(reader.path + ["variant"], "variant id \"\(variant.id)\" is already used by agent \"\(id)\"; the first one is used")
                return false
            }
            return true
        }

        var settings = Config.AgentSettings()
        let launcherName = reader.checkAllowed(reader.string("launcher"), key: "launcher", allowed: AgentLauncher.configNames)
        let terminal = checkedTerminal(reader.string("terminal"), path: reader.path + ["terminal"], customApps: config.apps)
        settings.launcher = AgentLauncher.fromConfig(name: launcherName, terminal: terminal)
        if let word = reader.string("prompt_arg") {
            if let argument = PromptArgument(configValue: word) { settings.promptArgument = argument } else {
                sink.error(reader.path + ["prompt_arg"], "\"\(word)\" is not \"positional\" or a flag such as \"--prompt\"")
            }
        }

        if KnownAgents.agent(id: id) != nil {
            settings.command = command
            settings.variants = variants
        } else {
            guard let name = reader.string("name"), let command else {
                if !sink.rejectedAgents.contains(id) { sink.error(reader.path, "an agent that is not built in needs name and command") }
                return
            }
            guard isPlainName(name, at: reader.path + ["name"], noun: "name") else {
                sink.rejectedAgents.insert(id)
                return
            }
            config.customAgents.append(AgentDescriptor(id: id, name: name, command: command, variants: variants))
        }
        config.agents[id] = settings
    }
}
