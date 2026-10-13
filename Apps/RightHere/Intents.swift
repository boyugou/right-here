import AppIntents
import Foundation
import RightHereCore
import RightHereKit

// Actions for Shortcuts and Spotlight that do not depend on the Finder extension. Each one only runs the
// bundled `rh` with an argument vector (`rh run <action id> --origin cli -- <path>`); the argument building
// and the validation of ids and paths are in RightHereKit (`IntentCommand`) and have tests. There is no
// free-text command parameter anywhere: an agent and a template are picked from what `rh` lists.

private enum Bundled {
    static var runner: IntentRunner {
        IntentRunner(helper: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/rh").path)
    }

    /// Runs the command and turns the outcome into a dialog, or an error Shortcuts shows as it is.
    static func perform(_ command: IntentCommand, success: (String) -> String) async throws -> some IntentResult & ProvidesDialog {
        do {
            let answer = try await runner.perform(command)
            return .result(dialog: IntentDialog(stringLiteral: success(answer)))
        } catch {
            throw IntentFailure(text: Localizer.system.render(.intentFailed(error.localizedDescription)))
        }
    }

    static func path(of file: IntentFile) throws -> String {
        guard let url = file.fileURL, url.isFileURL else {
            throw IntentFailure(text: Localizer.system.render(.intentFailed("no file location")))
        }
        return url.path
    }
}

struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    var text: String
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: text) }
}

struct OpenInTerminalIntent: AppIntent {
    static let title = LocalizedStringResource("intent.openTerminal.title", defaultValue: "Open in Terminal")
    static let description = IntentDescription(LocalizedStringResource("intent.openTerminal.description", defaultValue: "Opens a folder in your terminal app."))

    @Parameter(title: LocalizedStringResource("intent.param.folder", defaultValue: "Folder"), supportedContentTypes: [.folder])
    var folder: IntentFile

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let path = try Bundled.path(of: folder)
        return try await Bundled.perform(.openTerminal(folder: path)) { Localizer.system.render(.intentDone($0)) }
    }
}

struct StartAgentIntent: AppIntent {
    static let title = LocalizedStringResource("intent.startAgent.title", defaultValue: "Start AI Agent")
    static let description = IntentDescription(LocalizedStringResource("intent.startAgent.description", defaultValue: "Starts an AI agent in a folder, in your terminal app."))

    @Parameter(title: LocalizedStringResource("intent.param.agent", defaultValue: "Agent"))
    var agent: AgentEntity

    @Parameter(title: LocalizedStringResource("intent.param.folder", defaultValue: "Folder"), supportedContentTypes: [.folder])
    var folder: IntentFile

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let path = try Bundled.path(of: folder)
        return try await Bundled.perform(.startAgent(agent: agent.id, folder: path)) { Localizer.system.render(.intentDone($0)) }
    }
}

struct NewFileIntent: AppIntent {
    static let title = LocalizedStringResource("intent.newFile.title", defaultValue: "Create New File")
    static let description = IntentDescription(LocalizedStringResource("intent.newFile.description", defaultValue: "Creates a new file from one of your templates in a folder."))

    @Parameter(title: LocalizedStringResource("intent.param.template", defaultValue: "Template"))
    var template: TemplateEntity

    @Parameter(title: LocalizedStringResource("intent.param.folder", defaultValue: "Folder"), supportedContentTypes: [.folder])
    var folder: IntentFile

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let path = try Bundled.path(of: folder)
        return try await Bundled.perform(.newFile(template: template.id, folder: path)) { Localizer.system.render(.intentDone($0)) }
    }
}

struct CopyPathIntent: AppIntent {
    static let title = LocalizedStringResource("intent.copyPath.title", defaultValue: "Copy Path")
    static let description = IntentDescription(LocalizedStringResource("intent.copyPath.description", defaultValue: "Copies the path of a file or folder to the clipboard."))

    @Parameter(title: LocalizedStringResource("intent.param.item", defaultValue: "File or Folder"))
    var item: IntentFile

    @Parameter(title: LocalizedStringResource("intent.param.style", defaultValue: "Path Style"), default: .absolute)
    var style: PathStyleChoice

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let path = try Bundled.path(of: item)
        return try await Bundled.perform(.copyPath(style: style.pathStyle, path: path)) { _ in Localizer.system.string(.intentCopied) }
    }
}

// MARK: Entities

struct AgentEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("intent.type.agent", defaultValue: "AI Agent"))
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
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("intent.type.template", defaultValue: "File Template"))
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

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("intent.type.pathStyle", defaultValue: "Path Style"))
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
            shortTitle: LocalizedStringResource("intent.openTerminal.title", defaultValue: "Open in Terminal"),
            systemImageName: "terminal"
        )
        AppShortcut(
            intent: StartAgentIntent(),
            phrases: ["Start an agent with \(.applicationName)"],
            shortTitle: LocalizedStringResource("intent.startAgent.title", defaultValue: "Start AI Agent"),
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: NewFileIntent(),
            phrases: ["Create a new file with \(.applicationName)"],
            shortTitle: LocalizedStringResource("intent.newFile.title", defaultValue: "Create New File"),
            systemImageName: "doc.badge.plus"
        )
        AppShortcut(
            intent: CopyPathIntent(),
            phrases: ["Copy a path with \(.applicationName)"],
            shortTitle: LocalizedStringResource("intent.copyPath.title", defaultValue: "Copy Path"),
            systemImageName: "doc.on.clipboard"
        )
    }
}
