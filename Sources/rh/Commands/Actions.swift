import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

struct Actions: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the actions rh can run.",
        discussion: "Each row is an action id for `rh run`, with whether it can run on this machine."
    )

    @Flag(help: "Print JSON.")
    var json = false

    @Flag(help: "Include actions that cannot run here, with the reason.")
    var all = false

    func run() throws {
        let runtime = Runtime()
        let registry = ActionRegistry(config: runtime.config, facts: runtime.facts)
        let infos = registry.catalog().filter { all || $0.available }
        if json {
            try Output.json(infos)
            return
        }
        let width = (infos.map(\.id.count).max() ?? 0) + 2
        for info in infos {
            let id = info.id.padding(toLength: width, withPad: " ", startingAt: 0)
            Output.print(id + info.title + (info.available ? "" : "   [unavailable: \(info.unavailableReason ?? "")]"))
        }
    }
}

struct MenuCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "menu",
        abstract: "Preview the Finder menu for a selection.",
        discussion: "Prints the menu Finder would show, built from your config. Use it after editing the config."
    )

    @OptionGroup var context: ContextOptions

    @Option(help: "Show the menu in this language, for example de or zh-Hans. The Finder menu follows the system language.")
    var language: String?

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        let runtime = Runtime()
        runtime.reportConfigProblems()
        let here = try context.makeContext(facts: runtime.facts)
        let localizer = language.map { Localizer(languages: [$0]) } ?? .english
        let menu = MenuBuilder(config: runtime.config, facts: runtime.facts, localizer: localizer).build(for: here)
        if json {
            try Output.json(menu)
        } else {
            Output.print(Self.describe(here) + ":")
            Output.print(Self.render(menu, indent: 0))
        }
    }

    /// What the preview is for, since the menu depends on it: a menu on a selection differs from one on a folder.
    static func describe(_ here: HereContext) -> String {
        switch here.origin {
        case .items, .services, .sidebar, .toolbar:
            if here.items.isEmpty, let container = here.container { return "Menu for the folder \(container.path.withControlCharactersEscaped) (\(here.origin.rawValue))" }
            let names = here.items.prefix(3).map(\.lastPathComponent).joined(separator: ", ").withControlCharactersEscaped
            return "Menu for \(here.items.count) selected item\(here.items.count == 1 ? "" : "s") (\(here.origin.rawValue)): \(names)" + (here.items.count > 3 ? ", …" : "")
        case .container:
            return "Menu for the folder \((here.container?.path ?? "?").withControlCharactersEscaped) (container)"
        case .cli:
            return "Menu for the current folder (cli; pass a path or --container to preview another)"
        }
    }

    static func render(_ nodes: [MenuNode], indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        return nodes.map { node in
            switch node.kind {
            case .separator: return pad + "-----"
            case .action: return pad + node.title + "    (" + (node.actionID ?? "") + ")"
            case .submenu: return pad + node.title + " >\n" + render(node.children, indent: indent + 1)
            }
        }.joined(separator: "\n")
    }
}

struct Agents: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the AI agents rh knows, and which are set up.")

    @Flag(help: "Print JSON.")
    var json = false

    struct Row: Encodable {
        var id: String
        var name: String
        var command: String
        var enabled: Bool
        var foundInShell: Bool
        var variants: [String]
        var terminalLink: Bool
        var desktopLink: Bool
    }

    func run() async throws {
        let runtime = Runtime()
        let all = (runtime.config.customAgents + KnownAgents.all).compactMap { runtime.config.agent(id: $0.id) }
        let found = await Detector(facts: runtime.facts).commandsFound(all.map { $0.command.split(separator: " ").first.map(String.init) ?? $0.command })
        let rows = all.map { agent in
            Row(
                id: agent.id, name: agent.name, command: agent.command,
                enabled: runtime.config.enabledAgents.contains(agent.id),
                foundInShell: found.contains(agent.command.split(separator: " ").first.map(String.init) ?? agent.command),
                variants: agent.variants.map(\.id), terminalLink: agent.terminalLink != nil, desktopLink: agent.desktopLink != nil
            )
        }
        if json {
            try Output.json(rows)
            return
        }
        for row in rows {
            let state = row.enabled ? "enabled" : (row.foundInShell ? "found, not enabled" : "not found")
            Output.print("\(row.id.padding(toLength: 12, withPad: " ", startingAt: 0))\(row.name.padding(toLength: 16, withPad: " ", startingAt: 0))\(state)")
        }
    }
}

struct Apps: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the terminals and editors rh knows, and which are installed.")

    @Flag(help: "Print JSON.")
    var json = false

    struct Row: Encodable {
        var id: String
        var name: String
        var role: String
        var installed: Bool
        var bundleID: String?
    }

    func run() throws {
        let runtime = Runtime()
        let apps = runtime.config.allApps
        let rows = apps.map { app -> Row in
            let bundleID = app.installedBundleID(facts: runtime.facts)
            return Row(id: app.id, name: app.name, role: app.role.rawValue, installed: bundleID != nil, bundleID: bundleID)
        }
        if json {
            try Output.json(rows)
            return
        }
        func line(_ id: String, _ name: String, _ role: String, _ state: String) -> String {
            id.padding(toLength: 16, withPad: " ", startingAt: 0) + name.padding(toLength: 22, withPad: " ", startingAt: 0)
                + role.padding(toLength: 10, withPad: " ", startingAt: 0) + state
        }
        Output.print(line("ID", "NAME", "ROLE", "INSTALLED"))
        for row in rows { Output.print(line(row.id, row.name, row.role, row.installed ? "installed" : "-")) }
    }
}
