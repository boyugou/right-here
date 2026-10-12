import Foundation
import TOMLDecoder

public struct ConfigDiagnostic: Sendable, Equatable, Codable {
    public enum Severity: String, Sendable, Codable {
        case error
        case warning
    }

    public var severity: Severity
    /// Dotted location in the file, for example `agent.claude.launcher`; empty for the whole file.
    public var path: String
    public var message: String
    /// Line number, known for syntax errors.
    public var line: Int?
    /// A concrete fix, for example `did you mean "terminal"?`.
    public var suggestion: String?
    /// The text to put in place of the wrong key or value, when there is a likely candidate.
    public var replacement: String?

    public init(severity: Severity, path: String, message: String, line: Int? = nil, suggestion: String? = nil, replacement: String? = nil) {
        self.severity = severity
        self.path = path
        self.message = message
        self.line = line
        self.suggestion = suggestion
        self.replacement = replacement
    }

    /// One line for a terminal or a log: `error: config.toml:3 [agent.claude.launcher]: message (suggestion)`.
    public func summary(file: URL) -> String {
        var text = "\(severity.rawValue): \(file.lastPathComponent)"
        if let line { text += ":\(line)" }
        if !path.isEmpty { text += " [\(path)]" }
        text += ": \(message)"
        if let suggestion { text += " (\(suggestion))" }
        return text
    }
}

public struct ConfigLoadResult: Sendable, Equatable {
    public var config: Config
    public var diagnostics: [ConfigDiagnostic]

    public init(config: Config, diagnostics: [ConfigDiagnostic]) {
        self.config = config
        self.diagnostics = diagnostics
    }

    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
}

public enum ConfigParser {
    /// Lowercase letters, digits and dashes, not starting with a dash (it would read as an option on a command
    /// line). `ConfigSchema.identifierPattern` says the same in the JSON Schema, and a test holds them together.
    static func isIdentifier(_ text: String) -> Bool {
        guard let first = text.utf8.first, first != UInt8(ascii: "-") else { return false }
        return text.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == UInt8(ascii: "-") }
    }

    /// Parses config text. A file with a syntax error yields the default config plus the error;
    /// semantic problems are reported while everything valid is still applied.
    /// The deepest nesting of arrays and inline tables a config may have; real ones nest a few levels.
    static let maxNesting = 64

    public static func parse(_ text: String) -> ConfigLoadResult {
        let sink = Sink()
        // The TOML library recurses once per level and a deep enough file overflowed the stack and killed `rh`.
        if NestingDepth.tomlExceeds(text, limit: maxNesting) {
            sink.syntaxError("arrays or tables nested more than \(maxNesting) levels deep")
            return ConfigLoadResult(config: .default, diagnostics: sink.items)
        }
        let root: TOMLTable
        do {
            // A text that ends right after an empty quoted key inside an open bracket (`[""`, `[ ''`, `[[""`) makes the
            // library trap on reading past the end of its input, which killed every `rh` command and the Finder
            // menu. A final line break is harmless to a valid file and turns those into the ordinary syntax error.
            root = try TOMLTable(source: text + "\n")
        } catch {
            sink.syntaxError((error.description.hasSuffix(".") ? String(error.description.dropLast()) : error.description) + ". Usual causes: text without \"quotes\", a missing = or ], the same [table] twice. Defaults apply until it is fixed.")
            return ConfigLoadResult(config: .default, diagnostics: sink.items)
        }
        let config = Builder(sink: sink).build(Reader(table: root, path: [], schema: ConfigSchema.root, sink: sink))
        return ConfigLoadResult(config: config, diagnostics: sink.items)
    }
}

// MARK: - Diagnostics collection

private final class Sink {
    /// Agents whose definition was refused with an error of its own; later checks do not complain about them again.
    var rejectedAgents = Set<String>()
    var items: [ConfigDiagnostic] = []

    func error(_ path: [String], _ message: String, suggestion: Hint? = nil) {
        items.append(ConfigDiagnostic(severity: .error, path: path.joined(separator: "."), message: message,
                                      suggestion: suggestion?.text, replacement: suggestion?.replacement))
    }

    func warning(_ path: [String], _ message: String, suggestion: Hint? = nil) {
        items.append(ConfigDiagnostic(severity: .warning, path: path.joined(separator: "."), message: message,
                                      suggestion: suggestion?.text, replacement: suggestion?.replacement))
    }

