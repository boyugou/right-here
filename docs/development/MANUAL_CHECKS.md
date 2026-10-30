# Manual checks

The automated suite, the mutation check and `rh doctor --probe-launch` cover everything that they can check without a
screen or a person. The checks below need a real Finder, real terminals or a native speaker.

## 1. A real Finder click on protected folders

macOS protects the privacy of folders under Desktop, Documents and Downloads. macOS may refuse the sandboxed extension a
look at them. Then `rh` treats the path as unreadable, not as a folder (see `docs/DESIGN.md`, section 9).

1. Run `rh setup` and `rh doctor`. Every line shows `[ok]`.
2. In Finder, right-click a folder inside Documents. Then right-click one inside Desktop and one inside Downloads.
   - The Finder menu appears.
   - "Open in <terminal>" opens a window in that folder.
3. Right-click a file there and choose a path-copy item. Paste the path somewhere and compare.
4. Run `rh doctor` again. "Last action started from Finder" shows the time.

If a protected folder does not work, run `rh doctor --json` and the log command in `docs/TROUBLESHOOTING.md`. Record
the result in a decision record.

The runner script checks its arguments (DESIGN section 9, item 3). It passes on only the shapes that the extension
sends.

The tests run these shapes with a stand-in `rh` under zsh, sh, bash and dash. They do not run them through a
real `NSUserUnixTask`.

After step 2, check two things:

- `rh doctor` must show a new "Last action started from Finder".
- The Console must show no runner refusal. The extension logs a refusal as `failed`, with the runner's words,
  "right-here runner: refusing: ...".

`rh doctor --probe-launch` sends the launch probe through the same script.

## 2. Terminals that were never run

WezTerm, kitty, Alacritty and iTerm2 are built in. Each one follows the terminal's own documentation (ADR 0025).
None of them has been tried on a real Mac yet.

For each one on your Mac, run `rh doctor --probe-launch`. Then check these by hand:

- The window opens in the folder and runs the command.
- A folder named `it's a "test"` works.
- Closing the agent leaves a usable shell.
- For kitty and Alacritty, the app quits with its last window. `rh` starts these two as a new process each time.

Warp gets the `warp://action/new_window?path=` link of its documentation (`new_tab` with a tab placement); it cannot start
agents. With Warp installed, open these folders from the Finder menu, once with `terminal_placement = "window"` and once with
`"tab"`:

- `it's a "test"`, `a&b#c+d%e`, `日本` and a name with an accented letter. Each opens in that folder.
- The same with Warp not running: Warp starts and opens the folder.

Right Here hands cmux only a folder. Nothing documents what cmux does with it.

A config entry can start a terminal that has no adapter. The example below shows the shape. It uses the arguments of
Alacritty's own adapter, so it replaces the built-in one.

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

`rh config validate` warns that the entry replaces the built-in one. That is intended.

Check the entry the way the list above says. Report what had to change, so the docs can carry a verified one.

## 3. Translations

The translations in `Localization/Localizable.xcstrings` are machine-made, and many have since been read through against
macOS's own strings in that language (see CHANGELOG). A native speaker should still read the menu titles and the alert
texts of the setup window.

- `rh menu --language <tag>` prints the menu.
- The app's window follows the system language.
- Right-to-left languages (ar, he, fa, ur) deserve a look in the real menu.

The window's list of checks writes every sentence of the doctor in the system language.
`./script/preview_setup.sh out.png <code> --gallery` renders each of them in a language to a tall picture. It found two
kinds of problem:

- text that did not fit
- in right-to-left languages, paths and commands that the sentence around them reordered

Right Here now puts a value in a Unicode isolate. A command that ends in a bracket carries a left-to-right mark. That
picture is `ImageRenderer`, not a real window.

Check the real window in Arabic or Hebrew, with a state that has a path in it. A config that does not exist yet is
enough.

1. Look at the order of the path.
2. Select a command in a fix line.
3. Paste it into a terminal. Check that no invisible character came with it.

The doctor formats the relative time of the last action ("5 minutes ago") when it runs, in the locale of the process.

## 4. Agent prompt presets (0012)

This check needs a real Finder and a terminal that can run commands. The tests cover nothing here. They only plan.

