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

        if root.table.contains(key: "disabled") {
            sink.warning(["disabled"], ConfigLayers.disabledInSharedFileMessage())
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
        readPresets(root, into: &config)
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
        config.language = table.checkAllowed(table.string("language"), key: "language", allowed: Localizer.supportedLanguages)
        if let bypass = table.boolean("bypass_permissions") {
            config.bypassPermissions = bypass
        }
        general.terminal = table.string("terminal")
        general.editor = table.string("editor")
        general.agents = table.stringArray("agents") ?? []
        return general
    }

    /// Reads each table with `read` and keeps the first definition of every id; a later one is an error.
    /// `accepted` runs right after a definition is kept, so its diagnostics stay in file order.
    func readUnique<Value>(
        _ readers: [ConfigReader], kind: String, id: (Value) -> String,
        read: (ConfigReader) -> Value?, accepted: (Value, ConfigReader) -> Void = { _, _ in }
    ) -> [Value] {
        var seen = Set<String>()
        return readers.compactMap { reader in
            guard let value = read(reader) else { return nil }
            guard seen.insert(id(value)).inserted else {
                sink.error(reader.path + ["id"], "duplicate \(kind) id \"\(id(value))\"; the first definition is used")
                return nil
            }
            accepted(value, reader)
            return value
        }
    }

    /// Reports an id that breaks `IDRule`; `noun` is how the message names the ids it is about.
    func isValidID(_ id: String, at path: [String], noun: String = "ids") -> Bool {
        guard IDRule.isValid(id) else {
            sink.error(path, "\(noun) use lowercase letters, digits and dashes")
            return false
        }
        return true
    }

    /// A name or title the config sets is shown in menus and printed by `rh`. One with a line break or another control
    /// character (an escape sequence that clears a screen or sets the clipboard, say) is refused, as a preset's title
    /// always was: the config can arrive from the sync folder, and what it names things must not act on a terminal.
    /// - Parameter limit: The most characters. A file name of a template has its own limit, in bytes, checked where it is read.
    func isPlainName(_ text: String, at path: [String], noun: String, limit: Int = ConfigBuilder.longestName) -> Bool {
        // A name is part of the name of a file as well (a Quick Action is a bundle called after its title, and a file system takes a name only so long): a long one fails far from where it was typed.
        if text.count > limit {
            sink.error(path, "the \(noun) is longer than \(limit) characters")
            return false
        }
        if ShellQuoting.containsControlCharacter(text) {
            sink.error(path, "the \(noun) has a line break or control character")
            return false
        }
        if text.hasMisleadingCharacter(ignoringJoiners: true) {
            sink.error(path, "the \(noun) has a character that changes how it reads (a direction override, a zero-width space, a tag character)")
            return false
        }
        return true
    }

    /// The most characters of a name or a title: what a menu shows and what a Quick Action is called, with room for the words around it.
    static let longestName = 120

    /// The characters of a name that make it read as something other than what it says: a direction override, embedding or isolate reorders the letters around it, and a zero-width space,
    /// a word joiner, a byte order mark, a soft hyphen or a tag character shows nothing (the tag characters spell ASCII that a language model reads). The marks a script is written
    /// with stay: the left-to-right and right-to-left marks and the joiners of Persian and Indic words.
    static func changesHowTextReads(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00AD, 0x200B, 0x2060, 0xFEFF, 0x202A...0x202E, 0x2066...0x2069, 0xE0000...0xE007F: return true
        default: return false
        }
    }

    /// Says which of what an entry needs is not there: "an app needs id and name (missing: name)". Nothing when every key is
    /// there: one of the wrong type has been reported already, and a second complaint about the same key would only repeat it.
    func reportMissing(_ noun: String, needs required: [String], in reader: ConfigReader) {
        let missing = required.filter { !reader.table.contains(key: $0) }
        guard !missing.isEmpty else { return }
        func list(_ words: [String]) -> String {
            words.count < 2 ? (words.first ?? "") : words.dropLast().joined(separator: ", ") + " and " + words[words.count - 1]
        }
        sink.error(reader.path, "\(noun) needs \(list(required)) (missing: \(list(missing)))")
    }

    func allAppIDs(_ config: Config) -> [String] {
        (config.apps + KnownApps.all).map(\.id)
    }
}
