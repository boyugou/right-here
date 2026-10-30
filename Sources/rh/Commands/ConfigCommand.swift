import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Inspect, check and change the config file.",
        subcommands: [
            Path.self, Show.self, Validate.self, Schema.self, GetValue.self, SetValue.self, UnsetValue.self, AddItem.self, RemoveItem.self, MoveItem.self,
            UndoEdit.self, EditHistory.self, Pending.self, ConfigSyncCommand.self
        ]
    )

    struct Path: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print where the config file is.",
            discussion: "With --all, every file that makes up the config: config.toml, then config.local.toml (the per-machine overlay) when it exists."
        )

        @Flag(help: "Print every file that makes up the config, one per line, in the order they are read.")
        var all = false

        func run() {
            let runtime = Runtime()
            Output.print(runtime.paths.configFile.path)
            if all, runtime.loaded.localFileExists { Output.print(runtime.paths.localConfigFile.path) }
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the files that make up the config.",
            discussion: """
            Each file is printed as it is, under a line `==> <path> <==` that names it: config.toml, then config.local.toml \
            (the per-machine overlay) when it exists. There is no merged text; `rh menu` shows what the two make of the menu.
            """
        )

        func run() throws {
            let runtime = Runtime()
            var printed = 0
            for file in [runtime.paths.configFile, runtime.paths.localConfigFile] {
                switch ConfigStore.text(of: file) {
                case .absent: continue
                case .problem(let reason):
                    throw Output.fail("Cannot show \(file.path.withControlCharactersEscaped): \(reason.withControlCharactersEscaped)")
                case .text(let text):
                    if printed > 0 { Output.print("") }
                    Output.print("==> \(file.path.withControlCharactersEscaped) <==")
                    Output.print(text.hasSuffix("\n") ? String(text.dropLast()) : text)
                    printed += 1
                }
            }
            guard printed > 0 else {
                throw Output.fail("No config file yet at \(runtime.paths.configFile.path). Run `rh setup` to create one.")
            }
        }
    }

    struct Validate: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check the config file and report every problem.",
            discussion: """
            Exits with status 1 when there are errors. Warnings (unknown keys, unknown menu entries, an app that \
            replaces a built-in one) do not fail the check by default, because the rest of the file still applies; \
            but they are nearly always mistakes, so use --strict to fail on them too. Each problem names its file and \
            line. A note (`note:`) says what the config did on purpose, such as leaving out a shared preset whose \
            agent this Mac disables; it never fails the check. With a config.local.toml, config.toml is also checked \
            on its own, because other Macs read it that way: an error the overlay hides on this Mac still counts, and \
            so does a key named like a credential, which `rh config sync push` refuses.
            """
        )

        @Flag(help: "Print JSON.")
        var json = false

        @Flag(help: "Also exit with status 1 when there are warnings.")
        var strict = false

        struct Report: Encodable {
            var file: String
            var exists: Bool
            /// The per-machine overlay, `config.local.toml`, and whether it exists.
            var localFile: String
            var localExists: Bool
            /// No errors.
            var ok: Bool
            /// No errors and no warnings.
            var clean: Bool
            var diagnostics: [ConfigDiagnostic]
            /// What the config did that is no mistake (see `ConfigLoadResult.notes`).
            var notes: [ConfigDiagnostic]
        }

        func run() throws {
            let runtime = Runtime()
            // Each file is checked on its own as well: what the overlay hides on this Mac is what other Macs read.
            let loaded = ConfigStore.load(paths: runtime.paths, validating: true)
            let result = loaded.resultWithMenuCheck(facts: runtime.facts)
            let report = Report(file: runtime.paths.configFile.path, exists: loaded.fileExists,
                                localFile: runtime.paths.localConfigFile.path, localExists: loaded.localFileExists, ok: !result.hasErrors,
                                clean: result.diagnostics.isEmpty, diagnostics: result.diagnostics, notes: result.notes)
            if json {
                try Output.json(report)
            } else if !loaded.fileExists && !loaded.localFileExists {
                Output.print("No config file at \(report.file); defaults apply. Run `rh setup` to create one.")
            } else {
                if result.diagnostics.isEmpty {
                    Output.print("ok: \(report.file)" + (loaded.localFileExists ? " and \(report.localFile)" : ""))
                }
                for diagnostic in result.diagnostics + result.notes { Output.print(diagnostic.summary(file: loaded.file)) }
            }
            if result.hasErrors || (strict && !result.diagnostics.isEmpty) { throw ExitCode(1) }
        }
    }

    struct Schema: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the JSON Schema of the config file.",
            discussion: "Editors with TOML schema support (for example Taplo) can use it for completion and checking."
        )

        func run() throws {
            let data = try JSONSerialization.data(withJSONObject: ConfigSchema.jsonSchema(), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            Output.print(String(decoding: data, as: UTF8.self))
        }
    }
}

struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create the config file, filled in from what is installed and what you say.",
        discussion: """
        Only the config file: `rh setup` does this and connects Finder as well. The terminals, editors and agent commands on this \
        Mac (the agents through your login shell) are found, and --terminal, --editor and --agents say what you use instead; the \
        file is written commented, for you to edit. A file that exists is never rewritten: the lines that would make it say what \
        you asked for are listed instead, and --force replaces it (the old one is saved next to it first).
        """
    )

    @OptionGroup var choices: ChoiceOptions

    @Flag(help: "Replace a config file that exists, after saving it next to itself. Only when you asked to start the config over.")
    var force = false

    func run() async throws {
        let chosen = try choices.choices()
        let runner = try SetupCommandSupport.runner()
        let report = try await SetupCommandSupport.run(SetupRequest(pieces: [.config], choices: chosen, force: force), with: runner)
        try SetupCommandSupport.finish(report, json: false, withTitle: false)
    }
}
