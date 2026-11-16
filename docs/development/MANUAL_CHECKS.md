# Manual checks

The automated suite, the mutation check and `rh doctor --probe-launch` cover everything that can be verified
without a screen or a person. These need a real Finder, real terminals or a native speaker.

## 1. A real Finder click on protected folders

Folders under Desktop, Documents and Downloads are privacy-protected: the sandboxed extension may be refused a
look at them, and `rh` then treats the path as unreadable rather than as a folder (see
`docs/DESIGN.md`, section 9).

1. `rh setup` and `rh doctor` (everything `[ok]`).
2. In Finder, right-click a folder inside Documents, then each of Desktop and Downloads. The Right Here menu
   should appear and "Open in <terminal>" should open a window in that folder.
3. Right-click a file there and choose a path-copy item; paste it somewhere and compare.
4. `rh doctor` again: "Last action started from Finder" shows the time.

If a protected folder does not work, run `rh doctor --json` and the log shown in `docs/TROUBLESHOOTING.md`, and
record the result in a decision record.

The runner script checks its arguments (DESIGN section 9, item 3): it passes on only the shapes the extension sends, which the tests run with
a stand-in `rh` under zsh, sh, bash and dash, but not through a real `NSUserUnixTask`. After step 2, `rh doctor` must show a new "Last action started
from Finder" and no runner refusal in the Console (the extension logs it as `failed`, with the runner's words, "right-here runner: refusing: ...");
`rh doctor --probe-launch` sends the launch probe through the same script.

## 2. Terminals that were never run

WezTerm, kitty, Alacritty and iTerm2 are built in, from each terminal's own documentation (ADR 0025); none of them has been run on a Mac that Right Here
was written on. For each one on your Mac: `rh doctor --probe-launch`, then by hand: the window opens in the folder and runs the command, a folder named
`it's a "test"` works, closing the agent leaves a usable shell, and (kitty and Alacritty, which `rh` starts as a new process each time) the app quits with its last
window. Warp and cmux are only handed a folder, and what they do with it is not documented either.

A terminal that has no adapter can be started by a config entry. This is the shape, with the arguments Alacritty's own adapter uses, so it replaces the
built-in one:

```sh
rh config validate
rh run agent.claude@<id> --dry-run     # look at the argument vector
rh run agent.claude@<id>               # then for real, in a throwaway folder
```

```toml
[[app]]
id = "alacritty"
name = "Alacritty"
bundle_id = "org.alacritty"
role = "terminal"
open_args = ["/usr/bin/open", "-n", "-b", "org.alacritty", "--args", "--working-directory", "{dir}"]
run_args = ["/usr/bin/open", "-n", "-b", "org.alacritty", "--args", "--working-directory", "{dir}", "-e", "{shell}", "-lic", "{command}; exec {shell} -l"]
```

`rh config validate` warns that the entry replaces the built-in one; that is intended. Check the entry the way the list above says, and report what had to change so the docs
can carry a verified one.

## 3. Translations

The thirty languages in `Localization/Localizable.xcstrings` were machine-translated. A native speaker should read
the menu titles and the alert texts of the setup window (`rh menu --language <tag>` prints the menu; the app's
window follows the system language). Right-to-left languages (ar, he, fa, ur) deserve a look in the real menu.

The window's list of checks writes every sentence of the doctor in the system language.
`./script/preview_setup.sh out.png <code> --gallery` renders each of them in a language to a tall picture; it found text
that did not fit and, in right-to-left languages, paths and commands that the sentence around them reordered (a value is
put in a Unicode isolate now, and a command that ends in a bracket carries a left-to-right mark). That is `ImageRenderer`,
not a real window. In the real one, in Arabic or Hebrew, with a state that has a path in it (a config that does not exist
yet is enough), look at the order of the path, and select a command in a fix line, paste it into a terminal and see that no
invisible character came with it. The relative time of the last action ("5 minutes ago") is formatted when the doctor
runs, in the locale of the process.