1. Select two files in a project folder and right-click. Open More Agent Options, then Agent Presets.
   - The nested submenu shows Review, Explain and Write Tests.
   - Click Review. A terminal opens in the folder and starts the agent.
   - The agent has the prompt already sent. The prompt names both files as `@` mentions.
2. Right-click the empty background of a folder window. The Agent Presets submenu is missing (the built-ins all name
   files).
3. Select a folder (and a second one). The Agent Presets submenu is missing. A preset that names files has nothing to
   name.
   - Only here does the menu ask the file system about the selection, from the sandboxed extension. Nobody has seen it
     there.
   - If the submenu still shows for a folder, the extension could not tell it is a folder.
   - Clicking Review then fails with an alert that says to select files. The alert shows Right Here's icon, not a folder.
   - Record which one happens in the decision record.
   - A folder and a file together keep the submenu.
4. Use a file with a space and an apostrophe in its name. It arrives as a single mention.

## 5. The menu preview in the setup window

This check needs a real Finder and the real app window. The tests and `script/preview_setup.sh` render the view, but
they never open one. The preview is the same code as the extension's, not Finder's own word.

1. Run `rh setup` and switch the Finder extension on.
   - Relaunch Finder. Hold Option, right-click the Finder icon in the Dock and choose Relaunch.
   - Open Right Here and choose "Finder Menu" in its sidebar.
2. Right-click the empty background of a folder window. Compare the menu with the window's list.
   - The entries, their order, the separators and the titles match.
   - The icons match (the menu's own glyphs and the apps' icons).
   - Click a line with a chevron in the window. Its entries open in place, indented. The chevron turns down.
   - Open the same submenu in Finder. Compare its entries and separators.
   - Click an entry in the window. Nothing happens.
3. Change `[menu] items`, or enable another agent. Choose Install or Repair and relaunch Finder.
   - The window and the Finder menu both follow the config.
   - An app that is not installed is missing from both.
4. Put a syntax error in the config file and choose Install or Repair.
   - The "Finder Menu" section says there is no menu to show.
   - The config row under Checks says why.
   - Fix the file. The menu comes back.
5. Switch to Arabic or Hebrew in System Settings, General, Language & Region. Restart the app.
   - The lines mirror. The icons are on the right.
   - The chevron is on the left and points left.
   - In dark mode, the glyphs are light and an app's icon keeps its colors.
6. Turn VoiceOver on.
   - A submenu line reads like "Open With, submenu, collapsed, button".
   - Once opened, it says "expanded".
   - An entry reads its title only.
7. Overview is the first section.
   - While the Finder extension is off, it shows the three-step first-run card first.
   - Once the extension is on, it shows the status and the default terminal and editor.
   - "Finder Menu" is always the menu for a folder.
8. Open Worktrees.
   - The list is for the repository of the folder that you chose with "Choose Folder…".
   - Without one, it is for the first repository of your pinned and recent folders. The app has no folder of its own
     to start from.
   - Right Here's worktrees (under `.right-here/worktrees`) have a Remove… button. It asks first and never forces.
   - A worktree with uncommitted work stays, and the window shows what git said.
   - Remove… keeps the branch.
   - The main working copy and the worktrees that you made by hand have no button.
9. Open Folders and use Unpin and Clear Recent Folders. They change `state.toml`.
   - Afterwards, `rh pins` and `rh recents` show the same lists.
10. Switch to Arabic or Hebrew. Use a pinned folder whose names are right to left, for example a folder called مستندات.
    - In the preview, the Folders and Worktrees rows draw the names in reverse order
      (`script/preview_setup.sh --demo --tab folders ar`).
    - The left-to-right marks that Right Here adds did not change that.
    - Look at the real window.
    - If the names read in order there, the limit is the preview's.
    - If not, Right Here needs another way to draw the path rows. Write that in the decision record.
