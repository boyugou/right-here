#!/usr/bin/env bash
#
# Render the setup window to a PNG without a screen, for looking at layout and translations.
#
#   ./script/preview_setup.sh out.png                       English, light, the first section (Overview), the state of this Mac
#   ./script/preview_setup.sh out.png de                    German
#   ./script/preview_setup.sh out.png en --dark             dark mode
#   ./script/preview_setup.sh out.png en --tab worktrees    one section: overview, menu, agents, config, checks, ai, worktrees or folders
#   ./script/preview_setup.sh out.png en --onboarding       the first-run card, as when the Finder extension is off
#   ./script/preview_setup.sh out.png en --first-run        the very first run: no config file yet, the choice of terminal, editor and agents
#   ./script/preview_setup.sh out.png en --set-up           just after the first setup: what it did, and the Finder extension still to switch on
#   ./script/preview_setup.sh out.png en --demo --older-copy  the strip an old copy shows when a newer one is installed
#   ./script/preview_setup.sh out.png en --demo --repairing  the header while Install or Repair runs (--repaired: when it has ended, with what it changed)
#   ./script/preview_setup.sh out.png en --failed-set-up    the first run after a Set Up that did not come out: the chooser, and what went wrong above it
#   ./script/preview_setup.sh out.png en --first-run --shell-silent  the first run when the login shell said nothing about the agents
#   ./script/preview_setup.sh out.png en --location         the app runs from a disk image: the card that says to move it, with Set Up off
#   ./script/preview_setup.sh out.png en --picks-not-applied  after a setup that kept a config that was there: the choices it could not apply, with the edits, and a warning
#   ./script/preview_setup.sh out.png en --demo             a healthy setup with canned checks, folders, worktrees and menu (screenshots)
#   ./script/preview_setup.sh out.png en --demo --tab folders
#   ./script/preview_setup.sh out.png en --demo --submenus  the Finder menu with every submenu open
#   ./script/preview_setup.sh out.png en --demo --editing   the Finder menu page while it is edited: rows to drag, and the note of a change just made
#   ./script/preview_setup.sh out.png en --demo --tab config  the Config page: the text, a change an assistant proposed, the recent changes
#   ./script/preview_setup.sh out.png en --demo --proposals   the Overview with the line that says a change an assistant proposed is waiting
#   ./script/preview_setup.sh out.png en --demo --tab agents  the Agents page: the list in the menu, the others, the permission switch (--switch-on: switched on; --edited: the note of a change)
#   ./script/preview_setup.sh out.png en --demo --tab agents --agent claude  the page of one agent's own options (claude, codex or lazygit in the demo)
#   ./script/preview_setup.sh out.png en --demo --tab agents --preset find-bugs  the page of one prompt preset (explain: built in; review: customized; find-bugs: the person's own)
#   ./script/preview_setup.sh out.png en --demo --tab agents --variant claude/opus  the page of one start option of an agent (the demo's own: opus)
#   ./script/preview_setup.sh out.png en --demo --tab menu --template notes  the page of one New File template (the demo's own templates: notes, script)
#   ./script/preview_setup.sh out.png en --demo --app pulsar  the page of one app the config adds (the demo's own: tower, pulsar, tabby)
#   --long-titles gives the demo's presets, start option and templates titles that do not fit on one line, to look at how a line wraps.
#   --empty gives the demo no pinned or recent folders, no repository and no recent changes of the config, to look at the empty lists.
#   --wide draws a window 1400 points wide, where the header and the page stop growing and stand in the middle.
#   ./script/preview_setup.sh out.png de --gallery          every sentence the doctor can say, as rows of the checks
#   ./script/preview_setup.sh out.png ar --minimum --large-text  the smallest window, with large text
#   ./script/preview_setup.sh out.png ar --titlebar-ltr      a window in Arabic on a Mac whose language runs left to right (--titlebar-rtl: the reverse)
#   ./script/preview_setup.sh out.png en --demo --tab menu --default-window  the window at its default size, as a person sees it before scrolling (the website's screenshots)
#   --details is --tab checks.
#   --real-controls draws the controls that AppKit draws (switches, text fields, the segmented control, the config's text) instead of their
#     stand-ins, in a window that is never put on screen (`cacheDisplay`): what the app shows where the other pictures show a stand-in. It is for
#     looking at the app, not for the website: such a window draws its switches and its default button as a window in the background does.
#
# It builds a throwaway package under .build/preview that links the app's own window files and the package libraries, then
# renders SetupView with ImageRenderer. ImageRenderer draws nothing inside a ScrollView, so the window is compiled with its
# PREVIEW containers (a plain stack instead of a scroll view): the picture shows the whole section.
#
# Without --demo and --gallery the checks, folders and the Finder menu are the real ones for this machine, so the picture shows
# this Mac: its paths, its apps, its last action. --demo, --gallery, --first-run and --set-up show canned data and nothing from the machine that renders:
# the script stops if a canned text names the home folder or the account of that Mac. In those pictures an app's or a document's
# icon is a plain tile the preview draws (standInIcon), not its maker's artwork: they are the website's pictures.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?usage: preview_setup.sh out.png [language] [--tab section] [--dark] [--onboarding] [--first-run] [--shell-silent] [--failed-set-up] [--location] [--set-up] [--picks-not-applied] [--demo] [--submenus] [--gallery] [--minimum] [--large-text]}"
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
    --agent)
      i=$((i + 1))
      FLAGS+=(--agent "${args[$i]:?preview_setup.sh: --agent needs an agent id}")
      ;;
    --preset)
      i=$((i + 1))
      FLAGS+=(--preset "${args[$i]:?preview_setup.sh: --preset needs a preset id}")
      ;;
    --template)
      i=$((i + 1))
      FLAGS+=(--template "${args[$i]:?preview_setup.sh: --template needs a template id}")
      ;;
    --variant)
      i=$((i + 1))
      FLAGS+=(--variant "${args[$i]:?preview_setup.sh: --variant needs agent/id}")
      ;;
    --app)
      i=$((i + 1))
      FLAGS+=(--app "${args[$i]:?preview_setup.sh: --app needs an app id}")
      ;;
    --details) TAB="checks" ;;
    --older-copy | --repairing | --repaired | --dark | --onboarding | --first-run | --shell-silent | --failed-set-up | --location | --set-up | --picks-not-applied | --demo | --long-titles | --empty | --wide | --submenus | --editing | --proposals | --switch-on | --edited | --gallery | --minimum | --default-window | --large-text | --titlebar-ltr | --titlebar-rtl | --real-controls) FLAGS+=("$argument") ;;
    --*) echo "preview_setup.sh: unknown option $argument" >&2; exit 2 ;;
    *) LANGUAGE="$argument" ;;
  esac
