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
- `[[app]]`, `[[new_file.template]]` and `[[agent.<id>.variant]]` merge by `id`: the overlay entry replaces the base
  entry with that id in place, a new id is appended;
- `[agent.<id>]` is a table like the others, so the overlay can change one agent's `command` and the base's variants
  stay. (Reading "tables merge by id, the local entry replacing the base entry" as whole-table replacement would
  make the variant rule meaningless, since variants live inside the agent table. Key by key is the only reading in
  which both rules do something.)
- `disabled = ["id", ...]` in the overlay removes those ids from the result: app and template definitions, agent
  tables, the ids in `general.agents`, `menu.items` and `services.items` (by parsing each entry as an action id), a
  default terminal or editor of that id, and built-in new-file templates. An id that does not exist is skipped
  silently, because a shared config may name apps another Mac lacks. A built-in app cannot be removed this way (there
  is no list to remove it from), only left out of the menu. In `config.toml` the key is accepted by the schema and
  reported as "only meaningful in config.local.toml".

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
  and Finder-style conflict copies (`config 2.toml`) next to the copy.

## Verified and not verified

Verified by tests in temporary directories (no real home, no iCloud, no Finder): the merge rules and their
diagnostics, the equivalence of the merge path and the plain path, every sync status and decision, push, pull and the
refusals, atomicity under an injected interruption, the evicted stub and an unreadable file, conflict copies, secret
keys, oversize, a symlinked config, the CLI end to end with an isolated home, the doctor checks.

Not verified, because it needs the real iCloud Drive (which this work was not allowed to touch):

- what macOS 26 puts in place of an evicted file in `com~apple~CloudDocs` (the `.config.toml.icloud` stub of earlier
  systems, or a dataless file at the same name); the code handles both, but only the stub and the unreadable file are
  exercised;
- that `ubiquitousItemDownloadingStatus` reports `notDownloaded` for such a file;
- the time iCloud takes to deliver a push to another Mac, and that it leaves `config 2.toml` on a concurrent write.
  The doctor looks for that name, since it is the form Finder uses, but this is not observed.

Doctor check titles for sync (`sync.folder`, `sync.remote`, `sync.state`, `sync.conflict`) are English in the setup
window, which falls back to the check's own title for ids it has no catalog key for; they appear only when sync is on.
