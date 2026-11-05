import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

/// U+0412 CYRILLIC CAPITAL LETTER VE, and U+1C80 CYRILLIC SMALL LETTER ROUNDED VE: Unicode's case folding maps both to в (U+0432), and so does APFS when it compares
/// names; Foundation's case-insensitive folding, which `ServiceWorkflow.fold` uses, leaves U+1C80 as it is. Eight more letters of U+1C81 to U+1C88 do the same
/// (measured on this Mac's data volume by creating every case pair of U+0020 to U+3FFFF).
private let ve = "\u{0412}x"
private let roundedVe = "\u{1C80}x"

private func command(in bundle: URL) throws -> String? {
    let data = try Data(contentsOf: bundle.appendingPathComponent("Contents/document.wflow"))
    let document = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    let action = try #require((document["actions"] as? [[String: Any]])?.first?["action"] as? [String: Any])
    return (action["ActionParameters"] as? [String: Any])?["COMMAND_STRING"] as? String
}

private func temporaryHome() throws -> URL {
    try makeTemporaryDirectory()
}

@Suite("Quick Actions: installing the Quick Actions")
struct QuickActionsReviewKitTests {
    /// The platform fact the next tests stand on: the volume takes the two names for one, and so does `fold` (it kept them apart).
    @Test func theVolumeTakesTheseTwoNamesForOneAndSoDoesFold() throws {
        let folder = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(ve), withIntermediateDirectories: false)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(roundedVe).path), "this volume tells them apart")
        #expect(ServiceWorkflow.fold(ServiceWorkflow.namePrefix + ve) == ServiceWorkflow.fold(ServiceWorkflow.namePrefix + roundedVe))
    }

    /// A first install: both specs pass `distinct`, the second is written into the first one's staging folder (the bundle named for U+0412 then shows and runs the second action), and its
    /// swap finds nothing to move (ENOENT): the Quick Actions after it are not installed and the ones the config dropped are not removed. Later installs return without an error, but the
    /// first action never gets a Quick Action and `servicesAreCurrent` never becomes true: every setup says "updated" and runs `pbs -update`, and the window rewrites them after every edit.
    @Test func twoTitlesTheVolumeTakesForOneInstallOneServiceAndTheRestToo() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let wanted = [ServiceSpec(title: ve, actionID: "new-file.one", command: "echo one"),
                      ServiceSpec(title: roundedVe, actionID: "new-file.two", command: "echo two"),
                      ServiceSpec(title: "Open in Ghostty", actionID: "open.terminal", command: "echo three")]
        let written = try installer.installServices(wanted)
        #expect(written.count == 2, "\(written.map(\.lastPathComponent))")
        #expect(installer.installedServices().map(\.lastPathComponent).contains("Right Here - Open in Ghostty.workflow"))
        #expect(installer.servicesAreCurrent(wanted), "every setup would install them again")
    }

    /// A reinstall over a Quick Action of that name: the first swap puts the new bundle in, the second swaps the old one back (its staging name is the same folder),
    /// and the install returns as if it had worked. The Quick Action keeps running the `rh` it was written with.
    @Test func aReinstallWithTwoTitlesTheVolumeTakesForOneLeavesNoQuickActionOnTheOldRh() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        try installer.installServices([ServiceSpec(title: ve, actionID: "new-file.one", command: ServiceWorkflow.command(rhPath: "/old/rh", actionID: "new-file.one"))])
        let wanted = [ServiceSpec(title: ve, actionID: "new-file.one", command: ServiceWorkflow.command(rhPath: "/new/rh", actionID: "new-file.one")),
                      ServiceSpec(title: roundedVe, actionID: "new-file.two", command: ServiceWorkflow.command(rhPath: "/new/rh", actionID: "new-file.two"))]
        _ = try installer.installServices(wanted)
        let commands = try installer.installedServices().map { try command(in: $0) ?? "" }
        #expect(!commands.contains { $0.contains("/old/rh") }, "the install said it worked and a Quick Action still runs the old rh: \(commands)")
    }

    /// The same, end to end from a config that `rh config sync pull` takes without `--allow-commands` (two templates with no contents, see QuickActionsReviewCoreTests): the Quick Actions
    /// step of the next Install or Repair fails, and the ones after it never converge.
    @Test func aPulledConfigWithSuchTitlesMakesTheQuickActionsOfInstallAndRepairFail() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let text = """
        [general]
        agents = []

        [[new_file.template]]
        id = "one"
        title = "\(ve)"
        extension = "txt"

        [[new_file.template]]
        id = "two"
        title = "\(roundedVe)"
        extension = "txt"

        [services]
        items = ["new-file.one", "new-file.two", "copy-path.absolute"]
        """
        let parsed = ConfigParser.parse(text)
        #expect(!parsed.hasErrors)
        let specs = ActionRegistry(config: parsed.config, facts: FakeSystemFacts(homeDirectory: home)).serviceSpecs(rhPath: "/x/rh")
        let installer = Installer(home: home)
        #expect(throws: Never.self) { try installer.installServices(specs) }
        #expect(installer.servicesAreCurrent(specs))
    }

    /// The Checks compare the names of the bundles and nothing else. Quick Actions that run an `rh` that is gone (the app was moved, `rh install --services`
    /// was run from another copy that was removed since) are "installed" and fine, and the window, which rewrites them only when that check says they differ, leaves them.
    @Test func theChecksSayTheQuickActionsAreFineWhileTheyRunAnRhThatIsGone() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = RHPaths(environment: [:], home: home)
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        try "[general]\nagents = []\n\n[services]\nitems = [\"copy-path.absolute\"]\n".write(to: paths.configFile, atomically: true, encoding: .utf8)
        let facts = FakeSystemFacts(homeDirectory: home)
        let loaded = ConfigStore.load(paths: paths)
        let registry = ActionRegistry(config: loaded.config, facts: facts, localizer: loaded.config.localizer)
        let gone = home.appendingPathComponent("Moved Away/Right Here.app/Contents/Helpers/rh").path
        try Installer(home: home).installServices(registry.serviceSpecs(rhPath: gone))
        let current = "/Applications/Right Here.app/Contents/Helpers/rh"
        #expect(!Installer(home: home).servicesAreCurrent(registry.serviceSpecs(rhPath: current)), "setup itself sees that they are out of date")
        let check = Doctor(facts: facts, paths: paths, loaded: loaded, runner: FakeProcessRunner(), rhPath: current).servicesCheck()
        #expect(check.status != .ok, "the check says \(check.detail?.english() ?? "") while every Quick Action runs \(gone), which does not exist")
    }

    /// `installedServices` matched the prefix and the suffix with `String.hasPrefix`/`hasSuffix`, which compare grapheme clusters. A title that begins with a mark, a joiner or a
    /// vowel sign joins the space at the end of "Right Here - ", and one that ends in a Prepend character (U+0600 to U+0605, which a name may have) joins the dot of ".workflow". The
    /// bundle is written and then never seen: never current (every setup rewrites it and runs `pbs -update`), never removed when the config drops it, and left behind by `rh uninstall`.
    @Test("a Quick Action whose title joins the prefix or the suffix is seen, kept current and removed", arguments: [
        ("en", "Report\\u0600"),   // English: "New %@", the title ends the name
        ("de", "\\u0301Bericht")   // German: "%@ erstellen", the title starts it
    ])
    func aQuickActionWhoseTitleJoinsThePrefixOrTheSuffixIsStillRightHeres(language: String, title: String) throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let text = "[general]\nagents = []\nlanguage = \"\(language)\"\n\n[[new_file.template]]\nid = \"report\"\ntitle = \"\(title)\"\nextension = \"txt\"\n\n[services]\nitems = [\"new-file.report\"]\n"
        let parsed = ConfigParser.parse(text)
        #expect(!parsed.hasErrors, "\(parsed.diagnostics.map(\.message))")
        #expect(LaunchCommands.changes(from: Data("[general]\nagents = []\n".utf8), to: Data(text.utf8), overlay: nil).isEmpty, "a pull would ask about it")
        let specs = ActionRegistry(config: parsed.config, facts: FakeSystemFacts(homeDirectory: home), localizer: parsed.config.localizer).serviceSpecs(rhPath: "/x/rh")
        let installer = Installer(home: home)
        #expect(try installer.installServices(specs).count == 1)
        #expect(installer.installedServices().count == 1, "the installer does not see the bundle it wrote")
        #expect(installer.servicesAreCurrent(specs), "every setup would write it again")
        try installer.removeServices()
        let left = try FileManager.default.contentsOfDirectory(atPath: installer.locations.services.path).filter { !$0.hasPrefix(".") }
        #expect(left.isEmpty, "rh uninstall leaves \(left)")
    }

    /// `RealHomeGuard.checkSystemWide` refused only a process with `RH_NO_UI` and no `RH_HOME`: a test that gave `rh` a trial home and ran `rh install --finder`
    /// (which forces `systemWide`) would have registered the extension for the whole Mac. CLAUDE.md says no test registers anything. A fake runner records what would
    /// have been started.
    @Test func aProcessATestStartedWithATrialHomeDoesNotRegisterTheExtensionForTheWholeMac() async throws {
        let trial = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: trial) }
        let runner = FakeProcessRunner()
        let manager = FinderExtensionManager(runner: runner, environment: ["RH_NO_UI": "1", "RH_HOME": trial.path])
        try? await manager.register(appexPath: "/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex")
        #expect(runner.recorded.isEmpty, "pluginkit would have been started: \(runner.recorded.map { ([$0.executable] + $0.arguments).joined(separator: " ") })")
    }
}