done
case "$TAB" in
  overview | menu | agents | config | checks | ai | worktrees | folders) ;;
  *) echo "preview_setup.sh: no section \"$TAB\" (overview, menu, agents, config, checks, ai, worktrees, folders)" >&2; exit 2 ;;
esac
FLAGS+=(--tab "$TAB")
# The window's files draw a stand-in of SwiftUI's own views for a control that AppKit draws (STANDINS), which ImageRenderer would show as a
# "not allowed" sign; --real-controls builds them without, in a folder of its own so that neither build undoes the other.
PREVIEW="$ROOT/.build/preview"
DEFINES='.define("PREVIEW"), .define("STANDINS")'
case " ${FLAGS[*]} " in
  *" --real-controls "*) PREVIEW="$ROOT/.build/preview-real"; DEFINES='.define("PREVIEW")' ;;
esac
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
            swiftSettings: [.swiftLanguageMode(.v5), $DEFINES]
        )
    ]
)
PACKAGE
# The window's own files, the same ones the app compiles.
for file in SetupView.swift SetupModel.swift SetupModel+Header.swift SetupModel+Agents.swift SetupModel+Presets.swift SetupModel+NewFile.swift SetupModel+Variants.swift SetupModel+Lists.swift SetupModel+Apps.swift SetupPages.swift SetupFirstRun.swift MenuEditorView.swift ConfigPageView.swift ReorderableList.swift EditableText.swift FieldDraft.swift PlainTextView.swift AgentsPageView.swift AgentOptionsView.swift ArgumentListView.swift VariantView.swift PresetsView.swift NewFileView.swift ChoiceListView.swift AppsView.swift DefaultAppsView.swift; do
  ln -sf "$ROOT/Apps/RightHere/$file" "$PREVIEW/Sources/preview/$file"
