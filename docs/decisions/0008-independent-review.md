# 0008: Independent review, October 2026

Date: 2026-10-12. Status: findings fixed; the practice stays.

## What happened

Independent reviewers (fresh agents with read-only access to a clone and instructions to find real defects,
trace each one and reproduce it) went through the code in rounds: one at commit 7d34422, and a cold-start agent
set Right Here up using only the installed tool and its docs; then a second round on the code that had been
written or left uncovered since (commit 9c739d9, below); then a third on the second round's fixes (also below).
Every finding was re-verified before changing anything, and each fix has a test that fails against the old code.

## First round: what it found, and what changed

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

## Second round (commit 9c739d9)

Nothing critical or high; the reviewer reproduced each of these.

| Finding | Fix |
|---|---|
| Medium: the process timeout sent one SIGTERM, which an interactive zsh or bash ignores, so a login shell whose startup file loops outlived it and `rh install`, the doctor and the app waited forever | terminate, wait a second, then SIGKILL the child and its process group |
| Medium: the MCP limiter counted calls, not windows (`open.editor` with 300 paths was one token), and exempted `reveal` and `new-file`; `paths` had no cap | a plan is priced by what it opens (a document, a Finder window per folder, a new file: one unit; a started command or link: three) against twenty-four a minute; `paths` is capped at 200 entries of 1024 characters by the schema validator |
| Low-medium: writing standard input to a child that had already exited raised SIGPIPE (or an Objective-C exception) in the host | `F_SETNOSIGPIPE` and the throwing `write(contentsOf:)`, off the continuation |
| Low-medium: `serve()` kept every finished request (2.3 KB each, never freed), started one task per line without limit and buffered a line without limit | a discarding task group, eight requests at once, an 8 MB line cap answered with one error |
| Low-medium: a missing path still reached a prompt prefill, and `open.terminal proj proj-typo` planned the parent of `proj` | the planner refuses any named path that is not there, for every action; a path the system only refuses to look at counts as present |
| Low: the log escaped U+0085 and friends as `\u{85}`, which breaks the JSON of a probe result; an old log stayed world-readable | JSON's own `\uXXXX`; the mode is tightened on every open |
| Low: tests opened Finder (`new-file` with the default reveal), ran the person's login shell and its startup files, never noticed a missing probe time limit, never ran the Terminal.app path, and skipped fish everywhere | hermetic CLI tests, a test that watches the time limit, Terminal.app's line run in real shells, fish installed in CI |
| Low: Terminal.app's `cd` line was quoted for the account's login shell, but the profile may start another | POSIX quoting for every shell, and a folder with a backslash is refused (the one character fish reads differently) |
| Low: JSON-RPC ids (`true`, `[1]`, `{}`, `null` accepted; ids above 2^53 changed; a top-level `5` or a bad batch member got no reply) | ids are strings or exact integers; everything else is answered with -32600 |
| Low: the schema's id pattern allowed a leading dash the parser rejects, `extension` had no pattern; `general.terminal` could name an app the config had turned into an editor, and the planner ran it | patterns match the parser (a test holds them together); the parser and the planner check the role |
| Low: a dangling link was "missing" to copy-path but fine for reveal; `lexicallyNormalized` cut paths at Characters, so a slash plus a combining mark hid a `..` | `lstat`; paths are cut at scalars |
| Low: a `.probe` request never expired (an interrupted `rh doctor` opened a terminal at the next Finder start); one mutable menu table meant a click on an older menu could land on another action | requests older than two minutes are ignored; menu tags come from an append-only table and name their menu kind |
| Low: markdown links and @-mentions did not escape `]`, `)` or `"`; the DMG script leaked temp folders and a mounted image on failure; the MCP launcher ran any app Spotlight found under the bundle identifier; the workflow had no `permissions` | escaped; a trap that detaches and removes; fixed locations only; `contents: read` |

Found while fixing: concurrent `unlink` is not an exclusive claim on APFS (eight racing calls all returned
success in 393 of 400 rounds), so the probe request is now claimed with `rename`, which held in 2000 rounds;
`rh` died by SIGPIPE when an MCP client went away; the Homebrew formula's test named a file that does not
exist, which has been refused since the first round.

## Left as they are, on purpose

- The MCP launcher script prefers `rh` on PATH before known install locations: PATH is the person's.
- `open.editor` on an untrusted folder relies on the editor's own workspace trust.
- The launch probe types into `sh -c` in tests, not an interactive login shell: the real shell is covered by
  `rh doctor --probe-launch` on a real machine.

## Why keep doing it

Both reviewers found things the author, reading their own code, had not: the quoting bug had passed 150 tests and
a DESIGN claim of "round-tripped through real shells". Tests now generate their awkward input instead of listing it.