11. Check the first run, with no config file. Move yours aside first, and put it back afterwards.
    - Overview offers the terminals and editors installed here and the agents that Right Here knows.
    - Overview checks the ones that your login shell finds.
    - Choose and press Set Up. `rh config show` has what you chose.
    - "What Right Here set up" lists the pieces.
    - The three-step card waits for the Finder extension, as in item 7.
    - Open the window again with a config in place. The chooser is gone.
    - Nothing rewrites the file. Compare it byte for byte.
    - `script/preview_setup.sh --first-run` shows the card without a screen. This check is the real window, once.
12. Check the first run's failure paths in the real window. The tests render and test each one with a made-up Mac. A
    person has not seen them.
    - Open the app from the mounted disk image without moving it.
      - The first thing on Overview is the orange card "Move Right Here to your Applications folder first".
      - Set Up and Install or Repair are off.
      - Drag the app to Applications, eject, and open it from there. The card is gone.
    - Move the config folder away and put a file in its place (`touch ~/.config/right-here`). Press Set Up.
      - "What Right Here set up" appears above the chooser, with the config step in red.
      - The page scrolls to it.
      - Put things back and press Set Up again.
    - Use a login shell whose startup file takes more than ten seconds (`sleep 12` in `~/.zshrc`, removed afterwards).
      - The chooser says the shell did not say which agents are installed.
      - No agent is checked.
    - Turn VoiceOver on and press Set Up.
      - VoiceOver reads the result ("Everything is set up." or "Some checks need your attention.").
      - The sections are headings.
13. While Right Here is not running, run a Right Here action from the Shortcuts app (for example Open in Terminal).
    - The action must happen.
    - No setup window may be left open afterwards.
    - The window's scene is `.defaultLaunchBehavior(.presented)` (`Apps/RightHere/RightHereApp.swift`).
    - The app quits when its last window closes.
    - If a window appears and stays for every shortcut, that is the cause. The scene then needs another launch behavior.
    - The intents run in the app's own process.
    - Nobody has tried this on a real Mac yet.
    - In the action's card, the Saved Folder field lists your pinned folders (a pin) and then your recent ones (a clock), each by its
      name with its path under it. Pick one and run the action: it acts on that folder. With neither Folder nor Saved Folder set, the
      action asks for a Saved Folder, saying "Choose a folder, or one of your saved folders.", and runs with the one picked; the same
      when the phrase is said to Siri or typed in Spotlight. Unpin the folder, run the shortcut again: it still works, and the folder
      now shows a plain folder instead of a pin.
14. Update the way the README says, in Finder. Drag the newer Right Here.app over the old one in Applications.
    - Look at the dialog that Finder shows. It must offer "Replace".
    - After "Replace", open the app and press Install or Repair, or run `rh setup`. `rh doctor` is then all ok.
    - With "Keep Both", there are two copies. The doctor says "not registered" with no extension.
    - We measured this with a renamed copy. `rh setup` called the extension "already in place", and `pluginkit` knew
      none.
    - `mdfind 'kMDItemCFBundleIdentifier == "com.boyugou.righthere"'` lists the copies.
    - Nobody has looked at which button the dialog makes the default on macOS 26.

## 6. Editing the Finder menu in the window (ADR 0026)

This check needs the real window. The tests and `script/preview_setup.sh` cannot drag. They draw the rows without the
drag handlers.

1. Open "Finder Menu" and press "Edit Menu".
   - The preview becomes rows with a grip and a check box on the left. A separator has a minus button on the right.
   - A row that makes several entries (the agents) is one row.
   - Under the rows, "Not in the Menu" lists the groups that the menu does not have. Each has an empty check box.
   - Check one. It goes to the end of the menu.
   - Uncheck a line above. It goes out of the menu and shows up below.
   - The caption says to drag a line.
2. Drag a row onto another.
   - While it is over a row, a blue line shows above or below it.
   - The upper half of a row is "before", the lower half "after".
   - Drop it. The row is in its new place at once.
   - "Moved ..." and an Undo button appear.
   - `rh config show` has the list in the new order, with every comment still in place.
   - Drag a row to the very end, onto the lower half of the last row. Then drag one to the very top.
3. Press Undo. The order is back, and `rh config history` no longer lists the change.
   - Press the minus of a row. Then press "Add to Menu" and choose it again. It is back at the end.
   - "Separator" in that menu adds a line. Add and remove a few, and look at the config file.
