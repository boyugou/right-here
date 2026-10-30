import Foundation

/// What was found for one config file: nothing, its text, or a reason it was not read (too big, not UTF-8).
public enum ConfigSource: Sendable, Equatable {
    case absent
    case text(String)
    case unreadable(ConfigDiagnostic)
}

/// The shared config plus the optional per-machine overlay, read as one set of settings (`ConfigMerge` has the rules).
///
/// The two files are merged as plain TOML values and the result is built once, so every check (unknown keys, ids,
/// an overlay entry naming an app that only the shared file defines) sees the settings as they will apply. Each
/// diagnostic is then traced back to the file and the position in that file it came from.
public enum ConfigLayers {
    /// The overlay of the default config file, `config.toml`.
    public static let overlayFileName = overlayName(forConfigFile: "config.toml")

    /// The overlay's name for a config file: `config.local.toml` for `config.toml`, `<name>.local.<extension>` for any other
    /// (`toml` when it has none). The one place that says it.
    public static func overlayName(forConfigFile name: String) -> String {
        let file = name as NSString
        return file.deletingPathExtension + ".local." + (file.pathExtension.isEmpty ? "toml" : file.pathExtension)
    }

    /// What is said when `disabled` is in the shared file, where it does nothing: the overlay is the only place it works.
    static func disabledInSharedFileMessage(overlayName: String = overlayFileName) -> String {
        "only meaningful in \(overlayName), where it removes ids from the shared config; it does nothing here"
    }

    /// - Parameter withOrigins: Also say where each entry of the lists of tables is written (`ConfigLoadResult.entryOrigins`). With an overlay the merge says it at no cost; for the shared file
    ///   alone it takes a second reading of the text, which the Finder extension, that only needs the settings, does not pay.
    public static func load(base: ConfigSource, local: ConfigSource, overlayName: String = overlayFileName, withOrigins: Bool = false) -> ConfigLoadResult {
        var baseDiagnostics: [ConfigDiagnostic] = []
        var localDiagnostics: [ConfigDiagnostic] = []
        func tagged(_ items: [ConfigDiagnostic]) -> [ConfigDiagnostic] {
            items.map { var item = $0; item.file = overlayName; return item }
        }

        var baseText: String?, localText: String?
        switch base {
        case .absent: break
        case .text(let text): baseText = text
        case .unreadable(let diagnostic): baseDiagnostics.append(diagnostic)
        }
        switch local {
        case .absent: break
        case .text(let text): localText = text
        case .unreadable(let diagnostic): localDiagnostics += tagged([diagnostic])
        }

        // No overlay: the file is built as it always was.
        guard let localText else {
            let built = baseText.map(ConfigParser.parse)
            var alone = ConfigLoadResult(config: built?.config ?? .default, diagnostics: baseDiagnostics + (built?.diagnostics ?? []) + localDiagnostics)
            if withOrigins, let baseText, let tree = ConfigParser.readTree(baseText).tree { alone.entryOrigins = entryOrigins(of: ConfigMerge.merge(base: tree, local: [:])) }
            return alone
        }

        var baseTree: [String: TOMLValue] = [:]
        var baseUsable = false
        if let baseText {
            let read = ConfigParser.readTree(baseText)
            baseDiagnostics += read.diagnostics
            if let tree = read.tree { baseTree = tree; baseUsable = true }
        }
        // An overlay that cannot be read is left out, and the shared file still applies.
        let localRead = ConfigParser.readTree(localText, consequence: ConfigParser.fileLeftOut)
        localDiagnostics += tagged(localRead.diagnostics)
        guard let localTree = localRead.tree else {
            // An overlay that cannot be read is left out; the shared file still applies.
            let built = baseUsable ? baseText.map(ConfigParser.parse) : nil
            return ConfigLoadResult(config: built?.config ?? .default,
                                    diagnostics: baseDiagnostics + (built?.diagnostics ?? []) + localDiagnostics)
        }

        let merged = ConfigMerge.merge(base: baseTree, local: localTree)
        // What the builder says about the merged text has no lines worth keeping: they count the emitted text, not a file.
        var result = ConfigParser.parseUnlocated(TOMLEmitter.emit(merged.root))
        result.diagnostics = result.diagnostics.map { attribute($0, to: merged, overlayName: overlayName) }
        if baseTree["disabled"] != nil {
            baseDiagnostics.append(ConfigDiagnostic(severity: .warning, path: "disabled", message: disabledInSharedFileMessage(overlayName: overlayName)))
        }
        if merged.disabledProblem {
            localDiagnostics.append(ConfigDiagnostic(severity: .error, path: "disabled", message: "expected an array of strings", file: overlayName))
        }
        // `disabled` is what the person wrote; a shared preset that needs a disabled agent is left out because of it, which is
        // expected. A warning could not be silenced (naming the preset in `disabled` changes nothing) and would fail --strict
        // for ever, so it is a note.
        var notes: [ConfigDiagnostic] = []
        for preset in merged.droppedPresets {
            notes.append(ConfigDiagnostic(severity: .note, path: "disabled", message: "the preset \"\(preset.id)\" is not offered on this machine: its agent \"\(preset.agent)\" is disabled", file: overlayName))
        }
        // The catalogs that are not in the file: built-in templates are removed from the list, built-in apps are marked
        // removed (they are found through `KnownApps`, which a config cannot edit).
        result.config.newFile.templates.removeAll { merged.disabled.contains($0.id) }
        result.config.disabledApps = Set(merged.disabled.filter { KnownApps.app(id: $0) != nil })
        result.config.disabledAgents = Set(merged.disabled.filter { KnownAgents.agent(id: $0) != nil })
        result.entryOrigins = entryOrigins(of: merged)
        // Each problem is put at its line in the file it belongs to, the shared file's first.
        let all = baseDiagnostics + result.diagnostics + localDiagnostics
        result.diagnostics = ConfigParser.locate(all.filter { $0.file == nil }, in: baseText ?? "")
            + ConfigParser.locate(all.filter { $0.file != nil }, in: localText)
        result.notes = ConfigParser.locate(notes, in: localText)
        return result
    }