With a left-to-right system language, set only Right Here's app language to Arabic or Hebrew and reopen it. The sidebar must
move to the right, headings and action groups must follow that direction, and menu-preview chevrons must point toward their
submenus. On AI Assistants, JSON and command blocks must still start at the left and preserve indentation. Folder paths keep
their component order, including an Arabic or Hebrew folder name. Check the first-run choices too. Switching the app back to
English must restore the left-to-right layout. The headless preview uses the setup view's own direction setting; it must not
apply a separate correction that hides a native-window problem. See [ADR 0006](../decisions/0006-localization.md).

## 4. Agent prompt presets (0012)

Needs a real Finder and a terminal that can run commands; nothing here is covered by the tests, which only plan.

1. Select two files in a project folder, right-click, open More Agent Options, then Agent Presets. The nested
   submenu should show Review, Explain and Write Tests, and clicking Review should open a terminal in the folder and
   start the agent with the prompt already sent, naming both files as `@` mentions.
2. Right-click the empty background of a folder window: the Agent Presets submenu should be missing (the built-ins
   all name files).
3. Select a folder (and a second one): the Agent Presets submenu should be missing, since a preset that names files has nothing to name. This is the one place the menu asks the file system about the selection, from the sandboxed extension, and it was not seen there: if the submenu still shows for a folder, the extension could not tell it is a folder; clicking Review then fails with an alert that says to select files. Record which in the decision record. A folder and a file together keep the submenu.
4. A file with a space and an apostrophe in its name should arrive as a single mention.

## 5. The menu preview in the setup window

Needs a real Finder and the real app window: the tests and `script/preview_setup.sh` render the view, but they never
open one, and the preview is the same code as the extension's, not Finder's own word.

1. `rh setup`, switch the Finder extension on, and relaunch Finder (hold Option, right-click the Finder icon in the
   Dock, choose Relaunch). Open Right Here and choose "Finder menu" in its sidebar.
2. Right-click the empty background of a folder window. The entries, their order, the separators, the icons (the
   menu's own glyphs and the apps' icons) and the titles match the window's list. Click a line with a chevron in the
   window: its entries open in place, indented, and the chevron turns down; open the same submenu in Finder and compare
   its entries and separators. The introduction identifies the list as a preview and directs actual actions to Finder.
   Hovering and pressing a submenu gives feedback without dimming its title; static entries remain readable and do nothing
   when clicked. With keyboard navigation enabled, reach a submenu, verify its focus indication and expand it with Space.
3. Change `[menu] items`, or enable another agent, then refresh with Command-R: the window and
   the Finder menu both follow the config. An app that is not installed is missing from both.
4. Put a syntax error in the config and refresh: the "Finder menu" section says the config errors must be fixed and offers Show Checks.
   The config row under Checks says why; fix the file and refresh, and the menu comes back.
5. In Arabic or Hebrew (System Settings, General, Language & Region; restart the app) the lines mirror: icons on the
   right, the chevron on the left and pointing left. In dark mode the glyphs are light and an app's icon keeps its
   colors.
6. With VoiceOver, a submenu line reads like "Open With, submenu, collapsed, button" and says "expanded" once opened; an
   entry reads its title only.
7. Overview is the first section. With a config in place, a switched-off Finder extension shows Turn on the Finder extension
   and Finder Extension Settings; an unregistered extension shows its actual reason and Install or Repair. Once the
   extension is on it shows the status and the default terminal and editor. A healthy setup offers Preview Finder Menu.
   "Finder menu" is always the menu for a folder.
8. Worktrees: the list is for the repository of the folder you chose with "Choose Folder…", or else the first repository of your
   pinned and recent folders (the app has no folder of its own to start from). Right Here's worktrees (under
   `.right-here/worktrees`) have a Remove… button, which asks first and never forces: a worktree with uncommitted work stays,
   and the window shows what git said. The branch is kept. The main working copy and the worktrees you made by hand offer only
   Reveal in Finder. Choose a second repository, switch back through the menu and verify that both remain available. Long names
   and paths must leave Choose Folder and Refresh usable. Refresh updates just the worktree list. In a throwaway repository,
   temporarily move its `.git` directory aside, refresh, restore it and use Try Again: the list returns. Cancel a removal once,
   then confirm a clean worktree's removal; the row disappears and its branch remains. Repeat with a changed worktree: it stays,
   git's reason is shown and controls become usable after the list refresh. See [ADR 0028](../decisions/0028-worktree-browser-state.md).
