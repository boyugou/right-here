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

    public init(severity: Severity, path: String, message: String, line: Int? = nil, suggestion: String? = nil) {
        self.severity = severity
        self.path = path
        self.message = message
        self.line = line
        self.suggestion = suggestion
    }
}

public struct ConfigLoadResult: Sendable, Equatable {
    public var config: Config
    public var diagnostics: [ConfigDiagnostic]

    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
}

public enum ConfigParser {
    /// Parses config text. A file with a syntax error yields the default config plus the error;
    /// semantic problems are reported while everything valid is still applied.
    public static func parse(_ text: String) -> ConfigLoadResult {
        let sink = Sink()
        let root: TOMLTable
        do {
            root = try TOMLTable(source: text)
        } catch {
            sink.syntaxError(error.description)
            return ConfigLoadResult(config: .default, diagnostics: sink.items)
        }
        let config = Builder(sink: sink).build(Reader(table: root, path: [], schema: ConfigSchema.root, sink: sink))
        return ConfigLoadResult(config: config, diagnostics: sink.items)
    }
}

// MARK: - Diagnostics collection

private final class Sink {
    var items: [ConfigDiagnostic] = []

    func error(_ path: [String], _ message: String, suggestion: String? = nil) {
        items.append(ConfigDiagnostic(severity: .error, path: path.joined(separator: "."), message: message, suggestion: suggestion))
    }

    func warning(_ path: [String], _ message: String, suggestion: String? = nil) {
        items.append(ConfigDiagnostic(severity: .warning, path: path.joined(separator: "."), message: message, suggestion: suggestion))
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
            sink.warning(path + [key], "unknown key", suggestion: Suggestion.closest(to: key, in: known).map { "did you mean \"\($0)\"?" })
        }
    }

    func checkAllowed(_ value: String?, key: String, allowed: [String]) -> String? {
        guard let value else { return nil }
        guard allowed.contains(value) else {
            sink.error(path + [key], "\"\(value)\" is not one of " + allowed.joined(separator: ", "),
                       suggestion: Suggestion.closest(to: value, in: allowed).map { "did you mean \"\($0)\"?" })
            return nil
        }
        return value
    }
}

enum Suggestion {
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
            terminalChoice = general.string("terminal")
            editorChoice = general.string("editor")
            agentChoices = general.stringArray("agents") ?? []
        }

        if let menu = root.subtable("menu") {
            menu.checkKnownKeys()
            config.menuItems = menu.stringArray("items")
        }

        if let copyPath = root.subtable("copy_path") {
            copyPath.checkKnownKeys()
            if let names = copyPath.stringArray("styles") {
                config.copyPathStyles = names.compactMap { name in
                    if let style = PathStyle(rawValue: name) { return style }
                    sink.error(["copy_path", "styles"], "unknown style \"\(name)\"",
                               suggestion: Suggestion.closest(to: name, in: PathStyle.allCases.map(\.rawValue)).map { "did you mean \"\($0)\"?" })
                    return nil
                }
            }
        }

        if let newFile = root.subtable("new_file") {
            newFile.checkKnownKeys()
            if let then = newFile.checkAllowed(newFile.string("then"), key: "then", allowed: Config.AfterNewFile.allCases.map(\.rawValue)) {
                config.newFile.then = Config.AfterNewFile(rawValue: then) ?? .reveal
            }
            let templates = newFile.tableArray("template").compactMap(template)
            if !templates.isEmpty { config.newFile.templates = templates }
        }

        config.apps = root.tableArray("app").compactMap(app)
        config.terminal = checkedTerminal(terminalChoice, path: ["general", "terminal"], customApps: config.apps)
        if let editor = editorChoice {
            if config.app(id: editor) != nil {
                config.editor = editor
            } else {
                sink.error(["general", "editor"], "unknown app \"\(editor)\"",
                           suggestion: Suggestion.closest(to: editor, in: allAppIDs(config)).map { "did you mean \"\($0)\"?" })
            }
        }

        if let agents = root.subtable("agent") {
            for id in agents.table.keys.sorted() {
                guard Self.isIdentifier(id) else {
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
            } else {
                sink.error(["general", "agents"], "unknown agent \"\(id)\"; known agents: " + agentIDs.joined(separator: ", "),
                           suggestion: Suggestion.closest(to: id, in: agentIDs).map { "did you mean \"\($0)\"?" })
            }
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
        let terminals = (customApps + KnownApps.terminals).filter { $0.role == .terminal }.map(\.id)
        guard terminals.contains(id) else {
            sink.error(path, "unknown terminal \"\(id)\"; known terminals: " + terminals.joined(separator: ", "),
                       suggestion: Suggestion.closest(to: id, in: terminals).map { "did you mean \"\($0)\"?" })
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
        guard Self.isIdentifier(id) else {
            sink.error(reader.path + ["id"], "ids use lowercase letters, digits and dashes")
            return nil
        }
        if ext.contains(".") || ext.contains("/") {
            sink.error(reader.path + ["extension"], "write the extension without a dot or slash")
            return nil
        }
        return NewFileTemplate(
            id: id, title: title, baseName: reader.string("base_name") ?? "untitled",
            fileExtension: ext, contents: reader.string("contents") ?? ""
        )
    }

    private func app(_ reader: Reader) -> AppDescriptor? {
        reader.checkKnownKeys()
        guard let id = reader.string("id"), let name = reader.string("name") else {
            sink.error(reader.path, "an app needs id and name")
            return nil
        }
        guard Self.isIdentifier(id) else {
            sink.error(reader.path + ["id"], "ids use lowercase letters, digits and dashes")
            return nil
        }
        let bundleIDs = reader.stringArray("bundle_ids") ?? reader.string("bundle_id").map { [$0] } ?? []
        guard !bundleIDs.isEmpty else {
            sink.error(reader.path, "an app needs bundle_id or bundle_ids")
            return nil
        }
        let roleName = reader.checkAllowed(reader.string("role"), key: "role", allowed: AppDescriptor.Role.allCases.map(\.rawValue))
        return AppDescriptor(id: id, name: name, bundleIDs: bundleIDs, role: roleName.flatMap(AppDescriptor.Role.init(rawValue:)) ?? .general)
    }

    private func agent(id: String, reader: Reader, into config: inout Config) {
        reader.checkKnownKeys()
        let command = reader.string("command")
        let variants: [AgentDescriptor.Variant] = reader.tableArray("variant").compactMap { variant in
            variant.checkKnownKeys()
            guard let variantID = variant.string("id"), let title = variant.string("title") else {
                sink.error(variant.path, "a variant needs id and title")
                return nil
            }
            guard Self.isIdentifier(variantID) else {
                sink.error(variant.path + ["id"], "ids use lowercase letters, digits and dashes")
                return nil
            }
            return AgentDescriptor.Variant(id: variantID, title: title, arguments: variant.stringArray("arguments") ?? [])
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
                sink.error(reader.path, "an agent that is not built in needs name and command")
                return
            }
            config.customAgents.append(AgentDescriptor(id: id, name: name, command: command, variants: variants))
        }
        config.agents[id] = settings
    }

    static func isIdentifier(_ text: String) -> Bool {
        guard let first = text.utf8.first, first != UInt8(ascii: "-") else { return false }
        return text.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == UInt8(ascii: "-") }
    }
}