    /// `load`, and what only a look at the shared file on its own finds. `rh config validate` uses this and the Finder menu does
    /// not (it needs the config, not a second reading of it on every right-click).
    ///
    /// - The shared file is what other Macs read, with none of this Mac's overlay. An error that the overlay masks here (it sets
    ///   the same key itself, replaces the entry, disables what the error is about) is real there, and `rh config sync push`
    ///   refuses the file for it: it parses `config.toml` alone, which is what is done here, so the two agree by construction.
    /// - A key named like a credential in the shared file is what `push` refuses, so it is an error here too.
    public static func validate(base: ConfigSource, local: ConfigSource, overlayName: String = overlayFileName) -> ConfigLoadResult {
        var result = load(base: base, local: local, overlayName: overlayName)
        guard case .text(let baseText) = base else { return result }
        var extra: [ConfigDiagnostic] = []
        if case .text = local {
            for error in ConfigParser.parse(baseText).diagnostics where error.severity == .error {
                // Reported already when the key has an error for the file as it applies here. The sentence need not be the same: it
                // lists the choices, and the merged ones include what the overlay defines. (A problem with the file as a whole has no
                // key, and is the same sentence.)
                guard !result.diagnostics.contains(where: {
                    $0.file == nil && $0.severity == .error && $0.path == error.path && (!error.path.isEmpty || $0.message == error.message)
                }) else { continue }
                extra.append(ConfigDiagnostic(severity: .error, path: error.path,
                                              message: error.message + "; \(overlayName.withControlCharactersEscaped) hides it on this Mac, but other Macs read this file as it is",
                                              line: error.line, suggestion: error.suggestion, replacement: error.replacement))
            }
        }
        if let tree = ConfigParser.readTree(baseText).tree {
            for path in SyncValidation.secretKeys(in: tree) {
                // The unknown-key warning for the same key says it as well, and is not repeated.
                let note = "named like a credential: `rh config sync` refuses a config with such a key name (token, secret, password, api_key); keep credentials in the environment or the keychain"
                if let index = result.diagnostics.firstIndex(where: { $0.file == nil && $0.path == path && $0.message == "unknown key" }) {
                    result.diagnostics[index].message += "; " + note.withControlCharactersEscaped
                    result.diagnostics[index].severity = .error
                } else {
                    extra.append(ConfigDiagnostic(severity: .error, path: path, message: "key " + note))
                }
            }
        }
        guard !extra.isEmpty else { return result }
        let others = result.diagnostics.filter { $0.file != nil }
        result.diagnostics = ConfigParser.locate(result.diagnostics.filter { $0.file == nil } + extra, in: baseText) + others
        return result
    }

    /// Where each entry of each list of tables of the merged config is written, in the order the config has them.
    private static func entryOrigins(of merged: ConfigMerge.Result) -> [String: [ConfigEntryOrigin]] {
        var found: [String: [ConfigEntryOrigin]] = [:]
        for (key, origins) in merged.arrayOrigins {
            var value: TOMLValue? = .table(merged.root)
            for segment in key.split(separator: ".") { value = value?.tableValue?[String(segment)] }
            guard let items = value?.arrayValue, items.count == origins.count else { continue }
            found[key] = zip(items, origins).map { item, origin in
                var id: String?
                if case .string(let text)? = item.tableValue?["id"] { id = text }
                return ConfigEntryOrigin(id: id, target: origin.layer == .base ? .shared : .local, position: origin.index)
            }
        }
        return found
    }

    /// Names the file a diagnostic belongs to and puts its position in terms of that file: entry 3 of the merged
    /// `[[app]]` list may be entry 1 of the overlay.
    private static func attribute(_ diagnostic: ConfigDiagnostic, to merged: ConfigMerge.Result, overlayName: String) -> ConfigDiagnostic {
        var diagnostic = diagnostic
        var segments = diagnostic.path.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
        var layer: ConfigMerge.Layer?
        for position in segments.indices {
            let key = segments[...position].joined(separator: ".")
            if let origins = merged.arrayOrigins[key], position + 1 < segments.count,
               let number = Int(segments[position + 1]), origins.indices.contains(number - 1) {
                let origin = origins[number - 1]
                segments[position + 1] = String(origin.index)
                layer = origin.layer
                break
            }
        }
        if layer == nil {
            for length in stride(from: segments.count, through: 1, by: -1) {
                if let found = merged.keyOrigins[segments[..<length].joined(separator: ".")] { layer = found; break }
            }
        }
        diagnostic.path = segments.joined(separator: ".")
        if layer == .local { diagnostic.file = overlayName }
        return diagnostic
    }
}
