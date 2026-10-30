import Foundation
import RightHereCore

public enum InstallError: Error, Equatable, LocalizedError {
    /// Something that is not a link already sits where the command link goes.
    case notALink(path: String)
    case appNotFound
    case extensionMissing(path: String)
    /// The app is running from the temporary copy macOS makes of a downloaded app that was not moved
    /// anywhere yet. The runner script and the Services would point into a folder that disappears.
    case translocated
    /// The app is running from a disk image or another volume: the runner script, the command link and the Quick Actions would point into it,
    /// and stop working when it is ejected.
    case onAnotherVolume(path: String)
    /// Another setup (the setup window, `rh setup` in another terminal, an AI agent's) holds the turn, and did not finish in time.
    case anotherSetupIsRunning
    /// This `rh` is in a copy of the app other than the one to keep (`AppCopies.toKeep`): an older one, or one of the same version outside the Mac's
    /// Applications folder. Setting up from it would point the runner script, the Quick Actions and the Finder extension at this copy.
    case notTheCopyToKeep(copy: String, version: String, keep: String, keepVersion: String)
    /// The app runs from the Trash: what it sets up would point into a folder that is emptied.
    case inTrash

    public var errorDescription: String? {
        switch self {
        case .notALink(let path):
            return "\(path) exists and is not a link, so it was left alone. Move it away, then run `rh setup` again."
        case .appNotFound:
            return "Right Here.app was not found. Install the app, then run `rh setup`."
        case .extensionMissing(let path):
            return "\(path) does not exist."
        case .translocated:
            return "Right Here is running from the temporary location macOS uses for a downloaded app. Move Right Here.app into your Applications folder, open it from there, and install again."
        case .onAnotherVolume(let path):
            return "Right Here is running from \(path), which is a disk image or another volume. Drag Right Here.app into your Applications folder, eject the disk image, open the app from Applications, and install again."
        case .anotherSetupIsRunning:
            return "Another setup is running (the setup window, `rh setup` in another terminal, or an AI agent's) and did not finish in time, so this one did not start. Wait for it to finish, then run `rh setup` again."
        case .notTheCopyToKeep(let copy, let version, let keep, let keepVersion):
            // The paths are other copies' folder names: quoted for the shell (one has a space in "Right Here.app") and with their control characters shown.
            let command = ShellQuoting.quote(keep + "/Contents/Helpers/rh")
            return "This rh is in \(copy.withControlCharactersEscaped) (\(version)), and the copy of Right Here to keep is \(keep.withControlCharactersEscaped) (\(keepVersion)). Setting up from this one would make every click run it, so nothing was changed. Run the other copy's rh: \(command.withControlCharactersEscaped) setup"
        case .inTrash:
            return "Right Here is running from the Trash. What it sets up would stop working when the Trash is emptied. Open the copy in your Applications folder."
        }
    }

    /// The older-copy problem of an `rh` inside an app (`.app/Contents/Helpers/rh`) of version `version`, when a newer copy is among `copies`.
    public static func problem(helper: String, version: String, copies: [AppCopy], home: String) -> InstallError? {
        guard let range = helper.range(of: ".app/Contents/") else { return nil }
        let running = AppCopy(path: String(helper[..<range.lowerBound]) + ".app", version: version)
        guard let keep = AppCopies.toKeep(instead: running, among: AppCopies.installed(copies, home: home)) else { return nil }
        return .notTheCopyToKeep(copy: running.path, version: version, keep: keep.path, keepVersion: keep.version ?? "?")
    }

    /// Whether `path` is inside App Translocation's temporary mount.
    public static func isTranslocated(_ path: String) -> Bool {
        path.contains("/AppTranslocation/")
    }

    /// Why the app cannot set anything up from where it runs, or `nil`: the temporary copy macOS makes of a downloaded app, or a disk image or
    /// another volume. `helper` is the `rh` inside the app; one that is not inside an app (a build folder, Homebrew's) is the developer's or the package
    /// manager's business, and its volume is not the disk image's.
    public static func problem(runningFrom helper: String) -> InstallError? {
        if isTranslocated(helper) { return .translocated }
        if helper.contains("/.Trash/") { return .inTrash }
        guard helper.contains(".app/Contents/"), isOnAnotherVolume(helper) else { return nil }
        return .onAnotherVolume(path: URL(fileURLWithPath: helper).resolvingSymlinksInPath().path)
    }

