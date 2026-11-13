import Foundation

/// What a config must satisfy before it is copied to or from a sync folder: a file that is read, trusted and
/// copied between machines has to be one the parser accepts, of a sane size, and free of anything that looks like a secret.
public enum SyncValidation {
    /// Key names that suggest a credential, compared in lowercase with dashes read as underscores.
    public static let secretWords = ["token", "secret", "password", "api_key"]

    public enum Problem: Sendable, Equatable {
        case tooLarge(bytes: Int)
        /// The file is there but cannot be read (no permission, not a regular file).
        case unreadable(reason: String)
        case notUTF8
        /// The first error the parser reports, as one line.
        case invalid(String)
        /// Valid alone, and not with this Mac's `config.local.toml` laid over it, as a click reads it: the first error of that reading.
        case invalidWithThisMacsFile(String)
        /// Dotted paths of the keys.
        case secretKeys([String])

        /// The message with what it quotes of a config (the parser's first error, key names) marked as data (`Fence`): the config can come from a folder that
        /// other machines write, and the sentence stands next to advice that an AI assistant reads.
        public var fencedMessage: String {
            switch self {
            case .invalid(let reason): Problem.invalid(Fence.wrap(reason)).message
            case .invalidWithThisMacsFile(let reason): Problem.invalidWithThisMacsFile(Fence.wrap(reason)).message
            case .secretKeys(let keys): Problem.secretKeys(keys.map(Fence.wrap)).message
            case .tooLarge, .unreadable, .notUTF8: message
            }
        }

        /// No final period: a message ends a sentence of its own in the places that join several (`Refusing ...; ... Nothing was changed.`).
        public var message: String {
            switch self {
            case .tooLarge(let bytes): "the file is \(bytes / 1024) KB; a config is a few kilobytes (the limit is \(ConfigParser.maxBytes / 1024) KB)"
            case .unreadable(let reason): "the file cannot be read (\(reason))"
            case .notUTF8: "the file is not valid UTF-8"
            case .invalid(let reason): "the config is not valid: \(reason.hasSuffix(".") ? String(reason.dropLast()) : reason). Run `rh config validate`"
            case .invalidWithThisMacsFile(let reason):
                "the config is valid alone, and not with this Mac's config.local.toml laid over it, which is how a click reads it: \(reason.hasSuffix(".") ? String(reason.dropLast()) : reason)"
            case .secretKeys(let keys): "the config has key names that suggest a secret (\(keys.joined(separator: ", "))); a synced config must not hold credentials. Keep them in the environment or the keychain"
            }
        }
    }

    /// The copy read as a click on this Mac would read it, with `overlay` (`config.local.toml`) laid over it: a copy that is valid alone can make the merged text
    /// break a limit of the parser (a dotted key is a table and a key once it is written out), and the whole config, this Mac's own file included, would then run
    /// as the defaults.
    public static func check(_ data: Data, overlay: Data?) -> [Problem] {
        let alone = check(data)
        guard alone.isEmpty, let overlay, let text = String(data: data, encoding: .utf8), let local = String(data: overlay, encoding: .utf8) else { return alone }
        let merged = ConfigLayers.load(base: .text(text), local: .text(local))
        // An error that this Mac's file has alone is that file's, and the doctor says it already; only what the copy brings to the merge stops a pull.
        let ownErrors = Set(ConfigLayers.load(base: .absent, local: .text(local)).diagnostics.filter { $0.severity == .error }.map(\.message))
        guard let first = merged.diagnostics.first(where: { $0.severity == .error && !ownErrors.contains($0.message) }) else { return [] }
        return [.invalidWithThisMacsFile(first.summary(file: URL(fileURLWithPath: "config.toml")))]
    }

    public static func check(_ data: Data) -> [Problem] {
        if data.count > ConfigParser.maxBytes { return [.tooLarge(bytes: data.count)] }
        guard var text = String(data: data, encoding: .utf8) else { return [.notUTF8] }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        var problems: [Problem] = []
        let parsed = ConfigParser.parse(text)
        if let first = parsed.diagnostics.first(where: { $0.severity == .error }) {
            problems.append(.invalid(first.summary(file: URL(fileURLWithPath: "config.toml"))))
        }
        if let tree = ConfigParser.readTree(text).tree {
            let keys = secretKeys(in: tree)
            if !keys.isEmpty { problems.append(.secretKeys(keys)) }
        }
        return problems
    }

    static func secretKeys(in table: [String: TOMLValue], path: [String] = []) -> [String] {
        var found: [String] = []
        for key in table.keys.sorted() {
            let here = path + [key]
            let normalized = key.lowercased().replacingOccurrences(of: "-", with: "_")
            // The names are printed (a refusal lists them), and a key is whatever the file's author typed.
            if secretWords.contains(where: normalized.contains) { found.append(here.joined(separator: ".").withControlCharactersEscaped) }
            if let value = table[key] { found += secretKeys(in: value, path: here) }
        }
        return found
    }

    private static func secretKeys(in value: TOMLValue, path: [String]) -> [String] {
        switch value {
        case .table(let nested): return secretKeys(in: nested, path: path)
        case .array(let items): return items.flatMap { secretKeys(in: $0, path: path) }
        default: return []
        }
    }
}