    func syntaxError(_ description: String) {
        var message = description
        var line: Int?
        if let match = description.firstMatch(of: #/^\(Line (\d+)\) /#) {
            line = Int(match.1)
            message = String(description[match.range.upperBound...])
        }
        items.append(ConfigDiagnostic(severity: .error, path: "", message: "TOML syntax error: " + message, line: line))
    }
}

// MARK: - Typed reading with diagnostics

private struct Reader {
    let table: TOMLTable
    let path: [String]
    let schema: [SchemaNode]
    let sink: Sink

    func string(_ key: String) -> String? {
        guard table.contains(key: key) else { return nil }
        do { return try table.string(forKey: key) } catch {
            sink.error(path + [key], "expected a string")
            return nil
        }
    }

    func integer(_ key: String) -> Int64? {
        guard table.contains(key: key) else { return nil }
        do { return try table.integer(forKey: key) } catch {
            sink.error(path + [key], "expected an integer")
            return nil
        }
    }

    func stringArray(_ key: String) -> [String]? {
        guard table.contains(key: key) else { return nil }
        do {
            let array = try table.array(forKey: key)
            return try (0..<array.count).map { try array.string(atIndex: $0) }
        } catch {
            sink.error(path + [key], "expected an array of strings")
            return nil
        }
    }

    private func children(of key: String) -> [SchemaNode] {
        schema.first(where: { $0.key == key })?.children ?? []
    }

    func subtable(_ key: String) -> Reader? {
        guard table.contains(key: key) else { return nil }
        do {
            return Reader(table: try table.table(forKey: key), path: path + [key], schema: children(of: key), sink: sink)
        } catch {
            sink.error(path + [key], "expected a table")
            return nil
        }
    }

    func tableArray(_ key: String) -> [Reader] {
        guard table.contains(key: key) else { return [] }
        do {
            let array = try table.array(forKey: key)
            let childSchema = children(of: key)
            return try (0..<array.count).map { index in
                Reader(table: try array.table(atIndex: index), path: path + [key, String(index + 1)], schema: childSchema, sink: sink)
            }
        } catch {
            sink.error(path + [key], "expected an array of tables, written [[\((path + [key]).joined(separator: "."))]]")
            return []
        }
    }

    /// Warn about keys the schema does not know, with the closest valid key as a suggestion.
    func checkKnownKeys(extra: Set<String> = []) {
        let known = schema.map(\.key)
        for key in table.keys.sorted() where !known.contains(key) && !extra.contains(key) {
            sink.warning(path + [key], "unknown key", suggestion: Suggestion.didYouMean(key, in: known))
        }
    }

    func checkAllowed(_ value: String?, key: String, allowed: [String]) -> String? {
        guard let value else { return nil }
        guard allowed.contains(value) else {
            sink.error(path + [key], "\"\(value)\" is not one of " + allowed.joined(separator: ", "),
                       suggestion: Suggestion.didYouMean(value, in: allowed))
            return nil
        }
        return value
    }
}

/// A suggested fix for a diagnostic: prose for people and the replacement text for tools.
struct Hint {
    var text: String
    var replacement: String
}

enum Suggestion {
    static func didYouMean(_ word: String, in candidates: [String]) -> Hint? {
        closest(to: word, in: candidates).map { Hint(text: "did you mean \"\($0)\"?", replacement: $0) }
    }

    /// The closest candidate within a small edit distance, if any.
    static func closest(to word: String, in candidates: [String]) -> String? {
        let best = candidates.map { ($0, distance(word, $0)) }.min { $0.1 < $1.1 }
        guard let (candidate, score) = best, score <= max(2, word.count / 3) else { return nil }
        return candidate
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}

// MARK: - Building the Config

private struct Builder {
    let sink: Sink

