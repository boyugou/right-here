import Foundation
import RightHereCore

/// What an App Intent asks of the bundled `rh`. An intent never composes a command: it picks one of these cases,
/// and the arguments below are the only way the bundled `rh` is started. Paths and ids travel as argv entries, after
/// a `--` for paths, so no text of the person's is ever parsed by a shell or read as an option.
public enum IntentCommand: Sendable, Equatable {
    case openTerminal(folder: String)
    case startAgent(agent: String, folder: String)
    case newFile(template: String, folder: String)
    case copyPath(style: PathStyle, path: String)

    public enum Invalid: Error, Equatable, LocalizedError {
        case notAnActionID(String)
        case notAbsolute(String)

        public var errorDescription: String? {
            switch self {
            case .notAnActionID(let text): "\"\(text)\" is not a valid agent or template id."
            case .notAbsolute(let text): "\"\(text)\" is not an absolute path."
            }
        }
    }

    /// The argument vector for `rh`, or an error when an id is not a plain word or a path is not absolute. `languages` are the person's
    /// preferred languages, most preferred first: a new file takes its name in the first one the app has, as a file made from Finder does.
    public func arguments(languages: [String] = []) throws -> [String] {
        switch self {
        case .openTerminal(let folder):
            return try Self.run("open.terminal", path: folder, languages: languages)
        case .startAgent(let agent, let folder):
            return try Self.run("agent." + Self.word(agent), path: folder, languages: languages)
        case .newFile(let template, let folder):
            return try Self.run("new-file." + Self.word(template), path: folder, languages: languages)
        case .copyPath(let style, let path):
            return try Self.run("copy-path." + style.rawValue, path: path, languages: languages)
        }
    }

    private static func run(_ action: String, path: String, languages: [String]) throws -> [String] {
        guard ActionRef(parsing: action) != nil else { throw Invalid.notAnActionID(action) }
        guard path.hasPrefix("/"), !path.contains("\0") else { throw Invalid.notAbsolute(path) }
        return ["run", action, "--origin", "cli"] + languages.flatMap { ["--language", $0] } + ["--", path]
    }

    /// An id from the config goes into an action id only when `ActionRef` reads it back as one word.
    private static func word(_ id: String) throws -> String {
        guard !id.isEmpty, !id.contains("."), !id.contains("@"), ActionRef(parsing: "agent." + id) != nil else {
            throw Invalid.notAnActionID(id)
        }
        return id
    }
}

/// An agent or a template the intents offer, read from `rh agents --json` or `rh actions --json`.
public struct IntentChoice: Sendable, Equatable, Hashable {
    public var id: String
    public var name: String
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A pinned or recent folder the intents offer as a saved folder. Its path is its id, so a shortcut keeps naming the same folder when the
/// list changes.
public struct IntentFolder: Sendable, Equatable, Hashable {
    /// Where the folder is listed: among the pinned ones, among the recent ones, or nowhere any more (a shortcut made when it was).
    public enum Mark: Sendable, Equatable, Hashable {
        case pinned, recent, unlisted
    }

    public var path: String
    /// The folder's own name, which the list shows first.
    public var name: String
    /// The path with the home folder as `~`, which the list shows under the name.
    public var shown: String
    public var mark: Mark

    public init(path: String, name: String, shown: String, mark: Mark) {
        self.path = path
        self.name = name
        self.shown = shown
        self.mark = mark
    }
}

public enum IntentCatalog {
    /// Agents that are enabled or found in the login shell; the others would only fail with "not found".
    public static func agents(fromJSON data: Data) -> [IntentChoice] {
        guard let rows = try? JSONDecoder().decode([AgentRow].self, from: data) else { return [] }
        return rows.filter { $0.enabled || $0.foundInShell == true }.map { IntentChoice(id: $0.id, name: $0.name) }
    }

    /// The templates in `rh actions --json`: ids `new-file.<template>`, titled for the menu ("New Markdown File").
    public static func templates(fromJSON data: Data) -> [IntentChoice] {
        guard let infos = try? JSONDecoder().decode([ActionInfo].self, from: data) else { return [] }
        return infos.compactMap { info in
            guard info.available, info.id.hasPrefix("new-file."), case .newFile(let template)? = ActionRef(parsing: info.id) else { return nil }
            return IntentChoice(id: template, name: info.shortTitle.isEmpty ? info.title : info.shortTitle)
        }
    }

