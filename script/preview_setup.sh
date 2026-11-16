#!/usr/bin/env bash
#
# Render the setup window to a PNG without a screen, for looking at layout and translations.
#
#   ./script/preview_setup.sh out.png                       English, light, the first section (Overview), the state of this Mac
#   ./script/preview_setup.sh out.png de                    German
#   ./script/preview_setup.sh out.png en --dark             dark mode
#   ./script/preview_setup.sh out.png en --tab worktrees    one section: overview, menu, checks, ai, worktrees or folders
#   ./script/preview_setup.sh out.png en --onboarding       the first-run card, as when the Finder extension is off
#   ./script/preview_setup.sh out.png en --first-run        the very first run: no config file yet, the choice of terminal, editor and agents
#   ./script/preview_setup.sh out.png en --set-up           just after the first setup: what it did, and the Finder extension still to switch on
#   ./script/preview_setup.sh out.png en --failed-set-up    the first run after a Set Up that did not come out: the chooser, and what went wrong above it
#   ./script/preview_setup.sh out.png en --first-run --shell-silent  the first run when the login shell said nothing about the agents
#   ./script/preview_setup.sh out.png en --location         the app runs from a disk image: the card that says to move it, with Set Up off
#   ./script/preview_setup.sh out.png en --picks-not-applied  after a setup that kept a config that was there: the choices it could not apply, with the edits, and a warning
#   ./script/preview_setup.sh out.png en --demo             a healthy setup with canned checks, folders, worktrees and menu (screenshots)
#   ./script/preview_setup.sh out.png en --demo --tab folders
#   ./script/preview_setup.sh out.png en --empty-folders --tab folders  no saved folders, with its add action
#   ./script/preview_setup.sh out.png en --tab worktrees --worktrees-state failed  failed, empty, loading, none or long
#   ./script/preview_setup.sh out.png en --config-error --tab menu  a broken config and its recovery action
#   ./script/preview_setup.sh out.png en --empty-menu --tab menu    a valid config with no menu entries
#   ./script/preview_setup.sh out.png de --feedback --tab ai        a localized copy confirmation
#   ./script/preview_setup.sh out.png ar --failure-notice --tab worktrees  a localized action failure
#   ./script/preview_setup.sh out.png en --long-notice --minimum --tab worktrees  a long process error above a usable page
#   ./script/preview_setup.sh out.png en --demo --submenus  the Finder menu with every submenu open
#   ./script/preview_setup.sh out.png de --gallery          every sentence the doctor can say, as rows of the checks
#   ./script/preview_setup.sh out.png ar --minimum --large-text  the smallest window, with large text
#   --details is --tab checks.
#
# It builds a throwaway package under .build/preview that links the app's own window files and the package libraries, then
# renders SetupView with ImageRenderer. ImageRenderer draws nothing inside a ScrollView, so the window is compiled with its
# PREVIEW containers (a plain stack instead of a scroll view): the picture shows the whole section.
#
# Without --demo and --gallery the checks, folders and the Finder menu are the real ones for this machine, so the picture shows
# this Mac: its paths, its apps, its last action. --demo, --gallery, --first-run and --set-up show canned data and nothing from the machine that renders:
# the script stops if a canned text names the home folder or the account of that Mac. The icons of the demo menu's apps are the
# ones of the Mac that renders (an app this Mac does not have gets the system's plain app icon).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?usage: preview_setup.sh out.png [language] [--tab section] [--dark] [--onboarding] [--first-run] [--shell-silent] [--failed-set-up] [--location] [--set-up] [--picks-not-applied] [--demo] [--submenus] [--gallery] [--minimum] [--large-text] [--config-error] [--empty-menu] [--empty-folders] [--worktrees-state state] [--feedback] [--failure-notice] [--long-notice]}"
# The script changes folder before it renders, so a relative output path is resolved against where it was started.
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
LANGUAGE="en"
TAB="overview"
FLAGS=()
args=("${@:2}")
for ((i = 0; i < ${#args[@]}; i++)); do
  argument="${args[$i]}"
  case "$argument" in
    --tab)
      i=$((i + 1))
      TAB="${args[$i]:?preview_setup.sh: --tab needs a section}"
      ;;
    --details) TAB="checks" ;;
    --worktrees-state)
      i=$((i + 1))
      state="${args[$i]:?preview_setup.sh: --worktrees-state needs a state}"
      case "$state" in failed | empty | loading | none | long) ;; *) echo "preview_setup.sh: unknown worktree state $state" >&2; exit 2 ;; esac
      FLAGS+=(--worktrees-state "$state")
      ;;
    --dark | --onboarding | --first-run | --shell-silent | --failed-set-up | --location | --set-up | --picks-not-applied | --demo | --submenus | --gallery | --minimum | --large-text | --config-error | --empty-menu | --empty-folders | --feedback | --failure-notice | --long-notice) FLAGS+=("$argument") ;;
    --*) echo "preview_setup.sh: unknown option $argument" >&2; exit 2 ;;
    *) LANGUAGE="$argument" ;;
  esac
