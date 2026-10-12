import CryptoKit
import Foundation

/// One Finder Service (shown as a Quick Action). A Service works wherever Finder Sync does not
/// show a menu, such as iCloud Drive, and its menu item can be given a keyboard shortcut in
/// System Settings › Keyboard › Keyboard Shortcuts › Services.
public struct ServiceSpec: Sendable, Equatable {
    public enum Input: Sendable, Equatable {
        /// Files and folders.
        case items
        /// Folders only.
        case folders
    }

    public var title: String
    public var actionID: String
    public var input: Input
    public var command: String

    public init(title: String, actionID: String, input: Input = .items, command: String) {
        self.title = title
        self.actionID = actionID
        self.input = input
        self.command = command
    }
}

/// Builds the files of an Automator workflow bundle that Finder lists as a Service. The format
/// is the one Automator writes: an `Info.plist` with an `NSServices` entry, and a
/// `document.wflow` with a single "Run Shell Script" action that receives the items as arguments.
public enum ServiceWorkflow {
    public static let namePrefix = "Right Here - "

    public static func bundleName(for spec: ServiceSpec) -> String {
        // A slash would split the file name, and a colon shows as a slash in Finder.
        let safe = spec.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return namePrefix + safe + ".workflow"
    }

    /// The command a Service runs for an action: `rh` receives the selected items as arguments.
    public static func command(rhPath: String, actionID: String) -> String {
        "\(ShellQuoting.quote(rhPath)) run --alert \(ShellQuoting.quote(actionID)) --origin services -- \"$@\""
    }

    public static func infoPlist(for spec: ServiceSpec) throws -> Data {
        let service: [String: Any] = [
            "NSBackgroundColorName": "background",
            "NSIconName": "NSActionTemplate",
            "NSMenuItem": ["default": spec.title],
            "NSMessage": "runWorkflowAsService",
            "NSRequiredContext": ["NSApplicationIdentifier": "com.apple.finder"],
            "NSSendFileTypes": [spec.input == .folders ? "public.folder" : "public.item"]
        ]
        return try PropertyListSerialization.data(fromPropertyList: ["NSServices": [service]], format: .xml, options: 0)
    }

    public static func workflowDocument(for spec: ServiceSpec) throws -> Data {
        let inputType = spec.input == .folders ? "com.apple.Automator.fileSystemObject.folder" : "com.apple.Automator.fileSystemObject"
        let parameterNames = ["inputMethod", "CheckedForUserDefaultShell", "source", "COMMAND_STRING", "shell"]
        let defaults: [Any] = [0, false, "", "", "/bin/sh"]
        var arguments: [String: Any] = [:]
        for (index, name) in parameterNames.enumerated() {
            arguments[String(index)] = [
                "default value": defaults[index], "name": name, "required": "0", "type": "0", "uuid": String(index)
            ] as [String: Any]
        }

        let action: [String: Any] = [
            "AMAccepts": ["Container": "List", "Optional": true, "Types": ["com.apple.cocoa.string"]] as [String: Any],
            "AMActionVersion": "2.0.3",
            "AMApplication": ["Automator"],
            "AMParameterProperties": Dictionary(uniqueKeysWithValues: parameterNames.map { ($0, [String: Any]()) }),
            "AMProvides": ["Container": "List", "Types": ["com.apple.cocoa.string"]] as [String: Any],
            "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
            "ActionName": "Run Shell Script",
            "ActionParameters": [
                "COMMAND_STRING": spec.command,
                "CheckedForUserDefaultShell": true,
                "inputMethod": 1,
                "shell": "/bin/zsh",
                "source": ""
            ] as [String: Any],
            "BundleIdentifier": "com.apple.RunShellScript",
            "CFBundleVersion": "2.0.3",
            "CanShowSelectedItemsWhenRun": false,
            "CanShowWhenRun": true,
            "Category": ["AMCategoryUtilities"],
            "Class Name": "RunShellScriptAction",
            "InputUUID": uuid(spec, "input"),
            "Keywords": ["Shell", "Script", "Command", "Run", "Unix"],
            "OutputUUID": uuid(spec, "output"),
            "UUID": uuid(spec, "action"),
            "UnlocalizedApplications": ["Automator"],
            "arguments": arguments,
            "conversionLabel": 0,
            "isViewVisible": 1,
            "location": "309.000000:305.000000",
            "nibPath": "/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib"
        ]

        let document: [String: Any] = [
            "AMApplicationBuild": "534",
            "AMApplicationVersion": "2.10",
            "AMDocumentVersion": "2",
            "actions": [["action": action, "isViewVisible": 1] as [String: Any]],
            "connectors": [String: Any](),
            "workflowMetaData": [
                "applicationBundleIDsByPath": [String: Any](),
                "applicationPaths": [Any](),
                "inputTypeIdentifier": inputType,
                "outputTypeIdentifier": "com.apple.Automator.nothing",
                "presentationMode": 15,
                "processesInput": false,
                "serviceApplicationBundleID": "com.apple.finder",
                "serviceInputTypeIdentifier": inputType,
                "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
                "serviceProcessesInput": false,
                "systemImageName": "NSActionTemplate",
                "useAutomaticInputType": false,
                "workflowTypeIdentifier": "com.apple.Automator.servicesMenu"
            ] as [String: Any]
        ]
        return try PropertyListSerialization.data(fromPropertyList: document, format: .xml, options: 0)
    }

    /// A UUID derived from the action id, so regenerating a workflow gives the same file.
    private static func uuid(_ spec: ServiceSpec, _ role: String) -> String {
        let digest = Array(SHA256.hash(data: Data("\(spec.actionID)#\(role)".utf8)).prefix(16))
        var bytes = digest
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])).uuidString
    }
}

extension ActionRegistry {
    /// The Services to offer: the config's `[services] items`, or by default the direct actions of
    /// the default menu (open, agents, copy path) that can run on this machine.
    public func serviceSpecs(rhPath: String) -> [ServiceSpec] {
        let ids = config.serviceItems ?? defaultServiceItems()
        return ids.compactMap { id in
            guard let ref = ActionRef(parsing: id) else { return nil }
            let info = info(ref)
            guard info.available else { return nil }
            return ServiceSpec(title: info.title, actionID: id, command: ServiceWorkflow.command(rhPath: rhPath, actionID: id))
        }
    }

    private func defaultServiceItems() -> [String] {
        ["open.terminal", "open.editor"]
            + config.enabledAgents.map { "agent.\($0)" }
            + ["new-file.md", "copy-path.absolute", "copy-path.git-relative"]
    }
}