9. Folders: Pin Folder opens a directory chooser attached to the app window; Cancel and Escape leave the list unchanged and
   restore the controls. The repository chooser uses the same sheet. Pick a folder and check that it appears
   with its name and path. A recent folder's Pin button adds it to the pinned list; both occurrences now offer Unpin. Reveal in
   Finder selects the folder without launching a terminal or editor. Rename a pinned folder in Finder, then try to reveal it:
   the app reports that it is unavailable, retains the pin, and still allows Unpin. Pin, Unpin and Clear Recent Folders change
   `state.toml`; `rh pins` and `rh recents` show the same lists afterwards. Actions stay disabled until the updated list appears.
   Use the chooser's Go to Folder sheet to enter a file path: if the panel returns it, the app must reject it and leave the pins
   unchanged (the native panel did return a file in the check recorded in [ADR 0027](../decisions/0027-manage-folders-in-the-app.md)).
   With keyboard navigation and VoiceOver, reach both row buttons; each says its action and the folder it acts on. Try long paths,
   the minimum window and dark appearance. Returning from the chooser restores usable controls without leaving a spinner running.
   In an isolated review home, replace `state.toml` with malformed TOML and refresh: the failure panel must appear instead of an
   empty list, with Try Again and Reveal in Finder. Repair the fixture and retry; pins return without a full diagnostic refresh.
   Check the error and both actions in the accessibility tree. See [ADR 0030](../decisions/0030-saved-folder-read-failures.md).
   With enough folders to scroll, reach the bottom and press Command-F: the field returns into view and selects the current
   query. Try a name, part of a path, multiple words, accents and an input method. Refresh, switch sections and pin or unpin
   a filtered result: the query stays. An unmatched query offers Clear Search; its button, the field's clear button and Escape
   restore the list. A second Escape leaves the empty field. Clear Recent Folders is absent while filtering. Find is disabled
   in another section, during a failed read and for a genuinely empty list. From AI Assistants or Finder menu, press
   Command-4 then Command-F immediately: the search field must take focus and select an existing query. Repeatedly switch
   away and back, and leave immediately after Find; a pending focus request must not steal focus from the new page.
   Check field and clear-button labels with VoiceOver.
10. In Arabic or Hebrew, use a pinned folder with two successive right-to-left names (for example `مستندات/أبحاث`). Check that the
    Folders and Worktrees paths keep their component order and agree with the tooltip and basename. Earlier headless checks showed
    reversed names despite the left-to-right marks. The later native Arabic Folders check preserved both nested names in order
    ([ADR 0006](../decisions/0006-localization.md)); the corresponding Worktrees and Hebrew cases still need native inspection.
11. The first run, with no config file (move yours aside first, and put it back afterwards). Overview offers the terminals and editors
    installed here and the agents Right Here knows, with the ones your login shell finds checked. Choose and press Set Up: `rh config
    show` has what you chose, and the page returns to the remaining Finder task. "What Right Here set up" is collapsed below it;
    expand it and verify that a registered but disabled extension has an orange hollow circle and says it is switched off.
    Successful installation steps retain their green checks. Failures, warnings and choices that could not be applied stay
    visible above the task. Open the window again with a config in place: the chooser is gone, and nothing rewrites the file (compare it byte for
    byte). `script/preview_setup.sh --first-run` shows the card without a screen; this check is the real window, once.
