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
| Low-medium: `serve()` kept every finished request (2.3 KB each, never freed), started one task per line without limit and buffered a line without limit | a discarding task group, eight requests at once, a line cap (first 8 MB, then 2 MB once an 8 MB array of tiny strings was measured at 170 MB and three seconds to decode) answered with one error |
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

## Third round (commit bcb4d2e)

The reviewer looked only at the nine commits that fixed the second round, and found regressions in two of them.

| Finding | Fix |
|---|---|
| Medium: the existence check called a path "present" for every errno except ENOENT and ENOTDIR, so a path that cannot exist (a component over 255 bytes, a path over PATH_MAX, `/dev/fd/9999`, a link loop) passed the new "every named path must exist" rule: copy-path put attacker text on the clipboard and a terminal opened the parent of a name that was never there | only a refusal or an unreachable volume (EACCES, EPERM, EIO, ESTALE, ETIMEDOUT) is "unreadable"; everything else is missing. The planner is now also tested over the real file system, because the fake facts cannot say ENAMETOOLONG (I had found this from a test of my own and fixed it before the report arrived; the reviewer's repro refuses on the fixed code) |
| Medium: a folder `lstat` could not see through was replaced by its parent (the same substitution the rule exists to stop); a link that points nowhere did the same | an item has three states: present, unreadable, missing. An unreadable path stops a terminal, agent or new-file action with an error that names the permission and offers the Files & Folders page; a link that points nowhere has no folder and says so. Copy, reveal and open-in-editor, which only carry the path, still work (an advisor review flagged the first of these as my own regression before the reviewer's report arrived) |
| Medium: `copy-path.shell-quoted` was quoted for the login shell, but the text is pasted somewhere else: a fish user pasting a hostile name into an ssh session ran it | the form follows the text (POSIX single quotes, or backslash escapes when the name has a backslash), which sh, bash, zsh and fish read alike |
| Low: the in-flight gate paused reading, so ping, initialize and tools/list waited behind eight slow calls | everything that is not a tool call is answered at once; tool calls run eight at a time and 256 (16 MB of requests) are held, the rest get a JSON-RPC server-busy error at once; an MCP-started action is stopped after 120 s and says so (tests run `serve` in process over pipes) |
| Low: "the only character shells read differently" is false for csh and tcsh (`!` is expanded inside single quotes) | the claim is narrowed, and tests show csh and tcsh can only fail the `cd`, never run anything; dash and ksh join the round trip |
| Low: the default terminal and editor came from the preference order without a role check; a template's `open_with` could name a terminal, which then runs the new file | both check roles, in the parser and in the planner |
| Low: the rotated log kept its old world-readable mode | rotation tightens it |
| Low, latent: the stdin writer ran on the Swift concurrency pool and blocked threads the watchdogs need (48 runs with 300 KB of input to a sleeping child lasted its 30 s instead of 1 s) | the write happens on a Dispatch thread |
| Cosmetic: Character-level prefix tests survived (`~` for a path whose first component starts with a combining mark; an MCP path starting with one was rejected as relative) | scalar-level |

Found by me while fixing: running `serve` and its reply reader in one test process deadlocks, because `FileHandle.bytes`
does its blocking reads on a single queue shared by every such sequence; the tests read replies on a thread of their
own. The hand-run mutation sweep that said every protection was noticed was wrong: passing test output also contains
the word "error:". `script/mutation_check.py` keeps the check honest (a failed test is the only kill, a compile error
and a mutant that changes nothing are reported) and found two mutants that changed nothing.

## Fourth round (commit 0b0d3cb)

No critical or high finding; two medium.

| Finding | Fix |
|---|---|
| Medium: a request line of about 1 KB (an array nested 480 deep) overflowed the decoder's stack and killed `rh mcp` (SIGBUS); a config nested a few hundred deep killed every `rh` command | a byte scan refuses JSON nested past 32 levels and TOML past 64 before any decoder sees it |
| Medium: `shell-escaped` and `shell-quoted` were still unsafe for fish for a name with both a backslash and a control character (the fallback quoting is POSIX) | such a name has no form every shell reads alike, so copying it in a shell form is refused (the extension beeps; absolute path still works) |
| Low-medium: names reached the terminal raw in plan summaries, error text and the menu header (ESC and OSC sequences) | escaped at the source |
| Low-medium: the mutation check's own mutant made a test start a real terminal probe, and `RH_NO_UI` only gated alerts | the probe tests aim at a terminal that cannot be installed; under `RH_NO_UI` the process runner never starts `open` or `osascript` |
| Low: `rh doctor` over MCP ran outside the 120 s limit; `serve()` called `exit(0)` from inside tests; a busy server dropped malformed batch members; `unquote` was Character-level | the doctor is limited; `serve` takes an `onClientGone` callback; every member is answered; scalar-level |
| Low: a deleted working directory planned `cd .`; a new file in a folder that cannot be searched did 10,000 lookups and said "no free name"; a link into such a folder was called dangling | no target; the permission error; the message names both causes |
| Low: `verify_docs.py` could not tell `rh doctr` from `rh doctor`, nor `--dry` from `--dry-run`; unit tests read the real startup files via `$ENV` and `.zshenv`; `rh install` replaced a foreign link silently | subcommands are read from the help, flags matched whole; test shells get an empty home; install says what it replaced |

Left: a batch that holds a tool call is answered as a whole (a ping inside it waits); a ping behind several 2 MB lines
waits for their decoding; a Ctrl-C between the probe's disable and enable leaves the extension disabled until
`rh install --finder`.

## Fifth round (commit 53c13a4)

- The TOML depth scanner closed a multiline string at the first triple quote; `\"\"\"a\"\"\"\"` has up to two more
  quotes that belong to the string, so brackets after it were read as inside it. Now consumed.
- The `RH_NO_UI` guard compared the program name literally: `/usr/bin//open` and `/usr/bin/env open` passed. The
  path is standardized and `env` is looked through.
- Printed names now escape bidirectional controls (U+202E and the like), which can make a name read differently.
- A doctor probe killed by SIGINT, SIGTERM or SIGHUP left the Finder extension disabled; the handlers re-enable it.
- The config parser warns when `{dir}` sits inside a string a shell reads (`sh -c "cd {dir}"`).

## Sixth round (commit following 0e25e74)

- A config with a dotted key of about 200 segments (`a.a.a.…`) killed every `rh` command with a stack overflow: the
  TOML decoder recurses per segment, and the depth guard counted only brackets. Reproduced at exit 138; the scanner
  now counts a chain of dots (a float's single dot never builds one) against the same limit.
- The `RH_NO_UI` guard was case-sensitive (`/usr/bin/OPEN` exists on the default volume) and read only the first
  non-option word after `env`. It now compares lower-cased names and refuses a launcher (`env`, a shell, `arch`,
  `xcrun`...) whose arguments name `open` or `osascript`.
- The doctor probe's interrupt handler re-enabled the extension but left the probe request, so the extension could open
  a terminal after the interrupt. It now claims the request first. (The ordering is now a tested function; the signal wiring itself is not run by
  any test, since that would open a window.)
- Nothing found in the config-defined terminal expansion, the MCP limits, or `ProbeMarker`.

## Seventh round (functional correctness and usability, after 06c9616)

A round about behavior rather than security. Fixed:

- `rh run copy-path.* / reveal / open.editor` with no path failed ("no folder or selection") although the help says the
  current directory is used; the planner now takes it for every action from the command line (not when it was deleted).
- `rh run --json` printed nothing on stdout when the action failed; it prints `{"ok":false,"error":...}` now.
- An empty agent `command` validated and then typed nothing: now a config error.
- A style listed twice in `copy_path.styles` showed twice in the menu: now a warning, kept once. An empty
  `menu.items` is a warning. README's `rh actions` line and the doubled period in the TOML error were corrected.

Found and fixed afterwards: a file name stored precomposed (NFC) on disk was copied decomposed (NFD), because
Foundation's `URL.path` decomposes (measured for `path`, `lastPathComponent` and `absoluteString`) and keeps the case
that was typed. Lookups worked (APFS ignores normalization), but a text search for the copied name could miss.
`SystemFacts.onDiskPath` now reads each component's stored name (`URLResourceKey.name`, measured to return the stored
spelling and case), and `PathRenderer` builds every style from it; a component that cannot be looked up is kept as given.

## Eighth round (regressions and install flow, after c588935)

Little found. The on-disk path rendering matched the old output byte for byte on awkward names (except accents now
precomposed and `;` now `%3B`), and the suffix mapping cannot pick wrong components. Fixed: `rh uninstall` stopped at
its first failing step and left the Services and command link behind; it now keeps going like `install` and reports
the failures at the end (non-zero exit). Also fixed: `installServices` and `installCLILink` removed before they wrote, so a failure halfway lost the old
Services or link. Services are now staged and moved in once all exist, and the link is made beside the old one and
renamed over it.

## Left as they are, on purpose

- The MCP launcher script prefers `rh` on PATH before known install locations: PATH is the person's.
- `open.editor` on an untrusted folder relies on the editor's own workspace trust.
- The launch probe types into `sh -c` in tests, not an interactive login shell: the real shell is covered by
  `rh doctor --probe-launch` on a real machine.

## Why keep doing it

Every round found things the author, reading their own code, had not: the quoting bug had passed 150 tests and
a DESIGN claim of "round-tripped through real shells". Tests now generate their awkward input instead of listing it.
The third round found regressions in the fixes of the second, so a round is worth running on a round's own changes.
