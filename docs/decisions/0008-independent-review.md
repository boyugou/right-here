# 0008: Independent review and mutation checking

Status: accepted. The findings below are fixed; the practice continues.

## Practice

Large changes get an independent review: a reviewer with read-only access to a clone looks for real defects, traces
each one and reproduces it. A finding is reproduced before anything is changed, and every fix comes with a test that
fails against the old code. A cold-start usability test (setting Right Here up with only the installed tool and its
docs) complements the code reviews, and a review of a fix's own changes is worth running, because fixes introduce
regressions too.

`script/mutation_check.py` backs this up. It removes each protection that `docs/DESIGN.md` section 9 relies on in a
throwaway clone and expects a test to fail. A failed test is the only kill; a compile error and a mutant that changes
nothing are reported separately. A hand-run sweep once reported every protection as noticed because passing test
output also contains the word "error:"; the script exists to keep that check honest.

Long seeded fuzz runs complement the fixed seeds in `FuzzTests.swift` (kept small so `swift test` stays fast).
A one-off run over 3000 seeds of the config parser (750,000 random documents) found a crash no review had: a config
that ends right after an empty quoted key inside an open bracket (`[""`, `[ ''`, `[[""`) made TOMLDecoder trap. The
library is now given a final line break, which turns it into the ordinary syntax error; 6000 seeds (1.5 million
documents) then ran clean. Run the fuzzer wider after touching the parser. The upstream report is drafted in
[`docs/development/UPSTREAM_REPORTS.md`](../development/UPSTREAM_REPORTS.md).

## Findings by class

### Quoting and text that reaches a shell or terminal

| Finding | Fix | Pinned by |
|---|---|---|
| A quote, semicolon or other metacharacter followed by a combining mark, variation selector, ZWJ or keycap is one Swift `Character`, so quoting built on `Character` or `replacingOccurrences` left it alone; the default "Shell-Escaped Path" pasted a command (reproduced in zsh, bash, sh). Prefix tests, `unquote` and `lexicallyNormalized` had the same flaw (a slash plus a combining mark hid a `..`) | `ShellQuoting` works on Unicode scalars; `scalarReplacing` is used by the MCP fence, Service names and config validation; path and prefix handling cut at scalars | `ShellQuotingTests`: every metacharacter with every joining mark and a seeded fuzz round-trip through real shells (sh, bash, zsh, dash, ksh, fish) with a canary file |
| Terminal.app's `cd` used AppleScript `quoted form of` (POSIX), which fish reads differently; later, the line was quoted for the account's login shell although the profile may start another | the line is built in Swift with POSIX quoting for every shell; a folder with a backslash is refused (the one character fish reads differently). csh and tcsh expand `!` inside single quotes, so they can only fail the `cd`, never run anything | `TerminalAdapterTests` run the line in real shells |
| `copy-path.shell-quoted` was quoted for the login shell, but the text is pasted elsewhere (a fish user pasting a hostile name into an ssh session ran it) | the form follows the text: POSIX single quotes, or backslash escapes when the name has a backslash, which sh, bash, zsh and fish read alike. A name with both a backslash and a control character has no form every shell reads alike, so copying it in a shell form is refused (absolute path still works) | `ShellQuotingTests`, `PathRendererTests` |
| Names reached the terminal raw in plan summaries, error text and the menu header (ESC and OSC sequences, bidirectional controls such as U+202E) | control and bidirectional characters are escaped at the source | `LaunchPlanTests`, `ShellQuotingTests` |
| Markdown links and @-mentions did not escape `]`, `)` or `"` | escaped | `PathRendererTests` |
| The detector interpolated agent commands from the config into a shell script; a command with control characters was accepted | names travel as arguments; control characters are a config error. The parser also warns when `{dir}` sits inside a string a shell reads (`sh -c "cd {dir}"`) | `DetectorCommandLookupTests`, `ConfigParserTests` |

### Paths and planning

| Finding | Fix | Pinned by |
|---|---|---|
| A missing path still reached a prompt prefill, and `open.terminal proj proj-typo` planned the parent of `proj`; the existence check called every errno except ENOENT and ENOTDIR "present", so a path that cannot exist (a component over 255 bytes, a path over PATH_MAX, `/dev/fd/9999`, a link loop) passed | the planner refuses any named path that is not there, for every action. An item has three states: present, unreadable (EACCES, EPERM, EIO, ESTALE, ETIMEDOUT) and missing. An unreadable path stops a terminal, agent or new-file action with an error that names the permission; copy, reveal and open-in-editor, which only carry the path, still work. A link that points nowhere has no folder and says so. A deleted working directory has no target | `PlannerTests`, and `LiveSystemFactsTests` over the real file system (fake facts cannot produce ENAMETOOLONG) |
| A dangling symlink broke New File; template `base_name` could contain `../`; a new file in a folder that cannot be searched did 10,000 lookups and said "no free name" | `lstat` for naming; `base_name` is validated; the message names both causes | `PlannerTests`, `LiveSystemFactsTests`, `ConfigParserTests` |
| Variants ignored a link or desktop launcher; non-terminals were offered as terminals; the default terminal and editor, and a template's `open_with`, were taken without a role check | variants are typed; roles are checked in the parser and the planner | `PlannerTests`, `TemplateTerminalTests`, `ConfigParserTests` |
| Foundation's `URL.path` decomposes a name stored precomposed (NFC), so a copied name could miss a text search | `SystemFacts.onDiskPath` reads each component's stored name (`URLResourceKey.name`) and `PathRenderer` builds every style from it; a component that cannot be looked up is kept as given | `PathRendererTests`, `LiveSystemFactsTests` |
| `rh run copy-path.* / reveal / open.editor` with no path failed although the help says the current directory is used | the planner takes it for every action from the command line (not when it was deleted) | `CLITests` |

