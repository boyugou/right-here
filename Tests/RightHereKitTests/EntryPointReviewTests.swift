import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

/// From an independent review of the entry points outside the window and the MCP tools (the Finder extension and its runner, the Quick Actions,
/// the App Intents), 2026-11-12. Each test fails on the code it was written against.

/// The text of the shell script a workflow bundle runs, or of whatever is in its `document.wflow` when that is not a workflow.
private func script(in bundle: URL) throws -> String {
    let data = try Data(contentsOf: bundle.appendingPathComponent("Contents/document.wflow"))
    guard let document = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let action = (document["actions"] as? [[String: Any]])?.first?["action"] as? [String: Any],
          let command = (action["ActionParameters"] as? [String: Any])?["COMMAND_STRING"] as? String else {
        return String(decoding: data, as: UTF8.self)
    }
    return command
}

/// A workflow of the person's own: what Finder's Duplicate makes of one of Right Here's, after the person changed its script in Automator.
private func personsOwnWorkflow(at bundle: URL, script: String) throws {
    let contents = bundle.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    try script.write(to: contents.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)
    try "<plist>the person's Info.plist</plist>".write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
}

/// A sparse file of `bytes` at `url`: it takes no room on the disk, and reads back as that many zero bytes.
private func sparseFile(at url: URL, bytes: Int) throws {
    let descriptor = open(url.path, O_CREAT | O_TRUNC | O_WRONLY, 0o600)
    try #require(descriptor >= 0, "cannot make \(url.path): \(String(cString: strerror(errno)))")
    defer { close(descriptor) }
    try #require(ftruncate(descriptor, off_t(bytes)) == 0)
}

@Suite("Entry points review: a Quick Action the person made")
struct QuickActionOwnershipReviewTests {
    /// The record of what Right Here wrote (`installed-services.txt`) keeps `installedServices()`, and with it the removal of what the config no longer asks for and
    /// `rh uninstall`, away from a Service of the person's. The write does not ask it: `Installer.replace` swaps the new bundle with whatever has the name
    /// (`RENAME_SWAP`), the old one goes with the staging folder, and the name is then recorded as Right Here's. A pulled config that the sync folder brings without
    /// `--allow-commands` names the Quick Action: here a template titled "Markdown Document copy", whose Quick Action is "New Markdown Document copy", the name
    /// Finder's Duplicate gives a copy of the default "New Markdown Document". The person's changed copy is deleted by the next `rh setup` or repair.
    @Test func aQuickActionThePersonMadeIsNotReplacedByOneThatAPulledConfigNamesTheSame() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let own = installer.locations.services.appendingPathComponent("Right Here - New Markdown Document copy.workflow")
        try personsOwnWorkflow(at: own, script: "my own shell script")

        let before = "[general]\nagents = []\n"
        let pulled = before + """

        [[new_file.template]]
        id = "notes"
        title = "Markdown Document copy"
        extension = "md"

        [services]
        items = ["new-file.notes", "copy-path.absolute"]
        """
        #expect(LaunchCommands.changes(from: Data(before.utf8), to: Data(pulled.utf8), overlay: nil).isEmpty, "a pull would ask about it, and this would need --allow-commands")
        let parsed = ConfigParser.parse(pulled)
        #expect(!parsed.hasErrors, "\(parsed.diagnostics.map(\.message))")
        let specs = ActionRegistry(config: parsed.config, facts: FakeSystemFacts(homeDirectory: home), localizer: parsed.config.localizer).serviceSpecs(rhPath: "/x/rh")
        #expect(specs.map(ServiceWorkflow.bundleName(for:)).contains(own.lastPathComponent), "the pulled title names the person's Quick Action: \(specs.map(\.title))")