4. Right-click a row. Move Up and Move Down work, and they are off at the ends.
   - With VoiceOver, a row reads its title. It offers the same actions (Move Up, Move Down, Remove).
5. Change a menu that the config does not list. The first change writes `[menu] items = [...]` with the default lines
   first.
   - The note above the list says so.
   - Open Finder's menu afterwards. You do not need to relaunch Finder. The menu follows the list.
6. While the window shows the editor, change the list in a terminal (`rh config add menu.items presets --at 1`).
   - Drag a row or press a minus. The window refuses the change ("Something else changed this list").
   - Nothing of the file changes. The rows show the list as it is now.
   - Do the change again.
   - Make a hand edit, or let anything else change the file, then press Undo.
   - Undo refuses and says so, instead of throwing the edit away.
   - The note takes back its own change and no other.
7. Use a `config.local.toml` that lists `[menu] items`. A note says that this Mac's own file decides. The changes go
   there.
8. In Arabic or Hebrew, the rows mirror (grip on the right, minus on the left). The drop line still shows where the
   row goes.
9. Click a row (Tab to it with Full Keyboard Access on). Press Option with the up and down arrows.
   - The row moves one place, and the note says so.
10. Start dragging a row and let go outside the list (or press Escape).
    - Drag a piece of text from another app over a row and drop it.
    - In both cases, nothing moves.
    - Use a `config.local.toml` that has `disabled = ["zed"]` and a shared menu that lists `open.app.zed`.
    - A note says that you can change the list only as text. The rows do not drag.

## 6b. The Agents page and the pickers of the Overview (ADR 0026)

This check needs the real window. The tests and `script/preview_setup.sh` cannot drag, open the menus or answer the
question.

1. Open "Agents".
   - The agents that the menu offers are rows with a grip, a check, the icon, the name and the command.
   - When the command is not found, a line says so in orange.
   - "Not in the Menu" lists the rest, each with an empty check: first the ones your login shell has, then, under "Not found in your
     login shell", the ones it does not, one line each with the command and How to Install. That line is folded, with their number,
     when your login shell has any agent; a click opens it. With VoiceOver it reads as a button with the number.
   - Check one. It goes to the end.
   - Uncheck a line above. It goes out and shows up below.
   - Drag rows, use Option with the arrows, and use the right-click menu.
   - Each change says what it did, with Undo.
   - `rh config show` has `general.agents` in the new order, with every comment still in place.
2. Switch "Start agents without asking" on. A question lists each agent with the flag that it would start with.
   - The list has "Claude Code  --dangerously-skip-permissions" and Codex's flag that also turns its sandbox off.
   - It has an agent that has no flag.
   - It has an agent whose own `bypass_permissions = false` keeps it asking.
   - "Cancel" leaves the switch off and the file as it was.
   - "Start Without Asking" writes `general.bypass_permissions = true`. The lines stay under the switch.
   - Switching it off asks nothing.
   - Start Claude Code from Finder's menu with the switch on and off. Read the doctor's line for it (`rh doctor`).
3. On the Overview, the default terminal and editor are menus.
   - "Automatic (...)" takes the setting out of the file. `rh config get general.terminal` says it is not set.
   - Choosing an app writes it.
   - An app that the config names but that is not installed says so.
   - With Ghostty or iTerm, "Opens in" offers new window, new tab, split right and split down.
   - A Finder click then opens a session there.
   - With Warp, "Opens in" offers new window and new tab. With `terminal_placement = "split-right"` in the config it shows new
     window, and the note under the terminal says Warp has no splits. Choosing New window writes `"window"` and the note goes.
   - With Terminal or another terminal, the window does not offer "Opens in".
   - When the config asks for a tab, the terminal's row says the terminal always opens a window.
   - Choose Warp (or cmux). The terminal's row says it cannot start agents.
4. While the window is open, change the config in a terminal (`rh config set general.terminal terminal`).
   - Press Refresh, or come back to the window after half a minute.
   - The rows follow.
