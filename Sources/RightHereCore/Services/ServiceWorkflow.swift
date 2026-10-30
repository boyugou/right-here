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

    /// The longest file name that a volume of a Mac takes: 255 UTF-16 units (APFS, measured). The title of an action is part of the name of its
    /// bundle, so a title within the 120 characters of a name can still be too long for it (an emoji is two units, a letter with its marks one character).
    public static let longestName = 255

    public static func bundleName(for spec: ServiceSpec) -> String {
        // A slash would split the file name, and a colon shows as a slash in Finder.
        let safe = spec.title.scalarReplacing(["/": "-", ":": "-"])
        let whole = namePrefix + safe + ".workflow"
        guard length(whole) > longestName else { return whole }
        // A name that does not fit would fail the whole install. It is cut where a character ends, and the start of a digest of the whole title keeps two long
        // titles with the same start apart.
        let tag = "… " + SHA256.hash(data: Data(spec.title.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined() + ".workflow"
        let room = longestName - length(namePrefix) - length(tag)
        var kept = ""
        for character in safe {
            guard length(kept + String(character)) <= room else { break }
            kept.append(character)
        }
        return namePrefix + kept + tag
    }

    /// A name's length as the volume counts it: UTF-16 units, in the longer of its two canonical forms.
    public static func length(_ name: String) -> Int {
        max(name.utf16.count, name.decomposedStringWithCanonicalMapping.utf16.count)
    }

    /// The name as the volume compares it: a volume of a Mac does not tell apart two names that differ only in case or in the form of an accent.
    public static func fold(_ name: String) -> String {
        name.decomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: nil)
    }

    /// The specs whose bundles can stand side by side: of two whose names the volume takes for one (`Notes` and `notes`, or two actions with one title), the
    /// first is kept. A second bundle of such a name could not be put in place, and would leave the install half done.
    public static func distinct(_ specs: [ServiceSpec]) -> [ServiceSpec] {
        var seen = Set<String>()
        return specs.filter { seen.insert(fold(bundleName(for: $0))).inserted }
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
        Self.defaultServiceItems(enabledAgents: config.enabledAgents)
    }

    /// What `[services] items` comes to when the config does not write it.
    public static func defaultServiceItems(enabledAgents: [String]) -> [String] {
        ["open.terminal", "open.editor"]
            + enabledAgents.map { "agent.\($0)" }
            + ["new-file.md", "copy-path.absolute", "copy-path.git-relative"]
    }
}