done
# The Finder menu's own glyphs, which main.swift registers by name (the app finds them in its asset catalog), and the
# icon the window's header shows (this executable has none of its own).
ln -sfn "$ROOT/Apps/FinderExtension/Assets.xcassets" "$PREVIEW/Assets.xcassets"
ln -sf "$ROOT/docs/images/icon.png" "$PREVIEW/icon.png"
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
let demoRepository = URL(fileURLWithPath: "\(demoHome)/Projects/app")

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
    let installed = ["com.mitchellh.ghostty", "com.apple.Terminal", "com.microsoft.VSCode", "dev.zed.Zed", "com.apple.dt.Xcode", "com.apple.TextEdit", "com.fournova.Tower3", "dev.pulsar-edit.pulsar", "org.tabby"]
    return FakeSystemFacts(
        homeDirectory: URL(fileURLWithPath: demoHome),
        directories: [demoHome],
        applications: Dictionary(uniqueKeysWithValues: installed.map { ($0, live.applicationURL(bundleID: $0) ?? URL(fileURLWithPath: ProcessInfo.processInfo.environment["PREVIEW_GENERIC_APP"] ?? "/")) })
    )
}

/// The Finder menu of the demo Mac: the default layout, for the terminal, editor and agents of the demo's checks. With --long-titles it is the
/// menu of the demo's config, whose start option has a title longer than the page, to look at a menu line that does not fit.
func demoMenu(_ facts: FakeSystemFacts) -> [MenuNode] {
    let config = flag("--long-titles") ? demoConfig(bypass: false) : Config(terminal: "ghostty", editor: "vscode", enabledAgents: ["claude", "codex"])
    let menu = MenuPreview.folderMenu(ConfigLoadResult(config: config, diagnostics: []), facts: facts, folder: facts.homeDirectory, localizer: .system)
    requireNothingOfThisMac(menuTitles(menu))
    return menu
}

/// The Finder menu of the demo Mac as rows to edit, for --editing.
func demoMenuEditor(_ facts: FakeSystemFacts) -> MenuEditorState {
    let config = Config(terminal: "ghostty", editor: "vscode", enabledAgents: ["claude", "codex"])
    let editor = MenuEditor.state(config: config, facts: facts, localizer: .system, folder: facts.homeDirectory, inFile: config.menuItems)
    requireNothingOfThisMac(editor.rows.flatMap { menuTitles($0.nodes) } + editor.choices.map(\.title))
    return editor
}

/// The terminal, the editor and the agents of the demo Mac: Claude Code, Codex and lazygit in the menu, Goose (which has no flag for the permission switch) and the others not.
func demoGeneral(_ facts: FakeSystemFacts, bypass: Bool) -> GeneralSettingsState {
    let state = GeneralSettings.state(config: demoConfig(bypass: bypass), facts: facts, listedAgents: ["claude", "codex", "lazygit"])
    requireNothingOfThisMac(state.agents.flatMap { [$0.name, $0.command] } + state.terminals.map(\.name) + state.editors.map(\.name))
    return state
}

/// The config of the demo Mac: Claude Code started with three arguments, and lazygit as an agent of the person's own.
func demoConfig(bypass: Bool) -> Config {
    let text = """
    [general]
    terminal = "ghostty"
    editor = "vscode"
    agents = ["claude", "codex", "lazygit"]
    bypass_permissions = \(bypass)

    [agent.claude]
    args = ["--add-dir", "../shared", "--verbose"]

    [[agent.claude.variant]]
    id = "opus"
    title = "\(flag("--long-titles") ? "Use Opus with a title that is much too long to fit on one line of its panel" : "Use Opus")"
    arguments = ["--model", "opus"]

    [agent.lazygit]
    name = "lazygit"
    command = "lazygit"

    [[app]]
    id = "tower"
    name = "Tower"
    bundle_id = "com.fournova.Tower3"

    [[app]]
    id = "pulsar"
    name = "Pulsar"
    bundle_id = "dev.pulsar-edit.pulsar"
    role = "editor"

    [[app]]
    id = "tabby"
    name = "Tabby"
    bundle_id = "org.tabby"
    role = "terminal"

    [[preset]]
    id = "review"
    title = "Strict review"
    prompt = "Review {files} with great care: name every bug, and say how you would fix it. Do not modify any files."

    [[preset]]
    id = "find-bugs"
    title = "\(flag("--long-titles") ? "Find bugs, name every one, and say in plain words how you would fix each of them" : "Find Bugs")"
    prompt = "Find bugs in {files} and say how you would fix each one."
    agent = "claude"
    max_files = 10
    """
    return ConfigParser.parse(text).config
}

