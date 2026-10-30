import Foundation

/// How a terminal that has no built-in way of being driven is started, written in the config. Each is an argument
/// vector, never a shell line: `{dir}`, `{command}`, `{shell}` (the login shell) and `{app}` (the installed .app) are
/// replaced inside its elements, and the first element must be an absolute path (or start with `{app}/`).
public struct TerminalLaunch: Sendable, Equatable {
    /// Opens a folder. Without it the app is handed the folder with `open`.
    public var open: [String]?
    /// Starts a typed command in a folder. Without it the terminal cannot start agents.
    public var run: [String]?

    public init(open: [String]? = nil, run: [String]? = nil) {
        self.open = open
        self.run = run
    }
}

/// An application Right Here knows how to open a folder with.
public struct AppDescriptor: Sendable, Equatable, Identifiable {
    public enum Role: String, Sendable, Codable, CaseIterable {
        case terminal
        case editor
        case general
    }

    /// How a session is started in the app. Only a terminal needs more than being handed the folder.
    public enum Driver: Sendable, Equatable {
        /// Ghostty 1.3 and later, through its AppleScript dictionary.
        case ghostty
        /// Terminal.app: a folder is handed over, a command is typed with `do script`.
        case appleScriptTerminal
        /// iTerm2 3.0 and later, through its AppleScript dictionary.
        case iterm
        /// WezTerm CLI.
        case wezterm
        /// kitty CLI.
        case kitty
        /// Alacritty CLI.
        case alacritty
        /// Warp's URI scheme: a window or tab in a folder, no command.
        case warp
        /// The app is handed the folder with `open`; it cannot be told to run a command.
        case openFolder
        /// Started the way the config says (`open_args`, `run_args`).
        case template(TerminalLaunch)
    }

    /// Stable lowercase identifier used in the config and in action ids.
    public var id: String
    public var name: String
    /// Candidate bundle identifiers, most preferred first (stable, preview and beta builds).
    public var bundleIDs: [String]
    public var role: Role
    public var driver: Driver
    /// Where the app stands when no default is configured and the first installed app of its role is picked: lower
    /// comes first. `nil` means it is never picked that way, though the config can still name it.
    public var defaultRank: Int?

    public init(id: String, name: String, bundleIDs: [String], role: Role, driver: Driver = .openFolder, defaultRank: Int? = nil) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
        self.role = role
        self.driver = driver
        self.defaultRank = defaultRank
    }

    /// The first candidate that is installed on this machine.
    public func installedBundleID(facts: any SystemFacts) -> String? {
        bundleIDs.first { facts.applicationURL(bundleID: $0) != nil }
    }
}

public enum KnownApps {
    public static let all: [AppDescriptor] = terminals + editors

    /// `defaultRank` is where an app stands when no default is configured and the first installed one of its role is
    /// picked. Terminal.app is always there, so it comes last: a terminal someone installed on purpose is a better guess.
    /// An app without a rank is never picked that way.
    public static let terminals: [AppDescriptor] = [
        AppDescriptor(id: "ghostty", name: "Ghostty", bundleIDs: ["com.mitchellh.ghostty"], role: .terminal, driver: .ghostty, defaultRank: 0),
        AppDescriptor(id: "terminal", name: "Terminal", bundleIDs: ["com.apple.Terminal"], role: .terminal, driver: .appleScriptTerminal, defaultRank: 7),
        AppDescriptor(id: "iterm", name: "iTerm", bundleIDs: ["com.googlecode.iterm2"], role: .terminal, driver: .iterm, defaultRank: 2),
        AppDescriptor(id: "wezterm", name: "WezTerm", bundleIDs: ["com.github.wez.wezterm"], role: .terminal, driver: .wezterm, defaultRank: 3),
        AppDescriptor(id: "kitty", name: "kitty", bundleIDs: ["net.kovidgoyal.kitty"], role: .terminal, driver: .kitty, defaultRank: 4),
        AppDescriptor(id: "alacritty", name: "Alacritty", bundleIDs: ["org.alacritty"], role: .terminal, driver: .alacritty, defaultRank: 5),
        AppDescriptor(id: "warp", name: "Warp", bundleIDs: ["dev.warp.Warp-Stable", "dev.warp.Warp-Preview"], role: .terminal, driver: .warp, defaultRank: 6),
        AppDescriptor(id: "cmux", name: "cmux", bundleIDs: ["com.cmuxterm.app"], role: .terminal, defaultRank: 1)
    ]

