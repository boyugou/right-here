# Changelog

## 1.0.0 (2026-10-29)

The first public release, and the first version number of the public project: the repository, its releases and the website are
open to everyone, under the Apache License 2.0. The 0.x versions before it, in CHANGELOG.md, were the private beta.

- **Every language read through**: Hindi (112 corrections), Malay (138), Persian (78), Urdu (35), Bengali (48), Marathi (48), Tamil
  (24) and Telugu (28) join the 22 before them. In the languages macOS does not ship, the names of macOS's own places stay in English,
  as their users see them.
- The copyright notice is of The Right Here Authors (NOTICE, AUTHORS); CONTRIBUTING says how a contribution is licensed (Apache-2.0,
  with a sign-off).
- The website has a Download button for the latest release.

## 0.3.28 (2026-10-29)

- **New File makes Word, Excel and PowerPoint documents**: three more built-in templates, each a real blank document (a Word
  document, a workbook with one sheet, a presentation with one slide) and not an empty file with the extension. Every template has
  a check on the Finder Menu page: uncheck the ones you do not use, and the New File submenu leaves them out (`new_file.hidden`).
- **Install or Repair shows that it runs on its own button**: a spinner in place of its icon from the press to the end, beside the
  line under the header that says what it does; the button only went grey, at the other end of the header from that line.
  When a check still asks for it afterwards (a copy of the app that macOS registers again, say), the line under the header names
  that check instead of saying it is done: the button stayed the window's main one, and a press that changed nothing looked like a
  press that did nothing.
- **The Config page says what each file is for**: its two files are "Shared (config.toml)" and "This Mac Only
  (config.local.toml)", with a line under them about the one shown.
- Where a terminal session opens has a tile like the other rows of the Overview.
- The Finder menu's editor shows the agents as one item: its grip, its check and its link to the Agents page on the first agent's
  line, and the agents' lines on one ground (the controls stood on the middle line, and the lines around it looked like items that
  could not be checked). Agent Presets, when the menu does not have it, shows its symbol like the other groups.
- **Twelve more languages read through**: Russian (117 corrections), Polish (90), Dutch (118), Turkish (99), Greek (65),
  Romanian (77), Vietnamese (62), Ukrainian (108), Indonesian (95), Thai (166), Arabic (131) and Hebrew (257), each in the words
  and style of macOS's own strings in that language (Вы and приложение in Russian, kliknij w in Polish, imperative buttons in
  Dutch, Saptanmış in Turkish, OK in Greek, Infirmați for Undo in Romanian, Khôi phục for Revert in Vietnamese, інсталювати in
  Ukrainian, Batalkan in Indonesian, แถบ for a tab in Thai, فايندر in Arabic, impersonal instructions in Hebrew). A new-file item
  no longer needs the gender of a template's name in the languages that have one.
- Docs and comments describe Right Here on its own: no comparisons with other tools, and only documentation cited as the source of
  a terminal's or an agent's flags.
- The Quick Actions settings path writes System Settings as macOS does in Greek and Vietnamese; the check of that wording now
  compares case.

## 0.3.27 (2026-10-29)

- **Seven languages read through**: German (54 corrections), French (91), Spanish (27), Italian (67), Traditional Chinese (95), Korean
  (130) and Brazilian Portuguese (75). Each follows the words and style of macOS's own strings in that language:
  pin and unpin in German, Rétablir for Revert in French, pannello for a tab in Italian, 檔案夾 and 預設組 in Taiwan, 하십시오 and
  윈도우 in Korean, title case for buttons in Portuguese; one word each for preset and prompt; sentences that said the wrong thing.
- The Checks say why an agent cannot start in your language when the terminal only opens folders, or is not installed, or none is;
  it was English in every language.

## 0.3.26 (2026-10-29)

- **Four more agents are built in**: Cursor CLI, Qwen Code, Factory Droid and Kiro CLI, each with what its own documentation gives
  (the first prompt of a preset, the flag that turns permission prompts off, continuing a session). Cursor CLI shows the Cursor app's
  icon when it is installed.
- On the Agents page, the agents your login shell does not have are one folded line with their number, which a click opens, instead
  of a dozen lines above the presets. With none found they stay open: they are then what the page has to offer.

## 0.3.25 (2026-10-29)

- **Warp opens in the folder the way Warp documents it**: a `warp://action/new_window` link with the folder, or `new_tab` when the
  terminal placement is a tab, instead of handing Warp the folder with `open`, which nothing documents. Every character of the
  folder's name outside ASCII letters, digits and `-._~/` is percent-encoded, so an `&` or `#` in it stays part of the folder.
  Warp Preview gets its own `warppreview://` link. With a split asked for in the config, the Overview says Warp opens a window.
- `open` runs in `/`, so a link such as `warp://…` can never be taken for a file of the folder `rh` was started in.
- Save, Apply and Set Up are blue only while they can be pressed; while they cannot, they are grey like the buttons beside them, instead of a faded blue.

## 0.3.24 (2026-10-29)

- **Simplified Chinese, read through**: one word each for flag (标志), prompt (提示词) and saved folder (已保存), counts written as Chinese says them (已安装 7 个), the same separator in every System Settings path, and clearer wording in a few checks; Apple's own names for iCloud Drive, Spotlight and Launchpad (iCloud 云盘, 聚焦, 启动台).

## 0.3.23 (2026-10-29)

- A scrolled page is cut at a thin line under the header, as under a title bar, instead of text cut off bare under its buttons.

## 0.3.22 (2026-10-29)

- **Agents: a change is said where it was made.** Moving, checking or adding an agent says so, with Undo, under the list of
  the menu; a new preset under the presets; the switch under the switch. All of them stood at the end of the page, out of
  sight of the list that changed.
- **Calmer groups**: the lines between rows have the light grey of macOS's own settings, half as dark as before. The Finder
  menu's picture stands centred on a stage; the config's text looks like a field you can type in; the Overview's tiles are the
  sidebar's size.
- A new file's line in the Quick Actions and the menu's editor has the New File glyph, like the lines around it, instead of a
  faint white page.

## 0.3.21 (2026-10-29)

- **The pages follow one set of rules**: the Config page's buttons stand at the trailing edge, the one
  that saves or applies last; lines between rows of settings start where their text does; check titles and the forms not in
  the menu are in the text's regular weight and colour; buttons that act on a page are all of one size.
- **One spacing on every page**: 24 points between sections and 8 inside one, so a heading, its list and its note read as one
  section; on an agent's page the heading of Arguments and its note had stood a section away from the list.
- **The header is a title bar**: the page's title and its buttons stand on the line of the window's close, minimize and zoom
  buttons, in the 32 points of a title bar, instead of a large title 12 points below them; the pages start higher.

