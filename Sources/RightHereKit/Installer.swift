import Foundation
import RightHereCore

/// Installs the pieces that connect Finder to `rh`. Everything here writes under the user's
/// home directory, so no privileges are needed.
public struct Installer: Sendable {
    public struct Locations: Sendable, Equatable {
        public var applicationScripts: URL
        public var localBin: URL
        public var services: URL

        public init(home: URL) {
            applicationScripts = home.appendingPathComponent("Library/Application Scripts/\(AppIdentity.extensionBundleID)")
            localBin = home.appendingPathComponent(".local/bin")
            services = home.appendingPathComponent("Library/Services")
        }
    }

    public let locations: Locations
    private var fileManager: FileManager { .default }

    public init(home: URL) {
        locations = Locations(home: home)
    }

    public var runnerScript: URL {
        locations.applicationScripts.appendingPathComponent(AppIdentity.runnerScriptName)
    }

    public var cliLink: URL {
        locations.localBin.appendingPathComponent(AppIdentity.cliName)
    }

    /// The script a sandboxed Finder extension runs through `NSUserUnixTask`: it runs outside the
    /// sandbox, with an empty PATH, so it names `rh` by absolute path.
    public static func runnerScriptText(rhPath: String) -> String {
        """
        #!/bin/zsh -f
        # Installed by `rh install`. The Finder extension runs this outside its sandbox.
        exec \(ShellQuoting.quote(rhPath)) run --alert "$@"

        """
    }

    @discardableResult
    public func installRunnerScript(rhPath: String) throws -> URL {
        try fileManager.createDirectory(at: locations.applicationScripts, withIntermediateDirectories: true)
        let text = Self.runnerScriptText(rhPath: rhPath)
        try text.write(to: runnerScript, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runnerScript.path)
        return runnerScript
    }

    /// Links `rh` into `~/.local/bin`, replacing a link or file already there.
    @discardableResult
    public func installCLILink(rhPath: String) throws -> URL {
        try fileManager.createDirectory(at: locations.localBin, withIntermediateDirectories: true)
        if (try? fileManager.destinationOfSymbolicLink(atPath: cliLink.path)) != nil || fileManager.fileExists(atPath: cliLink.path) {
            try fileManager.removeItem(at: cliLink)
        }
        try fileManager.createSymbolicLink(atPath: cliLink.path, withDestinationPath: rhPath)
        return cliLink
    }

    /// What `rh` the runner script currently points at, if the script is installed.
    public func installedRunnerTarget() -> String? {
        guard let text = try? String(contentsOf: runnerScript, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("exec ") {
            let rest = line.dropFirst(5)
            guard let end = rest.range(of: " run ") else { continue }
            return Self.unquote(String(rest[..<end.lowerBound]))
        }
        return nil
    }

    static func unquote(_ word: String) -> String {
        guard word.hasPrefix("'"), word.hasSuffix("'"), word.count >= 2 else { return word }
        return String(word.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
    }

    // MARK: Services

    /// The workflow bundles Right Here has installed.
    public func installedServices() -> [URL] {
        let names = (try? fileManager.contentsOfDirectory(atPath: locations.services.path)) ?? []
        return names.filter { $0.hasPrefix(ServiceWorkflow.namePrefix) && $0.hasSuffix(".workflow") }
            .sorted().map { locations.services.appendingPathComponent($0) }
    }

    /// Replaces the installed Services with `specs`. Workflows are written fresh each time, so a
    /// Service dropped from the config disappears.
    @discardableResult
    public func installServices(_ specs: [ServiceSpec]) throws -> [URL] {
        try removeServices()
        try fileManager.createDirectory(at: locations.services, withIntermediateDirectories: true)
        var written: [URL] = []
        for spec in specs {
            let bundle = locations.services.appendingPathComponent(ServiceWorkflow.bundleName(for: spec))
            let contents = bundle.appendingPathComponent("Contents")
            try fileManager.createDirectory(at: contents, withIntermediateDirectories: true)
            try ServiceWorkflow.infoPlist(for: spec).write(to: contents.appendingPathComponent("Info.plist"))
            try ServiceWorkflow.workflowDocument(for: spec).write(to: contents.appendingPathComponent("document.wflow"))
            written.append(bundle)
        }
        return written
    }

    public func removeServices() throws {
        for bundle in installedServices() { try fileManager.removeItem(at: bundle) }
    }

    public func removeRunnerScript() throws {
        if fileManager.fileExists(atPath: runnerScript.path) { try fileManager.removeItem(at: runnerScript) }
    }
}

/// Registers and switches the Finder extension through `pluginkit`.
public struct FinderExtensionManager: Sendable {
    public enum State: Sendable, Equatable {
        case enabled
        case disabled
        case notRegistered
    }

    public struct Status: Sendable, Equatable {
        public var state: State
        /// Every registered location of the extension; more than one means stale copies.
        public var paths: [String]
    }

    private let runner: any ProcessRunner

    public init(runner: any ProcessRunner = LiveProcessRunner()) {
        self.runner = runner
    }

    public func status() async -> Status {
        let result = try? await runner.run(ProcessStep(
            executable: "/usr/bin/pluginkit",
            arguments: ["-m", "-A", "-D", "-v", "-p", "com.apple.FinderSync", "-i", AppIdentity.extensionBundleID]
        ))
        return Self.parse(result?.standardOutput ?? "")
    }

    static func parse(_ output: String) -> Status {
        var state = State.notRegistered
        var paths: [String] = []
        for line in output.split(separator: "\n") {
            guard line.contains(AppIdentity.extensionBundleID) else { continue }
            let trimmed = line.drop { $0 == " " }
            if let marker = trimmed.first {
                if marker == "+" { state = .enabled } else if marker == "-", state != .enabled { state = .disabled }
            }
            if let path = line.split(separator: "\t").last.map(String.init), path.hasPrefix("/") { paths.append(path) }
        }
        return Status(state: state, paths: paths)
    }

    /// Adds the extension inside `app` to the registry and switches it on.
    public func register(appexPath: String) async throws {
        try await run(["-a", appexPath])
        try await run(["-e", "use", "-i", AppIdentity.extensionBundleID])
    }

    public func disable() async throws {
        try await run(["-e", "ignore", "-i", AppIdentity.extensionBundleID])
    }

    public func unregister(appexPath: String) async throws {
        try await run(["-r", appexPath])
    }

    private func run(_ arguments: [String]) async throws {
        let result = try await runner.run(ProcessStep(executable: "/usr/bin/pluginkit", arguments: arguments))
        guard result.status == 0 else {
            throw ExecutionError.stepFailed(index: 0, step: "pluginkit " + arguments.joined(separator: " "),
                                            message: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