5. Click the chevron at the right end of an agent's line. Its page opens.
   - The header shows the agent's name after a round back button. The button, ⌘[ and leaving the section go back.
   - Type into Command and press Return. The note says "Changed the options of ...".
   - `rh config show` has the new `[agent.claude] command`.
   - The arrow button next to the field puts the built-in command back. That takes the key out of the file.
   - Type into Command. Without pressing Return, click the "Starts" menu and choose another way.
   - Both changes reach the file. The window reads the field as it loses its focus.
   - Press Escape in a field. The field gives up what you typed.
6. Check the permission prompts. Any change that makes an agent start without asking asks first.
   - One alert asks. It names the agent and its flag.
   - These changes ask:
     - "Start without asking"
     - "Same as all agents", while the switch for all agents is on and the agent's own setting was "Always ask"
     - a flag typed into "Flag that skips them", for an agent that had none
     - checking an agent into the menu while the switch is on
   - "Cancel" leaves the file as it was. The field shows the text it had before you typed.
   - Click another field, or another page. The alert does not come back.
   - "Always ask" asks nothing. Nothing asks while the switch is off.
   - For an agent with no flag (Goose), "Start without asking" is dimmed. The orange line says why.
   - Turn the switch off with one agent set to "Start without asking". The panel lists that agent.
   - The Terminal menu lists the terminals that can run a command.
   - "Automatic (…)" names the one that a start uses (the default terminal when it is installed).
   - The menu shows a terminal that cannot start agents (Warp) with the line that says so.
7. Check the arguments.
   - The empty line at the end adds an argument on Return, or when you leave the field.
   - A second Return adds nothing more.
   - The minus button takes one out. A double click takes out one.
   - To move one, drag a grip or use the right-click menu.
   - Do not drag the field. A drag in the field selects text.
   - VoiceOver offers Move Up, Move Down and Remove.
   - Meanwhile, change the same list in a terminal (`rh config add agent.claude.args foo`).
   - Take an argument out in the window. The window removes nothing in its place and says the list had changed.
8. Press "Add Your Own Agent…" below the lists. It opens the Name and Command fields.
   - "Add Agent" is off until both are filled.
   - "Add Agent" adds `[agent.<name>]` with both. In the same step, it puts the agent at the end of the menu's agents.
   - One Undo takes both back.
   - The new agent has its own page.
   - "Remove Agent" at the bottom of that page takes the entry and the table out and closes the page.
   - Undo puts both back.
9. Look at "Agent Presets" under the agents. It lists the built-in presets (Explain, Write Tests), a built-in one you
   customized, and your own.
   - Open a built-in one. It shows its words and "Customize".
   - Press "Customize". The page becomes editable, and the line gets the "Customized" tag.
   - `rh config show` has a `[[preset]]` with its id.
   - The Finder submenu (Agent Presets, with a file selected) shows the title that you wrote.
   - Change the prompt. Press Return or leave the field.
   - The window refuses a prompt with a backslash, a leading dash or a `{file}` that is no placeholder.
   - The refusal shows the config's sentence, and the text stays in the field.
   - "Use the Built-in Preset" takes your copy away.
   - "New Preset…" asks for a title and a prompt. "Add Preset" is off until both are there.
   - With a preset in `config.local.toml` as well, changes go to the file that holds the preset. Undo does too.
10. Open "Finder Menu" and look below the menu.
    - "New File" lists Text Document, Markdown Document, Word Document, Excel Workbook and PowerPoint Presentation, each with a
      check and no chevron.
    - Uncheck PowerPoint Presentation: Finder's New File submenu no longer offers it, and `rh config get new_file.hidden` names it.
      Check it again.
    - Make a Word document, an Excel workbook and a PowerPoint presentation from Finder's New File submenu, and open each in Word,
      Excel and PowerPoint (and in Pages, Numbers and Keynote if they are there). Each opens as an empty document, without a message
      that it is damaged or needs repair (ADR 0032).
    - "Customize Templates" writes all five out as `[[new_file.template]]` entries (`rh config show`); the Office ones say their
      `format`.
    - From then on, each line has a chevron.
    - Open one. It has these fields:
      - Title
      - File name
      - Extension
      - Contents. It is a block. Return is a line break. The window saves the change when you leave the field.
      - Opens with. It lists the installed editors, not a terminal.
    - "New Template…" asks for a title and an extension. It ignores a dot in front.
    - On built-in templates, "New Template…" writes them out first, so the five stay.
    - Make a file from Finder's New File submenu with each template. A file of the same name gets a number.
    - Make one with "After a file is made" set to each of its three choices.
    - "Remove Template" on the last one gives the built-in five back, and the file as it was.
    - With a template in `config.local.toml` as well, changes go to the file that holds the template. Undo does too.
    - Type `--`, a quote and several lines into Contents. They stay as typed (no dash, no curly quote).
    - The window saves the text after five seconds without a key. VoiceOver says nothing then.
    - "Recent Changes" lists each save.
    - The window saves the text again when you click another field.
    - Go back to "Finder Menu" at once. The window keeps the text.