    /// Whether `path` is on a volume that is mounted under `/Volumes` (a disk image, a USB stick, a network share). A link in `/Volumes` to the
    /// startup disk (`/Volumes/Macintosh HD`) leads to the same place as `/`, which is where Applications is, and is not one.
    public static func isOnAnotherVolume(_ path: String, volumes: String = "/Volumes/") -> Bool {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path.hasPrefix(volumes)
    }
}

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
    private let home: URL
    private let environment: [String: String]
    private let realHome: URL
    private var fileManager: FileManager { .default }

    /// The path of the running `rh` to write into the runner script and the Services. Symlinks are
    /// resolved (the link in `~/.local/bin` leads into the app), except that a Homebrew install, which
    /// resolves into a versioned Cellar folder that changes on every upgrade, keeps its prefix's
    /// `bin/rh`.
    public static func currentExecutablePath() -> String? {
        Bundle.main.executableURL.map { stablePath(forResolved: $0.resolvingSymlinksInPath().path) }
    }

    /// Whether `path` is an `rh` that Right Here would have linked: the helper inside Right Here.app, or the binary
    /// that is running now (which is what `rh setup` links to). A link to anything else was made by somebody
    /// else, whatever it is called.
    public static func isRightHereBinary(_ path: String) -> Bool {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolved.contains("/Right Here.app/Contents/Helpers/") { return true }
        guard let current = Bundle.main.executableURL?.resolvingSymlinksInPath().path else { return false }
        return resolved == current
    }

    static func stablePath(forResolved resolved: String) -> String {
        guard let range = resolved.range(of: "/Cellar/") else { return resolved }
        let alias = String(resolved[..<range.lowerBound]) + "/bin/" + URL(fileURLWithPath: resolved).lastPathComponent
        let target = URL(fileURLWithPath: alias).resolvingSymlinksInPath().path
        return target == URL(fileURLWithPath: resolved).resolvingSymlinksInPath().path ? alias : resolved
    }

    /// - Parameters:
    ///   - environment: What `RealHomeGuard` reads; the process's, but for a test of the guard.
    ///   - realHome: The home it protects; the account's, but for a test of the guard.
    public init(home: URL, environment: [String: String] = ProcessInfo.processInfo.environment, realHome: URL = LiveSystemFacts.realHomeDirectory) {
        self.home = home
        self.environment = environment
        self.realHome = realHome
        locations = Locations(home: home)
    }

    /// Asked before anything is written or removed under the home (`RealHomeGuard`).
    private func refuseUnderTest() throws {
        try RealHomeGuard.check(home: home, environment: environment, realHome: realHome)
    }

    public var runnerScript: URL {
        locations.applicationScripts.appendingPathComponent(AppIdentity.runnerScriptName)
    }

    public var cliLink: URL {
        locations.localBin.appendingPathComponent(AppIdentity.cliName)
    }

    /// The script a sandboxed Finder extension runs through `NSUserUnixTask`: it runs outside the
    /// sandbox, with an empty PATH, so it names `rh` by absolute path.
    ///
    /// It passes on only the shapes the extension sends (`RunnerArguments`), and builds the command it starts from the parts it has checked,
    /// so what a compromised extension asks for can only be one of those: `rh run` has options that start an agent with its permission
    /// prompts off (`--bypass-permissions`), with a first prompt of the caller's choosing (`--arg`), or in a new worktree, and
    /// `rh setup`, `rh install` and `rh init --force` change the machine. The action must be an action id (`ActionRef`'s grammar, and not an
    /// option: `--alert` takes none, so a first word with a dash would be read as one), the origin one the extension has, the folder an
    /// absolute path. What follows `--` is the items, which are never read as options. A refusal says so on standard error, which the
    /// extension writes to its log.
    public static func runnerScriptText(rhPath: String) -> String {
        let origins = FinderMenuKind.allCases.map(\.rawValue).joined(separator: "|")
        let placements = TerminalPlacement.configNames.joined(separator: "|")
        let letters = "abcdefghijklmnopqrstuvwxyz0123456789"
        return """
        #!/bin/zsh -f
        # Installed by `rh setup`. The Finder extension runs this outside its sandbox.
        # It passes on exactly what the extension sends, and builds the command from the parts it has checked:
        #   run --alert <action> --origin <origin> [--container <folder>] -- <items>
        #   probe automation --from-extension
        #   probe launch --from-extension [--placement <placement>]
        # Everything else is refused, so a compromised extension cannot start an agent with its prompts off or with a
        # prompt of its own, and cannot call rh setup, rh install, rh uninstall, rh init --force, ...
        refuse() { echo "right-here runner: refusing: $1" >&2; exit 64; }
        case "${1:-}" in
          run)
            [ "${2:-}" = "--alert" ] && [ "${4:-}" = "--origin" ] || refuse "run takes --alert <action> --origin <origin>"
            action=${3:-}
            origin=${5:-}
            case "$action" in
              ''|[!\(letters)]*|*[!\(letters).@-]*) refuse "the action is not an action id" ;;
            esac
            case "$origin" in
              \(origins)) ;;
              *) refuse "the origin is not one the Finder extension sends" ;;
            esac
            if [ "${6:-}" = "--container" ]; then
              container=${7:-}
              case "$container" in
                /*) ;;
                *) refuse "--container takes the absolute path of a folder" ;;
              esac
              [ "${8:-}" = "--" ] || refuse "the items come after --"
              shift 8
              set -- run --alert "$action" --origin "$origin" --container "$container" -- "$@"
            else
              [ "${6:-}" = "--" ] || refuse "the items come after --"
              shift 6
              set -- run --alert "$action" --origin "$origin" -- "$@"
            fi
            ;;
          probe)
            [ "${3:-}" = "--from-extension" ] || refuse "probe takes --from-extension"
            case "${2:-}" in
              automation)
                [ "$#" -eq 3 ] || refuse "probe automation takes nothing more"
                set -- probe automation --from-extension
                ;;
              launch)
                if [ "$#" -eq 3 ]; then
                  set -- probe launch --from-extension
                else
                  [ "$#" -eq 5 ] && [ "${4:-}" = "--placement" ] || refuse "probe launch takes --placement <placement> and nothing more"
                  case "${5:-}" in
                    \(placements)) ;;
                    *) refuse "the placement is not one the Finder extension sends" ;;
                  esac
                  set -- probe launch --from-extension --placement "$5"
                fi
                ;;
              *) refuse "probe takes automation or launch" ;;
            esac
            ;;
          *) refuse "only run and probe are passed on" ;;
        esac
        exec \(ShellQuoting.quote(rhPath)) "$@"

        """
    }

    /// Whether the runner script is what `installRunnerScript(rhPath:)` writes, permissions included: there is nothing to do.
    public func runnerScriptIsCurrent(rhPath: String) -> Bool {
        guard let text = try? String(contentsOf: runnerScript, encoding: .utf8), text == Self.runnerScriptText(rhPath: rhPath) else { return false }
        let mode = (try? fileManager.attributesOfItem(atPath: runnerScript.path))?[.posixPermissions] as? NSNumber
        return mode?.intValue == 0o755
    }

    @discardableResult
    public func installRunnerScript(rhPath: String) throws -> URL {
        try refuseUnderTest()
        try fileManager.createDirectory(at: locations.applicationScripts, withIntermediateDirectories: true)
        let text = Self.runnerScriptText(rhPath: rhPath)
        try text.write(to: runnerScript, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runnerScript.path)
        return runnerScript
    }

    /// Where the command link points now, when there is one.
    public func existingCLILinkTarget() -> String? {
        try? fileManager.destinationOfSymbolicLink(atPath: cliLink.path)
    }

    /// Links `rh` into `~/.local/bin`, replacing a link already there. A real file or folder with that
    /// name belongs to the person, so it is refused rather than deleted.
    @discardableResult
    public func installCLILink(rhPath: String) throws -> URL {
        try refuseUnderTest()
        try fileManager.createDirectory(at: locations.localBin, withIntermediateDirectories: true)
        let isLink = (try? fileManager.destinationOfSymbolicLink(atPath: cliLink.path)) != nil
        if !isLink, fileManager.fileExists(atPath: cliLink.path) { throw InstallError.notALink(path: cliLink.path) }
        // The new link is made beside the old one and renamed over it, so the name never points at nothing and a
        // failure to create it leaves the old link.
        let pending = locations.localBin.appendingPathComponent(".rh-link-\(UUID().uuidString)")
        try fileManager.createSymbolicLink(atPath: pending.path, withDestinationPath: rhPath)
        if rename(pending.path, cliLink.path) != 0 {
            let code = errno
            try? fileManager.removeItem(at: pending)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return cliLink
    }

    /// What `rh` the runner script currently points at, if the script is installed.
    public func installedRunnerTarget() -> String? {
        guard let text = try? String(contentsOf: runnerScript, encoding: .utf8) else { return nil }
        // The quoted path may itself hold a newline or ` "$@"`, so the word runs from `exec ` to the last ` "$@"`.
        guard let start = text.range(of: "\nexec ") else { return nil }
        let rest = text[start.upperBound...]
        guard let end = rest.range(of: " \"$@\"", options: .backwards) else { return nil }
        return Self.unquote(String(rest[..<end.lowerBound]))
    }

    /// Undoes `ShellQuoting.quote` for one word. On scalars: a quote followed by a combining mark is one `Character`, and
    /// a search for `'\''` that works on Characters does not see it.
    static func unquote(_ word: String) -> String {
        let scalars = Array(word.unicodeScalars)
        guard scalars.count >= 2, scalars.first == "'", scalars.last == "'" else { return word }
        let end = scalars.count - 1
        var result = String.UnicodeScalarView()
        var index = 1
        while index < end {
            if index + 3 < end + 1, scalars[index] == "'", scalars[index + 1] == "\\", scalars[index + 2] == "'", scalars[index + 3] == "'" {
                result.append("'")
                index += 4
            } else {
                result.append(scalars[index])
                index += 1
            }
        }
        return String(result)
    }

    // MARK: Services

    /// The workflow bundles Right Here has installed.
    public func installedServices() -> [URL] {
        let names = (try? fileManager.contentsOfDirectory(atPath: locations.services.path)) ?? []
        return names.filter { $0.hasPrefix(ServiceWorkflow.namePrefix) && $0.hasSuffix(".workflow") }
            .sorted().map { locations.services.appendingPathComponent($0) }
    }

    /// Whether the Services on disk are exactly the ones `installServices(specs)` would write: the same bundles, with the same
    /// two files in each. A Service that the config no longer asks for, or one whose command points at another `rh`, is not.
    public func servicesAreCurrent(_ specs: [ServiceSpec]) -> Bool {
        var expected: [String: ServiceSpec] = [:]
        for spec in ServiceWorkflow.distinct(specs) { expected[ServiceWorkflow.bundleName(for: spec)] = spec }
        guard Set(installedServices().map(\.lastPathComponent)) == Set(expected.keys) else { return false }
        for (name, spec) in expected {
            let contents = locations.services.appendingPathComponent(name).appendingPathComponent("Contents")
            guard let info = try? Data(contentsOf: contents.appendingPathComponent("Info.plist")),
                  let document = try? Data(contentsOf: contents.appendingPathComponent("document.wflow")),
                  info == (try? ServiceWorkflow.infoPlist(for: spec)), document == (try? ServiceWorkflow.workflowDocument(for: spec)) else { return false }
        }
        return true
    }

    /// Replaces the installed Services with `specs`. Workflows are written fresh each time, so a
    /// Service dropped from the config disappears. They are written to a staging folder first and moved in once
    /// all of them exist, so a failure while writing leaves the Services that were installed before.
    @discardableResult
    public func installServices(_ specs: [ServiceSpec]) throws -> [URL] {
        try installServices(specs, write: Self.writeWorkflow)
    }

    static func writeWorkflow(_ spec: ServiceSpec, to bundle: URL) throws {
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try ServiceWorkflow.infoPlist(for: spec).write(to: contents.appendingPathComponent("Info.plist"))
        try ServiceWorkflow.workflowDocument(for: spec).write(to: contents.appendingPathComponent("document.wflow"))
    }

    func installServices(_ specs: [ServiceSpec], write: (ServiceSpec, URL) throws -> Void) throws -> [URL] {
        try refuseUnderTest()
        try fileManager.createDirectory(at: locations.services, withIntermediateDirectories: true)
        // A name that does not start with the prefix, so nothing treats a half-written staging folder as installed.
        let staging = locations.services.appendingPathComponent(".rh-staging-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        var staged: [(name: String, url: URL)] = []
        // Two actions with one title (open.terminal and open.terminal@ghostty), or with titles that differ only in case, make one Service.
        for spec in ServiceWorkflow.distinct(specs) {
            let name = ServiceWorkflow.bundleName(for: spec)
            let bundle = staging.appendingPathComponent(name)
            try write(spec, bundle)
            staged.append((name, bundle))
        }
        // A Service whose title changed only in case keeps its old name through a swap, since the volume takes the two names for one: it is removed
        // first, so that the name on disk is the title's.
        let installed = installedServices()
        for (name, _) in staged {
            for bundle in installed where bundle.lastPathComponent != name && ServiceWorkflow.fold(bundle.lastPathComponent) == ServiceWorkflow.fold(name) {
                try removeIfThere(bundle)
            }
        }
        // Each Service takes the place of the one of its name in one step, so a name is never without its bundle, and two installs at once
        // (the setup window and `rh setup` in a terminal) cannot make each other fail: whichever comes second swaps in a bundle that is the
        // same. What the config no longer asks for is removed after the new ones are in.
        var written: [URL] = []
        for (name, bundle) in staged {
            let destination = locations.services.appendingPathComponent(name)
            try Self.replace(destination, with: bundle)
            written.append(destination)
        }
        let kept = Set(staged.map { ServiceWorkflow.fold($0.name) })
        for bundle in installedServices() where !kept.contains(ServiceWorkflow.fold(bundle.lastPathComponent)) { try removeIfThere(bundle) }
        return written
    }

    /// Puts `bundle` where `destination` is, in one step: `RENAME_EXCL` for a name that is free, `RENAME_SWAP` for one that is taken (the old
    /// one is then at `bundle`, where it goes with the staging folder). A plain `rename` cannot do it, since a folder is not moved onto a
    /// folder that has files. Where the file system has no swap, the old one is removed and the new one moved in.
    static func replace(_ destination: URL, with bundle: URL) throws {
        func fail(_ code: Int32) -> POSIXError { POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        // A name that was taken and is free again by the time of the swap (somebody removed it) is tried again.
        for _ in 0..<5 {
            if renamex_np(bundle.path, destination.path, UInt32(RENAME_EXCL)) == 0 { return }
            switch errno {
            case EEXIST: break
            case ENOTSUP, EINVAL: return try replaceByRemoving(destination, with: bundle)
            case let code: throw fail(code)
            }
            if renamex_np(bundle.path, destination.path, UInt32(RENAME_SWAP)) == 0 { return }
            switch errno {
            case ENOENT: continue
            case ENOTSUP, EINVAL: return try replaceByRemoving(destination, with: bundle)
            case let code: throw fail(code)
            }
        }
        throw fail(EBUSY)
    }

    private static func replaceByRemoving(_ destination: URL, with bundle: URL) throws {
        let manager = FileManager.default
        do { try manager.removeItem(at: destination) } catch CocoaError.fileNoSuchFile {}
        try manager.moveItem(at: bundle, to: destination)
    }

    public func removeServices() throws {
        try refuseUnderTest()
        for bundle in installedServices() { try removeIfThere(bundle) }
    }

    /// Removes a Service; one that is gone already (another install removed it) is as good.
    private func removeIfThere(_ bundle: URL) throws {
        do { try fileManager.removeItem(at: bundle) } catch CocoaError.fileNoSuchFile {}
    }

    public func removeRunnerScript() throws {
        try refuseUnderTest()
        if fileManager.fileExists(atPath: runnerScript.path) { try fileManager.removeItem(at: runnerScript) }
    }

    public enum LinkRemoval: Equatable, Sendable {
        case absent
        case removed(destination: String)
        /// `rh` is a short name other tools use too: a link to something that is not Right Here's is not ours to delete.
        case foreign(destination: String)
    }

    public func removeCLILink() throws -> LinkRemoval {
        try refuseUnderTest()
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: cliLink.path) else { return .absent }
        guard Self.isRightHereBinary(destination) else { return .foreign(destination: destination) }
        try fileManager.removeItem(at: cliLink)
        return .removed(destination: destination)
    }
}

/// Registers and switches the Finder extension through `pluginkit`.
public struct FinderExtensionManager: Sendable {
    public enum State: Sendable, Equatable {
        case enabled
        case disabled
        case notRegistered
        /// `pluginkit` was stopped for taking too long (its daemon is stuck), so nothing is known.
        case unanswered
    }

    public struct Status: Sendable, Equatable {
        public var state: State
        /// Every registered location of the extension; more than one means stale copies.
        public var paths: [String]
    }

    private let runner: any ProcessRunner
    private let environment: [String: String]

    /// - Parameter environment: What `RealHomeGuard` reads; the process's, but for a test of the guard.
    public init(runner: any ProcessRunner = LiveProcessRunner(), environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.runner = runner
        self.environment = environment
    }

    /// How long a look at the registration may take. It asks the same daemon as the calls that change it, and a daemon that is stuck made the window's first look,
    /// the doctor and the setup (which holds the setup lock) wait for ever.
    static let lookTimeout: Duration = .seconds(20)

    public func status() async -> Status {
        let result = try? await runner.run(ProcessStep(
            executable: "/usr/bin/pluginkit",
            arguments: ["-m", "-A", "-D", "-v", "-p", "com.apple.FinderSync", "-i", AppIdentity.extensionBundleID]
        ), timeout: Self.lookTimeout)
        if result?.terminatedAfter != nil { return Status(state: .unanswered, paths: []) }
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
            // `pluginkit` writes a tag for an election somebody made and none for the default, which is where an extension that macOS found and the
            // person has not switched on stands (of the 513 plug-ins on the Mac this was measured on, 477 had no tag). It is registered, and off.
            if state == .notRegistered { state = .disabled }
            if let path = line.split(separator: "\t").last.map(String.init), path.hasPrefix("/") { paths.append(path) }
        }
        return Status(state: state, paths: paths)
    }

    /// Adds the extension inside `app` to the registry and asks macOS to use it. The switch in System Settings can still be off, and then it
    /// is the person's (`status` says `disabled`, the doctor `needs-user`).
    public func register(appexPath: String) async throws {
        try await run(["-a", appexPath])
        try await run(["-e", "use", "-i", AppIdentity.extensionBundleID])
    }

    /// Registers the extension and checks, once macOS has had a moment to settle, that the registration stayed. Right
    /// after the installed app is replaced, pluginkit was seen dropping the entry again a few seconds later, which left
    /// Finder without its menu until `rh setup` was run by hand. It registers once more when the first did
    /// not stay.
    /// - Returns: whether it had to register again.
    @discardableResult
    public func registerAndConfirm(appexPath: String, settle: Duration = .seconds(3)) async throws -> Bool {
        try await register(appexPath: appexPath)
        try? await Task.sleep(for: settle)
        guard await status().state != .enabled else { return false }
        try await register(appexPath: appexPath)
        return true
    }

    public func disable() async throws {
        try await run(["-e", "ignore", "-i", AppIdentity.extensionBundleID])
    }

    public func unregister(appexPath: String) async throws {
        try await run(["-r", appexPath])
    }

    /// How long a `pluginkit` call that changes something may take. It talks to a daemon that is occasionally stuck, and a call that never comes back
    /// held the setup lock (and with it every other setup) until the app was quit.
    static let changeTimeout: Duration = .seconds(30)

    private func run(_ arguments: [String]) async throws {
        try RealHomeGuard.checkSystemWide(environment: environment)
        let step = "pluginkit " + arguments.joined(separator: " ")
        let result = try await runner.run(ProcessStep(executable: "/usr/bin/pluginkit", arguments: arguments), timeout: Self.changeTimeout)
        if result.terminatedAfter != nil { throw ExecutionError.timedOut(step: step, seconds: Int(Self.changeTimeout.components.seconds)) }
        guard result.status == 0 else {
            throw ExecutionError.stepFailed(index: 0, step: "pluginkit " + arguments.joined(separator: " "),
                                            message: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
