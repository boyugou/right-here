import Foundation

/// `[[preset]]` tables. A preset that is not valid is reported and left out; the built-in ones it does not replace stay.
extension ConfigBuilder {
    func readPresets(_ root: ConfigReader, into config: inout Config) {
        let known = config
        let declared = readUnique(root.tableArray("preset"), kind: "preset", id: \.id) { reader in
            preset(reader, config: known)
        }
        var presets = AgentPreset.builtIn
        for preset in declared {
            if let index = presets.firstIndex(where: { $0.id == preset.id }) { presets[index] = preset } else { presets.append(preset) }
        }
        config.presets = presets
    }

    private func preset(_ reader: ConfigReader, config: Config) -> AgentPreset? {
        reader.checkKnownKeys()
        guard let id = reader.string("id"), let title = reader.string("title"), let prompt = reader.string("prompt") else {
            sink.error(reader.path, "a preset needs id, title and prompt")
            return nil
        }
        guard isValidID(id, at: reader.path + ["id"]) else { return nil }
        var valid = true
        if let refusal = PresetTemplate.typingRefusal(prompt) {
            sink.error(reader.path + ["prompt"], "this prompt cannot be typed into a terminal: \(refusal)")
            valid = false
        }
        for word in PresetTemplate.unknownPlaceholders(in: prompt) {
            sink.error(reader.path + ["prompt"], "unknown placeholder {\(word)}; the placeholders are " + PresetTemplate.placeholders.map { "{\($0)}" }.joined(separator: ", "),
                       suggestion: Suggestion.didYouMean(word, in: PresetTemplate.placeholders).map { Hint(text: $0.text, replacement: "{\($0.replacement)}") })
            valid = false
        }
        if !isPlainName(title, at: reader.path + ["title"], noun: "title") { valid = false }

        var agent: String?
        if let named = reader.string("agent") {
            let agentIDs = (config.customAgents + KnownAgents.all).map(\.id)
            if agentIDs.contains(named) {
                agent = named
                if !config.enabledAgents.contains(named) {
                    sink.warning(reader.path + ["agent"], "agent \"\(named)\" is not in general.agents, so the menu does not offer this preset (it still runs as `rh run preset.\(id)`); add \"\(named)\" to general.agents")
                }
                if config.agent(id: named)?.promptArgument == nil {
                    sink.warning(reader.path + ["agent"], "agent \"\(named)\" is not known to take a first prompt, so this preset cannot run; set prompt_arg in [agent.\(named)]")
                }
            } else {
                sink.error(reader.path + ["agent"], "unknown agent \"\(named)\"; known agents: " + agentIDs.joined(separator: ", "),
                           suggestion: Suggestion.didYouMean(named, in: agentIDs))
                valid = false
            }
        }

        var maxFiles = AgentPreset.defaultMaxFiles
        if let value = reader.integer("max_files") {
            if (1...Int64(AgentPreset.maxFilesLimit)).contains(value) {
                maxFiles = Int(value)
            } else {
                sink.error(reader.path + ["max_files"], "max_files is \(value); it has to be from 1 to \(AgentPreset.maxFilesLimit), so the default \(AgentPreset.defaultMaxFiles) is used")
            }
        }
        return valid ? AgentPreset(id: id, title: title, agent: agent, prompt: prompt, maxFiles: maxFiles) : nil
    }
}