11. Open the page of an agent.
    - "First prompt" shows `positional` for Claude Code (grey, the built-in way).
    - It shows nothing for Goose. Goose's page says that it has no built-in way.
    - It also says that no preset can name it while the field is empty.
    - Type a flag there. The window writes it (`rh config get agent.claude.prompt_arg`).
    - The window refuses a word that is not a flag, with the config's sentence.
    - Type `positional`, or empty the field. That takes the setting out.
    - "Start Options" lists Continue Last Session and Resume a Session… with a "Built in" tag and no chevron.
    - It lists your own with a chevron. Its page has a title, the arguments and "Remove Start Option".
    - You add, change, drag and remove its arguments as for the agent's own.
    - "New Start Option…" asks for a title and opens the page of what it made.
    - The Finder menu's "More Agent Options" submenu lists it.
    - With a start option in `config.local.toml` as well, changes go to the file that holds it.
    - A new one for an agent defined there goes there.
12. Open "Finder Menu" and look below New File.
    - "Copy Path" has a Title field. Its placeholder is the localized "Copy Path". An empty field takes the setting out.
    - The six default forms are checked. The other four are under "Not in the Menu".
    - Uncheck one, check another, and drag.
    - The first change writes the whole list. `rh config get copy_path.styles` shows it.
    - Finder's submenu follows it. You do not need to relaunch Finder.
    - "Quick Actions" lists the default actions with their icons.
    - "Add Quick Action" has the actions that you can add in submenus.
    - The window writes a change to `services.items`. The Overview's Quick Actions check says they differ.
    - Install or Repair makes them. System Settings › Keyboard › Keyboard Shortcuts › Services lists them.
    - With `copy_path.styles` or `services.items` in `config.local.toml`, the change goes there.
13. Open "Overview" and look below the default terminal and editor.
    - On a new config, "Your Apps" is empty, with "Add App…".
    - Press "Add App…". Choose an application that Right Here does not offer (Tower, Nova, Pulsar...).
    - The form shows these:
      - its name (change it)
      - "Use as" (Editor, Terminal, Other app)
      - its bundle identifier
    - "Add App" writes an `[[app]]` entry (`rh config show`). The line appears with the app's own icon.
    - The app can be the default editor or terminal, or a line added with Edit Menu.
    - Choose Ghostty or Terminal (built in) and an app that you added. The note says it is available already.
    - The window then writes nothing.
    - The page of an app changes its name and role.
    - The role of a terminal that `config.toml` starts through `open_args` is dimmed. A line says why.
    - "Remove App" takes the entry out. For an entry that replaces a built-in app, the built-in one is back.
    - With an `[[app]]` entry in `config.local.toml` as well, changes go to the file that holds it.
    - Choose a terminal that Right Here does not know (Tabby, Rio).
    - When the app says it is a shell, the form starts with "Terminal".
    - Add `disabled = ["terminal"]` to `config.local.toml` and choose Terminal.
    - The note under the apps says that this Mac turns it off. The window writes nothing.
    - Open the page of an app with a built-in terminal's identifier. The role menu is dimmed, with the line that says why.
    - Drag a form of Copy Path over the Quick Actions (and the other way). Nothing moves.
    - Check a Quick Action. The Overview's Quick Actions check says at once that they differ.
    - Install or Repair clears it.

## 7. The Config page (ADR 0026)

This check needs the real window. For the last step, it also needs a real MCP client.

