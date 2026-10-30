import AppIntents
import Foundation
import RightHereCore
import RightHereKit

// Actions for Shortcuts and Spotlight that do not depend on the Finder extension. Each one only runs the
// bundled `rh` with an argument vector (`rh run <action id> --origin cli -- <path>`); the argument building
// and the validation of ids and paths are in RightHereKit (`IntentCommand`) and have tests. There is no
// free-text command parameter anywhere: an agent and a template are picked from what `rh` lists.
//
// What the intents are called is read by the system by key from this app's bundle: titles, descriptions and parameter
// names from `AppIntents.xcstrings` (each resource names its table, written out because the build reads these
// initializers statically for the intents' metadata), the path styles' names from `Localizable.xcstrings`. What a
// result says goes through `Localizer`, like the rest of the code.

private enum Bundled {
    /// The language the config names (`general.language`), or the system's: what a dialog says and what a new file is called.
    static var localizer: Localizer {
        ConfigStore.load(paths: RHPaths.current(facts: LiveSystemFacts())).config.localizer
    }

    static var runner: IntentRunner {
        IntentRunner(helper: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/rh").path, languages: localizer.languages)
    }

    /// Runs the command and turns the outcome into a dialog, or an error Shortcuts shows as it is.
    static func perform(_ command: IntentCommand, success: (String) -> String) async throws -> some IntentResult & ProvidesDialog {
        do {
            let answer = try await runner.perform(command)
            return .result(dialog: IntentDialog(stringLiteral: success(answer)))
        } catch {
            throw IntentFailure(text: Bundled.localizer.render(.intentFailed(error.localizedDescription)))
        }
    }

    static func path(of file: IntentFile) throws -> String {
        guard let url = file.fileURL, url.isFileURL else {
            throw IntentFailure(text: Bundled.localizer.render(.intentFailed(Bundled.localizer.render(.intentNoFileLocation))))
        }
        return url.path
    }

    /// The folder an intent is given one of two ways: a saved folder (a pinned or recent one, picked from a list), or a file. The saved one
    /// wins when both are set, as it was picked by name. Neither is `nil`: the intent then asks for a saved folder (`needsValueError`), as
    /// Shortcuts asked for the file while the parameter was required.
    static func path(folder: IntentFile?, saved: SavedFolderEntity?) throws -> String? {
        if let saved { return saved.id }
        guard let folder else { return nil }
        return try path(of: folder)
    }

    /// What asking for the saved folder says.
    static var askForFolder: IntentDialog { IntentDialog(stringLiteral: localizer.string(.intentNoFolder)) }

    static var home: String { LiveSystemFacts().homeDirectory.path }
}

struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    var text: String
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: text) }
}

struct OpenInTerminalIntent: AppIntent {
    static let title = LocalizedStringResource("intent.openTerminal.title", defaultValue: "Open in Terminal", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.openTerminal.description", defaultValue: "Opens a folder in your terminal app.", table: "AppIntents"))

    @Parameter(title: LocalizedStringResource("intent.param.folder", defaultValue: "Folder", table: "AppIntents"), supportedContentTypes: [.folder])
    var folder: IntentFile?

    @Parameter(title: LocalizedStringResource("intent.param.savedFolder", defaultValue: "Saved Folder", table: "AppIntents"))
    var savedFolder: SavedFolderEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let path = try Bundled.path(folder: folder, saved: savedFolder) else { throw $savedFolder.needsValueError(Bundled.askForFolder) }
        return try await Bundled.perform(.openTerminal(folder: path)) { Bundled.localizer.render(.intentDone($0)) }
    }
}

struct StartAgentIntent: AppIntent {
    static let title = LocalizedStringResource("intent.startAgent.title", defaultValue: "Start AI Agent", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.startAgent.description", defaultValue: "Starts an AI agent in a folder, in your terminal app.", table: "AppIntents"))

    @Parameter(title: LocalizedStringResource("intent.param.agent", defaultValue: "Agent", table: "AppIntents"))
    var agent: AgentEntity

    @Parameter(title: LocalizedStringResource("intent.param.folder", defaultValue: "Folder", table: "AppIntents"), supportedContentTypes: [.folder])
    var folder: IntentFile?

    @Parameter(title: LocalizedStringResource("intent.param.savedFolder", defaultValue: "Saved Folder", table: "AppIntents"))
    var savedFolder: SavedFolderEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let path = try Bundled.path(folder: folder, saved: savedFolder) else { throw $savedFolder.needsValueError(Bundled.askForFolder) }
        return try await Bundled.perform(.startAgent(agent: agent.id, folder: path)) { Bundled.localizer.render(.intentDone($0)) }
    }
}