/// The apps the demo Mac's config adds: a Git client, an editor and a terminal.
func demoApps(_ facts: FakeSystemFacts) -> AppsState {
    let state = AppOptions.state(config: demoConfig(bypass: false), entries: [
        "tower": EntryLocation(target: .shared, position: 1), "pulsar": EntryLocation(target: .shared, position: 2), "tabby": EntryLocation(target: .shared, position: 3)
    ], facts: facts)
    requireNothingOfThisMac(state.rows.flatMap { [$0.name] + $0.bundleIDs })
    return state
}

/// The presets of the demo Mac: one built-in, one customized, one of the person's own.
func demoPresets(_ bypass: Bool) -> PresetsState {
    let state = PresetOptions.state(config: demoConfig(bypass: bypass), entries: [
        "review": PresetRowState.Entry(target: .shared, position: 1), "find-bugs": PresetRowState.Entry(target: .shared, position: 2)
    ], localizer: .system)
    requireNothingOfThisMac(state.rows.flatMap { [$0.title, $0.prompt] })
    return state
}

/// The New File templates of the demo Mac: the built-in ones, or, for the page of a template (--template), two of the person's own.
func demoNewFile(_ facts: FakeSystemFacts) -> NewFileState {
    let text = """
    [general]
    editor = "vscode"

    [new_file]
    then = "open"

    [[new_file.template]]
    id = "notes"
    title = "\(flag("--long-titles") ? "Notes for a meeting, with the date and the names of everyone who came to it" : "Notes")"
    base_name = "notes"
    extension = "md"
    contents = "# Notes\\n\\n- \\n"
    open_with = "zed"

    [[new_file.template]]
    id = "script"
    title = "Shell Script"
    base_name = "run"
    extension = "sh"
    contents = "#!/bin/sh\\nset -eu\\n"
    """
    let custom = value(of: "--template") != nil
    let config = custom ? ConfigParser.parse(text).config : Config(terminal: "ghostty", editor: "vscode", enabledAgents: ["claude", "codex"])
    let entries = custom ? ["notes": EntryLocation(target: .shared, position: 1), "script": EntryLocation(target: .shared, position: 2)] : [:]
    let state = NewFileOptions.state(config: config, entries: entries, facts: facts, localizer: .system)
    requireNothingOfThisMac(state.rows.flatMap { [$0.title, $0.baseName, $0.contents] } + state.apps.map(\.name))
    return state
}

/// The forms of Copy Path of the demo Mac: the default ones.
func demoCopyPath() -> CopyPathState {
    let state = CopyPathOptions.state(config: Config(terminal: "ghostty", editor: "vscode", enabledAgents: ["claude", "codex"]), localizer: .system, listed: nil)
    requireNothingOfThisMac(state.offered.map(\.title) + state.others.map(\.title))
    return state
}

/// The Quick Actions of the demo Mac: the default ones.
func demoQuickActions(_ facts: FakeSystemFacts) -> QuickActionsState {
    let state = QuickActionsOptions.state(config: Config(terminal: "ghostty", editor: "vscode", enabledAgents: ["claude", "codex"]), facts: facts, localizer: .system, listed: nil)
    requireNothingOfThisMac(state.rows.map(\.title) + state.choices.map(\.title))
    return state
}

/// The options of each agent of the demo Mac.
func demoAgentOptions(_ facts: FakeSystemFacts, general: GeneralSettingsState, bypass: Bool) -> [AgentOptionsState] {
    let config = demoConfig(bypass: bypass)
    let options = general.agents.compactMap { agent in
        AgentOptions.state(id: agent.id, config: config, facts: facts, listedArgs: config.agents[agent.id]?.args,
                           variantEntries: agent.id == "claude" ? ["opus": EntryLocation(target: .shared, position: 1)] : [:], listedVariantArguments: agent.id == "claude" ? ["opus": ["--model", "opus"]] : [:])
    }
    requireNothingOfThisMac(options.flatMap { [$0.name, $0.command] + $0.args + $0.terminals.map(\.name) })
    return options
}

