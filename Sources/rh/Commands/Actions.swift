import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

struct Actions: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the actions rh can run.",
        discussion: "Each row is an action id for `rh run`. The plain list shows the actions that can run on this machine; --all adds the others, each with the reason it cannot run."
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
        // Titles and reasons are what the config named things (an app, a template), and a name can hold a control that acts on a
        // terminal, so they are printed with such characters as escapes.
        let width = (infos.map(\.id.count).max() ?? 0) + 2
        for info in infos {
            let id = Output.column(info.id, width)
            Output.print(id + info.title.withControlCharactersEscaped + (info.available ? "" : "   [unavailable: \((info.unavailableReason ?? "").withControlCharactersEscaped)]"))
        }
    }
}

struct MenuCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "menu",
        abstract: "Preview the Finder menu for a selection.",
        discussion: "Prints the menu Finder would show, built from your config. Use it after editing the config. --explain adds what the menu leaves out or changes, and why."
    )

    @OptionGroup var context: ContextOptions

    @Option(help: "Show the menu in this language, for example de or zh-Hans. The Finder menu follows general.language, or the system language.")
    var language: String?

    @Flag(help: "Print JSON.")
    var json = false

    @Flag(help: "Also list what the menu leaves out or changes, and why: an app that is not installed, no file selected for the presets, an agent the per-machine overlay disabled. With --json the output is {\"menu\": [...], \"notes\": [...]}.")
    var explain = false

    func run() throws {
        let runtime = Runtime()
        runtime.reportConfigProblems()
        let here = try context.makeContext(facts: runtime.facts)
        // The same rule as `rh run`: a preview of a menu for a path that is not there would only mislead.
        if let missing = here.firstMissingPath(facts: runtime.facts) { throw Output.fail("error: \(missing.path.withControlCharactersEscaped) does not exist.") }
        try Self.checkFolderForm(here, facts: runtime.facts)
        if let language, Localizer.match(language) == nil {
            throw ValidationError("No translation for \"\(language)\". Languages: " + Localizer.supportedLanguages.sorted().joined(separator: ", "))
        }
        let localizer = language.map { Localizer(languages: [$0]) } ?? .english
        let builder = MenuBuilder(config: runtime.config, facts: runtime.facts, localizer: localizer)
        let explanation: MenuExplanation
        if explain {
            // What a per-machine overlay disabled is the difference between the shared file's agents and the merged ones.
            let shared = runtime.loaded.localFileExists ? ConfigStore.sharedConfig(paths: runtime.paths) : nil
            explanation = builder.explain(for: here, sharedConfig: shared, overlayName: runtime.loaded.localFile.lastPathComponent)
        } else {
            explanation = MenuExplanation(menu: builder.build(for: here), notes: [])
        }
        if json {
            if explain { try Output.json(explanation) } else { try Output.json(explanation.menu) }
        } else {
            Output.print(Self.describe(here) + ":")
            if !explanation.menu.isEmpty { Output.print(Self.render(explanation.menu, indent: 0)) }
            if explain {
                Output.print(Self.render(explanation.notes))
            } else if explanation.menu.isEmpty {
                Output.print("(empty: `rh menu --explain` says why each entry is left out)")
            }
        }
    }

    /// `--origin container` and `--origin sidebar` are the menu of one folder, which `--container` names: a path given with it is a
    /// selection, and neither is a menu without a folder (it used to print `Menu for the folder ?`). `--container` is the folder being
    /// viewed, so a file there is a mistake, which a selection (the file as a path) is the way to preview.
    static func checkFolderForm(_ here: HereContext, facts: any SystemFacts) throws {
        if here.origin == .container || here.origin == .sidebar {
            if let first = here.items.first {
                throw ValidationError("--origin \(here.origin.rawValue) is the menu of one folder and needs --container <folder>; \(first.path.withControlCharactersEscaped) is a selection. Leave --origin out to preview the menu for it.")
            }
            if here.container == nil { throw ValidationError("--origin \(here.origin.rawValue) is the menu of one folder and needs --container <folder>.") }
        }
        if let container = here.container, facts.isDirectory(container) == false {
            throw ValidationError("--container needs a folder, and \(container.path.withControlCharactersEscaped) is a file. Give the file as a path to preview the menu for a selection.")
        }
    }

    /// What the menu leaves out and changes, as a short block after it.
    static func render(_ notes: [MenuNote]) -> String {
        guard !notes.isEmpty else { return "\nNothing is left out of this menu." }
        var lines: [String] = []
        for (kind, title) in [(MenuNote.Kind.leftOut, "Left out of this menu:"), (.changed, "Changed:")] {
            let these = notes.filter { $0.kind == kind }
            if these.isEmpty { continue }
            lines.append("")
            lines.append(title)
            lines += these.map { "  " + $0.line.withControlCharactersEscaped }
        }
        return lines.joined(separator: "\n")
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
            case .action: return pad + node.title.withControlCharactersEscaped + "    (" + (node.actionID ?? "") + ")"
            case .submenu: return pad + node.title.withControlCharactersEscaped + " >\n" + render(node.children, indent: indent + 1)
            }
        }.joined(separator: "\n")
    }
}

struct Agents: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the AI agents rh knows, and which are set up.")

    @Flag(help: "Print JSON.")
    var json = false

    func run() async throws {
        let runtime = Runtime()
        let shell = await Detector(facts: runtime.facts).probe(commands: runtime.config.allAgents.map(\.executable))
        let rows = runtime.config.agentRows(found: shell.found, shellAnswered: shell.answered, locations: shell.locations)
        if json {
            try Output.json(rows)
            return
        }
        // A header, as `rh apps` has: an agent reading the table is told which column is the id (docs/AGENT_SETUP.md).
        Output.print(Output.column("ID", 12) + Output.column("NAME", 16) + "STATE")
        for row in rows {
            Output.print(Output.column(row.id, 12) + Output.column(row.name.withControlCharactersEscaped, 16) + row.stateText)
        }
    }
}

struct Apps: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the terminals and editors rh knows, and which are installed.")

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        let runtime = Runtime()
        let rows = runtime.config.appRows(facts: runtime.facts)
        if json {
            try Output.json(rows)
            return
        }
        func line(_ id: String, _ name: String, _ role: String, _ state: String) -> String {
            Output.column(id, 16) + Output.column(name, 22) + Output.column(role, 10) + state
        }
        Output.print(line("ID", "NAME", "ROLE", "INSTALLED"))
        for row in rows { Output.print(line(row.id, row.name.withControlCharactersEscaped, row.role, row.installed ? "installed" : "-")) }
    }
}
