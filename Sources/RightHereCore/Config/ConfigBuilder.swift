import Foundation

/// Turns the typed reading of a config file into a `Config`, one section at a time (the `ConfigBuilder+...` files).
/// Every problem goes to the sink and the valid parts still apply.
struct ConfigBuilder {
    let sink: ConfigSink

    func build(_ root: ConfigReader) -> Config {
        var config = Config()
        root.checkKnownKeys()

        if let version = root.integer("version"), version != Int64(ConfigSchema.version) {
            sink.error(["version"], "unsupported config version \(version); this build reads version \(ConfigSchema.version)")
        }

        let general = readGeneral(root, into: &config)
        readMenu(root, into: &config)
        readServices(root, into: &config)
        readCopyPath(root, into: &config)
        readNewFile(root, into: &config)
        readApps(root, into: &config)
        checkTemplateApps(&config)
        resolveTerminalAndEditor(general, into: &config)
        readAgents(root, into: &config)
        enableAgents(general.agents, into: &config)
        checkActionTargets(config)
        return config
    }

    /// What `[general]` chose that can only be checked once the apps and agents are known.
    struct General {
        var terminal: String?
        var editor: String?
        var agents: [String] = []
    }

    private func readGeneral(_ root: ConfigReader, into config: inout Config) -> General {
        var general = General()
        guard let table = root.subtable("general") else { return general }
        table.checkKnownKeys()
        if let placement = table.checkAllowed(table.string("terminal_placement"), key: "terminal_placement", allowed: TerminalPlacement.configNames) {
            config.terminalPlacement = TerminalPlacement(configName: placement) ?? .newWindow
        }
        general.terminal = table.string("terminal")
        general.editor = table.string("editor")
        general.agents = table.stringArray("agents") ?? []
        return general
    }

    func allAppIDs(_ config: Config) -> [String] {
        (config.apps + KnownApps.all).map(\.id)
    }
}