## 0.3.20 (2026-10-29)

- **The first run shows each terminal and editor with its icon**, between its mark and its name.
- **The app's icon in dark mode**: its `>_` is white on the pin, where it had been violet on violet and hard to see.
- `rh agents` names its columns (ID, NAME, STATE), as `rh apps` does.

## 0.3.19 (2026-10-28)

- **A shortcut can pick one of your folders.** Each of the four Shortcuts actions takes a Saved Folder, picked from your pinned folders
  and then your recent ones, instead of a folder handed over as a file. A shortcut keeps its folder after you unpin it.

## 0.3.18 (2026-10-28)

- **A menu of the window shows what is chosen, then its chevrons**, as the screenshots always did. In the app the chevrons stood
  before the words ("⇕ Ghostty") on every such menu: the default terminal and editor, the language, where a session opens, and the
  choices of an agent, a preset and a template. The pointer over one now puts a light ground under it, and the default terminal and
  editor show the app's icon before its name.
- **The rows that open a page are drawn as the screenshots show them** (Your Apps, the presets, the templates, the start options).
  They were AppKit's borderless buttons, which in a window drawn off screen gave a whole row's words the grey of a disabled row.
- **Lines between the rows of every list** (the agents, the presets, the apps, the templates, the start options, Copy Path's forms and
  the Quick Actions), as the other lists of the window had. A word about a row (Built in, Customized, Main working copy) is one grey
  tag everywhere, and New File's templates no longer say "Built in" on each line when the note under them says so.
- **Finder's toolbar button is the app's pin**, with the prompt in it, drawn in lines like Finder's own buttons, instead of a
  generic menu symbol.
- New File's Customize Templates stands beside New Template under the list, and the note on the built-in templates right under
  it; a preset's two notes are one footnote.
- **Agents: the ones your login shell does not have are one quiet list**, under a line that says so once, one line each with the
  command and How to Install, instead of nine two-line rows that each said "Not found" beside the same icon.
- **An action from Finder that fails says so with Right Here's icon.** The alert showed a blue folder: `rh` has no bundle of its
  own, and an alert takes the icon of the folder its program is in. It now reads the app's own icon file, which is there at once
  even for a copy that macOS has not seen yet.
- **A wide window keeps the page together**: the page and its header stop at 780 points and stand in the middle, instead of a
  setting's name and its control drifting to the two edges of a full-screen window.
- **An empty list keeps its place**: no pinned or recent folders, no repository on Worktrees and no recent changes of the config
  are said inside the list's own group, instead of a line of grey text where the list would be.

## 0.3.17 (2026-10-28)

