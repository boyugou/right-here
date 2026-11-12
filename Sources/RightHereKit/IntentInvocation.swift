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
    /// `timeLimit` is how long a step of the run may take: `rh` stops what it started at that limit and says so, which the app's own limit,
    /// by stopping `rh` alone, cannot (what `rh` started leads a process group of its own and would go on).
    public func arguments(languages: [String] = [], timeLimit: Duration? = nil) throws -> [String] {
        let options = languages.flatMap { ["--language", $0] } + (timeLimit.map { ["--time-limit", String(max(1, $0.components.seconds))] } ?? [])
        switch self {
        case .openTerminal(let folder):
            return try Self.run("open.terminal", path: folder, options: options)
        case .startAgent(let agent, let folder):
            return try Self.run("agent." + Self.word(agent), path: folder, options: options)
        case .newFile(let template, let folder):
            return try Self.run("new-file." + Self.word(template), path: folder, options: options)
        case .copyPath(let style, let path):
            return try Self.run("copy-path." + style.rawValue, path: path, options: options)
        }
    }

    /// The folder an intent acts in, for the three that take one; Copy Path takes a file as well.
    public var folder: String? {
        switch self {
        case .openTerminal(let folder), .startAgent(_, let folder), .newFile(_, let folder): folder
        case .copyPath: nil
        }
    }

    private static func run(_ action: String, path: String, options: [String]) throws -> [String] {
        guard ActionRef(parsing: action) != nil else { throw Invalid.notAnActionID(action) }
        guard path.hasPrefix("/"), !path.contains("\0") else { throw Invalid.notAbsolute(path) }
        return ["run", action, "--origin", "cli", "--json"] + options + ["--", path]
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

    /// Whether `rh agents --json` says the agent starts without asking: the config switches its permission prompts off, or the alias its command is in the login
    /// shell adds the flag that does. An answer that cannot be read, or that does not list the agent, is taken as yes: the question it leads to costs a click, and
    /// its absence an agent that does whatever the folder it starts in tells it.
    public static func startsWithoutAsking(_ agent: String, agentsJSON data: Data) -> Bool {
        guard let rows = try? JSONDecoder().decode([AgentRow].self, from: data), let row = rows.first(where: { $0.id == agent }) else { return true }
        return row.bypassPermissions || row.bypassArgumentFromAlias != nil
    }

    /// Whether `rh pins --json` lists `path`: a folder the person pinned is one they chose to work in. Compared as written but for a slash at the end: a path with
    /// `.` or `..` in it is not the pinned folder, whatever it reads as (a link before `..` sends it elsewhere).
    public static func isPinned(_ path: String, pinsJSON data: Data) -> Bool {
        func trimmed(_ text: String) -> String {
            var text = text
            while text.count > 1, text.hasSuffix("/") { text.removeLast() }
            return text
        }
        let wanted = trimmed(path)
        guard wanted.hasPrefix("/"), !wanted.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return false }
        return ((try? JSONDecoder().decode([String].self, from: data)) ?? []).contains { trimmed($0) == wanted }
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
    public struct Failure: Error, LocalizedError, Equatable, LocalizedFailure {
        /// rh's own line, in English.
        public var text: String
        /// The same as sentences of the catalog, when rh gave them, which the app writes in the person's language.
        public var sentences: [LocalizedMessage] = []
        public var errorDescription: String? { text }

        public func text(in localizer: Localizer) -> String {
            sentences.isEmpty ? text : localizer.render(sentences: shownSentences, isolatingValues: true)
        }
    }

    /// What `rh run --json` writes: the plan on success, the reason's sentences on failure.
    private struct Answer: Decodable {
        struct Plan: Decodable {
            var summary: String
        }

        var plan: Plan?
        var messages: [LocalizedMessage]?
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
        // A Saved Folder travels as its path, and a pinned folder may have become a file since: `rh` reads a file as "the folder that holds it",
        // which would act in the folder around the one the person picked. A path the system will not let us look at is not known to be a file,
        // and goes on to `rh`, which says why it cannot act there.
        if let folder = command.folder {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), !isDirectory.boolValue {
                let refusal = PlanError.refused(.refusalNotAFolder(folder))
                throw Failure(text: refusal.localizedDescription, sentences: refusal.sentences)
            }
        }
        // `rh` stops a step at a limit below this one, so that it answers (in the person's language) before it is stopped itself.
        let stepLimit = timeout - min(.seconds(10), timeout / 2)
        let result = try await runner.run(ProcessStep(executable: helper, arguments: try command.arguments(languages: languages, timeLimit: stepLimit)), timeout: timeout)
        return try Self.interpret(result)
    }

    /// The new-file templates, in the person's language, as the Finder menu names them.
    public func templates() async -> [IntentChoice] {
        IntentCatalog.templates(fromJSON: await output(["actions", "--json"] + languages.flatMap { ["--language", $0] }))
    }

    /// Reads the output of `rh agents --json` or `rh actions --json`.
    public func output(_ arguments: [String]) async -> Data {
        guard let result = try? await runner.run(ProcessStep(executable: helper, arguments: arguments), timeout: .seconds(20)), result.status == 0 else {
            return Data()
        }
        return Data(result.standardOutput.utf8)
    }

    /// What an intent shows for what `rh run --json` wrote: the plan's summary, or a `Failure`.
    public static func interpret(_ result: ProcessResult) throws -> String {
        if let limit = result.terminatedAfter {
            let stopped = ExecutionError.timedOut(step: "rh", seconds: Int(limit.components.seconds))
            throw Failure(text: stopped.localizedDescription, sentences: stopped.sentences)
        }
        let out = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = try? JSONDecoder().decode(Answer.self, from: Data(out.utf8))
        guard result.status == 0 else {
            if let reason = failureReason(standardError: result.standardError) { throw Failure(text: reason, sentences: answer?.messages ?? []) }
            let silent = LocalizedMessage.appCommandStopped(String(result.status))
            throw Failure(text: Localizer.english.render(silent), sentences: answer?.messages ?? [silent])
        }
        if let summary = answer?.plan?.summary { return summary }
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
