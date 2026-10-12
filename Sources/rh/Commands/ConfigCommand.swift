import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Inspect, check and create the config file.",
        subcommands: [Path.self, Show.self, Validate.self, Schema.self]
    )

    struct Path: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print where the config file is.")

        func run() {
            Output.print(Runtime().paths.configFile.path)
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print the config file.")

        func run() throws {
            let runtime = Runtime()
            guard runtime.loaded.fileExists else {
                throw Output.fail("No config file yet at \(runtime.paths.configFile.path). Run `rh init` to create one.")
            }
            Output.print(try String(contentsOf: runtime.paths.configFile, encoding: .utf8))
        }
    }

    struct Validate: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check the config file and report every problem.",
            discussion: "Exits with status 1 when there are errors. Warnings (unknown keys) do not fail the check."
        )

        @Flag(help: "Print JSON.")
        var json = false

        struct Report: Encodable {
            var file: String
            var exists: Bool
            var ok: Bool
            var diagnostics: [ConfigDiagnostic]
        }

        func run() throws {
            let runtime = Runtime()
            let result = runtime.loaded.result
            let report = Report(file: runtime.paths.configFile.path, exists: runtime.loaded.fileExists, ok: !result.hasErrors, diagnostics: result.diagnostics)
            if json {
                try Output.json(report)
            } else if !runtime.loaded.fileExists {
                Output.print("No config file at \(report.file); defaults apply. Run `rh init` to create one.")
            } else if result.diagnostics.isEmpty {
                Output.print("ok: \(report.file)")
            } else {
                for diagnostic in result.diagnostics { Output.print(diagnostic.summary(file: runtime.loaded.file)) }
            }
            if result.hasErrors { throw ExitCode(1) }
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
        abstract: "Create the config file, filled in from what is installed.",
        discussion: "Detects your terminals, editors and agent commands (through your login shell) and writes a commented config. An existing file is kept unless --force is given."
    )

    @Flag(help: "Replace an existing config file.")
    var force = false

    func run() async throws {
        let runtime = Runtime()
        let detected = await Detector(facts: runtime.facts).detect()
        let wrote = try ConfigStore.initialize(paths: runtime.paths, detected: detected, force: force)
        if wrote {
            Output.print("Created \(runtime.paths.configFile.path)")
            Output.print("terminal: \(detected.terminal ?? "none found"), editor: \(detected.editor ?? "none found"), agents: \(detected.agents.isEmpty ? "none found" : detected.agents.joined(separator: ", "))")
            Output.print("Next: `rh menu` to preview the Finder menu, `rh doctor` to check the setup.")
        } else {
            Output.print("\(runtime.paths.configFile.path) already exists; kept it. Use --force to replace it.")
        }
    }
}