    public static let editors: [AppDescriptor] = [
        AppDescriptor(id: "vscode", name: "Visual Studio Code",
                      bundleIDs: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"], role: .editor, defaultRank: 0),
        AppDescriptor(id: "cursor", name: "Cursor", bundleIDs: ["com.todesktop.230313mzl4w4u92"], role: .editor, defaultRank: 1),
        AppDescriptor(id: "windsurf", name: "Windsurf", bundleIDs: ["com.exafunction.windsurf"], role: .editor, defaultRank: 3),
        AppDescriptor(id: "zed", name: "Zed", bundleIDs: ["dev.zed.Zed", "dev.zed.Zed-Preview"], role: .editor, defaultRank: 2),
        AppDescriptor(id: "antigravity", name: "Antigravity", bundleIDs: ["com.google.antigravity"], role: .editor),
        AppDescriptor(id: "xcode", name: "Xcode", bundleIDs: ["com.apple.dt.Xcode"], role: .editor),
        AppDescriptor(id: "sublime", name: "Sublime Text", bundleIDs: ["com.sublimetext.4", "com.sublimetext.3"], role: .editor, defaultRank: 4),
        AppDescriptor(id: "nova", name: "Nova", bundleIDs: ["com.panic.Nova"], role: .editor, defaultRank: 5),
        AppDescriptor(id: "bbedit", name: "BBEdit", bundleIDs: ["com.barebones.bbedit"], role: .editor, defaultRank: 6),
        AppDescriptor(id: "typora", name: "Typora", bundleIDs: ["abnerworks.Typora"], role: .editor),
        AppDescriptor(id: "obsidian", name: "Obsidian", bundleIDs: ["md.obsidian"], role: .editor),
        AppDescriptor(id: "textedit", name: "TextEdit", bundleIDs: ["com.apple.TextEdit"], role: .editor, defaultRank: 10),
        AppDescriptor(id: "intellij", name: "IntelliJ IDEA", bundleIDs: ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"], role: .editor, defaultRank: 7),
        AppDescriptor(id: "pycharm", name: "PyCharm", bundleIDs: ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"], role: .editor, defaultRank: 8),
        AppDescriptor(id: "webstorm", name: "WebStorm", bundleIDs: ["com.jetbrains.WebStorm"], role: .editor, defaultRank: 9),
        AppDescriptor(id: "android-studio", name: "Android Studio", bundleIDs: ["com.google.android.studio"], role: .editor),
        AppDescriptor(id: "trae", name: "Trae", bundleIDs: ["com.trae.app", "cn.trae.app", "com.byteplus.trae"], role: .editor),
        AppDescriptor(id: "positron", name: "Positron", bundleIDs: ["com.rstudio.positron", "co.posit.positron"], role: .editor),
        AppDescriptor(id: "rustrover", name: "RustRover", bundleIDs: ["com.jetbrains.rustrover"], role: .editor),
        AppDescriptor(id: "clion", name: "CLion", bundleIDs: ["com.jetbrains.CLion"], role: .editor),
        AppDescriptor(id: "goland", name: "GoLand", bundleIDs: ["com.jetbrains.goland"], role: .editor)
    ]

    /// The built-in terminals an agent can be typed into, as a phrase for advice: "Ghostty, Terminal or iTerm".
    public static var commandTerminalPhrase: String {
        let names = terminals.filter { TerminalAdapters.adapter(for: $0).supportsCommands }.map(\.name)
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " or " + last
    }

    public static func app(id: String) -> AppDescriptor? {
        all.first { $0.id == id }
    }

    public static func terminal(id: String) -> AppDescriptor? {
        terminals.first { $0.id == id }
    }

    /// The built-in terminal that one of `bundleIDs` names. The system finds an app by its bundle identifier whatever the case, so this compares without regard to it.
    public static func terminal(bundleIDs: [String]) -> AppDescriptor? {
        let wanted = Set(bundleIDs.map { $0.lowercased() })
        return terminals.first { terminal in terminal.bundleIDs.contains { wanted.contains($0.lowercased()) } }
    }
}
