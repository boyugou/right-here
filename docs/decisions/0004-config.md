# 0004: TOML config, never rewritten by the app

Date: 2026-10-11. Status: accepted.

## Decision

The config is TOML at `~/.config/right-here/config.toml`. A schema in code (`ConfigSchema`) is the single
source for validation, `rh docs config` and the JSON Schema. The app and the extension only read it.
People and agents edit the text; `rh config validate` checks it.

## Why

- Comments and ordering belong to the person. A UI that rewrites the file needs a format-preserving
  editor, which is a parser project of its own; no surface in version 1 needs to write the file.
- TOML allows comments and literal strings, which matter for shell-ish values, and the owner already uses it.
- A pure-Swift library (TOMLDecoder, MIT, full TOML 1.1) parses it; no hand-written parser.
- Errors carry a dotted path, a line for syntax errors and a suggestion (`did you mean "terminal"?`),
  which is what an agent needs to fix a file by itself.

## Consequences

- A settings UI, if added, edits through `rh config set`-style targeted edits, not by regenerating the file.
- Project folders never contribute configuration, so right-clicking a cloned repository cannot run anything.

## Strictness (added after an agent set it up cold)

A cold-start agent that only had the installed `rh` and its docs found the sharp edges, which shaped these rules:

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
