# 0004: TOML config, never rewritten by the app

Date: 2026-10-11. Status: accepted.

## Decision

The config is TOML at `~/.config/right-here/config.toml`. A schema in code (`ConfigSchema`) is the single
source for validation, `rh docs config` and the JSON Schema. The app and the extension only read it.
People and agents edit the text; `rh config validate` checks it.

## Why

- Comments and ordering belong to the person. A UI that rewrites the file needs a format-preserving
  editor, which is a parser project of its own; no surface in version 1 needs to write the file.
- TOML allows comments and literal strings, which matter for shell-ish values, and it is widely used for tool configuration.
- A pure-Swift library (TOMLDecoder, MIT, full TOML 1.1) parses it; no hand-written parser.
- Errors carry a dotted path, the file and line they are on, and a suggestion (`did you mean "terminal"?`),
  which is what an agent needs to fix a file by itself.

## Consequences

- A settings UI, if added, edits through `rh config set`-style targeted edits, not by regenerating the file.
- Project folders never contribute configuration, so right-clicking a cloned repository cannot run anything.

## Strictness

Setting Right Here up with only the installed `rh` and its docs showed the sharp edges, which shaped these rules:

- An unknown key is a warning, not an error, because everything else in the file still applies. It is
  almost always a typo, and what it was meant to set is then silently missing, so the playbook tells agents
  to fix warnings too, and `rh config validate --strict` exits 1 until the file is clean (`clean` in the JSON).
- Each diagnostic carries `replacement`, the likely fix as plain text, next to the prose `suggestion`.
- Ids must be unique: a duplicate app, template or variant id is an error (the first one is used).
  An app defined under a built-in id replaces the built-in everywhere (`Config.allApps` is the one list) and
  is warned about, so shadowing is never silent.
- The JSON Schema is stricter than the validator in one way on purpose: it rejects unknown keys, so an
  editor underlines a typo while `rh` keeps working. It also carries `required`, id patterns and the allowed
  values, so the two describe the same file.
- `rh init --force` saves the old file as `config.toml.bak-<date>` before replacing it.
- `rh docs config` names every way the file is located (`RH_CONFIG`, `RH_CONFIG_DIR`, `XDG_CONFIG_HOME`).

## Where a problem is, and what a syntax error says

- A syntax error names the line the trouble is on, in the words of this project and not the TOML library's. The library
  reports where it gave up, and for an array that was never closed that is the end of the file or the next statement
  ("Internal error", a line past the last one: line 8 of a six-line file). `TOMLOutline` is a light scan of the text (it
  tells strings and comments from structure, reads no values and accepts nothing the library refuses) that finds the
  array, inline table or table header that was left open and the line it opened on; `TOMLSyntax` maps the library's
  other sentences to ours. `TOMLError`'s reason is not public, so the library's sentence is what is matched, and a test
  per sentence feeds the library a text that makes it say so: a new version that rephrases one fails there. A line is
  never past the end of the file (the library counts the line break `readTable` adds).
- Every other problem (an unknown key, a wrong type, an unknown id) is put at the line of its key or table by the same
  outline, and the problems are listed in the order of the file, a file's own first. The merge of two files builds from
  emitted text, whose lines mean nothing, so each file's problems are located in that file's own text afterwards, the same
  way for one file and for two.
- A config file that is there and cannot be read (mode 000, a folder in its place) is an error naming the file and the
  reason (`cannot read <path>: Permission denied`), and it counts as existing: `validate --json` says `"exists": true`, the
  doctor's config row fails with that text, and `rh init` says the file exists but was not read (it does not offer
  `--force`, which could not save the old file first). It used to read as a missing file (`No config file ...; defaults
  apply`) everywhere except in `rh init`. The reading is `BoundedRead`, the one reader the sync folder uses too: a file
  past the size limit is not read, and a link is followed.
- A value of the wrong kind says what it is: `expected a string, found an integer`, `... found text without quotes` (with the
  quoted text as the replacement), `expected an array of strings, found a string` (with the list as the replacement),
  `... found an integer as item 2`. The kind is found by asking the library to read the value as each kind it has; a string in
  quotes that the library cannot read (a bad escape) is said with the library's reason, which `outline`'s written text tells from
  bare text. Enum errors list the valid values, an unknown key that is a key of another table says where it belongs
  (`"terminal_placement" belongs in [general]`; `id`, which a dozen tables have, says nothing), an id given as a display name
  ("Visual Studio Code", "Claude Code") is matched to its id, an entry that lacks keys says which, and an agent the config
  defines without a name is one error and not also an unknown agent in `general.agents` and in a preset.
- A value this build cannot type used to make the whole shared file unreadable the moment an overlay existed (the merge works on
  typed values; one bare word failed `TOMLValue.read`, so `config.toml` was dropped with "contains a value of a kind this build
  cannot read" and none of its settings applied, where the file alone applied everything else). Such a value is now carried
  through the merge as it was written (`TOMLValue.untyped`, found by the outline) and written back the same, so the builder
  reports it as it does for the file alone, and everything else in the file applies.
- `agent.<agent>@<word>` reads `link`, `desktop` and `default` as launchers, never as the id of a terminal, so an `[[app]]`
  with one of those ids (a terminal above all) could be defined and never started as the terminal of an agent action. Those
  ids are refused for `[[app]]` with an error naming the launcher meaning (`AgentLauncher.reservedWords`, the same constants
  the action id grammar reads), and the JSON Schema's app id pattern carries the rule (`^(?!(default|desktop|link)$)...`).
  `terminal` is not one of them: `agent.claude@terminal` is the terminal called terminal.

## Amended by 0026 (2026-10-16)

The title says the app never rewrites the file. The reason (a tool that regenerates a file the person edits by hand loses their comments and order) stands, and setup still never rewrites a config that exists. What changed is that an edit the person asks for, with `rh config set` and its kin (and later in the window), is made in place: the smallest change that does it, every other byte as it was, the text before it kept for undo. [0026](0026-one-config-two-editors.md) has the reasoning.