### Process runner and resource limits

| Finding | Fix | Pinned by |
|---|---|---|
| The timeout sent one SIGTERM, which an interactive zsh or bash ignores, so a login shell whose startup file loops outlived it | terminate, wait a second, then SIGKILL the child and its process group | `LiveExecutorTests` |
| A background child kept `rh agents`, the doctor and the app waiting on the pipe | pipes are drained for at most 300 ms after exit | `LiveExecutorTests` |
| Writing standard input to a child that had exited raised SIGPIPE; the stdin writer blocked the Swift concurrency pool threads the watchdogs need | `F_SETNOSIGPIPE` and the throwing `write(contentsOf:)`, on a Dispatch thread | `LiveExecutorTests` |
| A deeply nested JSON request (an array 480 deep, about 1 KB) overflowed the decoder's stack and killed `rh mcp`; a TOML config nested a few hundred deep, or a dotted key of about 200 segments, killed every `rh` command; the scanner closed a multiline string at the first triple quote | a byte scan refuses JSON nested past 32 levels and TOML past 64 before any decoder sees it; a chain of dots counts against the same limit; the scanner consumes the extra quotes that belong to a string | `NestingDepthTests`, `FuzzTests` |
| The 1 MiB config cap measured a symlink's own size, so a link to a huge file bypassed it | it stats the target | `ConfigStoreTests` |
| `RH_NO_UI` guard compared the program name literally (`/usr/bin//open`, `/usr/bin/env open`, `/usr/bin/OPEN`) and read only the first word after `env` | the path is standardized, names are compared lower-cased, and a launcher (`env`, a shell, `arch`, `xcrun`) whose arguments name `open` or `osascript` is refused | `LiveExecutorTests` |

### MCP server

| Finding | Fix | Pinned by |
|---|---|---|
| `dry_run` given as the string "true" really ran the action; unknown arguments were ignored | arguments are validated against the declared schema before anything runs | `MCPServerTests` |
| Framing split on U+2028, U+2029 and U+0085; no batches; a slow call blocked `ping` | split on line feed only, batch replies, concurrent calls | `MCPServerTests` |
| Agents could open unlimited windows and copy arbitrary text to the clipboard; the limiter counted calls, not windows | copy-path requires an existing path; a plan is priced by what it opens (a document, a Finder window per folder, a new file: one unit; a started command or link: three) against twenty-four a minute; `paths` is capped at 200 entries of 1024 characters | `MCPServerTests` |
| `serve()` kept every finished request, started one task per line without limit and buffered a line without limit; later, the in-flight gate made ping and `tools/list` wait behind slow calls | a discarding task group; lines are capped (8 MB, then 2 MB once an 8 MB array of tiny strings was measured at 170 MB and three seconds to decode) and answered with one error; everything that is not a tool call is answered at once; tool calls run eight at a time, 256 are held and the rest get a JSON-RPC server-busy error; an MCP-started action, `rh doctor` included, is stopped after 120 s and says so | `MCPServerTests` (run `serve` in process over pipes) |
| JSON-RPC ids (`true`, `[1]`, `{}`, `null` accepted; ids above 2^53 changed); a top-level `5` or a bad batch member got no reply; a stray response was answered with an error; `tools/list` accepted a cursor | ids are strings or exact integers, everything else is answered with -32600; every batch member is answered; stray responses are dropped; a cursor is refused (none is issued) | `MCPServerTests` |
| `rh` died by SIGPIPE when an MCP client went away; `serve()` called `exit(0)` from inside tests | the signal is handled; `serve` takes an `onClientGone` callback | `MCPServerTests` |

### Installer, probe and Finder integration

