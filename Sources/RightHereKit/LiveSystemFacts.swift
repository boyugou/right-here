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

    public var currentDirectory: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
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

    /// What is at the path. Only "no such file or directory" (or a file where a folder should be) means missing.
    /// When the system refuses to look (`EACCES`, or `EPERM` under a privacy-protected folder such as Desktop or
    /// Documents) the item may well be there, and saying it is not would reject a path the person just selected
    /// in Finder; saying it is a folder would be as wrong, so it is its own state.
    public func itemState(_ url: URL) -> ItemState {
        var status = stat()
        if lstat(url.path, &status) == 0 { return .present }
        return errno == ENOENT || errno == ENOTDIR ? .missing : .unreadable
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
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
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