    func build(_ root: Reader) -> Config {
        var config = Config()
        root.checkKnownKeys()

        if let version = root.integer("version"), version != Int64(ConfigSchema.version) {
            sink.error(["version"], "unsupported config version \(version); this build reads version \(ConfigSchema.version)")
        }

        var terminalChoice: String?
        var editorChoice: String?
        var agentChoices: [String] = []
        if let general = root.subtable("general") {
            general.checkKnownKeys()
            if let placement = general.checkAllowed(general.string("terminal_placement"), key: "terminal_placement", allowed: TerminalPlacement.configNames) {
                config.terminalPlacement = TerminalPlacement(configName: placement) ?? .newWindow
            }
            terminalChoice = general.string("terminal")
            editorChoice = general.string("editor")
            agentChoices = general.stringArray("agents") ?? []
        }

        if let menu = root.subtable("menu") {
            menu.checkKnownKeys()
            config.menuItems = menu.stringArray("items")
            if config.menuItems?.contains(where: { $0 != "-" }) == false {
                sink.warning(["menu", "items"], "the list has no entries, so the Finder menu will be empty; remove the key to use the default menu")
            }
            for entry in config.menuItems ?? [] where entry != "-" && !MenuBuilder.groups.contains(entry) && ActionRef(parsing: entry) == nil {
                sink.warning(["menu", "items"], "\"\(entry)\" is neither a menu group nor an action id",
                             suggestion: Suggestion.didYouMean(entry, in: Array(MenuBuilder.groups)))
            }
        }

        if let services = root.subtable("services") {
            services.checkKnownKeys()
            if let items = services.stringArray("items") {
                config.serviceItems = items.filter { item in
                    guard ActionRef(parsing: item) != nil else {
                        sink.warning(["services", "items"], "\"\(item)\" is not an action id; see `rh docs actions`")
                        return false
                    }
                    return true
                }
            }
        }

        if let copyPath = root.subtable("copy_path") {
            copyPath.checkKnownKeys()
            if let names = copyPath.stringArray("styles") {
                var seen = Set<String>()
                config.copyPathStyles = names.compactMap { name in
                    guard seen.insert(name).inserted else {
                        sink.warning(["copy_path", "styles"], "\"\(name)\" is listed twice; the second is ignored")
                        return nil
                    }
                    if let style = PathStyle(rawValue: name) { return style }
                    sink.error(["copy_path", "styles"], "unknown style \"\(name)\"",
                               suggestion: Suggestion.didYouMean(name, in: PathStyle.allCases.map(\.rawValue)))
                    return nil
                }
            }
        }

        if let newFile = root.subtable("new_file") {
            newFile.checkKnownKeys()
            if let then = newFile.checkAllowed(newFile.string("then"), key: "then", allowed: Config.AfterNewFile.allCases.map(\.rawValue)) {
                config.newFile.then = Config.AfterNewFile(rawValue: then) ?? .reveal
            }
            var seenTemplates = Set<String>()
            let templates = newFile.tableArray("template").compactMap { reader -> NewFileTemplate? in
                guard let template = template(reader) else { return nil }
                guard seenTemplates.insert(template.id).inserted else {
                    sink.error(reader.path + ["id"], "duplicate template id \"\(template.id)\"; the first definition is used")
                    return nil
                }
                return template
            }
            if !templates.isEmpty { config.newFile.templates = templates }
        }

        var seenApps = Set<String>()
        config.apps = root.tableArray("app").compactMap { reader -> AppDescriptor? in
            guard let app = app(reader) else { return nil }
            guard seenApps.insert(app.id).inserted else {
                sink.error(reader.path + ["id"], "duplicate app id \"\(app.id)\"; the first definition is used")
                return nil
            }
            if KnownApps.app(id: app.id) != nil {
                sink.warning(reader.path + ["id"], "replaces the built-in app \"\(app.id)\"; use another id to add one beside it")
            }
            return app
        }
        for (index, template) in config.newFile.templates.enumerated() {
            guard let app = template.openWith else { continue }
            let path = ["new_file", "template", String(index + 1), "open_with"]
            guard let found = config.app(id: app) else {
                sink.error(path, "unknown app \"\(app)\"", suggestion: Suggestion.didYouMean(app, in: allAppIDs(config)))
                config.newFile.templates[index].openWith = nil
                continue
            }
            // A terminal handed a file runs it (a `.command` file, say), so it can never be what opens one.
            if found.role == .terminal {
                sink.error(path, "\"\(app)\" is a terminal, and a terminal handed a file runs it; name an editor or viewer")
                config.newFile.templates[index].openWith = nil
            }
        }
        config.terminal = checkedTerminal(terminalChoice, path: ["general", "terminal"], customApps: config.apps)
        if let editor = editorChoice {
            if let app = config.app(id: editor) {
                if app.role == .terminal {
                    sink.error(["general", "editor"], "\"\(editor)\" is a terminal, not an editor; set general.terminal for it")
                } else {
                    config.editor = editor
                }
            } else {
                sink.error(["general", "editor"], "unknown app \"\(editor)\"; the first installed editor is used instead",
                           suggestion: Suggestion.didYouMean(editor, in: allAppIDs(config)))
            }
        }

        if let agents = root.subtable("agent") {
            for id in agents.table.keys.sorted() {
                guard ConfigParser.isIdentifier(id) else {
                    sink.error(["agent", id], "agent ids use lowercase letters, digits and dashes")
                    continue
                }
                guard let reader = agents.subtable(id) else { continue }
                agent(id: id, reader: Reader(table: reader.table, path: reader.path, schema: agentSchema, sink: sink), into: &config)
            }
        }

        let agentIDs = (config.customAgents + KnownAgents.all).map(\.id)
        for id in agentChoices {
            if agentIDs.contains(id) {
                if !config.enabledAgents.contains(id) { config.enabledAgents.append(id) }
            } else if !sink.rejectedAgents.contains(id) {
                sink.error(["general", "agents"], "unknown agent \"\(id)\"; known agents: " + agentIDs.joined(separator: ", "),
                           suggestion: Suggestion.didYouMean(id, in: agentIDs))
            }
        }
        // An agent the config defines is not in the menu until general.agents lists it, and nothing else says so.
        for agent in config.customAgents where !config.enabledAgents.contains(agent.id) {
            sink.warning(["agent", agent.id], "defined, but not in general.agents, so the menu does not offer it (it still runs as `rh run agent.\(agent.id)`); add \"\(agent.id)\" to general.agents")
        }
        return config
    }