| Finding | Fix | Pinned by |
|---|---|---|
| Concurrent `unlink` is not an exclusive claim on APFS (eight racing calls all returned success in 393 of 400 rounds), so a probe request claimed that way could start several terminals | the request is claimed with `rename`, which held in 2000 rounds (`O_EXCL` too); a request older than two minutes is ignored | `ProbeMarkerTests` |
| A doctor probe killed by SIGINT, SIGTERM or SIGHUP left the Finder extension disabled and the request in place | `InterruptGuard` withdraws the request, re-enables the extension, then finishes | `ProbeMarkerTests` (a test raises SIGUSR2 in the test process; nothing opens a window) |
| First `rh install` built Quick Actions without agents; `installServices` and `installCLILink` removed before they wrote, so a failure halfway lost the old Services or link; `rh uninstall` stopped at its first failing step; an install replaced a foreign link silently | the Services step re-reads the config; Services are staged and moved in once all exist; the link is made beside the old one and renamed over it; uninstall keeps going and reports failures at the end (non-zero exit); install says what it replaced; `RH_HOME` lets an install be tested | `InstallerTests` |
| The Finder extension keyed its config cache on the date of a symlink, so edits through a dotfile manager never reached the menu; it read a task's stderr only after the task ended, which could stall it | the target's date is used; stderr is drained while the task runs and kept to 8 KB | covered by `rh doctor` and the extension's build; not unit-tested |
| The doctor read the runner script by cutting at the first ` "$@"` and splitting on newlines, so an `rh` path holding either came back wrong | it reads from `exec ` to the last ` "$@"` | `RunnerArgumentsTests` |
| The setup window swallowed a failed install, a timeout and a failed config open | it shows the error | not unit-tested (SwiftUI) |
| Menu clicks: one mutable menu table meant a click on an older menu could land on another action | tags come from an append-only table and name their menu kind | `MenuBuilderTests` |
| Log lines could be forged with a newline; typed commands were logged; no rotation; the old log and its rotation stayed world-readable; escapes such as `\u{85}` broke the JSON of a probe result | control characters are escaped as JSON `\uXXXX`, summaries are dropped, the file is private and capped at 1 MB, and the mode is tightened on every open and rotation | `RunLogTests` |

### Config and usability

| Finding | Fix | Pinned by |
|---|---|---|
| Ids were not unique and built-in apps could be shadowed silently; no strict mode; the JSON Schema lacked required keys and patterns (an id pattern allowed a leading dash the parser rejects); `rh init --force` overwrote | unique ids, `--strict` validation with a `replacement` field, a schema whose patterns match the parser, a backup on `rh init --force` (see [0004](0004-config.md)) | `ConfigParserTests`, `script/verify_config_schema.py` |
| `general.terminal` could name an app the config had turned into an editor; an empty agent `command` typed nothing; a style or agent listed twice showed twice | role checks; an empty command is a config error; duplicates warn and are kept once; an empty `menu.items` warns | `ConfigParserTests` |
| `rh run --json` printed nothing on stdout when the action failed | it prints `{"ok":false,"error":...}` | `CLITests` |
| `verify_docs.py` could not tell `rh doctr` from `rh doctor`, nor `--dry` from `--dry-run` | subcommands are read from the help and flags matched whole | `script/verify_docs.py` |

### Tests and scripts

| Finding | Fix | Pinned by |
|---|---|---|
| Tests opened Finder, ran the person's login shell and its startup files (`$ENV`, `.zshenv`), never noticed a missing probe time limit, never ran the Terminal.app path, skipped fish everywhere, and one mutant started a real terminal probe | hermetic CLI tests with an empty home, a watchdog on every `rh` the tests start, fish installed in CI, probe tests aimed at a terminal that cannot be installed, and `RH_NO_UI` so `rh` never starts `open` or `osascript` | `CLITests`, `LaunchProbeTests` |
| The release checksum held an absolute path; the DMG script leaked temp folders and a mounted image on failure; the MCP launcher ran any app Spotlight found under a bundle identifier; the workflow had no `permissions`; `install_local.sh` deleted the installed app before copying the new one; the Homebrew formula's test named a file that does not exist | relative names; a trap that detaches and removes; fixed locations only; `contents: read`; copy beside and move over; corrected test | `script/verify_all.sh` |

## Left as they are, on purpose

- The MCP launcher script prefers `rh` on PATH before known install locations: PATH is the person's.
- `open.editor` on an untrusted folder relies on the editor's own workspace trust.
- The launch probe types into `sh -c` in tests, not an interactive login shell: the real shell is covered by
  `rh doctor --probe-launch`.
- A batch that holds a tool call is answered as a whole (a ping inside it waits), and a ping behind several 2 MB
  lines waits for their decoding.
- A Ctrl-C between the probe's disable and enable of the extension is handled by `InterruptGuard`, but a kill that
  cannot be caught leaves the extension disabled until `rh install --finder`.
- `initialize` with empty params and a request without `"jsonrpc":"2.0"` are served, and
  `notifications/cancelled` is ignored (calls are short and bounded by the 120 s limit): lenient rather than wrong.
- The localization check cannot detect a neighbour swap between languages that share a script (ru/uk, ar/fa/ur,
  hi/mr, ja/zh).
- `FileHandle.bytes` does its blocking reads on one queue shared by every such sequence, so a test must read
  `serve`'s replies on a thread of its own.