12. The first run's failure paths, in the real window (each is rendered and tested with a made-up Mac; a person has not seen them):
    - Open the app from the mounted disk image without moving it: the first thing on Overview is the orange card "Move Right Here to your Applications folder
      first", and Set Up and Install or Repair are off. Drag the app to Applications, eject, open it from there: the card is gone.
    - With a file where the config folder goes (`touch ~/.config/right-here` after moving the folder away), press Set Up: "What Right Here set up" appears above
      the chooser with the config step in red, and the page scrolls to it. Put things back and press Set Up again.
    - With a login shell whose startup file takes more than ten seconds (`sleep 12` in `~/.zshrc`, removed afterwards): the chooser says the shell did not say
      which agents are installed, and no agent is checked.
    - With VoiceOver on, press Set Up: the result is read ("Everything is set up." or "Some checks need your attention."), and the sections are headings.
13. Shortcuts: run a Right Here action (for example Open in Terminal) from the Shortcuts app while Right Here is not running. The action must happen and no setup
    window may be left open afterwards. The window's scene is `.defaultLaunchBehavior(.presented)` (`Apps/RightHere/RightHereApp.swift`) and the app quits when its last
    window closes; if a window appears and stays for every shortcut, that is the cause and the scene needs another launch behavior (the intents run in the app's own
    process). Not tried on a real Mac yet.
14. Updating the way the README says, in Finder: drag the newer Right Here.app over the old one in Applications and look at the dialog Finder shows. "Replace" must be offered; after it,
    `rh doctor` is all ok (open the app and press Install or Repair, or run `rh setup`). With "Keep Both" there are two copies, and the doctor says "not registered" with no extension
    (measured with a renamed copy: `rh setup` called the extension "already in place" and `pluginkit` knew none); `mdfind 'kMDItemCFBundleIdentifier == "com.boyugou.righthere"'`
    lists the copies. Which button the dialog makes the default has not been looked at on macOS 26.
15. Setup guidance (ADR 0026): before the first setup there is no attention badge. Expand More AI agents, select an additional agent,
    then close it: the selected agent stays visible. On Checks, optional and passed rows expand separately; issues stay above them.
    A row's Set Up button goes to the chooser without writing anything, and other recovery buttons match the row's fix. Return on a
    healthy page does not run repair. Command-R refreshes. Copy an MCP snippet or finish a terminal test: its result is visible above
    the content, remains until dismissed or replaced, and is announced by VoiceOver. Check text and its action are separate accessible
    controls. After dismissing a failure message, the diagnostic itself is still there.
    In Checks, inspect each row with VoiceOver: its name, status, complete detail, every additional note and its fix must be
    readable, followed by its separate action button when there is one. Cover attention, optional and passed rows; a config
    with an overlay and symlink is a useful case with multiple notes. The first-run fix must say Set Up, while an existing setup
    says Install or Repair. Paths and commands must match the visible localized text. Drag over a visible instruction to verify
    that it remains selectable. Do not accept a row that exposes only its name and status.
16. Feedback and navigation (ADRs 0029, 0035): View lists the same three groups as the sidebar: Overview, Finder menu, AI Assistants;
    Folders, Worktrees; Checks. Their shortcuts are Command-1 through Command-6 in that order; Refresh is Command-R.
    Switch sections by shortcut and verify the matching heading and sidebar selection; Command-5 also loads the worktree list.
    With enough pinned folders to scroll, go to the bottom of Folders and switch to AI Assistants: its first heading and setup-prompt
    action must be visible. Switch back: Pinned folders and Pin Folder are visible at the top. Repeat with the sidebar and with
    Checks, including expanded check groups. Scrolling partway down Folders, reselecting Folders and refreshing with Command-R
    must each retain the current position when the list is unchanged. Expanding content within a page must not jump to its top.
    A short confirmation takes only the space it needs. With a long error at minimum window size, scroll the complete message
    inside its banner while the heading, dismiss button and page remain reachable. Copy Message retains the error and copies all
    of it; copying a successful MCP snippet leaves the snippet on the clipboard. With VoiceOver, navigate the sidebar, page,
    feedback and repository groups separately, and find the AI-assistant and failed-list headings. Dismissing a notice must not
    clear the diagnostic or change the selected section. See [ADR 0029](../decisions/0029-feedback-and-keyboard-navigation.md).

    After ADR 0035, a separate native review verified the View menu's accessible item order and each Command-1 through Command-6
    destination against its sidebar selection and page heading. Command-4 / Command-F focused saved-folder search, including
    selecting an existing query after returning from AI Assistants. The review used fake system facts and a runner that launched
    no processes; its saved folders and other writes were confined to a temporary home.
