import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

/// What the commands that change the config have in common: which file, a dry run, JSON, and how an answer and a refusal are printed.
struct ConfigEditOptions: ParsableArguments {
    @Flag(help: "Change this Mac's own file, config.local.toml (it wins over config.toml here and is never synced), instead of config.toml.")
    var local = false

    @Flag(name: .customLong("dry-run"), help: "Show what would change and write nothing.")
    var dryRun = false

    @Flag(help: "Print JSON.")
    var json = false

    var target: ConfigTarget { local ? .local : .shared }
}

enum ConfigEditSupport {
    static let discussion = """
    The change is the smallest that does it: every other character of the file stays as it is, comments included. It is checked before it is written, \
    so a change that would make the config invalid is refused and the file is left alone, and the text before the change is kept so that `rh config undo` \
    can put it back. Names of settings are the ones of `rh docs config`, joined by dots (`general.terminal`, `menu.items`, `agent.claude.args`); the position \
    of an entry of a list of tables is a number from 1 (`preset.2.title`).
    """

    /// Runs one change and prints its answer.
    static func run(_ operations: [ConfigOperation], options: ConfigEditOptions) throws {
        let runtime = Runtime()
        let change: ConfigChange
        do {
            change = try ConfigService(paths: runtime.paths).apply(operations, target: options.target, actor: .cli, dryRun: options.dryRun)
        } catch {
            throw Output.fail(describe(error))
        }
        try print(change, dryRun: options.dryRun, json: options.json)
    }

    static func print(_ change: ConfigChange, dryRun: Bool, json: Bool) throws {
        if json {
            try Output.json(change)
            return
        }
        let name = URL(fileURLWithPath: change.file).lastPathComponent
        if !change.changed {
            Output.print("\(name) already says that: \(change.summary)")
        } else {
            Output.print((dryRun ? "Would change " : "Changed ") + name + ": " + change.summary)
            for line in change.diff { Output.print(line) }
            if dryRun { Output.print("(--dry-run: nothing was written)") }
        }
        for warning in change.warnings { Output.print(warning) }
    }

    static func describe(_ error: Error) -> String {
        if let error = error as? LocalizedError, let text = error.errorDescription { return text }
        return String(describing: error)
    }

    /// Makes a request: the item or the entry it names is looked for under the lock of the config, in the file as it is then. What is wrong with the request is said on standard error.
    static func run(_ request: ConfigRequest, options: ConfigEditOptions) throws {
        let change: ConfigChange
        do {
            change = try ConfigService(paths: Runtime().paths).apply(request, target: options.target, actor: .cli, dryRun: options.dryRun)
        } catch let problem as ConfigRequest.Problem {
            switch problem {
            case .usage(let text): throw ValidationError(text)
            case .notFound(let text): throw Output.fail(text + " `rh config get \(request.key)` shows what it has.")
            }
        } catch {
            throw Output.fail(describe(error))
        }
        try print(change, dryRun: options.dryRun, json: options.json)
    }
}

