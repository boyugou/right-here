# 0013: Config sync by an overlay file and a copy-based sync folder

Date: 2026-10-12. Status: accepted.

## Decision

Two independent pieces.

1. **A per-machine overlay.** An optional `config.local.toml` next to `config.toml`. `ConfigStore.load` reads both, so `rh`,
   the MCP server, the doctor and the Finder extension all see the merged settings. The overlay is never synced.
2. **`rh config sync`**, a copy of `config.toml` between the config folder and any plain folder (default
   `~/Library/Mobile Documents/com~apple~CloudDocs/Right Here`, resolved through `RHPaths`). `enable`, `status`, `pull`,
   `push`, `disable`; its state (the folder and the SHA-256 of the content both sides had at the last sync) is in
   `sync.toml`. The file stays an ordinary file on every Mac. No symlinks, no CloudKit, no network code of our own.

## The merge

Rules (`ConfigMerge`, pure, in `RightHereCore`):

- tables merge key by key; a scalar or a list the overlay sets replaces the base value as a whole (`menu.items`,
  `general.agents`, `services.items`, `copy_path.styles` are never merged element by element);
- `[[app]]`, `[[preset]]`, `[[new_file.template]]` and `[[agent.<id>.variant]]` merge by `id`: the overlay entry
  replaces the base entry with that id in place, a new id is appended (without `preset` in that list, the first
  `[[preset]]` in an overlay replaced every shared preset);
- `[agent.<id>]` is a table like the others, so the overlay can change one agent's `command` and the base's variants
  stay. (Reading "tables merge by id, the local entry replacing the base entry" as whole-table replacement would
  make the variant rule meaningless, since variants live inside the agent table. Key by key is the only reading in
  which both rules do something.)
- `disabled = ["id", ...]` in the overlay removes those ids from the result: app and template definitions, agent
  tables, the ids in `general.agents`, `menu.items` and `services.items` (by parsing each entry as an action id and
  looking at every id it names: the agent, the app or terminal, the terminal of a preset entry), a default terminal or
  editor of that id, and built-in new-file templates. An id that does not exist is skipped silently, because a shared
  config may name apps another Mac lacks. In `config.toml` the key is accepted by the schema and reported as "only
  meaningful in config.local.toml".
  - **A built-in app is removed from the catalog.** The merged `Config` records it in `disabledApps`, and
    `Config.app(id:)` and `Config.allApps`, which the planner, the registry and the menu read, no longer have it: a
    disabled terminal is not offered, cannot be named (`open.terminal@ghostty` is an unknown terminal even with Ghostty
    installed) and is no longer the default. (An earlier reading said a built-in app "has no list to remove it from"
    and could only be left out of the menu; that left the default terminal unchanged and no warning, which is not what
    "disabled" says.) A built-in agent is only taken out of `general.agents` and every list that names it: agents are
    offered by that list, and the registry keeps listing every defined agent.
  - **A preset whose `agent` is disabled is dropped, with a warning** on the overlay's `disabled` (it cannot run here,
    and keeping it would be an error about something removed on purpose), together with the menu and Services entries
    that name it. If it replaced a built-in preset (`review`), the built-in one is back, and entries naming it stay.

### Why the merge works on TOML values, not on parsed `Config` values

`Config` is the product of many cross-checks: a template's `open_with` must name an app that is not a terminal, the
default terminal must be a terminal among the apps as they will be, `menu.items` entries must name something defined,
an agent defined in the file needs `general.agents` to be offered. Parsing each file to a `Config` and merging the
two results would run those checks on each file alone and report the overlay's reference to an app only the base
defines as an error, and would have to repeat every check on the merged value. Merging first and building once
means every check, every schema rule and every future check sees the settings as they will apply, with no second
implementation of the rules.