struct NewFileIntent: AppIntent {
    static let title = LocalizedStringResource("intent.newFile.title", defaultValue: "Create New File", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.newFile.description", defaultValue: "Creates a new file from one of your templates in a folder.", table: "AppIntents"))

    @Parameter(title: LocalizedStringResource("intent.param.template", defaultValue: "Template", table: "AppIntents"))
    var template: TemplateEntity

    @Parameter(title: LocalizedStringResource("intent.param.folder", defaultValue: "Folder", table: "AppIntents"), supportedContentTypes: [.folder])
    var folder: IntentFile?

    @Parameter(title: LocalizedStringResource("intent.param.savedFolder", defaultValue: "Saved Folder", table: "AppIntents"))
    var savedFolder: SavedFolderEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let path = try Bundled.path(folder: folder, saved: savedFolder) else { throw $savedFolder.needsValueError(Bundled.askForFolder) }
        return try await Bundled.perform(.newFile(template: template.id, folder: path)) { Bundled.localizer.render(.intentDone($0)) }
    }
}

struct CopyPathIntent: AppIntent {
    static let title = LocalizedStringResource("intent.copyPath.title", defaultValue: "Copy Path", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.copyPath.description", defaultValue: "Copies the path of a file or folder to the clipboard.", table: "AppIntents"))

    @Parameter(title: LocalizedStringResource("intent.param.item", defaultValue: "File or Folder", table: "AppIntents"))
    var item: IntentFile?

    @Parameter(title: LocalizedStringResource("intent.param.savedFolder", defaultValue: "Saved Folder", table: "AppIntents"))
    var savedFolder: SavedFolderEntity?

    @Parameter(title: LocalizedStringResource("intent.param.style", defaultValue: "Path Style", table: "AppIntents"), default: .absolute)
    var style: PathStyleChoice

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let path = try Bundled.path(folder: item, saved: savedFolder) else { throw $savedFolder.needsValueError(Bundled.askForFolder) }
        return try await Bundled.perform(.copyPath(style: style.pathStyle, path: path)) { _ in Bundled.localizer.string(.intentCopied) }
    }
}

// MARK: Entities

struct AgentEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("intent.type.agent", defaultValue: "AI Agent", table: "AppIntents"))
    static let defaultQuery = AgentQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

/// The agents `rh agents --json` reports as enabled or found in the login shell.
struct AgentQuery: EntityQuery {
    func suggestedEntities() async throws -> [AgentEntity] {
        let data = await Bundled.runner.output(["agents", "--json"])
        return IntentCatalog.agents(fromJSON: data).map { AgentEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [String]) async throws -> [AgentEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
}

struct TemplateEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("intent.type.template", defaultValue: "File Template", table: "AppIntents"))
    static let defaultQuery = TemplateQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

/// The templates of the person's config, as `rh actions --json` lists them.
struct TemplateQuery: EntityQuery {
    func suggestedEntities() async throws -> [TemplateEntity] {
        let data = await Bundled.runner.output(["actions", "--json"])
        return IntentCatalog.templates(fromJSON: data).map { TemplateEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [String]) async throws -> [TemplateEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
}

/// A pinned or recent folder (ADR 0030): its path is its id, its name and its path with `~` are what the list shows, with a pin or a clock (a plain
/// folder when it is listed nowhere any more).
struct SavedFolderEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("intent.type.savedFolder", defaultValue: "Saved Folder", table: "AppIntents"))
    static let defaultQuery = SavedFolderQuery()

    var id: String
    var name: String
    var shown: String
    var mark: IntentFolder.Mark

    init(_ folder: IntentFolder) {
        id = folder.path
        name = folder.name
        shown = folder.shown
        mark = folder.mark
    }

    var displayRepresentation: DisplayRepresentation {
        let symbol = switch mark {
        case .pinned: "pin.fill"
        case .recent: "clock"
        case .unlisted: "folder"
        }
        return DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name), subtitle: LocalizedStringResource(stringLiteral: shown), image: .init(systemName: symbol))
    }
}

/// The pinned folders, then the recent ones, as `rh pins --json` and `rh recents --json` list them.
struct SavedFolderQuery: EntityQuery {
    func suggestedEntities() async throws -> [SavedFolderEntity] {
        let pins = await Bundled.runner.output(["pins", "--json"])
        let recents = await Bundled.runner.output(["recents", "--json"])
        return IntentCatalog.folders(pinsJSON: pins, recentsJSON: recents, home: Bundled.home).map(SavedFolderEntity.init)
    }

