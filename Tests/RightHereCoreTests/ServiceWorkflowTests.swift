import Foundation
import Testing
@testable import RightHereCore

private func plist(_ data: Data) throws -> [String: Any] {
    try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
}

@Suite("ServiceWorkflow")
struct ServiceWorkflowTests {
    private let spec = ServiceSpec(title: "Claude Code Here", actionID: "agent.claude", command: ServiceWorkflow.command(rhPath: "/Applications/Right Here.app/Contents/Helpers/rh", actionID: "agent.claude"))

    @Test func commandNamesRhByAbsolutePathAndPassesItemsAfterTheSeparator() {
        #expect(spec.command == "'/Applications/Right Here.app/Contents/Helpers/rh' run --alert agent.claude --origin services -- \"$@\"")
    }

    @Test func infoPlistDeclaresAFinderOnlyService() throws {
        let info = try plist(ServiceWorkflow.infoPlist(for: spec))
        let services = try #require(info["NSServices"] as? [[String: Any]])
        let service = try #require(services.first)
        #expect((service["NSMenuItem"] as? [String: String])?["default"] == "Claude Code Here")
        #expect(service["NSMessage"] as? String == "runWorkflowAsService")
        #expect((service["NSRequiredContext"] as? [String: String])?["NSApplicationIdentifier"] == "com.apple.finder")
        #expect(service["NSSendFileTypes"] as? [String] == ["public.item"])
    }

    @Test func folderServicesAcceptFoldersOnly() throws {
        var folders = spec
        folders.input = .folders
        let service = try #require((try plist(ServiceWorkflow.infoPlist(for: folders))["NSServices"] as? [[String: Any]])?.first)
        #expect(service["NSSendFileTypes"] as? [String] == ["public.folder"])
        let document = try plist(ServiceWorkflow.workflowDocument(for: folders))
        let meta = try #require(document["workflowMetaData"] as? [String: Any])
        #expect(meta["serviceInputTypeIdentifier"] as? String == "com.apple.Automator.fileSystemObject.folder")
    }

    @Test func documentRunsTheCommandInZshWithItemsAsArguments() throws {
        let document = try plist(ServiceWorkflow.workflowDocument(for: spec))
        let actions = try #require(document["actions"] as? [[String: Any]])
        let action = try #require(actions.first?["action"] as? [String: Any])
        let parameters = try #require(action["ActionParameters"] as? [String: Any])
        #expect(parameters["COMMAND_STRING"] as? String == spec.command)
        #expect(parameters["shell"] as? String == "/bin/zsh")
        #expect(parameters["inputMethod"] as? Int == 1)
        #expect(action["ActionBundlePath"] as? String == "/System/Library/Automator/Run Shell Script.action")
        let meta = try #require(document["workflowMetaData"] as? [String: Any])
        #expect(meta["workflowTypeIdentifier"] as? String == "com.apple.Automator.servicesMenu")
        #expect(meta["serviceApplicationBundleID"] as? String == "com.apple.finder")
    }

    @Test func outputIsDeterministic() throws {
        #expect(try ServiceWorkflow.workflowDocument(for: spec) == ServiceWorkflow.workflowDocument(for: spec))
        var other = spec
        other.actionID = "agent.codex"
        #expect(try ServiceWorkflow.workflowDocument(for: spec) != ServiceWorkflow.workflowDocument(for: other))
    }

    @Test func generatedIdentifiersAreValidUUIDs() throws {
        let document = try plist(ServiceWorkflow.workflowDocument(for: spec))
        let action = try #require(((document["actions"] as? [[String: Any]])?.first)?["action"] as? [String: Any])
        for key in ["UUID", "InputUUID", "OutputUUID"] {
            #expect(UUID(uuidString: action[key] as? String ?? "") != nil, "\(key) is not a UUID")
        }
    }

    @Test func bundleNamesCarryThePrefixAndAreSafeAsFileNames() {
        #expect(ServiceWorkflow.bundleName(for: spec) == "Right Here - Claude Code Here.workflow")
        var tricky = spec
        tricky.title = "Path: a/b"
        #expect(ServiceWorkflow.bundleName(for: tricky) == "Right Here - Path- a-b.workflow")
    }
}

@Suite("Service specs from the registry")
struct ServiceSpecTests {
    private let facts = FakeSystemFacts(applications: [
        "com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"),
        "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
    ])

    @Test func defaultsCoverOpenAgentsNewFileAndCopyPath() {
        let registry = ActionRegistry(config: Config(enabledAgents: ["claude"]), facts: facts)
        let specs = registry.serviceSpecs(rhPath: "/x/rh")
        #expect(specs.map(\.actionID) == ["open.terminal", "open.editor", "agent.claude", "new-file.md", "copy-path.absolute", "copy-path.git-relative"])
        #expect(specs.map(\.title) == ["Open in Ghostty", "Open in Visual Studio Code", "Claude Code Here", "New Markdown Document", "Copy Path: Full Path", "Copy Path: Path from Git Root"])
    }

    @Test func configuredItemsReplaceTheDefaults() {
        let registry = ActionRegistry(config: Config(serviceItems: ["open.terminal", "bogus", "open.app.zed"]), facts: facts)
        #expect(registry.serviceSpecs(rhPath: "/x/rh").map(\.actionID) == ["open.terminal"])
    }

    @Test func parsedFromTheConfigFile() {
        let result = ConfigParser.parse("[services]\nitems = [\"open.terminal\", \"nonsense\"]\n")
        #expect(result.config.serviceItems == ["open.terminal"])
        #expect(result.diagnostics.contains { $0.path == "services.items" })
    }

    @Test func unknownMenuEntriesWarnWithASuggestion() throws {
        let result = ConfigParser.parse("[menu]\nitems = [\"copy-pth\"]\n")
        let warning = try #require(result.diagnostics.first)
        #expect(warning.severity == .warning)
        #expect(warning.suggestion == "did you mean \"copy-path\"?")
    }
}