- **Settings as macOS 26 lists them.** A setting's name stands at the leading edge and its control at the trailing edge, with what it
  does under both. The Overview's default terminal, where it opens, default editor and language are one list. The page of an agent, a
  preset, a start option, a template or an app puts its name in the header after a round back button (⌘[), instead of a link back
  and a second title. Open Config is a round button with its symbol; Install or Repair keeps its words.
- **The Finder menu page shows the menu as a menu**: as wide as its lines, its rows a menu's height, on a sheet with a soft shadow. A
  line longer than the page is cut instead of widening it.
- **A calmer first run**: a plain card, chosen chips tinted without an edge, agents that were not found quieter, and Set Up at the
  trailing edge.
- **Buttons where macOS puts them.** A button that removes a thing has a frame and red words at the trailing edge (Reset of a
  customized preset is blue); Add and New stand at the trailing edge under their list; Customize is a button. On Folders, pin and
  unpin are symbols beside Reveal; on AI Assistants each Copy button stands on its section's heading. Folders and worktrees are rows
  of one list.
- **Smaller things.** Agents not in the menu are no longer grey, and How to Install stands at the end of the row. Section headings
  have one style, and the English titles are in title case (Finder Menu, Recent Changes). Paths are in one font, a command in a
  sentence a point smaller, Copy Path's titles in one column.
- **The window.** A window in a language that runs the other way from the Mac's (Arabic on an English Mac) no longer
  has the window's buttons on top of Install or Repair: the header leaves them room. A double-click on the header does what a title
  bar's does. The chosen section uses the system's colour of a selection, which keeps its text readable with any accent colour.
  VoiceOver reads the app's name and version as one line, and a header button's words once instead of twice.
- **A disk image that shows where the app goes.** Its window shows Right Here beside the Applications folder, at the size Finder shows
  icons, without a toolbar or a sidebar, on Finder's own ground (so the names stay readable in dark mode), and the volume has the
  app's icon. dmgbuild writes the layout into the image; nothing asks Finder to arrange it.

## 0.3.16 (2026-10-28)

- **A new icon.** A white pin that holds a `>_` prompt, on a violet-to-blue ground, made in Icon Composer: macOS draws its light,
  dark, tinted and clear looks, and it stays a pin at the 16 pixels of a menu. The old icon's pictures are no longer copied into
  the app (1.5 MB less). ADR 0028.
- **A window that looks like macOS 26.** No title bar above the window's own header: the sidebar runs to the top, with the window's
  buttons in its corner. Each section has a coloured tile as in System Settings, the chosen one stands on the accent colour, and the
  cards are the grouped settings of macOS 26, without an edge (with one under Increase Contrast). The buttons are capsules; in a
  narrow window the header's buttons show their symbols and keep their words as tooltips. ADR 0029.

## 0.3.15 (2026-10-22)

- **Today's translations, read again.** Of the 61 texts added today, in 29 languages, 16 were corrected: a Greek reason
  that said the reverse, grammar in German, Romanian and Greek, the catalog's own words for "command", "window", "default" and "app" in
  Korean, Malay, Telugu, Ukrainian, Persian, Urdu and Marathi, and the macOS form of "Help" in German, Polish and Traditional Chinese.

## 0.3.14 (2026-10-22)

- **Small things in the window.** The Reveal in Finder buttons of the Folders and Worktrees pages stand in one column. On the Config page,
  the header's button says "Open in Text Editor".

## 0.3.13 (2026-10-22)

- **The copies of the app are looked at again with each read** of the window, so a copy that was moved to the Trash or installed while the
  window was open counts at once.
- **One language on a proposal's card.** The agents that a switch of the permission prompts concerns are listed by name and flag after the
  window's own words.

## 0.3.12 (2026-10-22)

- **Copies of the app.** The command that the refusal of an older copy names can be pasted (its path has a space). Of
  two copies of one version, the one that the doctor says to move to the Trash sets nothing up either, and a copy that runs from the Trash
  sets nothing up. Versions such as 0.3.12b1 compare by their numbers. The time of an extension crash in `rh doctor` is English on a Mac
  of any locale.
- **An added app's next step.** The page of an app you added has Make Default (for a terminal or an editor) and Add to Menu, while it is
  not the default or in the menu yet.
- **Small things in the window.** The setup summary starts each remark with a capital, as its other words do. "Copied" on the AI Assistants
  page goes when you leave the page.

## 0.3.11 (2026-10-22)

- **A calmer first run.** Before Set Up, the sidebar says "Not set up yet." with no warning badge. Install or Repair is the main button only
  when a check asks for it, and "Press Install or Repair." is not repeated above that button.
- **One language in the window.** The checks name an agent's action ("Claude Code Here"), and an agent's page names its built-in start
  options, in the window's language. Why an AI assistant's proposal waits for you is said in that language too.
- **Right to left.** The MCP configuration and the plugin commands stay left to right in Arabic, Hebrew and Persian. A path with an
  Arabic or Hebrew folder name keeps `~` at its start, and its letters join.
- **Help next to its field.** On an agent's page and a template's page, the help for a field is under that field, not below the whole group.
  Start options have their own symbol, not the one of worktrees.
- **Where presets are.** The Agents page says that presets are in "Agent Presets", or in "More Agent Options" when the menu has no Agent
  Presets line. The note under the built-in New File templates says what Customize Templates does.
- **Checks speak the window's language.** A fix that the window has a control for says where it is ("choose one on the Overview", "uncheck
  it on the Agents page", "fix the errors on the Config page") instead of naming a config key or an `rh` command.
- **Agents in the menu editor.** The one line that stands for every agent of the menu has a link to the Agents page, where you choose them.
- **Find the old copy.** The check "Copies of Right Here" has a Reveal in Finder button that shows the copies to move to the Trash.

## 0.3.10 (2026-10-22)

- **An older copy sets nothing up.** While a newer copy is installed, an older one's Install or Repair and `rh setup` change nothing and say
  which copy to run. Before, they pointed the Finder menu and the Quick Actions at the older copy.
- **`rh setup` says what it does.** On a terminal it prints each step as it starts ("Registering the Finder extension…"), on standard error.
  A script or an AI agent that reads its output gets the same report as before.
- **`rh agents` says where.** Each agent the login shell finds shows its path ("enabled, found at ~/.local/bin/claude"), and one it does not
  find names its install page. `rh agents --json` has `location` and `installPage`.
- **One language per sentence.** The time in "Last action started from Finder" ("5 minutes ago") is in the window's language there, and in English
  in `rh doctor`. Before, it followed the system language in both.
- **Copies of the app.** Of two copies of one version, the doctor says to keep the one in /Applications; 1.0 and 1.0.0 count as one version.

## 0.3.9 (2026-10-22)

- **Fixes.**
  - An older copy of the app no longer rewrites the Quick Actions to run its own `rh` after a change in its window.
  - The first window starts your login shell once, not twice.
  - A startup file that prints a line ending in a carriage return, or prints a word that is an agent's command, no longer changes which agents count as installed.
  - A change in the window does not wait for another setup that is running.
  - "Open Version …" on an old copy opens the newer copy before it quits.
  - VoiceOver reads whether each agent is installed, and offers How to Install and a check's fix button as actions.
  - `rh setup` no longer asks the login shell about agents that are not in the menu.

## 0.3.8 (2026-10-22)

- **An old copy of the app says so.** When you open an older copy of Right Here while a newer one is installed, a strip under the header names
  both versions, with buttons to open the newer copy and to show the old one in Finder. `rh doctor` and the Checks page list the copies when
  more than one is installed.
- **Checks you can act on.** A check whose fix the window can do has a button under it: Install or Repair, the Finder extension settings, or
  the page where the setting is changed (Overview, Agents, Config).
- **How to install a missing agent.** An agent that your login shell does not find has a "How to Install" link to its own install page.
- **Keyboard and Help.** ⌘1 to ⌘8 open the sections of the window, ⌘R reads everything again, and Help › Right Here Help opens the guide
  on the website in the window's language.
- **Pinning from the window.** The Folders page has a Pin button on each recent folder and a "Pin a Folder…" button. Each folder and worktree
  has a button that shows it in Finder.
- **Smaller fixes in the window.** The Finder menu page says how to edit the menu, and its Edit Menu button has an icon. The AI Assistants page
  confirms a copy under the button. After the first setup, a Finder extension that is still switched off has an orange mark, not a green one.
  The first-run text no longer sends you to the config file to change your choices.

## 0.3.7 (2026-10-22)

- **Install or Repair shows what it does.** While it runs, a line under the header says the current step, for example "Registering the Finder
  extension". When it ends, the line says what it made or updated, or that everything was already in place. Before, the button only greyed
  out for several seconds. The checks also run once instead of twice, so a repair ends sooner.
- **Choose the language in the window.** The Overview has a Language menu. It sets `general.language` in the config, and the Finder menu, the
  window, the alerts and the names of the Quick Actions follow it. Leave it at "Same as macOS" to follow the system.
- **Quick Actions follow your changes.** A change in the window that adds, removes or renames a Quick Action now updates it at once. Before,
  it waited for Install or Repair.
- **The Agents page says which agents are installed.** Each agent shows whether your login shell finds its command, and where, for example
  "Found at ~/.local/bin/claude". A new terminal window finds the agent in the same place. Installed agents come first under "Not in the menu".
- **`rh doctor` names the changes that wait for you.** When an AI assistant proposed a change that you must approve, the doctor and the Checks
  page now have a row "Changes to approve". It points to the Config page and to `rh config pending`.
- **Shorter sentences in the window.** The 16 longest sentences of the setup window are split, in all 30 languages.
- **Plainer guides.** The roadmap, the release and build guides, the manual checks and the plugin's skills are rewritten in short steps.

## 0.3.6 (2026-10-22)

You can now change almost every setting in the setup window. The new editors were checked for ways in which an AI
assistant, or a config from the sync folder, could start a program or an agent without asking you, and this release closes the ones found.

### New in the setup window

- **Agent presets.** The Agents page lists the presets. Open a preset to change its title, its prompt, its agent and how many files it takes.
  Press **New Preset…** to make your own. To change a built-in preset, customize it. Remove your copy to get the built-in preset back.
- **First prompt and start options.** The page of an agent shows how its command takes a first prompt. It also lists the start options, such as
  "Use Opus". Press **New Start Option…** to add your own.
- **New File templates.** The Finder menu page lists the templates. Customize the two built-in templates, or press **New Template…**. A template
  has a title, a file name, an extension, contents and an app that opens it.
- **Copy Path and Quick Actions.** The Finder menu page lists the forms of Copy Path and the Quick Actions. Check or clear a line. Drag a line to
  move it. **Install or Repair** makes the Quick Actions from this list.
- **Your Apps.** The Overview lists the apps that your config adds, such as a Git client or a terminal that Right Here does not know. Press
  **Add App…** to add one.
- The window saves each change at once. Press **Undo** to take it back.

### Safety

- **An AI assistant now asks you first** before it does one of these things:
  - It adds a New File template with contents. Such a file can be a script, and the assistant chooses the folder.
  - It changes or empties the flag that switches an agent's permission prompts off.
  - It undoes a change that needed your approval.
  - It removes this Mac's own app that replaces a shared one. The shared app can be a different program.
  - It chooses a terminal that starts through a command template: as the default terminal, for an agent, or in the Finder menu or the Quick
    Actions.
- **A preset never starts an agent without its permission prompts.** A preset now refuses an agent whose command hides the flag. The flag can hide
  behind an assignment (`FOO=1`), `env`, `sh -c '…'`, `$'…'`, braces, a glob or the shell history. Tests compare the reading of a command with
  real zsh and bash.
- **The switch "Start agents without asking" names every agent that it affects.** This includes an agent that only a Quick Action offers.
- **A pull from the sync folder reads this Mac's own file too.** If a pull would start an agent without its permission prompts, it asks first.
- **`rh config pending apply` makes a change only as `rh config pending show` showed it.** If the config changed in between, look at it again.
- **A terminal is only given folders.** The config refuses an app that has the bundle identifier of a terminal and another role. A terminal runs a
  file that it is given.
- **`rh config sync pull` waits for an edit in progress.** Before, it could write over the edit.
- **`rh init --force` and `rh setup --force` wait for an edit in progress too.** They also never write the config of your real home folder
  from a test that forgot its trial home.
- **A pull compares a long template text in full.** Before, a copy that kept the start, the length and a short digest of the text passed
  for the same text.
- **Text that shows nothing is refused in names and prompts.** This includes marks such as U+034F and the Khmer and Hangul fillers. A
  selected file name with them is not put into a preset's prompt.

### Fixes

- The window edits the entry that you see, in the file that holds it. This is true also when `config.local.toml` defines the same entry.
- Undo refuses a file that something else changed.
- A field that you type in keeps your text when the config changes. Escape shows what the file says now. A held change does not ask twice.
- If a change cannot wait for the window, the window says so under the editor that you used.
- Two agents, or two start options of one agent, cannot have the same name. Names that differ only by an invisible joiner, by case or by
  full-width letters are the same name. A start option cannot repeat a built-in title in any language of the menu.
- A name has at most 120 characters. The contents of a template have at most 64 KB.
- A drag moves a line only inside its own list.
- The check of the Quick Actions shows at once when they differ from the config.
- `rh config add new_file.template` keeps the built-in templates.
- A Quick Action title that is too long for a file name, or two titles that differ only in case, no longer make the install of all Quick
  Actions fail.
- Dutch, Thai, Vietnamese and Malay name Quick Actions as Finder does.
- The guides of `rh docs`, the README and the troubleshooting guide are rewritten in short, plain sentences.

## 0.3.5 (2026-10-17)

Each agent gets a page of its own in the window, and this release closes trust gaps of the config editing that were in 0.3.3 and 0.3.4: an assistant could weaken an agent without asking you.

### The Agents page

- Agents: each agent has a page of its own (the chevron at the right of its line): the command that starts it, how it starts (in a terminal, in the last-used terminal, in its desktop app), the terminal it uses,
  whether it starts without its permission prompts (asks first) and the flag that does it, and the arguments it is given (add, change, drag, remove). A program of your own (lazygit, aider, a script) is added
  with "Add Your Own Agent…" and taken out again with "Remove Agent". Every change is saved at once and can be undone.
- `rh config add agent.<id> name=… command=…` and `rh config remove agent.<id>` (and the MCP tool) make and take out an agent of your own, as the window does.

### Fixes

- Fixed: an AI assistant could take out the arguments that keep an agent in its sandbox (by emptying the list, or through `config.local.toml`, or a sync-folder copy) and could
  put an agent in the menu that starts without asking while that switch is on, without asking you; the window now asks before any change that makes an agent start without its permission prompts, from
  whichever control it comes; names that read backwards or show nothing are refused; with `config.local.toml` in play, Remove Agent could leave the config with an error, an agent made while that file lists
  the agents could not be given its options, and Undo could not find the file; a second click on a minus took out two arguments; a field that kept the focus wrote old text back.

## 0.3.4 (2026-10-16)

Data-loss and trust problems of the config editing in 0.3.3 are fixed here, and the window gets its next two editors.

### Agents and the default apps, in the window

- A new section, Agents: the agents the Finder menu offers in the order it lists them, to drag, check and uncheck (the rest are listed below it), with the command that starts each and the doctor's word when it is not
  found. "Start agents without asking" is a switch that asks first and says what each agent would be started with.
- On the Overview the default terminal and the default editor are menus (with "Automatic", which takes the setting out of the config), and a terminal that has tabs and splits (Ghostty, iTerm) says where a session
  opens. A terminal that only opens a folder says it cannot start agents.

### Fixes

- Editing the Finder menu on a Mac whose `config.local.toml` has `disabled = [...]` removed or moved another line of the shared file; and an edit made while something else changed the list landed on another item.
  A change by place is now refused unless the list is what the window showed, and the window says so and reads again.
- Config page: leaving it threw away what was typed; a refresh let Save overwrite a change made meanwhile; Apply on a proposal's card applied against a file the card had not shown; Undo in the editor after a
  Revert could raise or garble the text; a text over 1 MiB could be saved and made the config unreadable. Quitting with unsaved text asks.
- The note "Moved X, Undo" took back the newest change of the file, not X; a read that started before an edit put the old rows back.
- An assistant could make an agent stop asking by taking out the per-agent `bypass_permissions = false`, or an argument that keeps it in a sandbox: taking out, removing and moving a program setting now wait for the
  person, and so does any change after which an agent that asked before no longer asks.
- U+202E, a zero-width space and tag characters were drawn raw on the card of a proposed change; they are written as escapes in summaries, diffs and error lines.
- `rh config add menu.items presets` on a config that does not write the menu left a menu of one item; adding to, taking out of and moving in the default lists now starts from the default (`menu.items`,
  `copy_path.styles`, `services.items`). Two `rh config` calls at the same time could delete the wrong items; a name is now looked up under the lock. An assistant's proposal that names an entry by its
  place (`app.1.bundle_id`) is refused, not applied to another entry, when the apps were reordered meanwhile.
- Config files: a line of a multi-line string that starts with `#` was taken for a comment (a key set after it ended up inside the string); a comment block that stands apart after an entry went with it;
  a CRLF file got line feeds among its lines and lost the comment of an item that was removed; a byte order mark was dropped; the history of two configs in one folder was shared; an edit went on without
  its lock (a linked `.config.lock`) and into a read-only file; a failed write cost the oldest history entry; undoing the first edit of `config.local.toml` left an empty file.
- The Finder extension's toolbar menu was never built again, a menu with no entries left was still served, and a warmup could put an old menu over a newer one.

## 0.3.3 (2026-10-16)

The Finder menu appears without the second of waiting, has no empty rows on macOS 26, and can be edited in the window. The
config can now be changed from the window, from `rh config` and by an AI assistant's tool, all through one editor that keeps your comments.

### Finder menu

- The menu showed the Right Here entries about a second after the click (macOS 26.5.1). An app's icon from `NSWorkspace` holds every size of itself (about thirty, tens of megabytes), and the
  menu is sent to Finder with its images: they are now one small bitmap each (a thousand times lighter), and a menu that has grown old (30 seconds) is served at once while a new one is built in the
  background instead of being built on the click (ADR 0027).
- On macOS 26 Finder drew each separator of the menu as an empty row: the menu, the setup window's preview of it, and the "Open With" submenu go without separators there. Separators stay on macOS 27
  and in the config, and the menu editor still lists them.

### Edit the menu and the config in the window

- The Finder menu page has Edit Menu: the lines become rows with a check box and a grip. Drag a line to move it, uncheck it to take it out (it shows up under "Not in the menu", where a check puts it
  back), and add the rest (each Copy Path style, a preset, an app, a separator) from the Add menu. Each change is written to the config file at once through the same editor as `rh config` (the smallest edit,
  comments kept), says what it did with an Undo button, and goes to `config.local.toml` when this Mac's own file lists the menu. VoiceOver and the right-click menu move a row up and down (ADR 0026).
- The window has a Config page: the settings file as text in a plain editor (no smart quotes), with what the config says about the text as it is typed (errors stop a save, warnings do not),
  Save refused when the file was changed while the text was being edited, and the same page for this Mac's own `config.local.toml`; the changes an AI assistant proposed that wait for you, each with
  the diff it would make, Apply and Dismiss (the Overview says one is waiting, and the sidebar row has a number); and the latest changes, whoever made them, with Undo for the newest.

### `rh config` and the MCP tools

- `rh config set`, `unset`, `add`, `remove`, `move`, `get`, `undo` and `history` change the config file without opening it: the smallest edit that does what was asked (every other byte of the file stays, comments
  included; a comment above a list item or an entry travels with it), checked before it is written, under a lock, through a link when the config is one, with the text before it kept so that `rh config undo`
  puts it back. `--dry-run` shows the diff, `--local` changes this Mac's `config.local.toml`, `--json` is for scripts. A value is taken as it is, never read by a shell or as TOML.
- The MCP server has two more tools, `right_here_config_get` and `right_here_config_edit`. An assistant may change most settings by itself, with the same editor. A setting that decides which program starts or
  switches an agent's permission prompts off (an agent's command and arguments, an app's bundle identifier, `bypass_permissions`) is not changed on its say-so: it is kept as a proposal, which `rh config pending`
  lists and which you apply or dismiss there or on the Config page. An assistant takes back only its own last change, and at most twenty proposals wait.

### Smaller changes

- `script/verify_mcp_protocol.py` starts the MCP server in a trial home and checks what it answers (initialize, `tools/list`, the read-only tools, `ping`, the errors) against the protocol's
  own JSON Schema for each of the four protocol versions it claims: it is conformant on all four.
- The launch flags of the terminal adapters were read against each terminal's own documentation (ADR 0025): none of WezTerm's, kitty's or iTerm2's is wrong. Alacritty, which was handed the
  folder with `open` although it declares no document types (so a window could open in the wrong folder), now has an adapter of its own that starts it with `--working-directory` and, for an
  agent, `-e` (it joins the terminals that can run commands). kitty is started with `-o macos_quit_when_last_window_closed=yes`, so a launch no longer leaves an idle kitty and its Dock icon
  behind. None of the three has been run on a real Mac.
- JetBrains Fleet was removed from the catalog of built-in editors; the bundle identifiers of the other built-in terminals and editors were checked against Homebrew's cask
  metadata (ADR 0024), the update path is documented for the mishap of two copies of the app (README, troubleshooting).

## 0.3.2 (2026-10-16)

A patch release: the setup window and `rh setup` on a first run, a login shell that says nothing, the built-in agents checked against their own documentation, and
words that now agree with macOS and with what the app does.

### Setup and the window

- Install or Repair on a Mac that has only the per-machine overlay no longer makes `config.toml` from what it found. A look at the Finder extension's registration is stopped after twenty
  seconds and says "pluginkit did not answer" (before, a stuck daemon held the window's first look, the doctor and the setup for ever); `rh uninstall` says "Unregistered" only when macOS did;
  coming back to the window reads the Mac again at most every twenty seconds (each read starts your login shell); a failed setup is shown until the next read of its own, and no longer
  next to a config that somebody else has made meanwhile; the window keeps looking at the Finder extension after it is on (every half minute), so switching it off again brings the
  first-run card back.
- `rh setup` without `--agents` says so when the login shell said nothing about the agents (a config with no agents was made without a word). `rh docs` and the refusal of the real-home
  guard say how to leave `RH_NO_UI` out.

### A login shell that says nothing

- A login shell that says nothing (a startup file that exits, such as an `exec tmux`, or one that waits or is slow) is no longer taken for one that did not find the agents: `rh doctor` and the
  Checks page say "did not say whether it is installed", `rh agents` leaves the command unlisted as found or not found, and the dry-run note of `rh run` does not claim "command not found".
- The question put to the login shell (which agents are installed, what is on the `PATH`) no longer loses its first line to a startup file that prints a word without ending the line
  (`printf Welcome` in `.zshrc` or `config.fish`: with fish 4.9 the first agent was read as `Welcomeclaude`, so it was not found), and a word a startup file prints can no longer pass for an
  agent that was asked about only because it was printed.

### The built-in agents

- The catalog was read against each tool's own documentation (ADR 0024) and what was wrong is corrected: Gemini CLI starts on a first prompt with `-i` and skips its approvals with
  `--approval-mode=yolo` (its `-y` is documented as deprecated); GitHub Copilot takes its prompt with `-i`; Kimi Code's `-p` ran the prompt once and exited, so it has no first-prompt flag,
  and its approvals flag is spelled `--yolo`; Goose is started with `goose session` (a bare `goose` prints its help) and has no prompt, continue or bypass entry; Muse Code, whose documentation
  names none of them (`--auto-approve` does not exist), has only its command; Cody is no longer built in.
  Presets are offered for five agents (Claude Code, Codex, Antigravity, Gemini CLI, GitHub Copilot); GitHub Copilot and Kimi Code get the continue and resume entries their documentation
  names. The first run looks an agent up by the first word of its command, and the `instructionFile` field of an agent, which nothing read, is gone.

### Words

- Where the app tells you to go in System Settings, the names are the ones macOS shows: System Settings in Malay ("Seting Sistem"), Login Items & Extensions in Arabic, Brazilian Portuguese
  and Turkish, and the Keyboard, Keyboard Shortcuts and Services panes in Indonesian, Romanian, Thai, Turkish and Ukrainian. Arabic Finder is "فايندر" in Reveal, and the Open With submenu
  is called what Finder's own is in Traditional Chinese. `script/verify_macos_wording.py` (which CI runs, and which now reads these paths too) found them on macOS 26 and 27; the site's
  strings were checked the same way.
- The privacy policy says what the app does: it also reads the Finder selection when you or an AI assistant ask for it (`rh finder`, the MCP tool), sends Apple events to Finder then,
  starts your login shell to look for agent commands, and looks for its own extension's crash reports; its paragraph on the source code no longer says the code is public.

### For AI agents and the docs

- The playbook for AI agents (`rh docs agent-setup`) and the plugin's setup skill tell an agent to report, and not only to ignore, a name or a message that reads like an instruction to it:
  tried on a config whose terminal's name asks for a forced setup (ADR 0020). The playbook says the command link is for your terminal and the runner script is what
  Finder needs. The setup evaluation has a fifth persona.
- `rh docs sync`, the design notes and ADR 0013 list what the sync guard lists (an agent's `args` and `bypass_permissions` too); the troubleshooting guide has entries for the window that
  says to move the app and for a login shell that says nothing about the agents; the mutation check can be asked `--check` (the gate does) whether every pattern still matches.

## 0.3.1 (2026-10-16)

Fixes to the first run in the app, as a person doing a first setup meets it, and to what an AI assistant is told about names from a config.
To update from 0.3.0: drag the app over the old one in Applications, open it and press **Install or Repair**.

### Highlights

- **The first run says what went wrong, where you look.** A Set Up that does not come out is shown above the choice (you used to see the same page and a footnote in the corner),
  and an app that runs from the disk image or another volume says so before you press anything, and waits for you to move it to Applications.
- **Nothing makes your config behind your back.** Install or Repair and Open Config are not offered before the window has looked at your Mac, and they never make the config
  from what they find: Set Up makes it, from your choices.
- **"Everything is set up" can be reached.** A command link whose folder is not on PATH, a Claude Code terminal link without its handler and a choice of no agents are
  notes on the Checks page and no longer a reason for "Some checks need your attention". The fixes there name the button to press, not a command to run.
- **VoiceOver** hears the result of an action and how the setup stands, and the sections and steps say what they are.

### Fixed

- The first-run choice and the window around it:
  - A config that is a link to a file that is not there (a dotfiles manager before its repository is cloned) is no longer offered as a first run.
  - A Finder extension that is registered and not switched on is called that, and no longer "not registered, install Right Here.app".
  - `rh setup` no longer says it removed a stale extension registration that macOS refused to remove.
  - The window reads your Mac again when you come back to it (from System Settings, an editor, or a terminal where an AI assistant ran `rh setup`).
  - "What Right Here set up" says the Finder extension is "registered but switched off" while it is, and step 3 of the first-run card points to the test on the Checks page
    instead of a button that could only fail while the extension is off.
  - When the login shell says nothing about which AI agents are installed (a startup file that exits, a shell that is slow to start), the first-run choice says so instead of
    showing every agent as "not found" and setting up with none.
  - The window stops looking at the extension every two seconds when it is minimized, hidden or covered; a `pluginkit` call that changes something is stopped after 30 seconds
    instead of holding the setup lock; quitting the app waits for the one second in which the launch test has the extension switched off.
  - The README and the release steps named a Set Up button that an updated app, which has a config, does not show; it is Install or Repair.
- The MCP tools mark two more texts from the config as data for the agent that reads them: the permission-bypass flag of an agent (`right_here_catalog`) and the file extension
  of a new-file template, which names the icon in `right_here_menu`. The structured data stays plain.
- `rh setup` and `rh doctor` no longer print the marks that tell an AI agent which words are data (`⟦user⟧Ghostty⟦/user⟧`) to a person at a terminal; a pipe and the JSON keep
  them (ADR 0020).

### Changed

- The setup window has a test target for its model (`Sources/AppModel`, `Tests/AppModelTests`), and ADR 0023 says what it says before it tries and what it calls attention.
- `rh` refuses to change the real home folder (the runner script, the command link, the Quick Actions, the extension's registration) when a test started it (`RH_NO_UI` set)
  without a trial home (`RH_HOME`), and the mutation check stops at the first mutant that changes it, because a mutant that removes a protection can make a test set up
  the Mac the check runs on (ADR 0022). It changes nothing for a person who runs `rh`.

### Known limits

- Only Ghostty and Terminal have been tried as terminals. iTerm2, WezTerm and kitty are built in and not verified on a real Mac (`rh doctor --probe-launch` checks yours).
- That removing the directory-observing overrides ends the Finder extension's crash on macOS 26.5.1 is not yet confirmed there. If the menu is still empty,
  `rh doctor` names the crash report to attach to a bug report.
- The setup window's first run, and its card updating when the extension is switched on, were rendered and tested (the model with a made-up Mac) but not yet tried by a person
  in a real window (`docs/development/MANUAL_CHECKS.md`).
- A few sentences of the setup window are English in every language: what a step of the setup says when it was skipped or failed, the edits it lists for an existing config
  and the report's warnings.

## 0.3.0 (2026-10-16)

Everything since 0.2.0.

### Highlights

- **Set it up in one step.** `rh setup`, or the app's first run (press Set Up), makes the config from what is installed, connects Finder and says what is left for you;
  or hand it to your AI assistant: **Copy Setup Prompt for AI** in the app, or `rh docs agent-setup`.
- **Two problems of 0.2.0, fixed:** the setup window no longer says `~/.local/bin` is missing from your PATH when your terminal has it, and the Finder extension no longer
  overrides the methods that crashed on macOS 26.5.1 (not yet confirmed there; `rh doctor` now tells you if it still crashes).
- **Agents in isolated git worktrees**, pinned and recent folders, six more built-in agents, and many hardening fixes.

### Added

- `rh setup` puts everything in place in one command and can be run again at any time: the config file, the runner script, the `rh` link, the
  Quick Actions and the Finder extension, then the checks, and it says what only you can do. `--terminal`, `--editor` and `--agents` say what you
  use instead of editing TOML (also on `rh init`), `--dry-run` shows the plan and `--json` is the report for an AI agent. A config that exists is
  never rewritten: the report lists the edit to make. The setup window's first run offers what is installed and runs the same setup (ADR 0018).
- `rh docs agent-setup` is a procedure for an AI agent (ask the person first, look with a dry run, make the edits an existing config needs, run
  setup once, tell the person what only they can do, check, hand back), and the prompt the app copies and the plugin's setup skill follow it. It
  was tried with cold agents on three personas (`docs/development/SETUP_EVALUATION.md`). `rh docs start` and `rh docs mcp` are new guides.
- Isolated git worktrees for agents: `rh worktree list|add|remove`, `rh run --worktree` and `--branch`, and the MCP tool `right_here_worktree`
  (ADR 0016). Worktrees are made under `.right-here/worktrees`; Right Here removes only the ones it made, the MCP tool never forces a removal, and a
  branch is deleted only when it is merged.
- Pinned and recent folders: `rh pin`, `rh unpin`, `rh pins`, `rh recents`, the MCP tool `right_here_bookmarks` and the setup window's Folders
  section. They live in `state.toml`, readable only by you; a pin is an absolute path.
- Agents: Antigravity (`agy`), Kimi Code, Muse Code, Goose, GitHub Copilot and Cody are built in (twelve in all). Starting an agent with its own
  permission prompts off is a launch option (`general.bypass_permissions`, `[agent.<id>] bypass_permissions`, `args`; `rh run --bypass-permissions`,
  `--safe`, `--arg`), off by default and never for a preset. The doctor, `rh agents`, `rh menu --explain` and the plan say when it is on, and the sync
  guard lists it.
- Terminals: WezTerm and kitty adapters (not verified on a real machine) and split placements for Ghostty and iTerm2
  (`terminal_placement = "split-right"` and `"split-down"`).
- `rh doctor --report` (versions, the doctor's rows without anything the config says, the home folder as `~`), `rh run --language` (so Shortcuts names a new file in the person's language),
  and a warning from `rh doctor` when the Finder extension has crashed since it was installed, with the newest crash report's name.
- The setup window is rebuilt: six sections (Overview, Finder menu, Checks, AI Assistants, Worktrees, Folders), every text in the thirty-language
  catalog, and a check that fails the gate when a view shows a literal. The preview script renders each section (`--tab`).

### Changed

- `rh install` now repairs one named piece (`--skip-finder` is gone), and the doctor's fixes say `rh setup`.
- `rh run`: a plan's text is never cut and every value in it is a JSON-quoted string; a refusal names the file or folder at fault; options that
  would do nothing (`--bypass-permissions`, `--safe`, `--arg`, `--worktree`, `--branch` on an action that is not an agent) are errors;
  `--worktree --dry-run` plans without creating anything and a failed run leaves no worktree behind; a misspelt command gets a did-you-mean.
- The doctor's row for the Services workflows is called Quick Actions, as the rest of the window says. The Claude Code link handler is warned
  about only where something starts Claude Code through the link.
- The version comes from one place, `AppIdentity.version`, which `script/verify_version.py` checks against the project, the changelog and the
  Homebrew files. The cask has the checksum of the v0.2.0 DMG; the App Store upload uses an API key and no password; the App Group is gone.

### Fixed

- `rh setup` and a config it cannot use: a config that does not parse, cannot be read, or is a link to a file that is not there made setup say
  "ok" (the edits were worked out from the defaults, the Quick Actions were made from them, and the person's choices were dropped). The config
  step now fails and names the file and the line, no edits are listed and no Quick Actions are made, the other steps run, the status is 1, and
  the report tells an AI agent to leave it to the person (or to let the agent make the smallest edit that makes it parse).
- `rh setup --dry-run --json` said `created` and "created (...)" for what it only planned; a step's outcome in a dry run is `would-create`,
  `would-update` or `would-fail`, and its text is the dry-run wording.
- The edits `rh setup` lists for an existing config work when they are made to the letter: a `[general]` written inline is changed in place (it
  was said to lack keys it has), a file without a `[general]` table gets one edit for the whole table (three edits made three tables, which is a
  syntax error that threw the whole config away), and a setting that a `disabled` list in `config.local.toml` turns off is traced to that list.
- Two setups at once (the setup window and a terminal, or an AI agent's) took away each other's Quick Actions and one of them failed: setups take
  turns now, and each Quick Action is replaced in one step (ADR 0021). Twenty `rh pin` at once kept twelve; the state file is changed in one step.
- An empty `RH_HOME`, `RH_CONFIG`, `RH_CONFIG_DIR` or `RH_LOG_DIR` is refused (status 64) and no longer means "not set": `RH_HOME=$TRIAL rh setup`
  with `$TRIAL` unset was a setup of the real home, and `rh uninstall` took the same value for a trial and removed the real home's files.
- `rh worktree list|add|remove` and `rh run --worktree` refuse a folder that does not exist and name it (a typo was replaced by the repository
  around it, and `rh worktree add --folder <typo>` made a worktree and a branch); a misspelt subcommand that is taken for a folder says so
  (`Did you mean "rh worktree add"?`).
- The setup window shows the edits that apply what the person chose when a config was there already, and the report's warnings; it showed neither.
- Finder extension: on macOS 26.5.1 it crashed each time Finder asked it to watch a folder, so the context menu showed none of its entries while
  every doctor check passed. It no longer overrides the directory-observing methods, which did nothing (ADR 0019); that this fixes it has not yet
  been confirmed on 26.5.1.
- Finder extension: it no longer keeps the Mac from sleeping, its menu cache expires after 30 seconds (it never did), and its warm-up no longer
  races the main thread (ADR 0015).
- The check for the `rh` link no longer tells a person to put `~/.local/bin` on their PATH when a new terminal already has it (the setup
  window and a program an AI assistant starts have launchd's PATH, which says nothing about a terminal). It asks the login shell, reads the folder
  however it is spelled (trailing slash, `.` part, symbolic link), and says "did not say" instead of "not on PATH" when the shell gives no answer.
- The AI Assistants section shows `rh setup` as code, without its backticks.
- Worktrees: a repository is somebody else's code, and its own files made git start programs while Right Here made, checked or removed a worktree: filter
  drivers in an included file or in `config.worktree` (and one whose name has an equals sign), `core.fsmonitor` and hooks for `worktree remove`, `status` and
  `branch -d`, hooks that the configuration names (git 2.54), and a promisor remote's `ext::` transport or `core.sshCommand` during the checkout of a partial
  clone. Every git command goes through one function that switches all of that off, the list of worktrees is read NUL-separated, and the commands that only read
  stop after twenty seconds (a named pipe in `include.path` held them for ever); a repository with a conditional include of its own (`includeIf`) gets no worktree. The Finder extension's runner script passes on only the shapes the extension sends,
  so a compromised extension cannot start an agent with its prompts off or with a prompt of its own (ADR 0016).
- `rh doctor --report`, for a public issue, held what the config says (an agent's command, an app's name, the text of an error, the sync folder). It now holds none of it
  and says what it holds; its block closes whatever a crash report's name holds. `rh setup` and `rh doctor` fence what the config names in every sentence an AI agent
  passes on (ADR 0020), and names that something else wrote (a crash report, a folder, a worktree, git's words) are shown with the characters that draw nothing as
  escapes, in every line `rh` prints, in its JSON and in the setup window's list of worktrees.
- The doctor counts the extension's crash reports by the UUID of the code that crashed and not by the date the code was written, so a crash of the copy that was
  replaced is not held against the new one.

### Known limits

- Only Ghostty and Terminal have been tried as terminals. iTerm2, WezTerm and kitty are built in and not verified on a real Mac (`rh doctor --probe-launch` checks yours).
- That removing the directory-observing overrides ends the Finder extension's crash on macOS 26.5.1 is not yet confirmed there. If the menu is still empty,
  `rh doctor` names the crash report to attach to a bug report.
- The setup window's first run, and its card updating when the extension is switched on, were rendered and tested but not yet tried by a person in a real window
  (`docs/development/MANUAL_CHECKS.md`).
- A few sentences of the setup window that only show in rare cases are English in every language: the edits it lists for an existing config and the report's warnings,
  a config it cannot use, another setup running, and a config that is a link to nowhere.

## 0.2.0 (2026-10-14)

- Finder menu: a prebuilt menu for single folders (the first right-click no longer waits for a build), the extension stays loaded, facts and
  directory lookups are cached.
- A built-in iTerm2 adapter (AppleScript, 3.0 and later), more editors detected (Trae, Positron, Fleet, RustRover, CLion, GoLand), a new app icon,
  a setup window with its action buttons pinned at the bottom.
- Copy Path: a single configured style gets a short title.

## 0.1.0 (2026-10-14)

First version, running on macOS 26 and later (Apple silicon).

- `rh`: run actions (copy a path in ten forms, open a folder in a terminal or editor, start an AI agent in a
  terminal, create a file, reveal), preview the Finder menu, list actions, apps and agents, validate the config,
  check the setup (`rh doctor`, with probes that prove the Finder click chain and a typed terminal launch),
  install and uninstall, serve an MCP server.
- Finder: a sandboxed Finder Sync extension (right-click menu and toolbar item) and Quick Actions, both generated
  from one config; Ghostty and Terminal.app adapters (new window, or a new Ghostty tab); agents typed into your
  own login shell, with Claude Code, Codex, Gemini CLI, opencode, aider and Amp built in and any command addable.
- A plain-text TOML config with a schema, unknown-key suggestions, `--strict` validation and a JSON Schema.
- The setup window previews the Finder menu as the extension builds it from your config (the same code, the same
  icons, submenus that open in place), so you see what you get before the extension is switched on.
- A setup app, thirty languages for the menu, the app (its list of checks: `rh doctor --json` gives each
  detail and fix as a code, its values and the English text), alerts and the permission prompt (machine-translated,
  awaiting native-speaker review), a Claude Code plugin and `rh docs` for agents.
- Hardened through repeated independent reviews and a mutation check (`docs/decisions/0008-independent-review.md`)
  that removes each protection and expects a test to fail: shell quoting that holds against combining
  marks, one place that refuses any path that does not exist, bounded and budgeted MCP calls, a process runner
  that stops a login shell for good, an atomic claim for the probe request, parsers that refuse nesting deep
  enough to overflow the stack, and installs that keep the old Services and link when they fail halfway.
- Config sync: an optional per-machine overlay `config.local.toml` (merged by id, with `disabled`), and
  `rh config sync` (enable, status, pull, push, disable) that copies the config through a plain folder such as iCloud
  Drive, with refusals for local or remote changes, secrets and invalid files, atomic writes and doctor checks. The
  folder is not trusted with programs: a pull that would add or change a terminal template or an agent command is
  refused, with the list, unless `--allow-commands`.
- Config problems name the file and the line they are on, in the order of the file, and say what is wrong: a syntax
  error says what it is (an array that is not closed is reported at the line where it opened), a value of the wrong kind
  says what it is (`expected a string, found an integer`), a choice lists the valid values, a key in the wrong table says
  where it belongs, and a display name that is typed for an id (`Visual Studio Code`) finds it. With a `config.local.toml`,
  `rh config validate` also reads `config.toml` on its own, because other Macs do: an error the overlay hides on this Mac
  is still reported (and refused by `push`), and so is a key named like a credential, which `push` refuses. `rh config show` prints each file that makes up the config under a header
  naming it, and `rh config path --all` lists them. A config that cannot be read is an error naming the reason, names and
  titles with control characters are refused, and a launcher an agent cannot use is a warning.
- The sync folder is not trusted with time or memory either: a file in it (or this Mac's config) past 1 MiB is never read,
  and `status` says so; an unreadable local config is no longer taken for a missing one that a plain `pull` replaces; an
  empty `--folder` is refused; `push` says it creates only the last folder and how to make the parent; `status` advises
  nothing that `push` or `pull` would refuse; a shared preset left out because its agent is disabled on this Mac is a note.
- Terminals without a built-in adapter can be defined in the config (`open_args`, `run_args`); copied paths use
  the spelling the file system stores.
- The menu says what it leaves out: `rh menu --explain` lists, with the reason, the entries the config asks for that are
  not there (an app that is not installed, no file selected for the presets, an agent the overlay disabled) and the
  defaults another app replaced; `rh doctor` and `rh config validate` say when a config leaves the menu empty for a
  folder. A default terminal or editor that is not installed (a config shared between Macs) gives way to the first
  installed one, and the doctor names both; an agent that is set to start in its desktop app or by its link keeps a
  typed launch in the default terminal under More Agent Options; Agent Presets are not offered for a selection of only
  folders; a new file is never handed to the system's default app when no editor is installed; each element of a
  variant's `arguments` is typed as one quoted argument.
- Verified: the whole chain after a menu click on a real Mac; real-shell round trips of quoting; a notarized,
  stapled DMG. Not yet verified: a real Finder click (see `docs/DESIGN.md`, section 5, Open).
