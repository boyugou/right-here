import Foundation
import RightHereCore

/// What an application says of itself, which is what the config needs to name it: the bundle identifier it is found by and the name it shows.
public struct AppBundleInfo: Sendable, Equatable {
    public var bundleID: String
    public var name: String
    /// The app says it is a shell (`CFBundleTypeRole` is `Shell` for a kind of document it opens): what a terminal says of itself, and what makes the form start with the role "terminal", since a terminal
    /// that is handed a file runs it.
    public var runsShellScripts: Bool

    public init(bundleID: String, name: String, runsShellScripts: Bool = false) {
        self.bundleID = bundleID
        self.name = name
        self.runsShellScripts = runsShellScripts
    }

    /// The application at `url`, read from its `Info.plist` and nothing else (no code of the app is run); `nil` when `url` is not an application bundle that has an identifier.
    public static func read(at url: URL) -> AppBundleInfo? {
        guard url.pathExtension == "app", let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier, !bundleID.isEmpty else { return nil }
        func text(_ key: String) -> String? {
            (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
        // What the Finder shows: the display name, else the bundle's name, else the name of the folder; the first of them that the config would accept as a name (the form fills the field with it,
        // and what an application says of itself is not the person's text).
        func accepted(_ name: String?) -> String? { name.flatMap { AppOptions.isPlainName($0) ? $0 : nil } }
        let name = accepted(text("CFBundleDisplayName")) ?? accepted(text("CFBundleName")) ?? accepted(url.deletingPathExtension().lastPathComponent) ?? "App"
        let documents = bundle.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
        return AppBundleInfo(bundleID: bundleID, name: name, runsShellScripts: documents.contains { ($0["CFBundleTypeRole"] as? String) == "Shell" })
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
