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
