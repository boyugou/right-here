# 0026: One config, two editors: the window and the agents can change the same things

Date: 2026-10-16. Status: decided; built in stages 1 to 10 (2026-10-16 to 2026-10-22), each recorded below under "As built".

## The goal

1. **Whatever an agent can configure, a person can configure by hand in the app.** At 0.3.2 an agent edited a text file and the window was a viewer.
2. **Whatever a person can set in the app, an agent can configure too.** The two are one contract, not two features.
3. **A what-you-see-is-what-you-edit editor.** Some settings are naturally a toggle; the rest should be a page you can edit in place: drag to order (the natural way to arrange a menu), click a title or a prompt to change it, no separate preview pane. This costs real design and implementation.
4. **No backward compatibility.** The config format, key names, ids and `state.toml` may change when the editor needs it, and a person may have to set up again (CLAUDE.md hard rule 8).

## Where the product stood (0.3.2)

The window could set up (first run: terminal, editor, agents), repair, run the launch test, copy the assistants' snippets, remove worktrees, and unpin or clear folders. Everything else that was
configurable was only in the text file: the window's Overview had **Open Config**, which opened it in a text editor. The Finder menu section was a faithful preview of the real menu (it was
built by the code the extension uses) and was read-only.

| Area (config keys) | Window | CLI | MCP | Agent |
| --- | --- | --- | --- | --- |
| Default terminal and editor (`general.terminal`, `general.editor`) | first run only | `rh setup --terminal/--editor` before a config exists | none | edits the file |
| Placement, prompts-off default (`general.terminal_placement`, `general.bypass_permissions`) | no | no | no | edits the file |
| Agents offered and their order (`general.agents`) | first run (no order) | `rh setup --agents`, first run | none | edits the file |
| One agent (`[agent.<id>]`: command, args, launcher, terminal, variants, prompt flag, prompts off) | no | no | no | edits the file |
| Finder menu: what is in it and in what order (`menu.items`) | preview only | `rh menu` (preview) | `right_here_menu` (preview) | edits the file |
| Quick Actions (`services.items`) | no | `rh install --services` (builds them) | none | edits the file |
| Copy Path forms and title (`copy_path.*`), new-file templates (`new_file.*`) | no | no | no | edits the file |
| Extra apps (`[[app]]`), prompt presets (`[[preset]]`) | no | no | no | edits the file |
| One config on several Macs | no | `rh config sync …` | none | CLI |
| Pinned and recent folders (`state.toml`) | list, unpin, clear (no pin, no order) | `rh pin/unpin/pins/recents` | `right_here_bookmarks` (read) | CLI |
| Setup and repair | Set Up, Install or Repair | `rh setup/install/uninstall` | none | CLI |

The distance was large on both sides: the window edited almost nothing, and an agent that is not allowed a shell (MCP only) edited nothing at all. An agent that has a shell hand-edited TOML against
`rh docs config` and `rh config validate`, which worked and was error-prone.

## Decision

- **D1. One source of truth: the config file.** `config.toml` (and the per-machine overlay) stays plain text that a person or an agent can read and edit, and the window keeps no second
  store of settings. Alternative: a structured store (JSON, plist) with the text file generated: rejected, because the plain-text config is what agents edit well and what a person can read,
  and a second store is where parity would go to die.