17. Visual system (ADR 0033): inspect Overview, first run, Folders, Worktrees and Checks at the minimum size in both appearances.
    The sidebar groups pages by purpose; View-menu shortcut mappings stay as documented above. The healthy Overview's bounded
    menu is a labeled preview of the actual configuration, including submenu indicators. Its button opens the complete preview.
    Long translations wrap; folder paths retain their full accessibility values. Quiet row actions remain visible before hover.
    With keyboard navigation enabled, verify focus and activation of each action, and read them with VoiceOver. Check a system
    accent override, increased contrast and the icon in Dock as well as the window.

    Native review on the machine reporting macOS 27.2 (26B123), using a separately identified app and temporary home, verified
    the new icon and hidden-title window, Chinese navigation and checks, search focus and Escape clearing, pin/unpin feedback,
    and retained queries through refresh and section switching. The original folder lists were preserved. A pink accent
    override in the review app's own defaults changed selection, focus and native buttons; no global appearance preference was
    changed. Accessibility exposed every row action and its complete path. The current system's Tab navigation remained on
    text fields; full keyboard-navigation mode and spoken VoiceOver still need the manual check above. Dark appearance was
    inspected in SwiftUI renders, including dark text on the light primary button. Dock was not verified in this revision.

    A follow-up native review verified submenu expansion and collapse with the corresponding accessibility values, and static
    leaf rows. In AI Assistants, an unusually long helper path wrapped inside the code block and copied in full (pasted back
    into the app's search field to compare). Copy Plugin Commands at the bottom of the page kept both the confirmation and
    its paste destination visible above the scrolled content. The review used a separate app identity and temporary home.
    That review also reproduced an intermittent lost search focus after rapid Command-6 / Command-F (Folders was Command-6 then;
    ADR 0035 changes it to Command-4). Moving the focus
    request from the appearance callback to a cancellable view task, yielding before assigning it, passed the same native
    sequence on first entry and repeated section switches. Existing queries were selected for replacement, Escape still
    cleared then unfocused the field, and leaving immediately after Find retained the other page's focus.
18. Remaining setup task (ADR 0034): perform item 11 from the bottom of the first-run chooser. The next task and its button must
    return into view after Set Up. Expanding the installation record must leave that task at the top. Switching the extension
    on updates Overview without Refresh and removes the ordinary installation record once the setup is healthy. With the
    extension unregistered, verify that Repair is offered instead of instructions for a switch that does not exist yet.

    Native review on the machine reporting macOS 27.2 (26B123) used the production views, model and setup actions with fake
    system facts, a process runner that executed nothing, and a temporary home. Set Up from the bottom of the chooser brought
    the remaining task into view. The initially collapsed disclosure opened, and its accessible text included "registered but switched
    off". A review-only change to the fake extension state reached the healthy Overview through the existing watcher without
    Refresh. Changing it to missing exposed the reason and Install or Repair; that action returned to the enable-extension task.
    This verifies native interaction and state presentation, not real extension registration, the System Settings switch or
    spoken VoiceOver. The uniquely identified review app and its temporary home were removed.
19. Config recovery (ADR 0036): with both config files present, introduce an error in the local file. Checks must name it in
    the detail and in the recovery button; the button must open that exact file. The header menu must offer both actual file
    names and open the chosen one, including the valid main file. With only one layer present after Refresh, the header is a
    single button that opens that layer. Move the selected file aside after Refresh: clicking its recovery action must show
    a missing-file message without opening the other file or creating anything. Repeat with a custom config basename.
    With VoiceOver, verify the file menu and the named action remain distinct from the diagnostic text.

    Native review with a separate app identity and temporary home verified the direct local-file action, both header choices,
    the single-overlay state after refresh, and the missing-target message. Its fake runner recorded exact arguments and
    started no editor; external-editor behavior and spoken VoiceOver remain manual. The review app and data were removed.