The cost: `TOMLTable` (the parser's type) is read-only, so the merged tree is written back as text
(`TOMLEmitter`, quoted keys, sorted, arrays of tables in order) and built by the unchanged `ConfigParser`. Two
things keep that honest:

- With no overlay nothing changes: the base text goes straight to `ConfigParser` as before.
- A property test (`ConfigLayersFuzzTests`) runs the existing random-config corpus through the merge path with an empty
  overlay and requires the same `Config` and the same diagnostics as parsing the file alone; another checks that
  reading a tree, writing it and reading it again is the identity.

Diagnostics are traced back after the build: each carries `file` (`config.local.toml` or nil for the main file), and a
path such as `app.3.id` is rewritten to the entry's position in its own file (the merged list's third app may be the
overlay's first). Each file is checked separately first, so a syntax error names its file and line, each file keeps the
1 MiB cap and the nesting guard, and a file that cannot be read is left out while the other still applies. The
Finder extension's cache is keyed on the pair of modification dates (with existence), not on the later one: a file
copied in with an old date (`cp -p`, a sync tool) must still invalidate it.

## Why a copy in a folder

| Option | Verdict |
|---|---|
| CloudKit | Needs the iCloud entitlement, which needs a provisioning profile for a Developer ID app, and a command-line tool cannot carry the entitlement (it has no bundle to hold the profile). Sourced from the research done for this feature, not tested here. It would also need network code and an Apple account state `rh` cannot inspect. Rejected. |
| A symlink from `config.toml` into iCloud Drive | The Finder extension's sandbox grants read access to `~/.config/right-here/` only; it cannot follow a link out of it (ADR 0002, consequences; `rh doctor` already warns for a symlinked config). And a file iCloud has evicted looks like a missing file through a link, so the menu would silently fall back to defaults. Rejected. |
| Copy-based sync (chosen) | The extension reads an ordinary file. Any folder works (iCloud Drive, Dropbox, a git checkout, a network share), with no code of ours that talks to a service. State is explicit and refusals are testable. |
| git or a dotfiles manager | Documented, not built: `rh docs sync` explains using a repository as the folder, and that a symlinked config is followed by `rh` but not by the extension. |

## Sync rules

The state machine (`SyncState`, pure, tested for every status and both directions) compares three hashes: local,
the folder's copy, and the content at the last sync.

- Statuses: `in-sync`, `local-ahead`, `remote-ahead`, `diverged` (both changed, or they differ and no sync has
  happened), `remote-missing`, `remote-evicted`.
- `pull` refuses when the local config changed since the last sync; `push` refuses when the folder's copy did; `--force`
  overrides, after saving the replaced file as `config.toml.bak-<date>` (next to the config for a pull, in the folder
  for a push). A backup is made only when something that may hold unique content is replaced.
- Both validate the source with the parser first and refuse an invalid config, a file over 1 MiB, invalid UTF-8, and
  key names containing token, secret, password or api_key (compared in lowercase, dashes as underscores; names only,
  not values). Refusing at the door is cheaper than scrubbing a secret out of a synced folder afterwards.
- `pull` also refuses a config that would add or change what Right Here starts, unless `--allow-commands` (see Trust).
- **Evicted wins over missing, and is never overwritten, not even with `--force`**: with a placeholder present the
  real `config.toml` may hold newer content than this Mac knows. The check also treats a file whose iCloud status is
  `notDownloaded` or that cannot be read as evicted, and asks that status before reading, because reading would
  block on the network.
- Writes are a temporary file in the destination's folder (rename is atomic only within a volume), `fsync`, then
  `rename`. A failed or interrupted write removes its own temporary file and leaves the old file. Nothing else is
  deleted; `disable` removes only `sync.toml`, the state file.
- A symlinked local config stays a link: `pull` writes into the file the link points at.
- `enable` records the folder and creates nothing (it never creates the iCloud folder); the first `push` creates the
  last path component when its parent exists, and explains when it does not.
- Hashes are over the raw bytes, so a byte order mark or a line-ending change counts as a change.
- The doctor gains checks only while sync is on: folder reachable, copy downloaded, copy valid, how the two compare,
  Finder-style conflict copies (`config 2.toml`) next to the copy, and one row about launch commands (see Trust).

## Trust: the sync folder can make a click run a program

A config is not only settings. An `[[app]]` with `open_args` or `run_args` names a program that `rh` starts, with the
folder and the typed command as arguments (`TemplateTerminalAdapter`); an agent's `command`, a variant's `arguments`
and `prompt_arg` are typed into a terminal. A config that redefines the built-in `terminal` with
`open_args = ["/usr/bin/id", "-un", "{dir}"]` and `run_args = ["/bin/sh", "-c", "{command}"]` turns the next "Open in
Terminal" or agent launch into that program. So the sync folder is a code-execution boundary: whatever can write it
(another machine, a sync service account, a shared drive, a git remote) can plant a config that `pull` copies over
`config.toml`. This record did not say so when sync was added, and `pull` checked syntax, size and secret-looking key
names only: with such a folder config, `rh config sync pull` exited 0 with "Pulled the config".

**Decision.** `pull` reads the incoming bytes and the config they would replace through `LaunchCommands` (pure, in
`RightHereCore`) and refuses, listing every setting, unless `--allow-commands` is passed.

- Compared, as each config reads when parsed alone (the overlay is left out: `pull` replaces `config.toml` only): the
  `open_args`, `run_args` and bundle identifiers of every `[[app]]` that has a template (`{app}` resolves through the
  bundle identifiers); for every agent as it will run, built-in or not, its `command`, `prompt_arg` (a flag is typed
  before the prompt) and each variant's `arguments`; and `general.terminal` when that terminal starts through a
  template. A built-in app or agent the config does not touch is the same on both sides and never listed.
- Listed: places the current config lacks, and places whose value differs (with the old value). Not listed: what the
  current config has and the incoming one lacks (a removal starts nothing). With no local config, everything custom
  counts as new, so a first pull of a config that only picks built-in apps and agents needs no flag, and one with a
  program of its own does.
- `--allow-commands` is its own flag. `--force` is about throwing away this Mac's own edits; making one answer the
  other would make `--force` mean two things and make anyone who wants the commands overwrite their edits.
  They combine.
- The refusal happens after validation and before the backup and the write, on the bytes that would be written, so it
  changes nothing: not `config.toml`, not `sync.toml`, no saved copy.
- `status` and `enable` print the same list (`pendingLaunchCommands` in `status --json`), so the question is asked
  before the pull. `enable` copies nothing, so `pull` is the only way a folder's config reaches this Mac, and the only
  gate. `push` sends this Mac's config out and is not gated; the receiving Mac's `pull` is.
- `rh doctor` has one row, `sync.commands`, while sync is on: a warning when the folder's copy would add or change
  something, otherwise an info row listing what this Mac's config starts through settings of its own. It is built
  by the sync checks, not by the main doctor, so it exists only while sync is on; without sync every config is the
  person's own.
- Every value is printed with control characters escaped (`ScalarEditing`), because the list is the first place a
  hostile config's text reaches a terminal.

| Alternative | Verdict |
|---|---|
| Honour launch keys only from `config.local.toml`, which is never synced | Strict and simple, but then no synced config could define a terminal template or a custom agent, which are what people most want to share. Rejected; the overlay stays for per-machine differences. |
| Warn after pulling | The next click runs it. Too late. Rejected. |
| Tie approval to `--force` | Two meanings for one flag, and overwriting edits to accept commands. Rejected. |
| Signatures or an allow-list of approved hashes | State and key handling for the same question at the same moment; the diff against the current config is the record of what was approved, and what was approved is now part of that config. Rejected. |

**Not guarded, on purpose.**

- Preset prompts (`[[preset]]`): text typed to an agent as one quoted word. They can tell an agent to do something, but
  the agent's own permission prompts stand between that and a command, and DESIGN section 9, item 2 already says
  presets are for folders the person trusts.
- A built-in app redefined without templates: it is opened by bundle identifier and never handed code.
- Edits made to the local config by hand or by another tool (a dotfiles repository): SECURITY.md puts write access to
  the person's own config out of scope. Only the sync folder is a boundary, because other things write to it.
- What runs after `--allow-commands`: that is the person's decision, made with the list in front of them.

## Verified and not verified

Verified by tests in temporary directories (no real home, no iCloud, no Finder): the merge rules and their
diagnostics, the equivalence of the merge path and the plain path, every sync status and decision, push, pull and the
refusals, atomicity under an injected interruption, the evicted stub and an unreadable file, conflict copies, secret
keys, oversize, a symlinked config, the CLI end to end with an isolated home, the doctor checks, and the launch-command
gate with a hostile folder config (a built-in terminal redefined to run `/bin/sh -c`): refused with and without
`--force`, nothing written, taken with `--allow-commands`.

Not verified, because it needs the real iCloud Drive (which this work was not allowed to touch):

- what macOS 26 puts in place of an evicted file in `com~apple~CloudDocs` (the `.config.toml.icloud` stub of earlier
  systems, or a dataless file at the same name); the code handles both, but only the stub and the unreadable file are
  exercised;
- that `ubiquitousItemDownloadingStatus` reports `notDownloaded` for such a file;
- the time iCloud takes to deliver a push to another Mac, and that it leaves `config 2.toml` on a concurrent write.
  The doctor looks for that name, since it is the form Finder uses, but this is not observed.

- whether reading `~/Library/Mobile Documents/com~apple~CloudDocs` makes macOS ask for Files & Folders (iCloud Drive)
  access, and for which process (the terminal running `rh doctor`, Right Here.app, or an MCP host); the doctor reads
  that folder only while sync is on.

The four sync doctor checks share one catalog key for their title in the setup window ("Config sync", thirty
languages, machine-translated like the rest of the catalog); their detail and fix lines stay in English, as the
other checks' do. The `sync.commands` row has the same English title, but the setup window's table of titles does not
list its id yet, so it shows that English text in every language. The tests use symlinks only as temporary-directory fixtures (a dotfiles-style config link), as the
config store's own symlink test does; the feature itself never creates one.