- **D2. One editing core.** A `ConfigDocument` that applies *minimal, format-preserving* edits to the file (set a value, add or remove an element of an array or a table of an array of tables,
  move an element, rename an id), validates the result against the schema before it writes, and writes atomically against the file as it is at that moment (an agent may have changed it a
  second ago). The window, `rh config …` and the MCP tool all call it. Alternatives: rewrite the whole file from the model (loses the person's comments, order and layout, and makes the app
  the file's owner); each surface patches the text itself (three implementations of the hard part). TOMLDecoder only decodes, so the editor is ours: a tokenizer that knows strings,
  multi-line arrays, comments and tables (a comment directly above an array element travels with it when it is moved).
- **D3. Parity is a tested contract, not an intention.** A registry lists every leaf of the config schema with how the window edits it (toggle, picker, list, text, or "raw only", with the
  reason). A test fails when a schema key has no entry, and when a control writes a key that `rh config set` and the MCP tool cannot set. A new setting cannot ship without a place for
  a person and a way for an agent.
- **D4. Direct manipulation where composition is the point; the plain control where it is not.**
  - *The Finder menu is edited where it is previewed*: rows drag to reorder (`menu.items` is an ordered list of ids, "-" for a separator), a row's toggle takes it in or out, "+" adds from the same
    catalog as `rh actions`, a row that is the person's own (a preset, a template, an extra app) renames in place. Because the preview is built by the extension's own code, what is drawn is what
    Finder shows.
  - *Lists whose order is the setting* are the same control: agents (`general.agents`), Copy Path forms, Quick Actions, presets, pinned folders.
  - *Toggles, segmented controls and pickers* for booleans, enums and "which installed app"; an `.app` dragged onto the extra-apps list fills in its bundle identifier.
  - *Click-to-edit text* for titles, prompts (with `{files}` and `{folder}` as chips) and arguments (a token list).
  - *"Edit as TOML"* per section is the escape hatch, so that nothing is unreachable in the window and the first slice is complete from the day it ships.
  Move up and move down are always offered next to dragging (VoiceOver and keyboards).
- **D5. An agent changes settings with the same operations.** `rh config get`, `set`, `unset`, `add`, `remove`, `move` (each `--dry-run` and `--json`, each validated), and an MCP tool `right_here_config`
  (get, and set with `dry_run` that returns the diff). The rule of ADR 0013 applies to what is written: a key that decides which program starts, or switches an agent's permission prompts off
  (`command`, `args`, `open_args`, `run_args`, `bundle_id(s)`, `bypass_permissions`, `bypass_permission_arg`, variant `arguments`, `prompt_arg`, an app's `role`), is *proposed* by an agent, not
  applied: the change waits as a pending proposal that the window shows as a card (what, where, the diff; Apply or Dismiss) and that `rh config pending apply` applies, after the person has looked.
  Everything else an agent may apply; the window shows what changed and from where.
- **D6. Changes are recorded and can be undone.** Every write through the core keeps the previous text (the last N states, with who made the change: window, CLI or MCP) so that the window can say
  "Claude Code changed the menu" and offer Undo, and `rh config undo` does the same.
- **D7. No backward compatibility.** If the editor is better served by another key name, another layout of `[menu]`, or a changed `state.toml`, the file changes and `rh setup` makes it again; no
  migration code, no deprecated aliases, no tests that keep the old shape.

## What this changes in earlier decisions

Right Here has promised that the app never rewrites the config (ADR 0004, "TOML config, never rewritten by the app"; ADR 0018 item 3, "a config that exists is never rewritten"; DESIGN section 3 on the
config; the README; the website; the playbook and TROUBLESHOOTING on `rh setup`; the help of `rh setup` and `rh init`). The reason was sound: a tool that
rewrites a file the person edits by hand loses their comments and order. This direction keeps the reason and drops the absolute:

- **Setup, repair and sync still never rewrite a config that exists.** They say which line would change and leave it to the person (ADR 0018 stands for them).
- **An edit the person asks for, in the window or with `rh config …`, is made in place:** the smallest change that does it, every other byte of the file as it was, the previous text kept (D6).
  An agent's `rh config` call is the same operation, and the playbook may then tell an agent to use it instead of hand-editing text.
- With the first slice the promise became "changed only when you ask, in the smallest way, with an undo": DESIGN.md says so, and ADR 0004 has a note that points here.

## What was considered

| Option | Verdict |
| --- | --- |
| Keep the window a viewer and improve the docs | Rejected: it leaves agents the only editors |
| An in-app text editor for the whole file with live diagnostics | Kept as step 2: complete parity at a small cost, but it is not WYSIWYG |
| Rewrite the file from the model on every change | Rejected (D2): comments and layout lost |
| A second settings store the app owns | Rejected (D1) |
| Let an agent apply program-defining changes directly | Rejected (D5): a prompt-injected agent could start any program on the next click |
| A web or Electron editor | Rejected: the window is native SwiftUI, previewed headlessly |

## Cost and risk

- The window grows from a viewer to an editor: it will want two places (Setup: first run, checks, repair; Settings: the editors), or a clear split inside one window.
- Every control's label and help is a string in 30 languages (the translation and verification pipeline exists; it is a cost per control, not a new kind of work).
- Drag and drop cannot be exercised by the headless preview or by `swift test`. The model behind it can: every operation (move, toggle, rename, add, remove) is a pure edit of the text, tested
  against the text, with property tests that an edit leaves every other byte alone; the interaction itself goes on the list of manual checks.
- Concurrency with an agent that edits at the same time is handled by editing the file as it is and writing atomically (D2), with a retry when it changed under the edit.
- A format-preserving TOML editor is real work; the schema registry (D3) and the `config` commands (D5) do not depend on the window and
  pay for themselves at once, because agents stop hand-editing text.

## Staged plan

1. **The core and the contract, no window yet:** `ConfigDocument` with its tests; `rh config get/set/unset/add/remove/move/undo`; the MCP tool `right_here_config`; the parity registry and its test;
   the pending-proposal store and `rh config pending`. Agents get structured editing first, and the window will sit on the same code.
2. **A Config page in the window:** an editor for the file with live diagnostics (`ConfigDiagnostic`), per-section "Edit as TOML", the pending-proposal card and the change history. Every key reachable.
3. **Direct manipulation, in this order of value:** the Finder menu (drag, toggle, add, rename), agents (toggle, order, one agent's options), general (pickers, toggles), presets, extra apps (drop an
   `.app`), Copy Path forms and Quick Actions, pinned folders (drag order, pin from the window).
4. **The rest of the symmetry:** MCP tools for pin and unpin, for setup and repair (dry run, then apply), for the sync settings; the menu preview gets "as the extension would show it for a selection of N files".

## As built, stage 1 (2026-10-16)

- **The editing core** is `ConfigDocument` (pure): set, unset, insert, remove and move an element of a list, add, remove and move an entry of a list of tables. It edits the bytes it was asked to
  and no others (a comment above an element or an entry travels with it), refuses a text that already has an error, an unknown key, a value of the wrong kind and any change after which the
  config has an error, and is held to that by a seeded random-edit test that checks the file against a model after each of 80 edits (the layout too: a list written on one line stays on
  one line). The per-machine overlay is edited with the same core, read as laid over the shared file (`ConfigDocument.Validation.overlay`).
- **One vocabulary:** a `ConfigRequest` (a verb, a setting, values or an item named by its text or its id) becomes `ConfigOperation`s against the file as it is now; `rh config` and the MCP tool
  both build one, and the window will build `ConfigOperation`s directly, since a drag knows the places.
- **`ConfigService`** (Kit) applies operations under a lock (`.config.lock`) against the file as it is at that moment, writes atomically through a link when the config is one, and keeps the text
  before each edit in `.history` (the newest fifty per file, with who made it) for `rh config undo`, which refuses a file that was changed after the last edit unless forced. Several operations
  are one edit and one undo. Nothing is made for a config that does not exist: `rh setup` makes the first one.
- **The line between the person and an assistant** is the actor. The command line (`.cli`) and the window are the person, or a shell the person gave an agent, and an agent with a shell can edit
  the file by hand anyway, so they are not stopped. A call of the MCP tool (`.mcp`) is: what `ConfigTrust` lists as deciding which program starts or switching prompts off (an agent's
  `command`, `args`, `prompt_arg`, bypass options and variant `arguments`, an app's `bundle_id(s)`, `role`, `open_args` and `run_args`, a new-file template's `contents`, and `bypass_permissions` set to true) is stored as a proposal in
  `.pending` and applied by the person with `rh config pending apply <id>` after `show <id>`. Taking something out, moving it, and values that cannot start anything are not stopped. An
  assistant takes back only its own last change. Every setting of the schema is decided in `ConfigTrust`, and a test fails for one that is not. A preset's `prompt` is deliberately not on
  the list: it is text for an agent that asks before it acts (presets keep their prompts on), and adding presets is the main thing an assistant is asked to do. A template's `contents` is on it,
  since a review found that `right_here_run new-file.<id>` takes the folder from whoever calls it: an assistant that could only call tools wrote a login item into `~/Library/LaunchAgents` with a
  template of its own (a new file is never written over an old one, but a new file is all a login item needs). The file name and extension of a template stay plain; the config holds them to what every
  name is.
- **Limits:** at most twenty proposals wait, a proposal is forgotten after a week, a change that cannot be made is refused at once and not proposed, and an MCP edit costs one unit of the
  server's per-minute budget, so that a loop cannot fill the history that undo reads.
- **The Finder menu editor** (the first direct editor of stage 3): `MenuBuilder.entries` says what each item of `menu.items` makes, `MenuEditor` (pure) turns that into rows and a catalog of what can
  be added and returns the `ConfigOperation`s of a drag (every drag of one or several rows is checked against SwiftUI's own `move(fromOffsets:toOffset:)`), a removal and an addition; the first change of a
  default menu writes the list first. The window applies them through `ConfigService` as `.window` in the file that decides the key on this Mac (`owner(of:)`), reads the menu and the rows again from
  the config without asking the doctor (which starts the login shell), and offers Undo. Drag and drop is drawn without the drag handlers in `script/preview_setup.sh` (`ImageRenderer` shows a drag
  source as a prohibited sign); the interaction is on the list of manual checks (6).
- **The Config page** (stage 2): the file as text in a plain `NSTextView` with every automatic substitution off, `ConfigDocument.Validation.problems` (errors and warnings with their lines) as the text is typed, a save as one
  `.replaceText` operation guarded by the digest of the text that was read (`editedMeanwhile` when the file changed under the editor), the proposals as cards with the dry-run diff and Apply/Dismiss, the history with Undo for the newest, and
  the same for `config.local.toml`. A whole-text replace is in `ConfigTrust` as a rewrite of the whole file, so an assistant's attempt would be a proposal. The sidebar row and the Overview carry a count of waiting proposals.
- **Left after stage 1:** the other direct editors (stages 3 to 9 below), the parity registry that ties each setting to a control (stage 3b), a doctor row for waiting
  proposals (the doctor has it now), MCP tools for pins and setup (not built).

## As built, stage 3b (2026-10-17): agents and the general settings, and what a review found

A review of stages 1 and 2 (the editing core and the service, the trust model, the window and the extension) found what an editor of a file shared with agents has to get right. These are decisions now.

- **A list is changed by place only on the list that was read.** The window's rows come from the config as this Mac reads it (an agent listed twice is one, and a per-machine `disabled` takes entries out), and the
  place of a row was applied to the file that decides the key: the wrong item went, in the synced file, with nothing visible on this Mac. `ConfigOperation.expect(list, in: key)` writes nothing and refuses the
  whole edit unless the list in the file is exactly what the window showed (`nil`: not written, which is not an empty list); every change by place starts with it (`MenuEditor`, `GeneralSettings`). The editors
  carry what the deciding file writes (`listed`), and offer nothing by place unless their rows are that list's items one for one (`isExact`, `agentsAreExact`); a note says to edit as text on the Config page then.
  Something else (an assistant, `rh config`, another window) that changes the list after the window drew it makes the change refused (`changedMeanwhile`, "something else changed this list"), and the window reads again.
- **The note of a change takes back that change.** The banner "Moved X, Undo" asked for the newest change of the file, whoever made it. `ConfigChange.afterDigest` is the digest of the text a change wrote;
  `ConfigService.undo(expecting:)` takes back that change and no other, and says so when it is no longer the last. A save on the Config page ends the note of an earlier edit.
- **A read does not put old rows back.** A read of the whole state takes seconds (the doctor starts the login shell); `SetupSnapshot.readAt` is when its config was read, and a read that began before the last
  change made through the window keeps the window's rows, menu and problems.
- **The Config page keeps what was typed.** Leaving the page and coming back keeps the draft; a draft is held to the digest of the text it started from, so a save never overwrites a change made meanwhile
  (the page says the file moved, and Revert reads it again); a text past what a config may be (1 MiB, which no reader accepts) is a problem and is not saved; quitting with unsaved text asks first.
- **Applying a proposal is held to the file the card showed.** `preview(proposal:)` gives the digest of the text its diff was computed against and `approve(... unchangedSince:)` refuses a file that is not that
  any more; the card is drawn again. (Request-based proposals, which would name an entry by its id instead of its place, are the next step of the same problem: ADR 0026 stage 4.)
- **A drop moves a row only if it carries what the window put in the drag** (a token per row): a drag that was cancelled, and text dropped from another app, move nothing. Rows move with Option and the arrow keys
  too, and with the right-click menu and VoiceOver's actions.
- **The trust model counts what a change does, not only what it writes.** Taking a program setting out, removing an item of its list and moving one wait for the person like writing one does (the per-agent
  `bypass_permissions = false` that keeps one agent asking, taken out, handed the agent to the general switch; an argument taken out may be the one that keeps it in its sandbox). The general switch taken out is
  the one case that can only make agents ask. And whatever the operations are, `ConfigTrust.approvals(changingFrom:to:)` reads the two files before and after: an agent that asked before it acted and does not
  after (or is started with another flag) waits (a per-machine `disabled` takes an agent's table, override and all, out of the merged config the same way).
- **What a person decides on shows no character that misleads the eye.** U+202E, a zero-width space and a tag character passed validation and were drawn raw on the proposal card. Summaries, diff lines and error lines
  are written with them as escapes where they are made (`ConfigOperation.summary`, `LineDiff`, the window's error line), so the window, the command line and the MCP answer agree. The history keeps at most 8 MB of text.
- **Agents (a section of the window).** The agents the menu offers, in the order it lists them: a grip, a check that takes one out, its icon, its name and the command that starts it, and what the doctor says if
  the command is not there; the agents it does not offer below, each with an empty check. The first agent enabled in a file that lists none writes the list; every other change goes by place under `expect`.
  The switch "Start agents without asking" asks first when it is switched on and says what each agent would be started with (its flag, "has no such flag and keeps asking", "keeps asking: its own setting says so");
  switching it off does not ask. Presets keep their prompts on, and the page says so.
- **The Overview names the default terminal and editor as menus.** "Automatic (Ghostty)" takes the setting out (an unset), so the first installed one is used again. A terminal says where a session opens (new window,
  new tab, split right, split down) only when it can: `TerminalAdapter.supportedPlacements` is Ghostty's and iTerm's, and Warp's window and tab (ADR 0025); the others open a window, and the card says when the config asks for more. A terminal that
  only opens a folder (Warp, cmux) says it cannot start agents. The cards read what the config says, not the doctor, so they follow a change at once.
- **A request is looked at under the lock, and a stored change keeps what it was for.** `rh config` and the MCP tool turned a name into a place before the lock was taken (two requests at the same time
  deleted the wrong items in 10 of 40 tries); `ConfigService.apply(request)` and `submit(request)` look at the file under the lock. A proposal that names an entry by its place
  (`app.1.bundle_id`) carries `expectEntry(id, at, in)`, and one that changes a list by place carries the list, so that Apply after a reorder is refused and not made for another entry. Adding to, taking out of
  or moving in a list the file does not write (`menu.items`, `copy_path.styles`, `services.items`) writes the list as it is first (`ConfigDefaults`), as the window's editors do, so that
  `rh config add menu.items presets` leaves the default menu and a preset and not a menu of one item.
- **What the files and the folder do to an edit.** The history is kept for each file (two configs in one folder, `RH_CONFIG`, could undo into each other); an edit is refused when the lock cannot be taken
  (a link in place of `.config.lock`: `FileLock` says nothing of it) or the file was made read-only; a failed write no longer costs the oldest history entry; a clock behind the newest entry no longer makes
  an edit spin; taking back the edit that made `config.local.toml` removes it. A file keeps its byte order mark; a file whose line breaks are all CRLF is edited as lines ended by line feeds and written
  back with CRLF (comments travel with their items, no line feed is put among the others, the diff is lines).
- **Comments and layout.** A line inside a multi-line string that starts with `#` is part of the value (set and add put their line inside the string before); a comment block that stands apart after an entry
  (blank lines around it) neither goes with the entry nor moves with it; the comments of a list that has no item, and the one on the line of its bracket, stay when the list is filled or emptied; a key
  written in quotes with a dot in it is not the setting it spells; an empty item is refused; the summary of a list is one line. `set` of a list still drops the comments inside it, which its help says.
- **The Finder extension's menu cache** is `FinderMenuCache` (tested): the toolbar's menu is built again by a warmup, a warmup that finds no entry leaves none served, and a warmup that began before a
  config change does not put what it read over a newer menu.
- **Parity registry (D3).** `ConfigParity` says for each setting of the schema which control changes it in the window, or that it is text on the Config page for now; a test fails for a setting that is not
  listed. The settings still text-only are the next editors: how an agent takes a prompt and its variants, presets, extra apps, the forms of Copy Path, the Quick Actions, new-file templates.
- **Window correctness is tested with the real service and the real window model** (`SetupModelSafetyTests`, with a Mac whose processes answer slowly), and 30 mutation entries remove each of the protections above.

## As built, stage 4 (2026-10-17): one agent's own options

- **A page per agent, inside the Agents section.** A chevron at the right end of an agent's line opens the agent's page (name for an agent of one's own, command, how it starts, its terminal, whether
  its permission prompts are off and the flag that does it, the arguments); "‹ Agents" or leaving the section goes back. Considered: a popover on the row (it cannot be drawn by the preview harness, so it
  could not be looked at without a screen, and a field in a popover loses its text when the popover is dismissed), and the options as a disclosure under the row (the rows would have different heights, and the
  drag arithmetic of `RowDrop` is one height). A page is also where later per-agent editors (variants, the prompt argument) will go.
- **A field makes its change when Return is pressed or the field is left, and gives it up on Escape** (`EditableText`). What it shows is read from the config again after every change, so that a change that
  was refused (an empty command) shows the saved text and an Undo shows the text it took back. A change is worked out from the options as they are when it is made, after the change that is running has ended
  (`SetupModel.settled`): a field that loses its focus as the person uses the next control makes its change while that control's change is made. `edit` drops a change that arrives while another is
  written, which is right for a line of a list (a double click) and would lose the second of two changes made by one person in a row; the page cannot be disabled meanwhile either, because that would take the
  focus from the next field. A test makes both changes at once and expects both in the file.
- **The arguments are a list changed by place under the same guard as the menu and the agents** (`AgentOptionsState.listedArgs`, `.expect`): a list that something else changed meanwhile is not changed in its
  place. A row is picked up by its grip alone (a drag inside a field selects text), and the arrow keys stay the field's.
- **"Start without asking" for one agent asks first**, as the general switch does, and names the flag; the choice is off for an agent that has no flag. "Always ask" and "Same as all agents" ask nothing.
- **A program of one's own is made whole.** `addTable` writes `[agent.<id>]` with its name and command at once (an agent that is not built in needs both, so setting the keys one after the other passes through
  configs that do not read), together with the entry in `general.agents` under the list guard, in one change and one Undo. The id is made from the name (lowercase letters, digits, dashes; never one that another
  agent or a built-in agent has). The command is a program, so an assistant that proposes the same change waits for the person (`ConfigTrust`).
- **A terminal the config names that cannot start agents** (Warp) is shown as the choice, as it is (installed, cannot run a command) with the sentence of the Overview, and is not offered for a new choice.
- **An agent of one's own is taken out again** with "Remove Agent" at the bottom of its page: its entry in `general.agents` goes first and then its table (`removeTable`, which takes the tables below it
  and the comment above it along). The order is not a matter of taste: a list that names an agent nobody defines does not read, so the other order is refused by the validation (a test pins it). There is no
  confirmation question: the note says what was removed, and one Undo puts back the entry and the table. An assistant that proposes the same change waits for the person, as for any program setting taken out
  (a table that is a built-in agent's override may be what keeps it asking). An agent that the config writes as dotted keys or as an inline table is refused with the sentence that sends the person to the text.
- **Left for stage 7:** the prompt argument and the variants.

## As built, a review of stage 4 (2026-10-17): what it found, and what changed

A review of the editing core, the window and trust reproduced these; each has a test that fails against the old code and a mutation entry.

- **The trust model decides by effect, not by the key written.** `ConfigTrust.approvals(changingFrom:to:)` compares what the merged config (both files) would start before and after: the command, `args`,
  the first-prompt argument and each variant's arguments of an agent that exists on both sides, in either direction (emptying `args = []`, which the key rule let through as "a list with nothing in it",
  took out the arguments that kept an agent in its sandbox, as did a variant replaced by its id in `config.local.toml`), and an agent that is new. `PromptEffects` adds the agents a click can start
  (`general.agents`, and the agents that a menu or Quick Action item names) that start without their prompts and did not before: an agent put in the menu while "Start agents without asking" is on
  has a flag of its own (Codex's also turns its sandbox off) that the person's yes never named. A copy from the sync folder that empties an agent's `args` is listed too.
- **The window asks for the same thing.** Every change made in the window goes through `SetupModel.edit`, which asks the service what the change would make start without asking and, when that is
  something, holds the change (`pendingLoosening`) until the person says yes in one alert that names each agent and its flag. That covers "Same as all agents" while the switch is on, a flag typed for an
  agent that had none, an agent checked into the menu, and any control added later; "Start without asking" no longer has a question of its own. The note after the general switch is turned off says
  that an agent whose own setting says "start without asking" still does not ask, and the switch's panel lists those agents.
- **The two files.** A change to `config.toml` is checked with `config.local.toml` laid over it: it is refused when this Mac's own file would then name what the change took out (a key of an
  agent that is gone, a preset that uses it), which left the config with an error that no editor was open to show. The keys of an agent of one's own go to the file that makes its table
  (`owner(of:anchor:)`), so an agent made while this Mac's file lists the agents can be given its terminal and its arguments. Taking an agent out when the list and the table are in two files is two
  changes, the entry first. Undo goes to the file the change was made in (`ConfigEdit.target`), not the file that decides the setting afterwards, which an edit that took the setting out of this Mac's
  file had changed. A new agent takes no id that a file mentions (`disabled`, the other file's table).
- **A change by place acts on what was shown.** A button's change in the list of arguments is worked out from the options the page showed and dropped while another change is written, like the menu's:
  the first version replayed it against the options read after the first change, so a second click on a minus took out two arguments. A field's change carries the text it started from (`baseline`),
  so a field that has the focus never writes its old text back over an Undo or another change, and a list that moved under a row does not take another argument for the one that was typed over.
  Typing in a field that was refused keeps what was typed. A second Return, or Return and then Tab, is one change.
- **`rh config` and the MCP tool can make and take out an agent of one's own** (`add agent.<id> name=… command=…`, `remove agent.<id>`), as the window does, in one change with its entry in the menu: an
  agent could not do what the window could. An assistant that asks for either is held for the person (`agent.*.command`).
- **Names that read as something else than they say are refused** on every path (see DESIGN.md section 9, item 6): the confirmation alerts name the agent, and a name with U+202E in it made the
  alert read backwards. An argument with a backslash is refused where it is written (the page used to write it and every start of the agent was then refused). A stored proposal is shown by what
  its operations do, not by the summary and approvals that its file says of itself.
- **Smaller:** an argument edited in place keeps its comments (`replace`); "Automatic (…)" on an agent's page names the terminal a start would use, and says so when that terminal cannot run an
  agent; the chevrons mirror in right-to-left languages and open the page when the list is not exact; the built-in flag typed in the flag field is the setting taken out; an id is at most 48
  characters, and one is made from the command when the name has no Latin letter; the note under a change shows the warnings the change left (an item of the menu that names an agent that is gone).

## As built, stage 5 (2026-10-17): the prompt presets

- **Under the agents, a list and a page per preset** ("Agent Presets", the name of the Finder submenu): a line has the title, a tag for what it is (built in, customized) and the start of the prompt; the page has
  the title, the prompt (it wraps), the agent that runs it ("First agent in the menu" is the setting taken out) and the most files it takes. Not a drag to reorder: the built-in presets come first and
  the config's own follow in the order of the file, which the person sets by writing them in that order, and a preset menu has a handful of lines.
- **A preset is an entry of a file, and the file is the one that holds it.** `ConfigService.presetEntries` says for each preset where the config writes it (this Mac's own file when it has the entry, else the
  shared one) and at which place; a change names the entry by that place under `expectEntry` (so a preset that moved meanwhile is refused and not replaced by another), and goes to that file. The same
  place of the other file is another preset, which is why a change of the window names its file (`SetupActions.editConfig(target:)`) instead of asking which file decides a key.
- **A built-in preset is read as it is and made the person's own with "Customize"**: an entry with its id, its title and its prompt, which replaces the built-in one in its place (that is what the config
  does with a built-in id). Taking the entry out puts the built-in preset back, and the file as it was (up to the final line break that the first change added when the file had none, and the blank lines at its end, which the removal takes with the entry; the banner's Undo is byte for byte). A preset of one's own is made with a title and a prompt (the id comes from the title and takes no id
  that a preset or a file has, an entry the config left out for an error included) and taken out with one button.
- **The config is the validator.** A prompt that cannot be typed into a terminal (a line break, a backslash, a leading dash, an unknown placeholder) is refused where it is written, with the config's sentence,
  and what was typed stays in the field; the window has no second set of rules.
- The same page edits what `rh config add preset id=… title=… prompt=…` and the MCP tool edit; presets are plain keys, so an assistant makes them without waiting, as before.

## As built, stage 6 (2026-10-17): the New File templates

- **On the Finder menu page, below the menu**: a line for each template (its title and extension), the menu "After a file is made" (`new_file.then`; "select it in Finder" is the setting taken out), and a page
  per template for its title, the file name (without the extension), the extension, what the file holds (a block of text where Return is a line break, saved when the field is left) and the app that opens it
  (an installed editor; a terminal would run the file, and the default editor is the setting taken out).
- **A config that defines any template replaces the two built-in ones** (text and Markdown), so a built-in template is read as it is and the first change writes both out as the config's own (`customizing`; the first
  "New Template…" does the same before it adds its entry). Taking the last entry out gives the built-in templates back, and the file as it was (with the same two exceptions at its end; Undo is byte for byte). It is the same rule as for presets, with a different consequence: a
  preset the config defines replaces one by id, a template replaces all of them.
- **Entries, as for presets**: `NewFileOptions` makes a `FileChange` that names the file that holds the entry and puts `expectEntry` first (`EntryLocation`, `ConfigService.entryLocations(of: "new_file.template")`), and
  the new id is made from the title and takes none that a shown template or a file has. The window shows one note per editor on the Finder menu page (`ConfigEditBanner` takes the settings it is for), since the
  menu rows and the templates are two editors of one page.
- **What a review changed in how entries are found** (stages 5 and 6 share it): the window used to find where an entry is by reading the two files on their own, which disagrees with the merged config
  wherever `disabled`, an id written another way (`"""mine"""`, an escape) or the merge by id is in play: a preset that this Mac drops was still a row's entry (a typed field wrote into a hidden entry, "Use the
  Built-in Preset" deleted it for every Mac), and an id written as a multi-line string pointed a row at the other file's entry. The merge now says where each entry it shows is written
  (`ConfigLoadResult.entryOrigins`, from `ConfigMerge.arrayOrigins`), the service checks that the file writes that id at that place, and the id is decoded as the parser decodes it. The built-in templates are
  written out in full by the first change whatever this Mac turns off, an id that `disabled` names is in use, and the agents this Mac turns off are not offered to a preset.
- The config is the validator again (an extension with a dot or a slash, a file name that is `..`, a name and an extension that together are longer than a file name, and a file name
  or extension with a control character or one that changes how it reads is refused where it is written).

## As built, stage 7 (2026-10-17): an agent's start options and its first prompt

- **On the page of an agent**, a "First prompt" field (`prompt_arg`: `positional` or a flag such as `-i`; the built-in way, or none, is the setting taken out) and a "Start Options" section below the arguments:
  the agent's built-in start options (only shown), and the config's own, each a line that opens a page of its own (a title, and the arguments it adds to the command), and "New Start Option…".
- **One list of arguments for both** (`ArgumentList`): the rows, the drag, the check that the file still writes the list the page showed, and the change by place are the same for an agent's `args` and a start
  option's `arguments`; the view is shared (`ArgumentListPanel`).
- **A start option is an entry of a file** like a preset, found by `entryLocations(of: "agent.<id>.variant")`, changed under `expectEntry` in the file that holds it. A new one goes to the file that defines
  the agent (the same anchor as the agent's other settings), so that the shared file alone still reads when the agent is this Mac's own.
- The config refuses an argument of a start option with a line break or another control character where it is written (it could not be typed into a terminal), as it does for an agent's `args`.

## As built, stage 8 (2026-10-17): the forms of Copy Path and the Quick Actions

- **Two more panels on the Finder menu page**, under the New File templates: "Copy Path" (a Title field, the forms the submenu offers as checked lines in the order of the list, and the forms it does not offer
  below them, which a check puts at the end) and "Quick Actions" (the action ids that become Finder Services, as lines with their icons, and an "Add Quick Action" menu of the actions that can still be added, grouped
  as the menu editor's Add menu is). Both lists drag, take out and move with the keyboard like the others, and each change says what it did, under its own panel, with Undo.
- **The lists have defaults**, so `ArgumentList` carries them (`ConfigDefaults.list`): while the file writes no list the rows are the default one and the first change writes it (the menu editor's rule), then
  changes it by place under the check of the list that was shown.
- **Quick Actions are made by Install or Repair** (`rh install --services`) from the list; the panel says so, and the Overview's check says they differ until it has run. Changing the list does not install anything.
  (Changed in stage 10: a change made in the window writes them again at once.)
- An id in `services.items` that names no action is left out of what the config reads (with a warning), so the rows are not the file's list and the page says the list can only be changed as text.

## As built, stage 9 (2026-10-17): the apps the config adds

- **"Your Apps" on the Overview**, under the default terminal and editor: a line for each `[[app]]` entry of the config (its icon, its name, what it is used as, "(not installed)" when it is not), a page for each and
  "Add App…". The built-in apps are not listed: they come with Right Here and have nothing to change.
- **An app is added by choosing it.** "Add App…" opens the file panel for an application; `AppBundleInfo` reads its `Info.plist` (its bundle identifier and the name it shows; no code of the app runs), and a small form
  asks for the name and what it is used as (an editor opens the files that are selected, a terminal opens a folder, any other app opens what is selected). An app that is available already (built in, or in the config) is
  said and not added twice, and the id is made from the name and is never one in use, so that a built-in app is not replaced by accident (the id of a built-in app in an entry replaces it; a page says so, and taking the
  entry out brings the built-in one back).
- **What the page changes**: the name and the role. A terminal that the config starts through templates (`open_args`, `run_args`) keeps its role and its templates, which only the text of the config changes, and so does
  an app with several bundle identifiers; the page says so. The bundle identifier is shown, not edited: an app that was chosen wrong is taken out and chosen again.
- **The same rules as the other entries**: `AppOptions` makes a `FileChange` that names the file that holds the entry and puts `expectEntry` first, a new app goes to the shared file, the new id takes none that a file
  mentions, and the window shows one note per editor on the Overview (`ConfigEditBanner` takes the settings it is for). An assistant still only proposes the keys that decide which program starts (`bundle_id`, `role`,
  `open_args`, `run_args`): the window is the person.
- `ConfigParity` says `app.*.id`, `name`, `bundle_id` and `role` have a control, and `bundle_ids`, `open_args` and `run_args` are text. What is still only text: `disabled`.

## As built, a review of stages 5 to 8 (2026-10-17): what it found, and what changed

A review of where entries are found and written, the window's model and views, and trust and hostile input reproduced these; each is fixed with a test that fails against the old code.

- **Entries.** A built-in preset reworded in an inline array was shown as built in, and Customize wrote this Mac's wording into the shared file for every Mac: a row is built in only when no file writes its id, and a
  built-in preset whose shared entry this Mac turns off is customized in this Mac's own file. A `[[table]]` was appended to a list that a file writes as an inline array, which spec-following parsers refuse:
  `ConfigDocument.addingEntry` refuses it, ids are read as the parser reads them (`parsedEntryIDs`, so an inline id is in use), and the window says the list can only be changed as text. Where a template goes depends on who
  defines templates: a Mac whose own file defines them keeps them there, and a new template does not take the built-in ones from the other Macs or bring them back on this one.
- **A start option that was made** is opened by its id (`createVariant` returns it): this Mac's own entries come after the shared ones in the merged list, so the last row is not the one made.
- **Typing and waiting.** A block of text (a template's contents) is written when it has rested for five seconds, without being announced, since each write is an entry of the history that `rh config undo` reads
  and a high-priority announcement for VoiceOver; the change that ends the typing is announced. Saying no to the "start without asking" alert makes the fields that were typed in for it give their text up
  (`fieldResetToken`), so the question is not asked again when the field or the page is left. A change that starts in the gap before it waits, or that the window is too busy for, says so under its own editor, as
  every other change does; the wait is `patience`, so a test of it does not take seconds.
- **Trust.** An empty string no longer needs no approval for every key: only a template's contents are exempt (`bypass_permission_arg = ""` turned the preset guard off for an assistant that could only set
  keys). An assistant's undo is held to the rule of an edit across both files, and what a synced config can start now includes the flag the switch types (`bypass_permission_arg`, always listed) and a template's
  contents (listed by digest). The flag typed as an agent's command, argument, first-prompt flag or a start option's argument counts as "starts without asking" in the alert and in the guard of presets, whatever
  the spelling, the quotes or `--flag=value` (`ShellWords` reads the words; a flag of several words is matched next to each other and in order); a config that types the flag with shell syntax is refused, and a
  word that is not plain is typed quoted. The prompt of a preset refuses the characters that the escaper treats as drawing nothing, not a shorter list.
- **Tests.** The window's own routes (the list dispatch of `ArgumentListOwner`, Move Up and Down, the busy refusals of every change, the notes' tab and key) were reached by no test; they are now, and the move that
  nothing called any more was taken out.
- **Left as they are**: an entry that both files write under one id is shown once, so the buttons act on this Mac's entry and a second click on "Use the Built-in Preset" takes the shared one out for every Mac
  (the buttons say what they do, and Undo exists); the forms of the Agents page are not exclusive (two open forms share Return and Escape). The field of an argument is labelled "Arguments" for VoiceOver, not with its own value.

## As built, a review of stages 8 and 9 and of the fixes above (2026-10-17)

The review covered entries, places and the apps; the model and the views; and trust and hostile input. Each finding is fixed with a test that fails against the old code.

- **A terminal as an editor** (rule 3). The window made it one in two ways: Add App with a built-in terminal that this Mac turns off (`available` left it out), and the role menu of an entry that replaces one. The config
  now refuses an `[[app]]` whose bundle identifier is a built-in terminal's, in any case (LaunchServices folds case: `com.apple.terminal` found Terminal), with another role; `AppsState.turnedOff` knows the built-in apps
  that `disabled` names (a notice says so, and `createApp` refuses); the role menu is dimmed for a terminal that comes with Right Here (`rolePinned`) and for one started through templates; the form starts as a terminal for an app
  that says it is a shell (`CFBundleTypeRole` `Shell`); the sync guard compares identifiers without regard to case.
- **The guard of presets read less than a shell does.** `ShellWords` now reads `$'…'`, redirections and separators, finds the program behind an assignment or a wrapper and in any case, and says when a line has an expansion
  (`$x`, `$(…)`, `{a,b}`, an unclosed quote), which a preset refuses; `AgentDescriptor.executable` skips assignments. A change of the typed flag of an agent that is not in the menu yet waits as well.
  A differential run of 12,000 generated lines against `/bin/zsh` 5.9 and `/bin/bash` 3.2 (a program started by either gets the arguments that `eval "set -- …"` makes) found what a reading of the
  documentation had not: zsh, the login shell macOS gives a person, drops the backslash of an unknown escape in `$'…'` (`$'--\d…'` is `--d…` to zsh and `--\d…` to bash), reads `\c` as `c`, reads `\x` or
  `\u` with no digit as a NUL, and gives a program the word up to its first NUL (bash cuts only the `$'…'` string), so a flag could be spelled in a way that only one of them reads as the flag. The reader now
  cuts a word at its NUL and says it cannot read a line that has such an escape or a NUL; `ShellWordsRealShellTests` keeps the comparison (bash 3.2 does not decode `\u`, which the reader does, the way
  zsh and bash 4.2 and later do).
- **Sync and proposals.** A pulled copy that only puts an agent in the menu while the prompts are off is listed; the card of a prompts-off proposal names each agent and its flag, Apply is held to the two files as they were
  looked at, and the window's Apply goes through the same alert as every change.
- **Seeds and files.** A change of this Mac's own file is checked against the shared file too (it could give a shared setting an error); the first change of a list starts from what its readers get (the Quick Actions of the other
  Macs, or the list this Mac shows for `--local`), so the shared file does not take this Mac's agents and `rh config add --local` does not replace a list with the default; `rh config add new_file.template` writes the built-in
  templates out first; a new app, template or agent takes no id that another of the three has (`disabled` is one list for all); the Add Quick Action menu leaves out an agent this Mac turns off; the note "this Mac's file
  sets it as well" is about the entry with the same id; a removal takes out the entry the page showed; a key of a table that dotted keys define is written as a dotted key.
- **Names.** Two agents, or two start options of one agent, may not share a name (the config refuses the second): two Quick Actions of one name are one Service. A name is at most 120 characters, a template's contents 64 KB, and
  a variation selector must select something where it stands.
- **The names of Quick Action bundles.** The 120 characters of a name are not what the volume counts: a file name is at most 255 UTF-16 units, and an emoji is two of
  them. A bundle name that would be longer is cut where a character ends, and the start of a digest of the whole title keeps two long titles apart (`ServiceWorkflow.bundleName`). Two
  titles that differ only in case, or in the form of an accent, are one name to the volume, so they make one Service, as two equal titles do (`ServiceWorkflow.distinct`). Before, either
  case made `rh install --services` fail: the long title installed no Quick Action at all, and the two titles left the install half done.
- **The window.** A held change that was made (a yes) leaves the field following the file (`FieldDraft`, a state machine with tests); a drop moves a row only in the list it was picked up in; the Quick Actions check says they
  differ at once; a change that is called off stops waiting and says nothing; an app's notices are said under the apps; a row without an icon keeps the room of one; the lists have their own sentence for a list that cannot be changed by
  place, the Quick Actions their own "Remove … from the Quick Actions", and their headings are headings for VoiceOver; 21 tests pin what the model tests left open.
- **Left as they are:** abbreviated long options that a tool reads as the bypass flag; the pull of a config with errors (the entry is left out and
  `rh config validate` says so); the stale bundle read of an app replaced at the same path in one session; a person's `command` with shell syntax now cannot be used by presets until it is plain words and quotes.

## As built, stage 10 (2026-10-22): the Quick Actions follow the window, and the language

- A person put Antigravity in the menu and its Quick Action was missing until they pressed Install or Repair again, which nothing told them
  to do. After a change made in the window (an edit, an undo, an approved proposal) that makes the Quick Actions on disk differ from the
  config, the window writes them again at once (`SetupActions.updateQuickActions`: the services piece of setup alone, a few files and one
  `pbs -update`, 0.44 s measured). Where there are none yet, nothing is made: the first setup is still the person's to start. A change
  made elsewhere (a text editor, `rh config`, a sync) still waits for Install or Repair, which the check says.
- `general.language` (ADR 0006) has a menu on the Overview; its parity entry is that control.

## Consequences

- The hard rules stand: the window never types user text into a shell, the core stays pure (the editor is a function from text and an operation to text), and an edit that makes the config invalid is
  refused before it is written.
- CLAUDE.md has a working agreement: a setting is not finished until `ConfigTrust` and `ConfigParity` (the registry) have an entry for it.
