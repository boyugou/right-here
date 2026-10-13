#!/usr/bin/env bash
#
# Render the setup window to a PNG without a screen, for looking at layout and translations.
#
#   ./script/preview_setup.sh out.png                    English, light, the checks of this Mac
#   ./script/preview_setup.sh out.png de                 German
#   ./script/preview_setup.sh out.png en --dark          dark mode
#   ./script/preview_setup.sh out.png en --onboarding    the first-run card, as when the Finder extension is off
#   ./script/preview_setup.sh out.png en --demo          a healthy setup, with the Finder menu open, that is the same on every Mac (screenshots)
#   ./script/preview_setup.sh out.png en --demo --details  the same, with the list of checks open too
#   ./script/preview_setup.sh out.png en --demo --submenus  the same, with every submenu of the Finder menu open
#   ./script/preview_setup.sh out.png en --onboarding --demo  the first-run card on those checks (the Finder menu is closed under it)
#   ./script/preview_setup.sh out.png de --gallery       every sentence the doctor can say, as rows of the list
#
# It builds a throwaway package under .build/preview that links the app's own view files and the
# package libraries, then renders SetupView with ImageRenderer.
#
# Without --demo and --gallery the checks and the Finder menu are the real ones for this machine, so the picture shows
# this Mac: its paths, its last action, its apps. --demo and --gallery show canned checks and nothing from the machine
# that renders: no real path (they are written as the window writes them, `~/...`), no real last action, no real agent
# or terminal. --demo also shows a canned Finder menu (a fixed home folder, a fixed set of installed apps and a fixed
# config); the icons of those apps are the ones of the Mac that renders, because an icon is read from the installed app
# (an app this Mac does not have gets the system's plain app icon). --gallery has no menu, so it shows none.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?usage: preview_setup.sh out.png [language] [--dark] [--onboarding] [--demo] [--details] [--submenus] [--gallery]}"
# The script changes folder before it renders, so a relative output path is resolved against where it was started.
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
LANGUAGE="en"
FLAGS=()
for argument in "${@:2}"; do
  case "$argument" in
    --dark | --onboarding | --demo | --details | --submenus | --gallery) FLAGS+=("$argument") ;;
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
# The Finder menu's own glyphs, which main.swift registers by name (the app finds them in its asset catalog), and the
# icon the window's header shows (this executable has none of its own).
ln -sfn "$ROOT/Apps/FinderExtension/Assets.xcassets" "$PREVIEW/Assets.xcassets"
ln -sf "$ROOT/Apps/RightHere/icon-1024.png" "$PREVIEW/icon-1024.png"
# An app of the demo menu that this Mac does not have is drawn with the plain icon of an app that has none of its own. The
# bundle is made in a temporary folder: inside the hidden .build folder macOS draws a "prohibited" sign on it instead.
STANDIN="$(mktemp -d)"
trap 'rm -rf "$STANDIN"' EXIT
mkdir -p "$STANDIN/Generic.app/Contents/MacOS"
printf '#!/bin/sh\n' > "$STANDIN/Generic.app/Contents/MacOS/Generic"
chmod +x "$STANDIN/Generic.app/Contents/MacOS/Generic"
cat > "$STANDIN/Generic.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>preview.generic</string>
<key>CFBundleExecutable</key><string>Generic</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
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

/// Stops, loudly, if a canned menu names something of the Mac that renders it, in any of its entries.
func requireNothingOfThisMac(_ menu: [MenuNode]) -> [MenuNode] {
    func titles(_ nodes: [MenuNode]) -> [String] { nodes.flatMap { [$0.title] + titles($0.children) } }
    let text = titles(menu).joined(separator: "\n")
    for own in [NSHomeDirectory(), NSUserName()] where own.count >= 4 && text.contains(own) {
        FileHandle.standardError.write(Data("the canned menu says \"\(own)\", which belongs to this Mac\n".utf8))
        exit(1)
    }
    return menu
}

/// The Mac of the demo: a fixed home folder and a fixed set of installed apps (no agent's desktop app, so an agent's entry
/// has the terminal glyph on every Mac). The icon of an app that is "installed" comes from the Mac that renders: the app's
/// real icon when it has the app, the plain app icon when it has not.
func demoFacts() -> FakeSystemFacts {
    let live = LiveSystemFacts()
    let installed = ["com.mitchellh.ghostty", "com.apple.Terminal", "com.microsoft.VSCode", "dev.zed.Zed", "com.apple.dt.Xcode", "com.apple.TextEdit"]
    return FakeSystemFacts(
        homeDirectory: URL(fileURLWithPath: "/Users/tester"),
        directories: ["/Users/tester"],
        applications: Dictionary(uniqueKeysWithValues: installed.map { ($0, live.applicationURL(bundleID: $0) ?? URL(fileURLWithPath: ProcessInfo.processInfo.environment["PREVIEW_GENERIC_APP"] ?? "/")) })
    )
}

