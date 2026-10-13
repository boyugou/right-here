#!/usr/bin/env bash
#
# Render the setup window to a PNG without a screen, for looking at layout and translations.
#
#   ./script/preview_setup.sh out.png                    English, light, the checks of this Mac
#   ./script/preview_setup.sh out.png de                 German
#   ./script/preview_setup.sh out.png en --dark          dark mode
#   ./script/preview_setup.sh out.png en --onboarding    the first-run card, as when the Finder extension is off
#   ./script/preview_setup.sh out.png en --demo          a healthy setup that is the same on every Mac (screenshots)
#   ./script/preview_setup.sh out.png en --demo --details  the same, with the list of checks open
#   ./script/preview_setup.sh out.png de --gallery       every sentence the doctor can say, as rows of the list
#
# It builds a throwaway package under .build/preview that links the app's own view files and the
# package libraries, then renders SetupView with ImageRenderer.
#
# Without --demo and --gallery the checks are the real ones for this machine, so the picture shows this Mac: its
# paths, its last action. Both of those show canned checks and nothing from the machine that renders: no real path
# (they are written as the window writes them, `~/...`), no real last action, no real agent or terminal.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?usage: preview_setup.sh out.png [language] [--dark] [--onboarding] [--demo] [--details] [--gallery]}"
# The script changes folder before it renders, so a relative output path is resolved against where it was started.
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
LANGUAGE="en"
FLAGS=()
for argument in "${@:2}"; do
  case "$argument" in
    --dark | --onboarding | --demo | --details | --gallery) FLAGS+=("$argument") ;;
    --*) echo "preview_setup.sh: unknown option $argument" >&2; exit 2 ;;
    *) LANGUAGE="$argument" ;;
  esac
done
PREVIEW="$ROOT/.build/preview"
# SwiftPM names a path dependency after its folder, which is not "right-here" in a worktree or a renamed clone.
PKG="$(basename "$ROOT")"

mkdir -p "$PREVIEW/Sources/preview"
cat > "$PREVIEW/Package.swift" <<PACKAGE
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Preview",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "$ROOT")],
    targets: [
        .executableTarget(
            name: "preview",
            dependencies: [.product(name: "RightHereCore", package: "$PKG"), .product(name: "RightHereKit", package: "$PKG")],
            path: "Sources/preview",
            swiftSettings: [.swiftLanguageMode(.v5), .define("PREVIEW")]
        )
    ]
)
PACKAGE
ln -sf "$ROOT/Apps/RightHere/SetupView.swift" "$PREVIEW/Sources/preview/SetupView.swift"
ln -sf "$ROOT/Apps/RightHere/SetupModel.swift" "$PREVIEW/Sources/preview/SetupModel.swift"
cat > "$PREVIEW/Sources/preview/main.swift" <<'SWIFT'
import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

/// Where Right Here.app is installed; a fixed place, not one of this Mac's.
let appContents = "/Applications/Right Here.app/Contents"

/// What a check that was a minute ago reads as, in the language of the window and from a fixed pair of dates.
func ago(_ seconds: Double) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    formatter.locale = Locale(identifier: Locale.preferredLanguages.first ?? "en")
    let now = Date(timeIntervalSinceReferenceDate: 0)
    return formatter.localizedString(for: now.addingTimeInterval(-seconds), relativeTo: now)
}

/// Stops, loudly, if canned checks name something of the Mac that renders them: its home folder or its account.
func requireNothingOfThisMac(_ checks: [DoctorCheck]) -> [DoctorCheck] {
    let text = checks.flatMap { $0.englishLines() }.joined(separator: "\n")
    for own in [NSHomeDirectory(), NSUserName()] where own.count >= 4 && text.contains(own) {
        FileHandle.standardError.write(Data("the canned checks say \"\(own)\", which belongs to this Mac\n".utf8))
        exit(1)
    }
    return checks
}