extension ConfigCommand {
    struct GetValue: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Print a setting as the config file writes it.",
            discussion: "The value as it is in config.toml (or config.local.toml with --local), as TOML: `\"ghostty\"`, `true`, `[\"claude\", \"codex\"]`. A setting the file does not set is said to be not set; its default is in `rh docs config`."
        )

        @Argument(help: "The setting: general.terminal, menu.items, preset.2.title.")
        var key: String

        @Flag(help: "Read config.local.toml instead of config.toml.")
        var local = false

        @Flag(help: "Print JSON.")
        var json = false

        struct Answer: Encodable {
            var key: String
            var file: String
            var isSet: Bool
            var value: String?
        }

        func run() throws {
            do { _ = try ConfigDocument.node(at: key) } catch { throw Output.fail(ConfigEditSupport.describe(error)) }
            let target: ConfigTarget = local ? .local : .shared
            let service = ConfigService(paths: Runtime().paths)
            let document: ConfigDocument
            do { document = try service.document(of: target) } catch { throw Output.fail(ConfigEditSupport.describe(error)) }
            let file = service.file(of: target)
            let value = document.rawValue(at: key)
            if json {
                try Output.json(Answer(key: key, file: file.path, isSet: value != nil, value: value))
            } else if let value {
                Output.print(value)
            } else {
                Output.print("\(key) is not set in \(file.lastPathComponent)")
            }
        }
    }

    struct SetValue: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Set a setting.",
            discussion: ConfigEditSupport.discussion + """


            The value is the argument as it is (never read as TOML or by a shell): one text, a whole number, `true` or `false`, or for a list any number of texts, none for an \
            empty list. Example: `rh config set general.agents claude codex`.
            """
        )

        @Argument(help: "The setting: general.terminal, general.agents, copy_path.title.")
        var key: String

        @Argument(help: "The value; for a list, its items. Put -- before one that starts with a dash.")
        var values: [String] = []

        @OptionGroup var options: ConfigEditOptions

        func run() throws {
            try ConfigEditSupport.run(ConfigRequest(.set, key, values: values), options: options)
        }
    }

    struct UnsetValue: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "unset",
            abstract: "Remove a setting from the file, so that its default applies.",
            discussion: ConfigEditSupport.discussion
        )

        @Argument(help: "The setting to remove.")
        var key: String

        @OptionGroup var options: ConfigEditOptions

        func run() throws {
            try ConfigEditSupport.run(ConfigRequest(.unset, key), options: options)
        }
    }

    struct AddItem: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add items to a list, an entry to a list of tables, or an agent of your own.",
            discussion: ConfigEditSupport.discussion + """


            For a list of text (`menu.items`, `general.agents`, `copy_path.styles`) the arguments are the items: `rh config add menu.items open-editor --at 2`. For a list of tables \
            (`preset`, `app`, `new_file.template`, `agent.<id>.variant`) they are the fields of the new entry, `name=value`: \
            `rh config add preset id=review title=Review prompt='Review {files}' agent=claude`. A list a field takes is given by repeating the field.

            A program of your own (lazygit, aider, a script) is an agent: `rh config add agent.lazygit name=lazygit command=lazygit` makes its table and puts it in `general.agents` in one change. \
            Its command is a program, so an AI assistant that asks for it is held for you (`rh config pending`).
            """
        )

        @Argument(help: "The list: menu.items, general.agents, preset.")
        var key: String

        @Argument(help: "The items, or the fields name=value. Put -- before one that starts with a dash.")
        var values: [String] = []

        @Option(help: "Where to put it, from 1 (first, last). At the end without it.")
        var at: String?

        @OptionGroup var options: ConfigEditOptions

        func run() throws {
            try ConfigEditSupport.run(ConfigRequest(.add, key, values: values, at: at), options: options)
        }
    }

    struct RemoveItem: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Remove an item from a list, an entry from a list of tables, or an agent of your own.",
            discussion: ConfigEditSupport.discussion + """


            The item is named by its text (a list of text) or its id (a list of tables): `rh config remove menu.items open-editor`, `rh config remove preset review`. \
            `--position` names it by its place instead. A comment above an entry goes with it. An agent of your own is removed by its table, `rh config remove agent.lazygit`, which \
            takes it out of `general.agents` first.
            """
        )

        @Argument(help: "The list: menu.items, general.agents, preset.")
        var key: String

        @Argument(help: "The item's text, or the entry's id.")
        var item: String?

        @Option(help: "The item's place in the list, from 1, instead of its name.")
        var position: Int?

        @OptionGroup var options: ConfigEditOptions

        func run() throws {
            try ConfigEditSupport.run(ConfigRequest(.remove, key, item: item, position: position), options: options)
        }
    }

    struct MoveItem: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "move",
            abstract: "Move an item of a list, or an entry of a list of tables, to another place.",
            discussion: ConfigEditSupport.discussion + """


            `rh config move menu.items open-editor --to 1` makes it the first. The other items keep their order, and a comment travels with the item it is above.
            """
        )

        @Argument(help: "The list: menu.items, general.agents, preset.")
        var key: String

        @Argument(help: "The item's text, or the entry's id.")
        var item: String?

        @Option(help: "The place to move it to, from 1, or first or last.")
        var to: String

        @Option(help: "The item's place in the list, from 1, instead of its name.")
        var position: Int?

        @OptionGroup var options: ConfigEditOptions

        func run() throws {
            try ConfigEditSupport.run(ConfigRequest(.move, key, item: item, position: position, to: to), options: options)
        }
    }

    struct UndoEdit: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "undo",
            abstract: "Put the config back as it was before the last change made with `rh config`, in the window or by an agent.",
            discussion: """
            Each change keeps the text before it (`rh config history` lists them, newest first); this puts the newest back and forgets it. It refuses when the file \
            was changed after that change (by hand, or by something else), since that change would be undone with it: --force undoes anyway.
            """
        )

        @Flag(help: "Undo for config.local.toml instead of config.toml.")
        var local = false

        @Flag(help: "Undo even though the file was changed after the last change.")
        var force = false

        @Flag(name: .customLong("dry-run"), help: "Show what would change and write nothing.")
        var dryRun = false

        @Flag(help: "Print JSON.")
        var json = false

        func run() throws {
            let runtime = Runtime()
            let change: ConfigChange
            do {
                change = try ConfigService(paths: runtime.paths).undo(target: local ? .local : .shared, force: force, dryRun: dryRun)
            } catch {
                throw Output.fail(ConfigEditSupport.describe(error))
            }
            try ConfigEditSupport.print(change, dryRun: dryRun, json: json)
        }
    }

    struct EditHistory: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "history",
            abstract: "List the changes that `rh config undo` can take back, newest first.",
            discussion: "Each line says when, by whom (window, cli or mcp) and what."
        )

        @Flag(help: "List the changes of config.local.toml instead of config.toml.")
        var local = false

        @Flag(help: "Print JSON.")
        var json = false

        struct Item: Encodable {
            var time: String
            var by: String
            var change: String
        }

        func run() throws {
            let runtime = Runtime()
            let formatter = ISO8601DateFormatter()
            let items = ConfigService(paths: runtime.paths).history(of: local ? .local : .shared).map {
                Item(time: formatter.string(from: $0.time), by: $0.actor.rawValue, change: $0.summary)
            }
            if json {
                try Output.json(items)
            } else if items.isEmpty {
                Output.print("No change to take back.")
            } else {
                for item in items { Output.print("\(item.time)  \(Output.column(item.by, 6))\(item.change)") }
            }
        }
    }
}
