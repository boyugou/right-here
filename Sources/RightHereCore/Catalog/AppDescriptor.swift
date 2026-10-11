import Foundation

/// An application Right Here knows how to open a folder with.
public struct AppDescriptor: Sendable, Equatable, Identifiable {
    public enum Role: String, Sendable, Codable, CaseIterable {
        case terminal
        case editor
        case general
    }

    /// Stable lowercase identifier used in the config and in action ids.
    public var id: String
    public var name: String
    /// Candidate bundle identifiers, most preferred first (stable, preview and beta builds).
    public var bundleIDs: [String]
    public var role: Role

    public init(id: String, name: String, bundleIDs: [String], role: Role) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
        self.role = role
    }

    /// The first candidate that is installed on this machine.
    public func installedBundleID(facts: any SystemFacts) -> String? {
        bundleIDs.first { facts.applicationURL(bundleID: $0) != nil }
    }
}

public enum KnownApps {
    public static let all: [AppDescriptor] = terminals + editors

    public static let terminals: [AppDescriptor] = [
        AppDescriptor(id: "ghostty", name: "Ghostty", bundleIDs: ["com.mitchellh.ghostty"], role: .terminal),
        AppDescriptor(id: "terminal", name: "Terminal", bundleIDs: ["com.apple.Terminal"], role: .terminal),
        AppDescriptor(id: "iterm", name: "iTerm", bundleIDs: ["com.googlecode.iterm2"], role: .terminal),
        AppDescriptor(id: "wezterm", name: "WezTerm", bundleIDs: ["com.github.wez.wezterm"], role: .terminal),
        AppDescriptor(id: "kitty", name: "kitty", bundleIDs: ["net.kovidgoyal.kitty"], role: .terminal),
        AppDescriptor(id: "alacritty", name: "Alacritty", bundleIDs: ["org.alacritty"], role: .terminal),
        AppDescriptor(id: "warp", name: "Warp", bundleIDs: ["dev.warp.Warp-Stable"], role: .terminal),
        AppDescriptor(id: "cmux", name: "cmux", bundleIDs: ["com.cmuxterm.app"], role: .terminal)
    ]

    public static let editors: [AppDescriptor] = [
        AppDescriptor(id: "vscode", name: "Visual Studio Code",
                      bundleIDs: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"], role: .editor),
        AppDescriptor(id: "cursor", name: "Cursor", bundleIDs: ["com.todesktop.230313mzl4w4u92"], role: .editor),
        AppDescriptor(id: "windsurf", name: "Windsurf", bundleIDs: ["com.exafunction.windsurf"], role: .editor),
        AppDescriptor(id: "zed", name: "Zed", bundleIDs: ["dev.zed.Zed", "dev.zed.Zed-Preview"], role: .editor),
        AppDescriptor(id: "xcode", name: "Xcode", bundleIDs: ["com.apple.dt.Xcode"], role: .editor),
        AppDescriptor(id: "sublime", name: "Sublime Text", bundleIDs: ["com.sublimetext.4", "com.sublimetext.3"], role: .editor),
        AppDescriptor(id: "nova", name: "Nova", bundleIDs: ["com.panic.Nova"], role: .editor),
        AppDescriptor(id: "bbedit", name: "BBEdit", bundleIDs: ["com.barebones.bbedit"], role: .editor),
        AppDescriptor(id: "typora", name: "Typora", bundleIDs: ["abnerworks.Typora"], role: .editor),
        AppDescriptor(id: "obsidian", name: "Obsidian", bundleIDs: ["md.obsidian"], role: .editor),
        AppDescriptor(id: "textedit", name: "TextEdit", bundleIDs: ["com.apple.TextEdit"], role: .editor),
        AppDescriptor(id: "intellij", name: "IntelliJ IDEA", bundleIDs: ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"], role: .editor),
        AppDescriptor(id: "pycharm", name: "PyCharm", bundleIDs: ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"], role: .editor),
        AppDescriptor(id: "webstorm", name: "WebStorm", bundleIDs: ["com.jetbrains.WebStorm"], role: .editor),
        AppDescriptor(id: "android-studio", name: "Android Studio", bundleIDs: ["com.google.android.studio"], role: .editor)
    ]

    public static func app(id: String) -> AppDescriptor? {
        all.first { $0.id == id }
    }

    public static func terminal(id: String) -> AppDescriptor? {
        terminals.first { $0.id == id }
    }
}