/// A healthy setup, the same on every Mac: what the website's screenshots show.
func demo() -> [DoctorCheck] {
    requireNothingOfThisMac([
        DoctorCheck(.config, status: .ok, detail: .doctorVerbatim("~/.config/right-here/config.toml")),
        DoctorCheck(.terminalDefault, status: .ok, detail: .menuOpenIn("Ghostty")),
        DoctorCheck(.editorDefault, status: .ok, detail: .menuOpenIn("Visual Studio Code")),
        DoctorCheck(.agent("claude"), title: "Claude Code", status: .ok, detail: .doctorAgentOk("claude", "Claude Code Here")),
        DoctorCheck(.agent("codex"), title: "Codex", status: .ok, detail: .doctorAgentOk("codex", "Codex Here")),
        DoctorCheck(.claudeLink, status: .ok, detail: .doctorClaudeLinkOk),
        DoctorCheck(.finderRunner, status: .ok, detail: .doctorRunnerOk("\(appContents)/Helpers/rh")),
        DoctorCheck(.services, status: .ok, detail: .doctorServicesOk("14")),
        DoctorCheck(.cliLink, status: .ok, detail: .doctorVerbatim("~/.local/bin/rh")),
        DoctorCheck(.finderExtension, status: .ok, detail: .doctorVerbatim("\(appContents)/PlugIns/FinderExtension.appex")),
        DoctorCheck(.finderActivity, status: .ok, detail: .doctorActivityRecent("agent.claude", "container", ago(300)))
    ])
}

/// One row for each way the doctor can answer, with long values, so the details list can be checked for text that does not fit.
/// A row has the id and title of a check; the second kind of row is an agent's, which keeps the ids unique.
func gallery() -> [DoctorCheck] {
    let config = "~/.config/right-here/config.toml"
    let target = "\(appContents)/Helpers/rh"
    let folder = "~/Library/Mobile Documents/com~apple~CloudDocs/Right Here"
    let changes = [
        #"[[app]] terminal open_args = ["/usr/bin/id", "-un", "{dir}"]"#,
        #"[[app]] terminal run_args = ["/bin/sh", "-c", "{command}"]"#,
        #"[agent.claude] command = "claude --dangerously-skip-permissions" (was "claude")"#
    ].joined(separator: "; ")
    var rows: [DoctorCheck] = [
        DoctorCheck(.config, status: .warn, detail: .doctorConfigMissing(config), notes: [.doctorConfigOverlay("~/.config/right-here/config.local.toml"), .doctorConfigSymlink("config.toml")], fix: .doctorFixConfigInit),
        DoctorCheck(.terminalDefault, status: .fail, detail: .doctorTerminalNone, fix: .doctorFixTerminal),
        DoctorCheck(.editorDefault, status: .ok, detail: .menuOpenIn("Visual Studio Code")),
        DoctorCheck(.agents, status: .warn, detail: .doctorAgentsNone, fix: .doctorFixAgentsAdd),
        DoctorCheck(.claudeLink, status: .warn, detail: .doctorClaudeLinkMissing, fix: .doctorFixClaudeLink),
        DoctorCheck(.finderRunner, status: .warn, detail: .doctorRunnerStale(target), fix: .doctorFixInstallScripts),
        DoctorCheck(.services, status: .warn, detail: .doctorServicesDiffer("12", "3", "1"), fix: .doctorFixInstallServices),
        DoctorCheck(.cliLink, status: .warn, detail: .doctorCliNotOnPath("~/.local/bin/rh"), fix: .doctorFixCliPath),
        // Ok, so that the window shows the list of checks and not the first-run card (a row that is not ok would show the card).
        DoctorCheck(.finderExtension, status: .ok, detail: .doctorVerbatim("\(appContents)/PlugIns/FinderExtension.appex")),
        DoctorCheck(.finderActivity, status: .ok, detail: .doctorActivityRecent("agent.claude", "container", ago(300))),
        DoctorCheck(.syncFolder, status: .warn, detail: .doctorSyncFolderUnreachable(folder), fix: .doctorFixSyncFolder),
        DoctorCheck(.syncRemote, status: .warn, detail: .doctorSyncRemoteEvicted, fix: .doctorFixSyncDownload),
        DoctorCheck(.syncCommands, status: .warn, detail: .doctorSyncCommandsPending("5", changes), notes: [.doctorSyncCommandsMore("2")], fix: .doctorFixSyncCommands),
        DoctorCheck(.syncState, status: .warn, detail: .doctorSyncDiverged, fix: .doctorFixSyncCompare),
        DoctorCheck(.syncConflict, status: .warn, detail: .doctorSyncConflict("config 2.toml, config 3.toml", folder), fix: .doctorFixSyncConflict),
        DoctorCheck(.finderChain, status: .needsUser, detail: .doctorVerbatim("Ghostty: timed out, Terminal: granted"), fix: .doctorVerbatim("macOS is waiting for you to allow Right Here to control the terminal. Click Allow, then run this again.")),
        DoctorCheck(.finderLaunch, status: .ok, detail: .doctorVerbatim("Ghostty ran a typed command in a new session in 1.1 s (request accepted after 0.3 s); login shell /bin/zsh"))
    ]
    let more: [(DoctorCheck.Status, LocalizedMessage, LocalizedMessage?)] = [
        (.fail, .doctorVerbatim("error: config.toml:1: expected ] to close the table"), .doctorFixConfigErrors),
        (.warn, .doctorConfigWarnings("12"), .doctorFixConfigWarnings),
        (.ok, .menuOpenIn("Ghostty"), nil),
        (.warn, .doctorEditorNone, .doctorFixEditor),
        (.fail, .doctorAppNotInstalled("Ghostty"), .doctorFixTerminal),
        (.warn, .doctorAgentNotFound("claude"), .doctorFixAgentRemove("claude")),
        (.warn, .doctorVerbatim("Ghostty cannot run commands yet."), .doctorFixAgentLauncher),
        (.ok, .doctorAgentOk("claude", "Claude Code in Last-Used Terminal"), nil),
        (.ok, .doctorClaudeLinkOk, nil),
        (.ok, .doctorRunnerOk(target), nil),
        (.fail, .doctorRunnerTargetMissing(target), .doctorFixInstallScripts),
        (.fail, .doctorRunnerMissing, .doctorFixInstallScripts),
        (.warn, .doctorServicesNone, .doctorFixInstallServices),
        (.ok, .doctorServicesOk("12"), nil),
        (.warn, .doctorCliMissing("~/.local/bin/rh"), .doctorFixInstallCLI),
        (.warn, .doctorExtensionMultiple("2", "\(target); ~/Library/Developer/Xcode/DerivedData/RightHere/Build/Products/Release/Right Here.app/Contents/PlugIns/FinderExtension.appex"), .doctorFixExtensionClean),
        (.fail, .doctorExtensionNotRegistered, .doctorFixExtensionInstall),
        (.needsUser, .doctorExtensionDisabled, .doctorFixExtensionEnable),
        (.ok, .doctorActivityNone, nil),
        (.warn, .doctorSyncStateUnreadable("~/.config/right-here/sync.toml"), .doctorFixSyncReenable),
        (.warn, .doctorSyncRemoteMissing, .doctorFixSyncPush),
        (.ok, .doctorSyncRemoteValid, nil),
        (.fail, .doctorVerbatim("config.toml has an error: expected a value on line 3"), .doctorFixSyncFixRemote),
        (.ok, .doctorSyncCommandsOwn("2", changes), nil),
        (.ok, .doctorSyncInSync, nil),
        (.warn, .doctorSyncLocalAhead, .doctorFixSyncPushShort),
        (.warn, .doctorSyncRemoteAhead, .doctorFixSyncPull)
    ]
    for (number, row) in more.enumerated() {
        rows.append(DoctorCheck(.agent("gallery\(number)"), title: "Agent \(number + 1)", status: row.0, detail: row.1, fix: row.2))
    }
    let said = Set(rows.flatMap { [$0.detail?.key, $0.fix?.key].compactMap { $0 } + $0.notes.map(\.key) })
    for key in LocalizationKey.allCases where key.rawValue.hasPrefix("doctor.") && !said.contains(key) {
        FileHandle.standardError.write(Data("the gallery has no row for \(key.rawValue)\n".utf8))
    }
    return requireNothingOfThisMac(rows)
}

