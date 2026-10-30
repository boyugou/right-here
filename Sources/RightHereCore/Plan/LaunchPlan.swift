import Foundation

/// What an action will do, as plain data. Planning produces it, the runtime executes it, and
/// `rh run --dry-run --json` prints it, so a person or an agent can inspect an action before
/// it runs and tests can assert on it without touching the system.
public struct LaunchPlan: Sendable, Equatable, Codable {
    public var action: String
    public var summary: String
    public var steps: [Step]
    /// Things the user should know that do not stop the action, such as a missing optional app.
    public var notices: [String]

    public init(action: String, summary: String, steps: [Step], notices: [String] = []) {
        self.action = action
        // The summary names folders and files, which are whatever somebody called them: a terminal escape sequence
        // in one must not reach the screen of the person reading `rh run`.
        self.summary = summary.withControlCharactersEscaped
        self.steps = steps
        self.notices = notices
    }
}

public enum Step: Sendable, Equatable {
    /// Open paths with an application through LaunchServices (`open -b`).
    case open(OpenStep)
    /// Open a URL, such as a deep link into an app.
    case openURL(String)
    /// Run an executable with an argument vector. Never a shell command line.
    case run(ProcessStep)
    /// Run AppleScript. The source is a constant; user-derived text only travels in `arguments`.
    case appleScript(AppleScriptStep)
    case copyToPasteboard(String)
    case createFile(CreateFileStep)
    /// Select items in a Finder window.
    case reveal([String])
    case pause(milliseconds: Int)
}

public struct OpenStep: Sendable, Equatable, Codable {
    public var bundleID: String?
    public var targets: [String]
    public var activate: Bool

    public init(bundleID: String?, targets: [String], activate: Bool = true) {
        self.bundleID = bundleID
        self.targets = targets
        self.activate = activate
    }
}

public struct ProcessStep: Sendable, Equatable, Codable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    public var currentDirectory: String?
    public var standardInput: String?

    public init(
        executable: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        currentDirectory: String? = nil,
        standardInput: String? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.currentDirectory = currentDirectory
        self.standardInput = standardInput
    }
}

public struct AppleScriptStep: Sendable, Equatable, Codable {
    public var source: String
    public var arguments: [String]
    /// The application the script controls, so a permission failure can name it.
    public var controls: String?

    public init(source: String, arguments: [String] = [], controls: String? = nil) {
        self.source = source
        self.arguments = arguments
        self.controls = controls
    }
}

public struct CreateFileStep: Sendable, Equatable, Codable {
    public var path: String
    public var contents: String
    /// The file is a blank document of this format, whose bytes the executor asks `OfficeDocument` for: the plan names the format, not kilobytes of a package.
    public var format: OfficeFormat?

    public init(path: String, contents: String = "", format: OfficeFormat? = nil) {
        self.path = path
        self.contents = contents
        self.format = format
    }

    /// What is written to the file.
    public var bytes: [UInt8] { format.map(OfficeDocument.bytes) ?? Array(contents.utf8) }
}

extension Step: Codable {
    private enum Kind: String, Codable {
        case open, openURL, run, appleScript, copyToPasteboard, createFile, reveal, pause
    }

    private enum CodingKeys: String, CodingKey {
        case kind, url, text, paths, milliseconds
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .open(let step):
            try container.encode(Kind.open, forKey: .kind)
            try step.encode(to: encoder)
        case .openURL(let url):
            try container.encode(Kind.openURL, forKey: .kind)
            try container.encode(url, forKey: .url)
        case .run(let step):
            try container.encode(Kind.run, forKey: .kind)
            try step.encode(to: encoder)
        case .appleScript(let step):
            try container.encode(Kind.appleScript, forKey: .kind)
            try step.encode(to: encoder)
        case .copyToPasteboard(let text):
            try container.encode(Kind.copyToPasteboard, forKey: .kind)
            try container.encode(text, forKey: .text)
        case .createFile(let step):
            try container.encode(Kind.createFile, forKey: .kind)
            try step.encode(to: encoder)
        case .reveal(let paths):
            try container.encode(Kind.reveal, forKey: .kind)
            try container.encode(paths, forKey: .paths)
        case .pause(let milliseconds):
            try container.encode(Kind.pause, forKey: .kind)
            try container.encode(milliseconds, forKey: .milliseconds)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .open: self = .open(try OpenStep(from: decoder))
        case .openURL: self = .openURL(try container.decode(String.self, forKey: .url))
        case .run: self = .run(try ProcessStep(from: decoder))
        case .appleScript: self = .appleScript(try AppleScriptStep(from: decoder))
        case .copyToPasteboard: self = .copyToPasteboard(try container.decode(String.self, forKey: .text))
        case .createFile: self = .createFile(try CreateFileStep(from: decoder))
        case .reveal: self = .reveal(try container.decode([String].self, forKey: .paths))
        case .pause: self = .pause(milliseconds: try container.decode(Int.self, forKey: .milliseconds))
        }
    }
}