done
case "$TAB" in
  overview | menu | checks | ai | worktrees | folders) ;;
  *) echo "preview_setup.sh: no section \"$TAB\" (overview, menu, checks, ai, worktrees, folders)" >&2; exit 2 ;;
esac
FLAGS+=(--tab "$TAB")
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
# The window's own files, the same ones the app compiles.
for file in SetupView.swift SetupModel.swift SetupPages.swift SetupFirstRun.swift SetupChecks.swift SetupFolders.swift SetupWorktrees.swift SetupFeedback.swift SetupNavigation.swift; do
  ln -sf "$ROOT/Apps/RightHere/$file" "$PREVIEW/Sources/preview/$file"
done
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

/// The arguments of this run: `--tab` takes the name of a section after it.
let arguments = CommandLine.arguments
func flag(_ name: String) -> Bool { arguments.contains(name) }
func value(of name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

/// Where Right Here.app is installed; a fixed place, not one of this Mac's.
let appContents = "/Applications/Right Here.app/Contents"
/// The home folder and the repository of the demo: fixed, and not this Mac's.
let demoHome = "/Users/tester"
let demoRepository = URL(fileURLWithPath: value(of: "--worktrees-state") == "long"
    ? "\(demoHome)/Projects/Shared resources/Research and evaluation for upcoming agent experiments"
    : "\(demoHome)/Projects/app")

/// What a check that was a minute ago reads as, in the language of the window and from a fixed pair of dates.
func ago(_ seconds: Double) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    formatter.locale = Locale(identifier: Locale.preferredLanguages.first ?? "en")
    let now = Date(timeIntervalSinceReferenceDate: 0)
    return formatter.localizedString(for: now.addingTimeInterval(-seconds), relativeTo: now)
}

/// Stops, loudly, if a canned text names something of the Mac that renders it: its home folder or its account.
func requireNothingOfThisMac(_ texts: [String]) {
    let text = texts.joined(separator: "\n")
    for own in [NSHomeDirectory(), NSUserName()] where own.count >= 4 && text.contains(own) {
        FileHandle.standardError.write(Data("the canned text says \"\(own)\", which belongs to this Mac\n".utf8))
        exit(1)
    }
}

func menuTitles(_ nodes: [MenuNode]) -> [String] {
    nodes.flatMap { [$0.title] + menuTitles($0.children) }
}

/// The app's icons of the demo: the apps this demo says are installed, read from the Mac that renders (the apps' own icons).
func demoFacts() -> FakeSystemFacts {
    let live = LiveSystemFacts()
    let installed = ["com.mitchellh.ghostty", "com.apple.Terminal", "com.microsoft.VSCode", "dev.zed.Zed", "com.apple.dt.Xcode", "com.apple.TextEdit"]
    return FakeSystemFacts(
        homeDirectory: URL(fileURLWithPath: demoHome),
        directories: [demoHome],
        applications: Dictionary(uniqueKeysWithValues: installed.map { ($0, live.applicationURL(bundleID: $0) ?? URL(fileURLWithPath: ProcessInfo.processInfo.environment["PREVIEW_GENERIC_APP"] ?? "/")) })
    )
}

