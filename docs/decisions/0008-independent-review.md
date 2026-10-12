# 0008: Independent review, October 2026

Date: 2026-10-12. Status: findings fixed; the practice stays.

## What happened

An independent reviewer (a fresh agent with read-only access and instructions to find real defects, trace
each one and reproduce it) went through the code at commit 7d34422, and a cold-start agent set Right Here up
using only the installed tool and its docs. Every finding was re-verified before changing anything, and each fix
has a test that fails against the old code.

## What it found, and what changed

| Finding | Fix |
|---|---|
| High: a quote, semicolon or other metacharacter followed by a combining mark, variation selector, ZWJ or keycap is one Swift `Character`, so quoting built on `Character` or `replacingOccurrences` left it alone; the default "Shell-Escaped Path" pasted a command (reproduced in zsh, bash, sh) | `ShellQuoting` works on Unicode scalars; `scalarReplacing` is used by the MCP fence, Service names and config validation; tests round-trip every metacharacter with every joining mark and a seeded fuzz through three shells with a canary file |
| High: Terminal.app's `cd` used AppleScript `quoted form of` (POSIX) which fish reads differently | the line is built in Swift for the login shell's flavor |
| MCP `dry_run` as the string "true" really ran the action; unknown arguments ignored | arguments are validated against the declared schema |
| MCP framing split on U+2028, U+2029, U+0085; no batches; a slow call blocked `ping` | split on line feed only, batch replies, concurrent calls |
| MCP agents could open unlimited windows and copy arbitrary text to the clipboard | eight window-opening calls a minute; copy-path requires an existing path |
| A background child kept `rh agents`, the doctor and the app waiting on the pipe | pipes are drained for at most 300 ms after exit |
| The detector interpolated agent commands from the config into a shell script | names travel as arguments; a command with control characters is a config error |
| First `rh install` built Quick Actions without agents | the Services step re-reads the config; `RH_HOME` lets an install be tested |
| Variants ignored a link or desktop launcher; `open.terminal@vscode` was offered | variants are typed; non-terminals are not offered as terminals |
| Dangling symlink broke New File; template `base_name` could contain `../` | `lstat` for naming; `base_name` is validated |
| Log lines could be forged with a newline; typed commands were logged; no rotation | control characters escaped, summaries dropped, private file, 1 MB cap |
| Release checksum held the developer's path; the runner script was a generic trampoline | relative name; the runner passes on `run` and `probe` only |

From the cold-start agent: unique ids, no silent shadowing of built-in apps, `--strict` validation with a
`replacement` field, a JSON Schema with required keys and patterns, a backup on `rh init --force`, clearer
docs and dry-run output (see [0004](0004-config.md)).

## Left as they are, on purpose

- The MCP launcher script prefers `rh` on PATH before known install locations: PATH is the person's.
- `open.editor` on an untrusted folder relies on the editor's own workspace trust.
- The launch probe types into `sh -c` in tests, not an interactive login shell: the real shell is covered by
  `rh doctor --probe-launch` on a real machine.

## Why keep doing it

Both reviewers found things the author, reading their own code, had not: the quoting bug had passed 150 tests and
a DESIGN claim of "round-tripped through real shells". Tests now generate their awkward input instead of listing it.