/// The Finder menu of the demo Mac: the default layout, for the terminal, editor and agents of the demo's checks.
func demoMenu(_ facts: FakeSystemFacts) -> [MenuNode] {
    let config = Config(terminal: "ghostty", editor: "vscode", enabledAgents: ["claude", "codex"])
    return requireNothingOfThisMac(MenuPreview.folderMenu(ConfigLoadResult(config: config, diagnostics: []), facts: facts, folder: facts.homeDirectory, localizer: .system))
}

/// Every submenu of a menu, for --submenus.
func allSubmenus(_ nodes: [MenuNode]) -> Set<String> {
    var open = Set<String>()
    while let next = MenuPreview.rows(nodes, expanded: open).first(where: { $0.hasChildren && !$0.isExpanded }) { open.insert(next.id) }
    return open
}

/// The Finder menu's own glyphs. The app finds them in its asset catalog (Apps/FinderExtension/Assets.xcassets, which
/// project.yml gives both targets); this package has none, so the same PDFs are registered under the names the catalog
/// gives them, and the picture shows the glyphs of the real menu and not the system symbols that stand in elsewhere.
func registerMenuGlyphs() {
    for glyph in Set(IconProvider.dedicatedGlyphs.values) {
        let file = URL(fileURLWithPath: "Assets.xcassets/\(glyph).imageset/\(glyph).pdf")
        guard let image = NSImage(contentsOf: file), image.setName(glyph) else {
            FileHandle.standardError.write(Data("no glyph \(glyph) in Assets.xcassets\n".utf8))
            exit(1)
        }
    }
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
        DoctorCheck(.finderExtension, status: .ok, detail: .doctorExtensionEnabled("\(appContents)/PlugIns/FinderExtension.appex")),
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
        DoctorCheck(.agents, status: .warn, detail: .doctorAgentsNone, fix: .doctorFixAgentsAdd(#"agents = ["claude"]"#)),
        DoctorCheck(.finderMenu, status: .warn, detail: .doctorMenuEmpty, notes: [.doctorVerbatim("Agents: none is enabled; general.agents lists none."), .doctorVerbatim("Copy Path: copy_path.styles lists no style.")], fix: .doctorFixMenuEmpty),
        DoctorCheck(.claudeLink, status: .warn, detail: .doctorClaudeLinkMissing(#"launcher = "link""#), fix: .doctorFixClaudeLink),
        DoctorCheck(.finderRunner, status: .warn, detail: .doctorRunnerStale(target), fix: .doctorFixInstallScripts),
        DoctorCheck(.services, status: .warn, detail: .doctorServicesDiffer("12", "3", "1"), fix: .doctorFixInstallServices),
        DoctorCheck(.cliLink, status: .warn, detail: .doctorCliNotOnPath("~/.local/bin/rh"), fix: .doctorFixCliPath("~/.local/bin")),
        // Ok, so that the window shows the list of checks and not the first-run card (a row that is not ok would show the card).
        DoctorCheck(.finderExtension, status: .ok, detail: .doctorExtensionEnabled("\(appContents)/PlugIns/FinderExtension.appex")),
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
        (.warn, .doctorVerbatim("Ghostty cannot run commands yet."), .doctorFixAgentLauncher(#"launcher = "link""#, #""desktop""#)),
        (.warn, .doctorAppFallback("iTerm", "Ghostty"), .doctorFixTerminalFallback),
        (.warn, .doctorAppFallback("Zed", "Visual Studio Code"), .doctorFixEditorFallback),
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
    registerMenuGlyphs()
    if flags.contains("--gallery") {
        model.simulate(checks: gallery(), opensDetails: true)
    } else if flags.contains("--demo") {
        model.simulate(checks: demo(), opensDetails: flags.contains("--details"))
        let facts = demoFacts()
        model.simulate(menu: demoMenu(facts), icons: IconProvider(facts: facts))
    } else {
        await model.refresh()
    }
    if flags.contains("--onboarding") { model.simulateExtensionOff() }
    if flags.contains("--submenus") { model.simulate(openSubmenus: allSubmenus(model.menu)) }
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
    // The header shows the app's icon, which this executable does not have: the checked-in source of the real one stands in.
    guard let icon = NSImage(contentsOfFile: "icon-1024.png") else {
        FileHandle.standardError.write(Data("no icon-1024.png to use as the app's icon\n".utf8))
        exit(1)
    }
    NSApplication.shared.applicationIconImage = icon
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
PREVIEW_GENERIC_APP="$STANDIN/Generic.app" "$BIN" "$OUT" ${FLAGS[@]+"${FLAGS[@]}"} -AppleLanguages "($LANGUAGE)"
