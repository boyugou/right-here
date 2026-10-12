import AppKit
import Foundation
import RightHereCore

/// Answers questions about the real machine.
public struct LiveSystemFacts: SystemFacts {
    public init() {}

    /// The real home directory. In a sandboxed process `NSHomeDirectory()` is the container, so the
    /// account database is asked instead.
    public var homeDirectory: URL {
        // `RH_HOME` points every per-user path (config, logs, Services, the runner script, the command
        // link) at another folder, so an install can be tried or tested without touching the real one.
        if let override = ProcessInfo.processInfo.environment["RH_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory))
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }

    /// Where the command started. When that folder has been deleted `currentDirectoryPath` is empty and a URL made
    /// from it is the relative path ".", which names whatever folder a terminal starts in: a path that cannot exist
    /// stands in instead, so the action reports there is no folder instead of planning `cd .`.
    public var currentDirectory: URL {
        let path = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: path.hasPrefix("/") ? path : "/dev/null/no-working-directory")
    }

    public var loginShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            return String(cString: shell)
        }
        return "/bin/zsh"
    }

    public func isDirectory(_ url: URL) -> Bool? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue
    }

    public func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// What is at the path. When the system refuses to look (`EACCES`, or `EPERM` under a privacy-protected folder
    /// such as Desktop or Documents) or cannot (a network volume that does not answer), the item may well be there,
    /// and saying it is not would reject a path the person just selected in Finder; saying it is a folder would be
    /// as wrong, so it is its own state. Every other failure means there is no such path (`ENOENT`, a file where a
    /// folder should be, a name longer than the file system allows, a link loop): it cannot be a typo-proof item.
    public func itemState(_ url: URL) -> ItemState {
        var status = stat()
        if lstat(url.path, &status) == 0 { return .present }
        switch errno {
        case EACCES, EPERM, EIO, ESTALE, ETIMEDOUT: return .unreadable
        default: return .missing
        }
    }

    public func onDiskPath(_ url: URL) -> String {
        var names: [String] = []
        var prefix = URL(fileURLWithPath: "/")
        var lookingUp = true
        for component in url.lexicallyNormalized.pathComponents.dropFirst() {
            prefix.appendPathComponent(component)
            if lookingUp, let stored = try? prefix.resourceValues(forKeys: [.nameKey]).name {
                names.append(stored)
            } else {
                lookingUp = false
                names.append(component)
            }
        }
        return "/" + names.joined(separator: "/")
    }

    public func gitRoot(containing url: URL) -> URL? {
        let home = homeDirectory.lexicallyNormalized.path
        var directory = url.lexicallyNormalized
        if isDirectory(directory) != true { directory.deleteLastPathComponent() }
        while true {
            let marker = directory.appendingPathComponent(".git").path
            if directory.path != home, FileManager.default.fileExists(atPath: marker) { return directory }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { return nil }
            directory = parent
        }
    }

    public func applicationURL(bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    public func displayName(bundleID: String) -> String? {
        guard let url = applicationURL(bundleID: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    public func bundleVersion(bundleID: String) -> String? {
        guard let url = applicationURL(bundleID: bundleID) else { return nil }
        return Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    public func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    public func environment(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }
}