/// The Config page of the demo: a short config, one change an assistant proposed that waits, and the changes that can be taken back.
func demoConfigPage() -> ConfigPageState {
    let text = """
    # My Right Here config.
    version = 1

    [general]
    terminal = "ghostty"
    editor = "vscode"
    agents = ["claude", "codex"]

    [menu]
    items = ["open-terminal", "open-editor", "-", "agents", "copy-path"]

    """
    let summary = "set agent.claude.args = [\"--add-dir\", \"../shared\"]"
    let proposal = ConfigProposal(id: "a1b2c3d4", time: Date(timeIntervalSinceReferenceDate: 0), actor: .mcp, target: .shared, operations: [.set("agent.claude.args", .strings(["--add-dir", "../shared"]))],
                                  summary: summary, approvals: [ConfigTrust.Approval(key: "agent.*.args", reason: "it is part of the command that starts the agent")])
    let change = ConfigChange(target: .shared, file: "\(demoHome)/.config/right-here/config.toml", summary: summary, changed: true, written: false,
                              diff: ["@@ -10,0 +11,3 @@", "+", "+[agent.claude]", "+args = [\"--add-dir\", \"../shared\"]"], warnings: [])
    let day: TimeInterval = 86_400
    let history = [
        ConfigService.HistoryItem(time: Date(timeIntervalSinceReferenceDate: 3 * day), actor: .window, summary: "move item 4 of menu.items to 1"),
        ConfigService.HistoryItem(time: Date(timeIntervalSinceReferenceDate: 2 * day), actor: .mcp, summary: "add \"copy-path\" to menu.items"),
        ConfigService.HistoryItem(time: Date(timeIntervalSinceReferenceDate: 1 * day), actor: .cli, summary: "set general.terminal = \"ghostty\"")
    ]
    requireNothingOfThisMac([text, summary] + change.diff + history.map(\.summary))
    return ConfigPageState(target: .shared, text: ConfigService.ConfigText(text: text, digest: "demo", exists: true), problem: nil,
                           proposals: [ProposalPreview(proposal: proposal, change: change, problem: nil)], history: flag("--empty") ? [] : history, validation: .standalone)
}

/// Every submenu of a menu, for --submenus.
func allSubmenus(_ nodes: [MenuNode]) -> Set<String> {
    MenuPreview.submenuIDs(nodes)
}

/// The Finder menu's own glyphs. The app finds them in its asset catalog (Apps/FinderExtension/Assets.xcassets, which
/// project.yml gives both targets); this package has none, so the same PDFs are registered under the names the catalog
/// gives them, and the picture shows the glyphs of the real menu and not the system symbols that stand in elsewhere.
/// In a picture for the website, an app's or a document's icon is a plain tile of this project's own drawing: the canned data names real
/// apps (Ghostty, Visual Studio Code, Microsoft Word…), and their icons are their makers' artwork, which the website does not show.
@MainActor
func standInIcon(_ icon: Icon) -> NSImage? {
    let palette: [NSColor] = [.systemBlue, .systemIndigo, .systemTeal, .systemGreen, .systemOrange, .systemPink, .systemPurple, .systemBrown]
    func hue(_ text: String) -> NSColor { palette[text.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % palette.count] }
    switch icon.kind {
    case .app:
        // The last part of the bundle identifier that starts with a letter: com.mitchellh.ghostty is G, com.apple.dt.Xcode is X.
        let part = icon.value.split(separator: ".").reversed().first { $0.first?.isLetter == true } ?? Substring(icon.value)
        let letter = String(part.prefix(1)).uppercased()
        // At the size the window asks for (16 points, as IconProvider gives an app's icon): every measure is a part of the side.
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let side = rect.width
            let tile = NSBezierPath(roundedRect: rect.insetBy(dx: side * 0.06, dy: side * 0.06), xRadius: side * 0.22, yRadius: side * 0.22)
            NSGradient(starting: hue(icon.value).blended(withFraction: 0.25, of: .white) ?? hue(icon.value), ending: hue(icon.value))?.draw(in: tile, angle: -90)
            let text = NSAttributedString(string: letter, attributes: [.font: NSFont.systemFont(ofSize: side * 0.55, weight: .semibold), .foregroundColor: NSColor.white])
            let size = text.size()
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            return true
        }
    case .fileType:
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let side = rect.width
            let page = NSBezierPath(roundedRect: NSRect(x: side * 0.2, y: side * 0.06, width: side * 0.6, height: side * 0.86), xRadius: side * 0.08, yRadius: side * 0.08)
            NSColor.white.setFill()
            page.fill()
            NSColor(white: 0.6, alpha: 1).setStroke()
            page.lineWidth = max(0.5, side * 0.04)
            page.stroke()
            hue(icon.value).setFill()
            NSBezierPath(rect: NSRect(x: side * 0.3, y: side * 0.25, width: side * 0.4, height: side * 0.12)).fill()
            return true
        }
    default:
        return nil
    }
}

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
        terminals: [.init(id: "ghostty", name: "Ghostty", available: true, icon: .app("com.mitchellh.ghostty")),
                    .init(id: "terminal", name: "Terminal", available: true, icon: .app("com.apple.Terminal"))],
        // Only apps the Mac that renders has (docs/development/WEBSITE.md): a first run offers installed apps alone, each with its own icon.
        editors: [.init(id: "vscode", name: "Visual Studio Code", available: true, icon: .app("com.microsoft.VSCode")),
                  .init(id: "xcode", name: "Xcode", available: true, icon: .app("com.apple.dt.Xcode")),
                  .init(id: "textedit", name: "TextEdit", available: true, icon: .app("com.apple.TextEdit"))],
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
let demoRecents = ["\(demoHome)/Projects/web", "\(demoHome)/Downloads", "\(demoHome)/Projects/app/Sources"]