    private var agentSchema: [SchemaNode] {
        ConfigSchema.root.first(where: { $0.key == "agent" })?.children ?? []
    }

    private func allAppIDs(_ config: Config) -> [String] {
        (config.apps + KnownApps.all).map(\.id)
    }

    private func checkedTerminal(_ id: String?, path: [String], customApps: [AppDescriptor]) -> String? {
        guard let id else { return nil }
        // An `[[app]]` with a built-in id replaces the built-in, role included, so the choice is checked
        // against the apps as they will be, not against the built-in list.
        let replaced = Set(customApps.map(\.id))
        let apps = customApps + KnownApps.all.filter { !replaced.contains($0.id) }
        let terminals = apps.filter { $0.role == .terminal }.map(\.id)
        guard terminals.contains(id) else {
            if let other = apps.first(where: { $0.id == id }) {
                sink.error(path, "\"\(id)\" is defined with role \"\(other.role.rawValue)\", not as a terminal; known terminals: " + terminals.joined(separator: ", "))
            } else {
                sink.error(path, "unknown terminal \"\(id)\"; known terminals: " + terminals.joined(separator: ", ") + ". The first installed terminal is used instead.",
                           suggestion: Suggestion.didYouMean(id, in: terminals))
            }
            return nil
        }
        return id
    }

    private func template(_ reader: Reader) -> NewFileTemplate? {
        reader.checkKnownKeys()
        guard let id = reader.string("id"), let title = reader.string("title"), let ext = reader.string("extension") else {
            sink.error(reader.path, "a template needs id, title and extension")
            return nil
        }
        guard ConfigParser.isIdentifier(id) else {
            sink.error(reader.path + ["id"], "ids use lowercase letters, digits and dashes")
            return nil
        }
        if ext.containsAnyScalar(of: [".", "/", "\0"]) || ext.isEmpty {
            sink.error(reader.path + ["extension"], "write the extension without a dot or slash, and not empty")
            return nil
        }
        let baseName = reader.string("base_name") ?? "untitled"
        if baseName.isEmpty || baseName == "." || baseName == ".." || baseName.containsAnyScalar(of: ["/", "\0"]) {
            sink.error(reader.path + ["base_name"], "a file name cannot be empty, \".\" or \"..\", or contain a slash")
            return nil
        }
        // APFS allows 255 bytes in a name; a number is added to avoid a clash (`name 2.md`), so leave room for it.
        if baseName.utf8.count + 1 + ext.utf8.count > 240 {
            sink.error(reader.path + ["base_name"], "base_name and extension together are too long for a file name (at most 240 bytes)")
            return nil
        }
        return NewFileTemplate(
            id: id, title: title, baseName: baseName,
            fileExtension: ext, contents: reader.string("contents") ?? "", openWith: reader.string("open_with")
        )
    }

