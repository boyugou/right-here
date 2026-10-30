import Foundation

/// `[[app]]` entries and the default terminal and editor, which are checked against the apps as they will be.
extension ConfigBuilder {
    func readApps(_ root: ConfigReader, into config: inout Config) {
        config.apps = readUnique(root.tableArray("app"), kind: "app", id: \.id, read: app) { app, reader in
            if KnownApps.app(id: app.id) != nil {
                sink.warning(reader.path + ["id"], "replaces the built-in app \"\(app.id)\"; use another id to add one beside it")
            }
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
                           suggestion: Suggestion.didYouMean(editor, in: config.allApps.filter { $0.role != .terminal }.map { ($0.id, $0.name) }))
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
                           suggestion: Suggestion.didYouMean(id, in: apps.filter { $0.role == .terminal }.map { ($0.id, $0.name) }))
            }
            return nil
        }
        return id
    }

    private func app(_ reader: ConfigReader) -> AppDescriptor? {
        reader.checkKnownKeys()
        guard let id = reader.string("id"), let name = reader.string("name") else {
            reportMissing("an app", needs: ["id", "name"], in: reader)
            return nil
        }
        guard isValidID(id, at: reader.path + ["id"]) else { return nil }
        guard !AgentLauncher.reservedWords.contains(id) else {
            sink.error(reader.path + ["id"], "\"\(id)\" cannot be an app id: in `agent.<agent>@\(id)` it names a launcher, so an app called that could never be started as a terminal there; use another id")
            return nil
        }
        guard isPlainName(name, at: reader.path + ["name"], noun: "name") else { return nil }
        let bundleIDs = reader.stringArray("bundle_ids") ?? reader.string("bundle_id").map { [$0] } ?? []
        if reader.stringArray("bundle_ids") != nil, reader.string("bundle_id") != nil {
            sink.warning(reader.path + ["bundle_id"], "bundle_id is ignored because bundle_ids is set; use one of them")
        }
        guard !bundleIDs.isEmpty else {
            sink.error(reader.path, "an app needs bundle_id or bundle_ids")
            return nil
        }
        let roleName = reader.checkAllowed(reader.string("role"), key: "role", allowed: AppDescriptor.Role.allCases.map(\.rawValue))
        let role = roleName.flatMap(AppDescriptor.Role.init(rawValue:)) ?? .general
        // A terminal handed a file runs it (CLAUDE.md rule 3), and what makes Right Here hand an app files is its role: an entry that gives a terminal's bundle identifier (in any case: the system finds an
        // app by it whatever the case) another role is refused, whoever wrote it.
        if role != .terminal, let terminal = KnownApps.terminal(bundleIDs: bundleIDs) {
            sink.error(reader.path + ["role"], "\"\(name)\" has the bundle identifier of \(terminal.name), a terminal; a terminal handed a file runs it, so its role has to be \"terminal\"")
            return nil
        }
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
        // An entry that reuses a built-in id replaces that app but is still the same kind of app: it is started the way the
        // built-in is and keeps its place in the default order, unless it brings launch arguments of its own.
        let replaced = KnownApps.app(id: id).flatMap { $0.role == role ? $0 : nil }
        return AppDescriptor(
            id: id, name: name, bundleIDs: bundleIDs, role: role,
            driver: launch.map { .template($0) } ?? replaced?.driver ?? .openFolder,
            defaultRank: replaced?.defaultRank
        )
    }

    /// A shell is given a string to interpret: the program is a shell, or an element is a `-c` style option.
    private static func shellReadsAString(_ argv: [String]) -> Bool {
        let shells: Set<String> = ["sh", "bash", "zsh", "fish", "dash", "ksh", "{shell}"]
        if let first = argv.first, shells.contains(first.split(separator: "/").last.map(String.init) ?? first) { return true }
        return argv.contains { $0.hasPrefix("-") && !$0.hasPrefix("--") && $0.dropFirst().contains("c") && $0.dropFirst().allSatisfy(\.isLetter) }
    }
}