@MainActor
func render(dark: Bool, to path: String) async {
    let flags = Set(CommandLine.arguments)
    let model = SetupModel()
    if flags.contains("--gallery") {
        model.simulate(checks: gallery(), opensDetails: true)
    } else if flags.contains("--demo") {
        model.simulate(checks: demo(), opensDetails: flags.contains("--details"))
    } else {
        await model.refresh()
    }
    if flags.contains("--onboarding") { model.simulateExtensionOff() }
    // A real window mirrors itself for a right-to-left system language; the renderer needs to be told.
    let language = Locale.preferredLanguages.first ?? "en"
    let rightToLeft = Locale.Language(identifier: language).characterDirection == .rightToLeft
    let view = SetupView(model: model)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        print("render failed"); exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(Int(image.size.width)) x \(Int(image.size.height)) pt)")
}

let arguments = CommandLine.arguments
MainActor.assumeIsolated {
    _ = NSApplication.shared
    Task { @MainActor in
        await render(dark: arguments.contains("--dark"), to: arguments[1])
        exit(0)
    }
    RunLoop.main.run()
}
SWIFT

cd "$PREVIEW"
if ! swift build > "$PREVIEW/build.log" 2>&1; then
  grep -E "error" "$PREVIEW/build.log" >&2 || tail -20 "$PREVIEW/build.log" >&2
  exit 1
fi
BIN="$(swift build --show-bin-path)/preview"
"$BIN" "$OUT" ${FLAGS[@]+"${FLAGS[@]}"} -AppleLanguages "($LANGUAGE)"
