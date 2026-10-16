import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

// What the setup window needs on a first run (found by the independent review of the app): the loader and the runner agree about what a config is,
// an app on a disk image is refused, and a Finder extension that is registered and not switched on is not called missing. Nothing here touches the
// real home folder, the real Finder or an installed app: a temporary home, fake system facts and a fake process runner.

private struct FirstRunMac {
    let home: URL
    let paths: RHPaths

    init() throws {
        home = try makeTemporaryDirectory()
        paths = RHPaths(environment: [:], home: home)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: home) }

    var facts: FakeSystemFacts {
        FakeSystemFacts(homeDirectory: home, directories: [home.path], applications: [
            "com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            "com.apple.TextEdit": URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        ])
    }

    func loader(_ runner: any ProcessRunner = FakeProcessRunner()) -> SetupLoader {
        SetupLoader(facts: facts, paths: paths, runner: runner, helperPath: "/opt/app/rh", localizer: .english)
    }

    /// The setup of the window: the app's own `rh`, and a Mac that nothing else is registered on (a trial home would skip the extension, which
    /// is what the window never does).
    func actions(helper: String = "/opt/app/rh", runner: any ProcessRunner = FakeProcessRunner()) -> SetupActions {
        SetupActions(facts: facts, paths: paths, runner: runner, helperPath: helper, trialHome: nil)
    }
}

@Suite("The first run of the setup window")
struct FirstRunWindowTests {
    /// A dotfiles manager makes `~/.config/right-here/config.toml` a link before its repository is cloned. The runner says there is something
    /// there (it never rewrites a config) and its config step fails. The loader says there is no config, so the window draws the first-run
    /// chooser, whose one button can only fail, and a failed first run is drawn without its report (the report is shown only when
    /// `needsFirstRunChoice` is false), so the person is left with a footnote.
    @Test func aConfigThatIsALinkToNothingIsNotOfferedAsAFirstRun() async throws {
        let mac = try FirstRunMac(); defer { mac.cleanUp() }
        try FileManager.default.createDirectory(at: mac.paths.configDirectory, withIntermediateDirectories: true)
        let missing = mac.home.appendingPathComponent("dotfiles/right-here/config.toml").path
        try FileManager.default.createSymbolicLink(atPath: mac.paths.configFile.path, withDestinationPath: missing)

        let result = await mac.actions().setUp(SetupChoices(terminal: "terminal", editor: "textedit", agents: []))
        #expect(result.report?.step(.config)?.outcome == .failed, "the runner treats the link as a config that is there and cannot be used")

        let snapshot = await mac.loader().load()
        #expect(snapshot.configExists, "the loader must agree with the runner: a link to nothing is not a first run that the Set Up button can finish")
        #expect(snapshot.offer == nil)
    }

    /// The README says to drag the app to Applications. The refusal covers the temporary copy macOS makes of a downloaded app
    /// (`/AppTranslocation/`) and nothing else; an app that is run from a mounted volume writes the runner script, the command link,
    /// the Quick Actions and the extension's registration into the volume, with no word, and they all break when it is ejected.
    /// (Not verified here: whether macOS translocates the app of a quarantined disk image opened in place. A volume without the
    /// quarantine mark, a USB stick or a network share is not translocated.)
    @Test func anAppRunFromAMountedVolumeIsRefusedOrWarnedAbout() async throws {
        let mac = try FirstRunMac(); defer { mac.cleanUp() }
        let onTheImage = "/Volumes/Right Here 0.3.0/Right Here.app/Contents/Helpers/rh"
        let result = await mac.actions(helper: onTheImage).setUp()

        let refused = result.report == nil && result.notice?.isProblem == true
        let warned = result.report?.warnings.contains { $0.contains("/Volumes") || $0.localizedCaseInsensitiveContains("disk image") } == true
        #expect(refused || warned, "setup wrote \(String(describing: Installer(home: mac.home).installedRunnerTarget())) into the machine and said nothing")
    }

    /// A `rh` that is not inside an app (a build folder, Homebrew's) is the developer's or the package manager's business: its volume is not the
    /// disk image's, and refusing it would stop a person who keeps their projects on an external drive.
    @Test func anRhThatIsNotInsideAnAppIsNotRefusedForItsVolume() async throws {
        let mac = try FirstRunMac(); defer { mac.cleanUp() }
        let result = await mac.actions(helper: "/Volumes/Projects/right-here/.build/release/rh").setUp()
        #expect(result.report != nil, "setup ran: \(String(describing: result.notice))")
    }

    /// `pluginkit -m` prints a tag for an election the person made (`+`, `-`) and none for the default: of the 513 plug-ins on the Mac this was
    /// measured on, 477 have no tag. An extension that macOS found and the person has not switched on is such a line, with its path, and it
    /// is registered. The parser reads any other tag as "not registered", so the doctor tells a person who is inside Right Here.app to
    /// "Install Right Here.app, then run `rh setup`", and no "switch it on" item is made for an agent (SetupAdvice reads only needs-user).
    @Test func anExtensionThatIsRegisteredAndNotSwitchedOnIsNotReportedAsMissing() async {
        let appex = "/Applications/Right Here.app/Contents/PlugIns/FinderExtension.appex"
        let untagged = "     \(AppIdentity.extensionBundleID)(0.3.0)\tA022864B-91F6-4FBF-BCCC-E2F904C14267\t2026-10-16 07:33:49 +0000\t\(appex)\n (1 plug-in)\n"
        let status = FinderExtensionManager.parse(untagged)
        #expect(status.paths == [appex], "the line names the extension, so it is registered")
        #expect(status.state != .notRegistered)

        let check = await Doctor.extensionCheck(runner: FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: untagged)]))
        #expect(check.status == .needsUser, "it is switched off, which only the person can change; the doctor said \(check.status.rawValue): \(check.detail?.english() ?? "")")
    }
}
