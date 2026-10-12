import AppKit
import Foundation
import RightHereCore

/// Answers questions about the real machine.
public struct LiveSystemFacts: SystemFacts {
    public init() {}

    /// The real home directory. In a sandboxed process `NSHomeDirectory()` is the container, so the
    /// account database is asked instead.
    public var homeDirectory: URL {
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

    public func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    public func environment(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }
}
