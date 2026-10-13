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
    public static let overlayFileName = "config.local.toml"

    public static func load(base: ConfigSource, local: ConfigSource, overlayName: String = overlayFileName) -> ConfigLoadResult {
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
            return ConfigLoadResult(config: built?.config ?? .default, diagnostics: baseDiagnostics + (built?.diagnostics ?? []) + localDiagnostics)
        }

        var baseTree: [String: TOMLValue] = [:]
        var baseUsable = false
        if let baseText {
            let read = ConfigParser.readTree(baseText)
            baseDiagnostics += read.diagnostics
            if let tree = read.tree { baseTree = tree; baseUsable = true }
        }
        let localRead = ConfigParser.readTree(localText)
        localDiagnostics += tagged(localRead.diagnostics)
        guard let localTree = localRead.tree else {
            // An overlay that cannot be read is left out; the shared file still applies.
            let built = baseUsable ? baseText.map(ConfigParser.parse) : nil
            return ConfigLoadResult(config: built?.config ?? .default,
                                    diagnostics: baseDiagnostics + (built?.diagnostics ?? []) + localDiagnostics)
        }

        let merged = ConfigMerge.merge(base: baseTree, local: localTree)
        var result = ConfigParser.parse(TOMLEmitter.emit(merged.root))
        result.diagnostics = result.diagnostics.map { attribute($0, to: merged, overlayName: overlayName) }
        if baseTree["disabled"] != nil {
            baseDiagnostics.append(ConfigDiagnostic(severity: .warning, path: "disabled", message: "only meaningful in \(overlayName), where it removes ids from the shared config; it does nothing here"))
        }
        if merged.disabledProblem {
            localDiagnostics.append(ConfigDiagnostic(severity: .error, path: "disabled", message: "expected an array of strings", file: overlayName))
        }
        for preset in merged.droppedPresets {
            localDiagnostics.append(ConfigDiagnostic(severity: .warning, path: "disabled", message: "the preset \"\(preset.id)\" is not offered on this machine: its agent \"\(preset.agent)\" is disabled", file: overlayName))
        }
        // The catalogs that are not in the file: built-in templates are removed from the list, built-in apps are marked
        // removed (they are found through `KnownApps`, which a config cannot edit).
        result.config.newFile.templates.removeAll { merged.disabled.contains($0.id) }
        result.config.disabledApps = Set(merged.disabled.filter { KnownApps.app(id: $0) != nil })
        result.diagnostics = baseDiagnostics + result.diagnostics + localDiagnostics
        return result
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