        _ = try? installer.installServices(specs)
        let afterSetup = try script(in: own)
        #expect(afterSetup == "my own shell script", "rh setup put Right Here's Quick Action in place of the person's and deleted theirs")
        try installer.removeServices()
        #expect(FileManager.default.fileExists(atPath: own.path), "rh uninstall removed a Quick Action of the person's name, as if Right Here had written it")
    }

    /// `aNameThatIsNoLongerInstalledLeavesTheRecord` says a Service the person makes under a name Right Here no longer uses is theirs. It is, until the config asks
    /// for that name again: the next install swaps it out and deletes it.
    @Test func aQuickActionThePersonMadeUnderANameRightHereNoLongerUsedIsKeptWhenTheConfigAsksForItAgain() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let ghostty = ServiceSpec(title: "Open in Ghostty", actionID: "open.terminal@ghostty", command: ServiceWorkflow.command(rhPath: "/x/rh", actionID: "open.terminal@ghostty"))
        let copy = ServiceSpec(title: "Copy Path", actionID: "copy-path.absolute", command: ServiceWorkflow.command(rhPath: "/x/rh", actionID: "copy-path.absolute"))
        try installer.installServices([ghostty, copy])
        try installer.installServices([copy])
        let own = installer.locations.services.appendingPathComponent(ServiceWorkflow.bundleName(for: ghostty))
        try personsOwnWorkflow(at: own, script: "mine")

        _ = try? installer.installServices([ghostty, copy])
        let afterInstall = try script(in: own)
        #expect(afterInstall == "mine", "the person's Quick Action was swapped out and deleted")
    }

    /// What keeps the person's Quick Action must not keep an old one of Right Here's: a release from before the record was kept wrote bundles that no record
    /// names, and an update replaces them. Their script is the command a Quick Action of Right Here's runs, whichever `rh` it names.
    @Test func aQuickActionAnOlderReleaseWroteWithoutARecordIsStillReplaced() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let old = ServiceSpec(title: "Open in Ghostty", actionID: "open.terminal@ghostty",
                              command: ServiceWorkflow.command(rhPath: "/Volumes/Right Here/Right Here.app/Contents/Helpers/rh", actionID: "open.terminal@ghostty"))
        let bundle = installer.locations.services.appendingPathComponent(ServiceWorkflow.bundleName(for: old))
        try Installer.writeWorkflow(old, to: bundle)
        #expect(installer.installedServices().isEmpty, "the record names it, so this is not the case of a release without one")
        let new = ServiceSpec(title: old.title, actionID: old.actionID, command: ServiceWorkflow.command(rhPath: "/Applications/Right Here.app/Contents/Helpers/rh", actionID: old.actionID))
        try installer.installServices([new])
        let afterUpdate = try script(in: bundle)
        #expect(afterUpdate == new.command)
        #expect(installer.servicesAreCurrent([new]))
    }
}

@Suite("Entry points review: what the doctor says of a name the person holds")
struct HeldQuickActionTests {
    /// While a Quick Action of the person's holds a name, the others are current: a check that counted the held name would have the window rewrite the rest after
    /// every change, and every setup say "updated". The doctor says how many are left out and why, and that the person's rename, not another setup, changes it.
    @Test func whileThePersonHoldsANameTheOthersAreCurrentAndTheDoctorSaysWhy() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = RHPaths(environment: [:], home: home)
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        try "[general]\nagents = []\n\n[services]\nitems = [\"copy-path.absolute\", \"copy-path.name\"]\n".write(to: paths.configFile, atomically: true, encoding: .utf8)
        let facts = FakeSystemFacts(homeDirectory: home)
        let loaded = ConfigStore.load(paths: paths)
        let specs = ActionRegistry(config: loaded.config, facts: facts, localizer: loaded.config.localizer).serviceSpecs(rhPath: "/x/rh")
        try #require(specs.count == 2)
        let installer = Installer(home: home)
        let own = installer.locations.services.appendingPathComponent(ServiceWorkflow.bundleName(for: specs[0]))
        try personsOwnWorkflow(at: own, script: "mine")
        #expect(installer.heldByThePerson(specs) == [own.lastPathComponent])
        #expect(!installer.servicesAreCurrent(specs), "the other one is not installed yet")
        try installer.installServices(specs)
        #expect(installer.servicesAreCurrent(specs), "only the name the person holds is left out, and no install would change that")
        #expect(try script(in: own) == "mine")
        #expect(installer.installedServices().map(\.lastPathComponent) == [ServiceWorkflow.bundleName(for: specs[1])])
        let check = Doctor(facts: facts, paths: paths, loaded: loaded, runner: FakeProcessRunner(), rhPath: "/x/rh").servicesCheck()
        #expect(check.status == .warn)
        #expect(check.detail?.english() == "1 installed; 1 left out because a Quick Action of yours in ~/Library/Services has the same name", "\(check.detail?.english() ?? "")")
        #expect(check.fix?.english() == "Give your Quick Action in ~/Library/Services another name, then run `rh setup` again.")
    }

    /// A Quick Action Right Here wrote stays Right Here's when its script was changed in Automator: the record names it, and setup puts back what the config says.
    /// A version of one's own goes under another name, which the doctor's sentence says.
    @Test func aQuickActionRightHereWroteIsPutBackWhenItsScriptWasChanged() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let spec = ServiceSpec(title: "Copy Path", actionID: "copy-path.absolute", command: ServiceWorkflow.command(rhPath: "/x/rh", actionID: "copy-path.absolute"))
        try installer.installServices([spec])
        let bundle = installer.locations.services.appendingPathComponent(ServiceWorkflow.bundleName(for: spec))
        try "changed in Automator".write(to: bundle.appendingPathComponent("Contents/document.wflow"), atomically: true, encoding: .utf8)
        #expect(installer.heldByThePerson([spec]).isEmpty)
        #expect(!installer.servicesAreCurrent([spec]))
        try installer.installServices([spec])
        #expect(try script(in: bundle) == spec.command)
    }

    /// The same Quick Action unchanged, which Finder's Duplicate makes: its script is the command a Quick Action of Right Here's runs, so it is not taken for the person's.
    @Test func aCopyThatStillRunsRightHereIsNotHeld() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let spec = ServiceSpec(title: "Copy Path", actionID: "copy-path.absolute", command: ServiceWorkflow.command(rhPath: "/Applications/Right Here.app/Contents/Helpers/rh", actionID: "copy-path.absolute"))
        try Installer.writeWorkflow(spec, to: installer.locations.services.appendingPathComponent(ServiceWorkflow.bundleName(for: spec)))
        #expect(installer.heldByThePerson([spec]).isEmpty)
        // A script that only starts like one (more after it) is the person's.
        let longer = ServiceSpec(title: "Copy Name", actionID: "copy-path.name", command: ServiceWorkflow.command(rhPath: "/x/rh", actionID: "copy-path.name") + "; curl example.com")
        try Installer.writeWorkflow(longer, to: installer.locations.services.appendingPathComponent(ServiceWorkflow.bundleName(for: longer)))
        #expect(installer.heldByThePerson([longer]).count == 1)
    }
}