    /// The saved folders: the pinned ones first, then the recent ones that are not pinned, as `rh pins --json` and `rh recents --json` list
    /// them (each an array of absolute paths). A path that is not absolute is left out: `rh` never writes one, and an intent passes the id on as a
    /// path.
    public static func folders(pinsJSON: Data, recentsJSON: Data, home: String) -> [IntentFolder] {
        let pins = (try? JSONDecoder().decode([String].self, from: pinsJSON)) ?? []
        let recents = (try? JSONDecoder().decode([String].self, from: recentsJSON)) ?? []
        var seen = Set<String>()
        var folders: [IntentFolder] = []
        for (path, mark) in pins.map({ ($0, IntentFolder.Mark.pinned) }) + recents.map({ ($0, .recent) }) where path.hasPrefix("/") && seen.insert(path).inserted {
            folders.append(folder(path: path, home: home, mark: mark))
        }
        return folders
    }

    /// One saved folder, named by its last component and shown with the home folder as `~`.
    public static func folder(path: String, home: String, mark: IntentFolder.Mark) -> IntentFolder {
        IntentFolder(path: path, name: URL(fileURLWithPath: path).lastPathComponent, shown: tilde(path, home: home), mark: mark)
    }

    /// The path with the home folder as `~`, as `PathStyle.tilde` writes it: compared by scalars, because a combining mark right after the slash
    /// would hide the slash from a Character-level prefix test.
    static func tilde(_ path: String, home: String) -> String {
        if path == home { return "~" }
        let scalars = path.unicodeScalars
        guard !home.isEmpty, scalars.starts(with: (home + "/").unicodeScalars) else { return path }
        return "~" + String(String.UnicodeScalarView(scalars.dropFirst(home.unicodeScalars.count)))
    }
}

/// Starts the bundled `rh` for an intent and turns what it says into a short result.
public struct IntentRunner: Sendable {
    public struct Failure: Error, LocalizedError, Equatable {
        public var text: String
        public var errorDescription: String? { text }
    }

    public let helper: String
    public let runner: any ProcessRunner
    public let timeout: Duration
    /// The person's preferred languages, handed to `rh` so that what it names follows the system language as the Finder menu's does.
    public let languages: [String]

    public init(
        helper: String, runner: any ProcessRunner = LiveProcessRunner(), timeout: Duration = .seconds(60), languages: [String] = Locale.preferredLanguages
    ) {
        self.helper = helper
        self.runner = runner
        self.timeout = timeout
        self.languages = languages
    }

    /// Runs the command; returns rh's one-line answer (`ok: ...`) or throws `Failure` with rh's own error text.
    public func perform(_ command: IntentCommand) async throws -> String {
        let result = try await runner.run(ProcessStep(executable: helper, arguments: try command.arguments(languages: languages)), timeout: timeout)
        return try Self.interpret(result)
    }

    /// Reads the output of `rh agents --json` or `rh actions --json`.
    public func output(_ arguments: [String]) async -> Data {
        guard let result = try? await runner.run(ProcessStep(executable: helper, arguments: arguments), timeout: .seconds(20)), result.status == 0 else {
            return Data()
        }
        return Data(result.standardOutput.utf8)
    }

    static func interpret(_ result: ProcessResult) throws -> String {
        if let limit = result.terminatedAfter {
            throw Failure(text: "rh did not finish within \(limit.components.seconds) seconds and was stopped.")
        }
        let out = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0 else {
            throw Failure(text: failureReason(standardError: result.standardError) ?? "rh exited with status \(result.status).")
        }
        let line = out.split(separator: "\n").last.map(String.init) ?? ""
        return line.hasPrefix("ok: ") ? String(line.dropFirst(4)) : line
    }

    /// The line in which `rh` says why it stopped. Before that it reports the problems it found in the config, one line
    /// each (`warning: config.toml [general.termnial]: ...`), which quote the person's own file and have nothing to
    /// do with what an intent asked for; the reason comes last, as `error: ...` or, from the argument parser, `Error: ...`.
    /// `nil` when there is none, so that nothing of the config is ever shown as an answer.
    static func failureReason(standardError: String) -> String? {
        let configProblem = #/^(?:error|warning): \S+?\.toml(?::\d+)?(?: \[[^\]]*\])?: /#
        return standardError.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { ($0.hasPrefix("error: ") || $0.hasPrefix("Error: ")) && $0.firstMatch(of: configProblem) == nil }
    }
}