1. Open "Config". It shows the text of `config.toml` in a monospaced editor.
   - Type a `"` and two hyphens. They stay as typed (no curly quotes, no dash).
   - So a text typed here is still TOML.
   - Command-Z undoes typing.
   - VoiceOver announces the editor as "Text of the config file".
2. Delete the closing bracket of a list. Under the editor, a line names the error with its number. Save is off.
   - Put it back. The line says "No problems.", and Command-S saves.
   - "Recent Changes" shows the change as made by this window, with Undo.
   - The Finder menu page follows the text.
3. Type something. Meanwhile, change the file in another editor (or `rh config set ...` in a terminal). Press Save.
   - The window saves nothing.
   - The page says the file was changed while you were editing it.
   - What you typed is still in the editor.
   - Save stays refused until Revert reads the file again, even after Refresh or a visit to another section.
   - Leave the page and come back. What you typed is still there.
   - Quit (Command-Q, or close the window) with text that is not saved. A question asks, with Cancel as the default.
   - Press Revert and then Command-Z in the editor. Nothing is garbled.
4. Choose `config.local.toml`. The choice is off while there is text that is not saved.
   - Save a text there. That makes the file.
   - The window accepts a terminal there that only the shared file defines.
   - It refuses one that nobody defines.
   - The note says that this Mac's file wins over the shared one and is never synced.
5. Connect an AI assistant (`claude mcp add right-here -- rh mcp`). Ask it to set an agent's `args`.
   - Its answer says the change was proposed.
   - The window's Overview shows the line that a change is waiting.
   - The Config row has a number.
   - The page has the card with the diff.
   - Apply makes the change. The file has it, and "Recent Changes" says it was made by this window.
   - Dismiss forgets it.
   - `rh config pending` agrees with both.