    func entities(for identifiers: [String]) async throws -> [SavedFolderEntity] {
        let listed = try await suggestedEntities()
        return identifiers.compactMap { identifier in
            if let found = listed.first(where: { $0.id == identifier }) { return found }
            // A folder that was unpinned, or has left the recent ones, since the shortcut was made: still that folder, while it exists.
            var isDirectory: ObjCBool = false
            guard identifier.hasPrefix("/"), FileManager.default.fileExists(atPath: identifier, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            return SavedFolderEntity(IntentCatalog.folder(path: identifier, home: Bundled.home, mark: .unlisted))
        }
    }
}

/// One case per `PathStyle`; the exhaustive switch in `pathStyle` stops the build when a style is added.
enum PathStyleChoice: String, AppEnum {
    case absolute
    case tilde
    case gitRelative = "git-relative"
    case name
    case parent
    case shellEscaped = "shell-escaped"
    case shellQuoted = "shell-quoted"
    case fileURL = "file-url"
    case aiMention = "ai-mention"
    case markdownLink = "markdown-link"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("intent.type.pathStyle", defaultValue: "Path Style", table: "AppIntents"))
    static let caseDisplayRepresentations: [PathStyleChoice: DisplayRepresentation] = [
        .absolute: DisplayRepresentation(title: LocalizedStringResource("copyPath.absolute", defaultValue: "Full Path")),
        .tilde: DisplayRepresentation(title: LocalizedStringResource("copyPath.tilde", defaultValue: "Path from Home (~)")),
        .gitRelative: DisplayRepresentation(title: LocalizedStringResource("copyPath.gitRelative", defaultValue: "Path from Git Root")),
        .name: DisplayRepresentation(title: LocalizedStringResource("copyPath.name", defaultValue: "File Name")),
        .parent: DisplayRepresentation(title: LocalizedStringResource("copyPath.parent", defaultValue: "Parent Folder Path")),
        .shellEscaped: DisplayRepresentation(title: LocalizedStringResource("copyPath.shellEscaped", defaultValue: "Shell-Escaped Path")),
        .shellQuoted: DisplayRepresentation(title: LocalizedStringResource("copyPath.shellQuoted", defaultValue: "Quoted Path")),
        .fileURL: DisplayRepresentation(title: LocalizedStringResource("copyPath.fileURL", defaultValue: "File URL")),
        .aiMention: DisplayRepresentation(title: LocalizedStringResource("copyPath.aiMention", defaultValue: "@ Mention for AI")),
        .markdownLink: DisplayRepresentation(title: LocalizedStringResource("copyPath.markdownLink", defaultValue: "Markdown Link"))
    ]

    var pathStyle: PathStyle {
        switch self {
        case .absolute: .absolute
        case .tilde: .tilde
        case .gitRelative: .gitRelative
        case .name: .name
        case .parent: .parent
        case .shellEscaped: .shellEscaped
        case .shellQuoted: .shellQuoted
        case .fileURL: .fileURL
        case .aiMention: .aiMention
        case .markdownLink: .markdownLink
        }
    }
}

// MARK: Shortcuts and Spotlight

struct RightHereShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenInTerminalIntent(),
            phrases: ["Open in terminal with \(.applicationName)"],
            shortTitle: LocalizedStringResource("intent.openTerminal.title", defaultValue: "Open in Terminal", table: "AppIntents"),
            systemImageName: "terminal"
        )
        AppShortcut(
            intent: StartAgentIntent(),
            phrases: ["Start an agent with \(.applicationName)"],
            shortTitle: LocalizedStringResource("intent.startAgent.title", defaultValue: "Start AI Agent", table: "AppIntents"),
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: NewFileIntent(),
            phrases: ["Create a new file with \(.applicationName)"],
            shortTitle: LocalizedStringResource("intent.newFile.title", defaultValue: "Create New File", table: "AppIntents"),
            systemImageName: "doc.badge.plus"
        )
        AppShortcut(
            intent: CopyPathIntent(),
            phrases: ["Copy a path with \(.applicationName)"],
            shortTitle: LocalizedStringResource("intent.copyPath.title", defaultValue: "Copy Path", table: "AppIntents"),
            systemImageName: "doc.on.clipboard"
        )
    }
}