/// `git worktree list --porcelain -z` of the demo repository: its main working copy, and two worktrees Right Here made for agents (every line ends with a NUL).
let demoPorcelain = """
worktree \(demoHome)/Projects/app
HEAD 1f2e3d4c5b6a
branch refs/heads/main

worktree \(demoHome)/Projects/app/.right-here/worktrees/rh-1760000000
HEAD 9a8b7c6d5e4f
branch refs/heads/rh/1760000000

worktree \(demoHome)/Projects/app/.right-here/worktrees/fix-login
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
    let folders = flag("--empty") ? FolderSnapshot(pins: [], recents: [], repositories: []) : FolderSnapshot(pins: demoPins, recents: demoRecents, repositories: [demoRepository])
    requireNothingOfThisMac(demoPins + demoRecents + [demoRepository.path])
    let general = demoGeneral(facts, bypass: flag("--switch-on"))
    // Only the demo has apps the config adds: a Mac that was just set up has none.
    var apps = demoApps(facts)
    if !flag("--demo") { apps.rows = [] }
    return SetupSnapshot(
        checks: demoChecks(), menu: demoMenu(facts), menuEditor: demoMenuEditor(facts), general: general, agentOptions: demoAgentOptions(facts, general: general, bypass: flag("--switch-on")), presets: demoPresets(flag("--switch-on")), newFile: demoNewFile(facts), copyPath: demoCopyPath(), quickActions: demoQuickActions(facts), apps: apps, folders: folders,
        configFile: URL(fileURLWithPath: "\(demoHome)/.config/right-here/config.toml"), configProblems: [], mcpCommand: "rh",
        home: URL(fileURLWithPath: demoHome), agentCommands: demoAgentCommands(general))
}

/// What the demo's login shell says of the agents: the ones of the menu and Gemini CLI are installed, the rest are not.
func demoAgentCommands(_ general: GeneralSettingsState) -> LoginShellFacts {
    let locations = ["claude": "\(demoHome)/.local/bin/claude", "codex": "/opt/homebrew/bin/codex", "lazygit": "/opt/homebrew/bin/lazygit", "gemini": "/opt/homebrew/bin/gemini"]
    return LoginShellFacts(asked: Set(general.agents.map(\.executable)), found: Set(locations.keys), locations: locations, answered: true)
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
        DoctorCheck(.pending, status: .needsUser, detail: .doctorPendingWaiting("2"), fix: .doctorFixPending),
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
        DoctorCheck(.appCopies, status: .warn, detail: .doctorAppCopies("2", "0.3.7 (/Applications), 0.3.2 (~/Applications)"), fix: .doctorFixAppCopies("/Applications/Right Here.app")),
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
        (.ok, .doctorCliPathUnknown("~/.local/bin/rh"), nil),
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
    for key in LocalizationKey.allCases where key.rawValue.hasPrefix("doctor.") && !said.contains(key) {
        FileHandle.standardError.write(Data("the gallery has no row for \(key.rawValue)\n".utf8))
    }
    requireNothingOfThisMac(rows.flatMap { $0.englishLines() })
    return rows
}

/// The window as the person sees it at the moment of the picture: the section the flags ask for, with the data they ask for.
@MainActor
func render(to path: String) async {
    let model = SetupModel()
    registerMenuGlyphs()
    let tab = SetupTab(rawValue: value(of: "--tab") ?? "overview") ?? .overview
    // The canned pictures are the ones the website shows: no app's or document's own icon in them.
    if ["--demo", "--first-run", "--set-up", "--failed-set-up", "--location", "--picks-not-applied"].contains(where: flag) { SetupModel.drawIcon = standInIcon }
    if flag("--gallery") {
        model.simulate(SetupSnapshot(checks: gallery(), configFile: URL(fileURLWithPath: "\(demoHome)/.config/right-here/config.toml"),
                                     home: URL(fileURLWithPath: demoHome)), tab: .checks)
    } else if flag("--first-run") || flag("--failed-set-up") || flag("--location") {
        model.simulate(SetupSnapshot(checks: firstRunChecks(), configFile: URL(fileURLWithPath: "\(demoHome)/.config/right-here/config.toml"),
                                     configExists: false, offer: demoOffer(), home: URL(fileURLWithPath: demoHome)), tab: .overview, icons: IconProvider(facts: demoFacts()))
    } else if flag("--demo") || flag("--set-up") || flag("--picks-not-applied") {
        let facts = demoFacts()
        model.simulate(demoSnapshot(facts), tab: tab, icons: IconProvider(facts: facts), worktrees: flag("--empty") ? .idle : await demoWorktrees(),
                       repository: flag("--empty") ? nil : demoRepository)
    } else {
        await model.refresh()
        model.selectedTab = tab
        if tab == .worktrees { await model.refreshWorktrees() }
    }
    if flag("--onboarding") || flag("--set-up") { model.simulateExtensionOff() }
    if flag("--set-up") { model.simulate(setupReport: demoSetupReport()) }
    if flag("--failed-set-up") { model.simulate(setupReport: demoFailedSetupReport()) }
    if flag("--location") { model.simulateLocationProblem() }
    if flag("--picks-not-applied") { model.simulate(setupReport: demoKeptConfigReport()) }
    if flag("--older-copy") { model.simulate(running: AppCopy(path: "\(demoHome)/Applications/Right Here.app", version: "0.3.2"), newer: AppCopy(path: "/Applications/Right Here.app", version: AppIdentity.version)) }
    if flag("--repairing") { model.simulate(phase: .piece(.finderExtension)) }
    if flag("--repaired") { model.simulate(repaired: SetupReport(steps: [
        SetupStep(.config, .unchanged), SetupStep(.runnerScript, .updated), SetupStep(.cliLink, .unchanged), SetupStep(.services, .updated), SetupStep(.finderExtension, .unchanged)])) }
    if flag("--submenus") { model.simulate(openSubmenus: allSubmenus(model.snapshot?.menu ?? [])) }
    if flag("--demo") && tab == .config { model.simulate(configPage: demoConfigPage()) }
    if flag("--demo") && flag("--proposals") && tab != .config {
        model.simulate(configPage: demoConfigPage())
        model.selectedTab = tab
    }
    if flag("--editing") { model.simulateEditingMenu(edit: ConfigEdit(message: .appMenuEditedMoved(model.snapshot?.menu.first?.title ?? ""), key: "menu.items", tab: .menu, digest: nil)) }
    if let agent = value(of: "--agent") { model.openAgentOptions(agent) }
    if let preset = value(of: "--preset") { model.openPreset(preset) }
    if let template = value(of: "--template") { model.openTemplate(template) }
    if let app = value(of: "--app") { model.openApp(app) }
    if let variant = value(of: "--variant") {
        let parts = variant.split(separator: "/").map(String.init)
        if parts.count == 2 { model.openVariant(VariantRef(agent: parts[0], id: parts[1])) }
    }
    if flag("--edited") {
        let edit: ConfigEdit = tab == .agents && value(of: "--agent") != nil ? ConfigEdit(message: .appAgentEdited("Claude Code"), key: "agent.claude.args", tab: .agents, digest: nil)
            : tab == .agents ? ConfigEdit(message: .appMenuEditedMoved("Codex"), key: "general.agents", tab: .agents, digest: nil)
            : ConfigEdit(message: .appEditSaved, key: "general.terminal", tab: .overview, digest: nil)
        model.simulate(edit: edit)
    }
    // A real window mirrors itself for a right-to-left system language; the renderer needs to be told.
    let language = Locale.preferredLanguages.first ?? "en"
    let rightToLeft = Locale.Language(identifier: language).characterDirection == .rightToLeft
    // The width of the window: its default, or its smallest. The text wraps at that width, as it does in the window; without a width
    // the picture would be as wide as the longest line.
    let width: CGFloat = flag("--minimum") ? 800 : flag("--wide") ? 1400 : 860
    // The window has a height of its own, which clips what does not fit (the rest is scrolled to); without a height the picture is as tall as the whole section.
    let height: CGFloat? = flag("--minimum") || flag("--default-window") ? 560 : nil
    // The window's title bar runs the way the system's language does, unless a flag says the window's language runs the other way.
    let titlebarRightToLeft = flag("--titlebar-rtl") ? true : flag("--titlebar-ltr") ? false : rightToLeft
    // The part of the window under the header shows the page.
    let window = SetupView(model: model)
        .environment(\.previewPageHeight, height.map { $0 - SetupView.headerHeight })
        .environment(\.previewTitlebarRightToLeft, titlebarRightToLeft)
        .environment(\.previewWindowWidth, width)
        .frame(width: width, height: height, alignment: .topLeading)
        // The window's close, minimize and zoom buttons, which belong to the window and not to the view: where macOS puts them, at the top of
        // the side the title bar starts from, in its order.
        .overlay(alignment: titlebarRightToLeft == rightToLeft ? .topLeading : .topTrailing) {
            WindowButtons().padding(9).environment(\.layoutDirection, titlebarRightToLeft ? .rightToLeft : .leftToRight)
        }
        .environment(\.colorScheme, flag("--dark") ? .dark : .light)
        .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
    let sized: AnyView = height != nil ? AnyView(window.clipped()) : AnyView(window)
    let scaled: AnyView = flag("--large-text") ? AnyView(sized.environment(\.dynamicTypeSize, .accessibility2)) : sized
    if flag("--real-controls") {
        renderInAWindow(scaled, width: width, height: height, dark: flag("--dark"), to: path)
        return
    }
    let renderer = ImageRenderer(content: scaled)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        print("render failed"); exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(Int(image.size.width)) x \(Int(image.size.height)) pt)")
}

/// For --real-controls: the window's view in a window that is never put on screen (made with `defer`, never ordered in), drawn with
/// `cacheDisplay`, which draws the controls that AppKit draws. The page is the preview's plain stack, so the window is as tall as the page.
@MainActor
func renderInAWindow(_ view: AnyView, width: CGFloat, height: CGFloat?, dark: Bool, to path: String) {
    let host = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: width, height: height ?? 600), styleMask: [.borderless], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = host
    let tall = height ?? host.fittingSize.height
    window.setContentSize(NSSize(width: width, height: tall))
    host.frame = NSRect(x: 0, y: 0, width: width, height: tall)
    host.layoutSubtreeIfNeeded()
    // AppKit's controls and the apps' icons are drawn after a turn of the run loop.
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("render failed"); exit(1) }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { print("render failed"); exit(1) }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(Int(width)) x \(Int(tall)) pt, real controls)")
}

/// The close, minimize and zoom buttons of an active window: 14-point circles, 9 points apart.
struct WindowButtons: View {
    var body: some View {
        HStack(spacing: 9) {
            ForEach([Color(red: 1, green: 0.373, blue: 0.341), Color(red: 0.996, green: 0.737, blue: 0.180), Color(red: 0.157, green: 0.784, blue: 0.251)], id: \.self) { color in
                Circle()
                    .fill(color)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                    .frame(width: 14, height: 14)
            }
        }
    }
}

MainActor.assumeIsolated {
    // The header shows the app's icon, which this executable does not have: its picture in docs/images stands in.
    guard let icon = NSImage(contentsOfFile: "icon.png") else {
        FileHandle.standardError.write(Data("no icon.png to use as the app's icon\n".utf8))
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