6. Ask the AI assistant to change something that is not a program (a menu entry, a preset's title).
   - The change happens at once. "Recent Changes" says "By an AI assistant".
   - Ask it to take out an agent's `args` or its `bypass_permissions` override. The change waits like a write does.
   - With a change waiting on the card, edit the file in a terminal and press Apply. The window makes nothing.
   - The card says the file changed. It shows the change against the file as it is.
7. Look at the page in Arabic or Hebrew.
   - The page mirrors.
   - The diff and the text of the file stay left to right (they are code).
   - The picker of the two files still works.

## 8. What goes to Finder: speed and separators (ADR 0027)

This check needs a real Finder on macOS 26 (the reports came from 26.5.1). To compare, it also needs one on
macOS 27.

1. Install the build, relaunch Finder, and right-click a folder in a window.
   - The Right Here entries are in the menu when it opens, not a second later.
   - Wait a minute and click again. The result is the same. The extension serves an old menu while it makes a new one.
   - Then click once more.
2. Open Console (or run `log show --last 5m --predicate 'subsystem == "com.boyugou.righthere.FinderExtension"'`).
   - Each right-click has a line from the extension, with how long `menu(for:)` took.
   - The line says "served from cache" or "served from an old cache" or "built".
   - None is slower than about 50 ms.
3. On macOS 26, the Right Here part of the menu has no empty row anywhere. The "Open With" submenu has none either.
   - On macOS 27, there are separator lines where the config has `"-"`.
   - If there are empty rows instead, `FinderMenuPresentation.showsSeparators` must be false there as well, and ADR
     0027 says so.
4. The setup window's "Finder Menu" page shows the same entries, in the same order. It shows lines, or no lines, as
   Finder does on that macOS.

## 9. The language, the progress of a repair and the copies of the app (0.3.7 to 0.3.9)

1. On the Overview, choose a language other than the Mac's in the Language menu (for example Deutsch on an English Mac).
   - The window changes at once. Arabic or Hebrew mirror it.
   - Right-click a folder in Finder. The Right Here menu is in the chosen language. This is what the language promises,
     and no test can see Finder.
   - Right-click a file and open Quick Actions. Their names are in the chosen language.
   - Choose "Same as macOS". All three come back to the Mac's language.
2. In System Settings › General › Language & Region › Applications, give Right Here another language than the Mac's,
   and leave `general.language` out of the config. ADR 0006 expects the window to follow it and the Finder menu not to.
   Write down what happens.
3. Press Install or Repair.
   - A spinner and a line under the header say each step while it runs.
   - When it ends, the line says what it made or updated, or that everything was in place.
4. On the Agents page, check an agent that is installed but not in the menu.
   - Right-click a file and open Quick Actions. Its Quick Action is there without pressing Install or Repair.
5. Help › Right Here Help opens the guide on the website, in the window's language.
6. Put an older copy of Right Here in `~/Applications` and open it.
   - The strip under the header names both versions.
   - "Open Version …" opens the newer copy, and the older one quits. Write down whether macOS needed a new instance for
     that (the code asks for one).
   - `rh doctor` lists both copies under "Copies of Right Here".

## 10. The window without a title bar, and the disk image (0.3.16 and later, ADR 0029)

No test can see the window's own chrome or Finder's window of a disk image.

1. Open the app.
   - The close, minimize and zoom buttons stand in the top corner of the sidebar, above the app's name, and nothing covers them.
   - The page's title and the header's buttons stand on the line of the close, minimize and zoom buttons, as a title bar's would.
   - Scroll a long page (Finder Menu): a thin line appears under the header while it is scrolled, and goes at the top.
   - With System Settings › Accessibility › Display › Increase contrast: the lines between rows and the groups' edges are darker.
   - Drag the window by the top of the sidebar and by the empty part of the header: it moves. A click on the header's buttons presses them.
   - Double-click the empty part of the header: the window does what System Settings › Desktop & Dock says a title bar's double-click does.
   - Make the window as narrow as it goes, in German: the header's buttons show their symbols, with their words as tooltips.
   - Switch to another app: the chosen section in the sidebar turns grey, and blue again when the window comes back.
   - Zoom the window: the page and its header stop growing and stand in the middle of the space beside the sidebar, their edges in
     line. Drag and double-click the empty band beside the header: the window moves, and does what a title bar's double-click does.
     Make it full screen: the same middle column.
   - With System Settings › Appearance › Show scroll bars set to Always, in a zoomed window: the page's edges stay in line with the
     header's, and the page does not move sideways between a short section (AI Assistants) and a long one (Finder Menu).
2. Choose Arabic in the Language menu on a Mac whose language is English (the window right to left, the system left to right).
   - The window's buttons stand at the top left, over the end of the header, beside its buttons and not on them (the preview's
     `--titlebar-ltr` draws what is expected). Write down if they are anywhere else.
   - Zoom the window: the header's buttons line up with the end of the page, and the window's buttons stay clear of them (the
     preview's `--wide --titlebar-ltr`).
3. Open a disk image made by `script/package_dmg.sh`.
   - Its window shows Right Here and the Applications folder side by side, without a toolbar or a sidebar, and the names are readable in
     light and in dark mode.
   - The disk on the desktop or in Finder's sidebar has the app's icon.
4. In Finder, View › Customize Toolbar, drag Right Here into the toolbar.
   - Its button is the app's pin with the prompt in it, drawn in lines like Finder's own buttons, in light and in dark mode. With
     nothing selected a click opens the menu of the folder the window shows; with files selected, the menu for them.
5. The value menus (the Overview's default terminal, Opens in, default editor and language; an agent's Starts and Terminal; a
   template's Opens With).
   - Each shows what is chosen, then the chevrons, as in `script/preview_setup.sh`'s pictures. Write down a chevron before the words.
   - The default terminal and editor show the app's icon before its name, and each app in their menus has its icon.
   - The pointer over one puts a light ground under it. A click opens its choices, and a choice is written at once.
   - While Install or Repair runs they are grey and do not open.
   - With VoiceOver, VO-Space opens one (it is a menu button with its name and what is chosen, measured: ADR 0029, 10). Tab reaches
     it when Keyboard Navigation is on.
6. The rows that open a page: Your Apps on the Overview, the presets on Agents, the templates on Finder Menu, an agent's start options.
   - Their names are in the text colour, as the agents' names above them, not grey. Write down a grey row and whether the window
     was in front.
   - A click anywhere on a row, also on its empty middle, opens its page; the row dims while it is pressed.
