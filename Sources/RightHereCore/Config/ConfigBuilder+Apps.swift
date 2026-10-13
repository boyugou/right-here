import Foundation

/// `[[app]]` entries and the default terminal and editor, which are checked against the apps as they will be.
extension ConfigBuilder {
    func readApps(_ root: ConfigReader, into config: inout Config) {
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
    }

    func resolveTerminalAndEditor(_ general: General, into config: inout Config) {
        config.terminal = checkedTerminal(general.terminal, path: ["general", "terminal"], customApps: config.apps)
        if let editor = general.editor {
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
    }

    func checkedTerminal(_ id: String?, path: [String], customApps: [AppDescriptor]) -> String? {
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

    private func app(_ reader: ConfigReader) -> AppDescriptor? {
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
}