/// The Finder menu of the demo Mac: the default layout, for the terminal, editor and agents of the demo's checks.
func demoMenu(_ facts: FakeSystemFacts) -> [MenuNode] {
    let config = Config(terminal: "ghostty", editor: "vscode", enabledAgents: ["claude", "codex"])
    let menu = MenuPreview.folderMenu(ConfigLoadResult(config: config, diagnostics: []), facts: facts, folder: facts.homeDirectory, localizer: .system)
    requireNothingOfThisMac(menuTitles(menu))
    return menu
}

/// Every submenu of a menu, for --submenus.
func allSubmenus(_ nodes: [MenuNode]) -> Set<String> {
    MenuPreview.submenuIDs(nodes)
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

/// A healthy setup, the same on every Mac: the checks the website's screenshots show.
func demoChecks() -> [DoctorCheck] {
    let checks = [
        DoctorCheck(.config, status: .ok, detail: .doctorVerbatim("~/.config/right-here/config.toml")),
        DoctorCheck(.terminalDefault, status: .ok, detail: .menuOpenIn("Ghostty")),
        DoctorCheck(.editorDefault, status: .ok, detail: .menuOpenIn("Visual Studio Code")),
        DoctorCheck(.agent("claude"), title: "Claude Code", status: .ok, detail: .doctorAgentOk("claude", "Claude Code Here")),
        DoctorCheck(.agent("codex"), title: "Codex", status: .ok, detail: .doctorAgentOk("codex", "Codex Here")),
        DoctorCheck(.claudeLink, status: .ok, detail: .doctorClaudeLinkOk),
        DoctorCheck(.finderRunner, status: .ok, detail: .doctorRunnerOk("\(appContents)/Helpers/rh")),
        DoctorCheck(.services, status: .ok, detail: .doctorServicesOk("7")),
        DoctorCheck(.cliLink, status: .ok, detail: .doctorVerbatim("~/.local/bin/rh")),
        DoctorCheck(.finderExtension, status: .ok, detail: .doctorExtensionEnabled("\(appContents)/PlugIns/FinderExtension.appex")),
        DoctorCheck(.finderActivity, status: .ok, detail: .doctorActivityRecent("agent.claude", "container", ago(300)))
    ]
    requireNothingOfThisMac(checks.flatMap { $0.englishLines() })
    return checks
}

/// What a Mac with nothing set up yet says: no config, nothing connected to Finder.
func firstRunChecks() -> [DoctorCheck] {
    let checks = [
        DoctorCheck(.config, status: .warn, detail: .doctorConfigMissing("~/.config/right-here/config.toml"), fix: .doctorFixRunSetup),
        DoctorCheck(.terminalDefault, status: .ok, detail: .menuOpenIn("Ghostty")),
        DoctorCheck(.editorDefault, status: .ok, detail: .menuOpenIn("Visual Studio Code")),
        DoctorCheck(.agents, status: .warn, detail: .doctorAgentsNone, fix: .doctorFixAgentsAdd(#"agents = ["claude"]"#)),
        DoctorCheck(.finderRunner, status: .fail, detail: .doctorRunnerMissing, fix: .doctorFixRunSetup),
        DoctorCheck(.services, status: .warn, detail: .doctorServicesNone, fix: .doctorFixRunSetup),
        DoctorCheck(.cliLink, status: .warn, detail: .doctorCliMissing("~/.local/bin/rh"), fix: .doctorFixRunSetup),
        DoctorCheck(.finderExtension, status: .fail, detail: .doctorExtensionNotRegistered, fix: .doctorFixExtensionInstall),
        DoctorCheck(.finderActivity, status: .ok, detail: .doctorActivityNone)
    ]
    requireNothingOfThisMac(checks.flatMap { $0.englishLines() })
    return checks
}

/// What a first run offers: the terminals and editors of the demo Mac, and every agent Right Here knows, two of them found.
func demoOffer() -> SetupOffer {
    // A login shell that said nothing (--shell-silent) found no agent, and the window says it could not tell.
    let silent = flag("--shell-silent")
    let found: Set<String> = silent ? [] : ["claude", "codex"]
    let agents = KnownAgents.all.map { SetupOffer.Option(id: $0.id, name: $0.name, available: found.contains($0.id)) }
    return SetupOffer(
        terminals: [.init(id: "ghostty", name: "Ghostty", available: true), .init(id: "terminal", name: "Terminal", available: true)],
        editors: [.init(id: "vscode", name: "Visual Studio Code", available: true), .init(id: "zed", name: "Zed", available: true),
                  .init(id: "xcode", name: "Xcode", available: true), .init(id: "textedit", name: "TextEdit", available: true)],
        agents: agents.filter(\.available) + agents.filter { !$0.available },
        detected: DetectedEnvironment(terminal: "ghostty", editor: "vscode", agents: silent ? [] : ["claude", "codex"]),
        loginShellAnswered: !silent)
}

/// What the first setup did on the demo Mac.
func demoSetupReport() -> SetupReport {
    SetupReport(steps: [
        SetupStep(.config, .created, detail: .doctorVerbatim("~/.config/right-here/config.toml")),
        SetupStep(.runnerScript, .created, detail: .doctorVerbatim("~/Library/Application Scripts/com.boyugou.righthere.FinderExtension/rh-run")),
        SetupStep(.cliLink, .created, detail: .doctorVerbatim("~/.local/bin/rh")),
        SetupStep(.services, .created, detail: .doctorServicesOk("7")),
        SetupStep(.finderExtension, .created, detail: .doctorVerbatim("\(appContents)/PlugIns/FinderExtension.appex"))
    ])
}

/// A first setup in which the config step failed (a file in the way) and the others did not: what the chooser stays above.
func demoFailedSetupReport() -> SetupReport {
    SetupReport(steps: [
        SetupStep(.config, .failed, detail: .doctorVerbatim("~/.config/right-here/config.toml cannot be used (line 1: TOML syntax error)")),
        SetupStep(.runnerScript, .created, detail: .doctorVerbatim("~/Library/Application Scripts/com.boyugou.righthere.FinderExtension/rh-run")),
        SetupStep(.cliLink, .created, detail: .doctorVerbatim("~/.local/bin/rh")),
        SetupStep(.services, .skipped, detail: .doctorVerbatim("they are made from the config, which cannot be used (see the config file above)")),
        SetupStep(.finderExtension, .created, detail: .doctorVerbatim("\(appContents)/PlugIns/FinderExtension.appex"))
    ])
}

/// A setup that found a config that was there: it was kept, the choices could not be applied, and what would apply them is listed.
func demoKeptConfigReport() -> SetupReport {
    let kept = "# My own notes.\nversion = 1\n\n[general]\nterminal = \"ghostty\"\neditor = \"vscode\"\nagents = [\"claude\"]\n"
    return SetupReport(
        steps: [
            SetupStep(.config, .unchanged, detail: .doctorVerbatim("~/.config/right-here/config.toml; it is yours, so setup never rewrites it")),
            SetupStep(.runnerScript, .unchanged, detail: .doctorVerbatim("~/Library/Application Scripts/com.boyugou.righthere.FinderExtension/rh-run")),
            SetupStep(.cliLink, .unchanged, detail: .doctorVerbatim("~/.local/bin/rh")),
            SetupStep(.services, .unchanged, detail: .doctorServicesOk("7")),
            SetupStep(.finderExtension, .unchanged, detail: .doctorVerbatim("\(appContents)/PlugIns/FinderExtension.appex"))
        ],
        configEdits: ConfigEdits.needed(for: SetupChoices(agents: ["claude", "codex"]), config: ConfigParser.parse(kept).config, base: kept, local: nil),
        warnings: [
            "config.toml already exists, so Right Here left it alone and did not apply your choices. The edits that would make it say so are listed above (and in configEdits with --json)."
        ])
}

/// The folders of the demo: pinned and recent, and the repository they are in.
let demoPins = ["\(demoHome)/Projects/app", "\(demoHome)/Projects/notes", "\(demoHome)/مستندات/مشروع"]
let demoRecents = ["\(demoHome)/Projects/web", "\(demoHome)/Downloads",
                   "\(demoHome)/Projects/Shared resources/Design and research/Research notes and evaluation references for upcoming experiments"]

/// `git worktree list --porcelain -z` of the demo repository: its main working copy, and two worktrees Right Here made for agents (every line ends with a NUL).
let demoPorcelain = """
worktree \(demoRepository.path)
HEAD 1f2e3d4c5b6a
branch refs/heads/main

worktree \(demoRepository.path)/.right-here/worktrees/rh-1760000000
HEAD 9a8b7c6d5e4f
branch refs/heads/rh/1760000000

worktree \(demoRepository.path)/.right-here/worktrees/fix-login
HEAD 5e4d3c2b1a09
branch refs/heads/fix/login

""".replacingOccurrences(of: "\n", with: "\0")

/// The worktrees of the demo, read through the same code the window uses, with git's answer given.
func demoWorktrees() async -> WorktreeListing {
    let runner = FakeProcessRunner(results: [ProcessResult(status: 0, standardOutput: demoPorcelain)])
    let listing = await WorktreeBrowser(runner: runner).list(in: demoRepository)
    if case .loaded(let rows) = listing {
        requireNothingOfThisMac(rows.map { $0.entry.path })
    }
    return listing
}

/// Everything the window shows in the demo: a healthy setup, the Finder menu, the folders and the repository.
func demoSnapshot(_ facts: FakeSystemFacts) -> SetupSnapshot {
    let folders = FolderSnapshot(pins: demoPins, recents: demoRecents,
                                 repositories: [demoRepository, URL(fileURLWithPath: "\(demoHome)/Projects/web")])
    requireNothingOfThisMac(demoPins + demoRecents + [demoRepository.path])
    return SetupSnapshot(
        checks: demoChecks(), menu: demoMenu(facts), folders: folders,
        configFile: URL(fileURLWithPath: "\(demoHome)/.config/right-here/config.toml"), configProblems: [], mcpCommand: "rh",
        home: URL(fileURLWithPath: demoHome))
}

/// One row for each way the doctor can answer, with long values, so the list of checks can be checked for text that does not fit.
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
        DoctorCheck(.config, status: .warn, detail: .doctorConfigMissing(config), notes: [.doctorConfigOverlay("~/.config/right-here/config.local.toml"), .doctorConfigSymlink("config.toml")], fix: .doctorFixRunSetup),
        DoctorCheck(.terminalDefault, status: .fail, detail: .doctorTerminalNone, fix: .doctorFixTerminal),
        DoctorCheck(.editorDefault, status: .ok, detail: .menuOpenIn("Visual Studio Code")),
        DoctorCheck(.agents, status: .warn, detail: .doctorAgentsNone, fix: .doctorFixAgentsAdd(#"agents = ["claude"]"#)),
        DoctorCheck(.finderMenu, status: .warn, detail: .doctorMenuEmpty, notes: [.doctorVerbatim("Agents: none is enabled; general.agents lists none."), .doctorVerbatim("Copy Path: copy_path.styles lists no style.")], fix: .doctorFixMenuEmpty),
        DoctorCheck(.claudeLink, status: .warn, detail: .doctorClaudeLinkMissing(#"launcher = "link""#), fix: .doctorFixClaudeLink),
        DoctorCheck(.finderRunner, status: .warn, detail: .doctorRunnerStale(target), fix: .doctorFixRunSetup),
        DoctorCheck(.services, status: .warn, detail: .doctorServicesDiffer("12", "3", "1"), fix: .doctorFixRunSetup),
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
        (.warn, .doctorAgentUnknown("claude"), nil),
        (.warn, .doctorVerbatim("Ghostty cannot run commands yet."), .doctorFixAgentLauncher(#"launcher = "link""#, #""desktop""#)),
        (.warn, .doctorAppFallback("iTerm", "Ghostty"), .doctorFixTerminalFallback),
        (.warn, .doctorAppFallback("Zed", "Visual Studio Code"), .doctorFixEditorFallback),
        (.ok, .doctorAgentOk("claude", "Claude Code in Last-Used Terminal"), nil),
        (.ok, .doctorClaudeLinkOk, nil),
        (.ok, .doctorRunnerOk(target), nil),
        (.fail, .doctorRunnerTargetMissing(target), .doctorFixRunSetup),
        (.fail, .doctorRunnerMissing, .doctorFixRunSetup),
        (.warn, .doctorServicesNone, .doctorFixRunSetup),
        (.ok, .doctorServicesOk("12"), nil),
        (.warn, .doctorCliMissing("~/.local/bin/rh"), .doctorFixRunSetup),
        (.warn, .doctorCliPathUnknown("~/.local/bin/rh"), nil),
        (.warn, .doctorExtensionMultiple("2", "\(target); ~/Library/Developer/Xcode/DerivedData/RightHere/Build/Products/Release/Right Here.app/Contents/PlugIns/FinderExtension.appex"), .doctorFixExtensionClean),
        (.fail, .doctorExtensionNotRegistered, .doctorFixExtensionInstall),
        (.needsUser, .doctorExtensionDisabled, .doctorFixExtensionEnable),
        (.ok, .doctorActivityNone, nil),
        (.ok, .doctorAgentBypass("claude", "Claude Code in Last-Used Terminal", "--dangerously-skip-permissions"), nil),
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
    let missing = LocalizationKey.allCases.filter { $0.rawValue.hasPrefix("doctor.") && !said.contains($0) }
    for key in missing {
        FileHandle.standardError.write(Data("the gallery has no row for \(key.rawValue)\n".utf8))
    }
    guard missing.isEmpty else { exit(1) }
    requireNothingOfThisMac(rows.flatMap { $0.englishLines() })
    return rows
}

/// The window as the person sees it at the moment of the picture: the section the flags ask for, with the data they ask for.
@MainActor
func render(to path: String) async {
    let model = SetupModel()
    registerMenuGlyphs()
    let tab = SetupTab(rawValue: value(of: "--tab") ?? "overview") ?? .overview
    if flag("--gallery") {
        model.simulate(SetupSnapshot(checks: gallery(), configFile: URL(fileURLWithPath: "\(demoHome)/.config/right-here/config.toml"),
                                     home: URL(fileURLWithPath: demoHome)), tab: .checks)
    } else if flag("--first-run") || flag("--failed-set-up") || flag("--location") {
        model.simulate(SetupSnapshot(checks: firstRunChecks(), configFile: URL(fileURLWithPath: "\(demoHome)/.config/right-here/config.toml"),
                                     configExists: false, offer: demoOffer(), home: URL(fileURLWithPath: demoHome)), tab: tab)
    } else if flag("--demo") || flag("--set-up") || flag("--picks-not-applied") || flag("--config-error") || flag("--empty-menu") || flag("--empty-folders") || flag("--feedback") || flag("--failure-notice") || flag("--long-notice") || value(of: "--worktrees-state") != nil {
        let facts = demoFacts()
        var snapshot = demoSnapshot(facts)
        if flag("--config-error") {
            snapshot.configProblems = ConfigParser.parse("[general\n").diagnostics
            snapshot.checks = snapshot.checks.replacing(DoctorCheck(.config, status: .fail,
                detail: .doctorVerbatim("config.toml:1: expected ] to close the table"), fix: .doctorFixConfigErrors))
        }
        if flag("--config-error") || flag("--empty-menu") { snapshot.menu = [] }
        if flag("--empty-folders") { snapshot.folders = FolderSnapshot() }
        var worktrees = await demoWorktrees()
        var repository: URL? = demoRepository
        switch value(of: "--worktrees-state") {
        case "failed": worktrees = .failed("git worktree list failed: The repository is temporarily unavailable.")
        case "empty": worktrees = .loaded([])
        case "loading": worktrees = .loading
        case "none":
            worktrees = .idle
            repository = nil
            snapshot.folders.repositories = []
        default: break
        }
        model.simulate(snapshot, tab: tab, icons: IconProvider(facts: facts), worktrees: worktrees, repository: repository)
    } else {
        await model.refresh()
        model.selectedTab = tab
        if tab == .worktrees { await model.refreshWorktrees() }
    }
    if flag("--onboarding") || flag("--set-up") {
        model.simulate(check: DoctorCheck(.finderExtension, status: .needsUser, detail: .doctorExtensionDisabled, fix: .doctorFixExtensionEnable))
    }
    if flag("--set-up") { model.simulate(setupReport: demoSetupReport()) }
    if flag("--failed-set-up") { model.simulate(setupReport: demoFailedSetupReport()) }
    if flag("--location") { model.simulateLocationProblem() }
    if flag("--picks-not-applied") { model.simulate(setupReport: demoKeptConfigReport()) }
    if flag("--feedback") { model.simulate(notice: tab == .folders ? .folderPinned("~/Projects/app") : .mcpConfigurationCopied) }
    if flag("--failure-notice") {
        model.simulate(notice: tab == .folders ? .folderUnavailable("~/Projects/notes") : .notARepository("~/Projects/notes"))
    }
    if flag("--long-notice") {
        let text = (1...12).map { "Diagnostic \($0): The operation could not finish. The repository is temporarily unavailable. This is a canned long error for checking that the rest of the window stays usable." }.joined(separator: "\n\n")
        model.simulate(notice: .failed(text))
    }
    if flag("--submenus") { model.simulate(openSubmenus: allSubmenus(model.snapshot?.menu ?? [])) }
    // A real window mirrors itself for a right-to-left system language; the renderer needs to be told.
    let language = Locale.preferredLanguages.first ?? "en"
    let rightToLeft = Locale.Language(identifier: language).characterDirection == .rightToLeft
    // The width of the window: its default, or its smallest. The text wraps at that width, as it does in the window; without a width
    // the picture would be as wide as the longest line.
    let width: CGFloat = flag("--minimum") ? 800 : 860
    let window = SetupView(model: model, expandCheckDetails: flag("--gallery"), previewViewport: flag("--minimum"))
        .frame(width: width, height: flag("--minimum") ? 560 : nil, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, flag("--dark") ? .dark : .light)
        .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
    let sized: AnyView = flag("--minimum") ? AnyView(window.clipped()) : AnyView(window)
    let scaled: AnyView = flag("--large-text") ? AnyView(sized.environment(\.dynamicTypeSize, .accessibility2)) : sized
    let renderer = ImageRenderer(content: scaled)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        print("render failed"); exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(Int(image.size.width)) x \(Int(image.size.height)) pt)")
}

MainActor.assumeIsolated {
    // The header shows the app's icon, which this executable does not have: the checked-in source of the real one stands in.
    guard let icon = NSImage(contentsOfFile: "icon-1024.png") else {
        FileHandle.standardError.write(Data("no icon-1024.png to use as the app's icon\n".utf8))
        exit(1)
    }
    NSApplication.shared.applicationIconImage = icon
    Task { @MainActor in
        await render(to: arguments[1])
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