@Suite("Entry points review: files another program writes are read only as far as they can matter")
struct UnboundedReadReviewTests {
    private func paths(in directory: URL) -> RHPaths {
        RHPaths(environment: ["RH_CONFIG_DIR": directory.path], home: directory)
    }

    /// The Finder extension reads `.probe` in its `init`, on the main thread, before Finder gets a menu (and every Open panel starts one). The request is a word
    /// (`automation`, `launch`, `launch:<placement>`), but the file is read whole with `FileManager.contents(atPath:)`: a fresh `.probe` of gigabytes, which any
    /// process of the person's can leave in the config folder that the sandbox lets the extension read (or a link to one, whose own date is what is checked),
    /// costs the extension that many gigabytes of memory and about a quarter of a second each (measured: 1 GB, 0.25 s, 577 MB resident). A file that cannot be
    /// a request is no request; it is not read.
    @Test func aProbeMarkerTooLargeToBeARequestIsNoRequest() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        try sparseFile(at: ProbeMarker.url(in: target), bytes: 8 << 20)
        // Its length, not the text: the expectation would print eight million NUL characters.
        let request = ProbeMarker.pending(in: target)?.utf8.count
        #expect(request == nil, "an 8 MB marker was read whole and taken for a request")
    }

    /// `StateStore.read` refuses a state file over 128 KB, after `Data(contentsOf:)` has read all of it. Every `rh run` reads it (the recent folder, after the
    /// action: a Finder click, a Quick Action, a Shortcut, which waits for the JSON that comes after), and so does each `rh pins` and `rh recents` that Shortcuts
    /// starts to list the Saved Folders. The size is known before anything is read (`fstat`, as `BoundedRead` does for the config), so a file of a gigabyte
    /// is refused in microseconds. Reading it took 146 ms on the Mac this was written on (macOS 27.2, Apple silicon); an `open` and an `fstat` take well under a
    /// millisecond, so 50 ms leaves room for a slow or busy machine either way.
    @Test func aStateFileFarTooLargeIsRefusedWithoutBeingRead() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        try sparseFile(at: target.stateFile, bytes: 1 << 30)
        let clock = ContinuousClock()
        let started = clock.now
        let reading = StateStore.read(paths: target)
        let took = clock.now - started
        guard case .unreadable = reading else {
            Issue.record("a state file of 1 GB was read as \(reading)")
            return
        }
        #expect(took < .milliseconds(50), "a state file of 1 GB was read whole before its size was looked at (\(took))")
    }
}