    private func app(_ reader: Reader) -> AppDescriptor? {
        reader.checkKnownKeys()
        guard let id = reader.string("id"), let name = reader.string("name") else {
            sink.error(reader.path, "an app needs id and name")
            return nil
        }
        guard ConfigParser.isIdentifier(id) else {
            sink.error(reader.path + ["id"], "ids use lowercase letters, digits and dashes")
            return nil
        }
        let bundleIDs = reader.stringArray("bundle_ids") ?? reader.string("bundle_id").map { [$0] } ?? []
        guard !bundleIDs.isEmpty else {
            sink.error(reader.path, "an app needs bundle_id or bundle_ids")
            return nil
        }
        let roleName = reader.checkAllowed(reader.string("role"), key: "role", allowed: AppDescriptor.Role.allCases.map(\.rawValue))
        let role = roleName.flatMap(AppDescriptor.Role.init(rawValue:)) ?? .general
        var launch: TerminalLaunch?
        let open = reader.stringArray("open_args"), run = reader.stringArray("run_args")
        if open != nil || run != nil {
            if role != .terminal {
                sink.error(reader.path, "open_args and run_args only apply to an app with role = \"terminal\"")
            } else {
                for (key, argv) in [("open_args", open), ("run_args", run)] {
                    guard let argv else { continue }
                    if let first = argv.first, TemplateTerminalAdapter.isValidExecutable(first) { continue }
                    sink.error(reader.path + [key], "the first element must be an absolute path to a program, or start with {app}/")
                }
                if let run, !run.contains(where: { $0.contains("{command}") }) {
                    sink.error(reader.path + ["run_args"], "run_args has to place {command} somewhere, or the agent would not be started")
                }
                if let run, !run.contains(where: { $0.contains("{dir}") }), !(open ?? []).contains(where: { $0.contains("{dir}") }) {
                    sink.warning(reader.path + ["run_args"], "run_args does not use {dir}, so the session will not start in the folder")
                }
                // `{dir}` as an argument of its own is safe. Inside a string a shell reads (`sh -c "cd {dir}"`) a folder
                // called `x'; touch y; '` becomes shell syntax, which only the template's author can prevent.
                for (key, argv) in [("open_args", open), ("run_args", run)] {
                    guard let argv, Self.shellReadsAString(argv) else { continue }
                    if argv.contains(where: { $0 != "{dir}" && $0.contains("{dir}") }) {
                        sink.warning(reader.path + [key], "{dir} sits inside a string a shell will read, so a folder name can become shell syntax; pass {dir} as an argument of its own")
                    }
                }
                launch = TerminalLaunch(open: open, run: run)
            }
        }
        return AppDescriptor(id: id, name: name, bundleIDs: bundleIDs, role: role, launch: launch)
    }

    /// A shell is given a string to interpret: the program is a shell, or an element is a `-c` style option.
    private static func shellReadsAString(_ argv: [String]) -> Bool {
        let shells: Set<String> = ["sh", "bash", "zsh", "fish", "dash", "ksh", "{shell}"]
        if let first = argv.first, shells.contains(first.split(separator: "/").last.map(String.init) ?? first) { return true }
        return argv.contains { $0.hasPrefix("-") && !$0.hasPrefix("--") && $0.dropFirst().contains("c") && $0.dropFirst().allSatisfy(\.isLetter) }
    }

    private func agent(id: String, reader: Reader, into config: inout Config) {
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
            guard ConfigParser.isIdentifier(variantID) else {
                sink.error(variant.path + ["id"], "ids use lowercase letters, digits and dashes")
                return nil
            }
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
        let launcherName = reader.checkAllowed(reader.string("launcher"), key: "launcher", allowed: ["terminal", "link", "desktop"])
        let terminal = checkedTerminal(reader.string("terminal"), path: reader.path + ["terminal"], customApps: config.apps)
        switch launcherName {
        case "link"?: settings.launcher = .terminalLink
        case "desktop"?: settings.launcher = .desktop
        case "terminal"?: settings.launcher = .terminal(terminal)
        default: if let terminal { settings.launcher = .terminal(terminal) }
        }

        if KnownAgents.agent(id: id) != nil {
            settings.command = command
            settings.variants = variants
        } else {
            guard let name = reader.string("name"), let command else {
                if !sink.rejectedAgents.contains(id) { sink.error(reader.path, "an agent that is not built in needs name and command") }
                return
            }
            config.customAgents.append(AgentDescriptor(id: id, name: name, command: command, variants: variants))
        }
        config.agents[id] = settings
    }

}
