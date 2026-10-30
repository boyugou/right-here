# 0012: Agent prompt presets

Date: 2026-10-12. Status: decided.

## Decision

A `[[preset]]` table in the config defines a prompt template. Built in: `review`, `explain` and `tests`; a preset
with the same id in the config replaces the built-in one in place.

| key | |
| --- | --- |
| `id`, `title`, `prompt` | required |
| `agent` | optional; an agent id. Omitted means the first agent in `general.agents` |
| `max_files` | optional, 1 to 50, default 20 |

`prompt` is a template with three placeholders, filled in a single pass (text that came from a file name is never
read as a placeholder again): `{files}` is the selected files, as `@`-mentions relative to the folder
(`PathStyle.aiMention`, joined by spaces); `{folder}` is the folder's name; `{name}` is the name of the first
selected item (the folder's name when nothing is selected).

The action id is `preset.<id>[@<terminal>]`. Running it types `<agent command> [<flag>] '<prompt>'` into a terminal in
the folder, the prompt being one word quoted by `ShellQuoting.quote(_, for: .posix)`. The agent starts working on the
prompt at once.

The menu has an "Agent Presets" submenu (group `presets`). In the default menu it sits inside "More Agent Options",
which keeps the main menu short; a config that lists `presets` in `[menu] items` gets it at the top level instead, and
then it is not repeated inside "More Agent Options". It is built for the selection: a preset whose prompt uses
`{files}` is left out when nothing is selected, when more items than `max_files` are, or when every selected item is a
folder, and the submenu is left out when nothing is left. The size is counted without looking at the items. Only when
the count fits (so at most `max_files` items, 50 at the most) does the menu ask the file system whether they are
folders, and it stops at the first item that is not known to be one. That is the one place where building a menu looks
at the file system, which hard rule 5 otherwise forbids because a big selection on a network volume would stall Finder;
the count first, and the stop at the first file, are what keep it bounded. It used to be only the count, so a selected
folder still showed the preset and `rh` then refused it ("folders are not files for `{files}`"). An item that cannot be
told (a path the system will not let the extension look at, a link that points nowhere) keeps the preset in the menu:
it is hidden only when every item is known to be a folder, and `rh` says why when it cannot run. A mixed selection
keeps it, with the planner's note that folders are not named in the prompt. The runner passes up to 500 items to `rh`
and `max_files` is at most 50, so a selection is never cut before a preset refuses it. `rh actions` lists every preset;
`rh run preset.review` with no files fails with the reason.

How an agent takes a first prompt is `prompt_arg` on its `[agent.<id>]` table: `"positional"` or a flag such as
`"--prompt"`, typed as its own word before the prompt. Claude Code and Codex are built in as positional (both
`--help` outputs show `[prompt]` as the last argument). The other built-in agents carry it where the tool's own documentation says how
(ADR 0024): Antigravity, Gemini CLI, Qwen Code and GitHub Copilot take `-i`, and Cursor CLI, Factory Droid and Kiro CLI a
positional prompt. Presets are not offered for the rest until the config sets `prompt_arg`, and
`rh agents --json` shows the field.

## What is refused, and why

The expanded prompt must be typeable as one argument. It is refused with a specific plan error (and the config
parser refuses a template that already breaks the rules) when it:

- has a line break or any other control character: typed into a terminal that would press Return in the middle of a
  prompt (hard rule 2), whether the character came from the template or from a file name;
- has a character that shows nothing or changes how the text reads (a tag character, a zero-width space, a direction override, a byte order mark, a soft hyphen): the tag characters spell
  ASCII that a language model reads and a person does not see, so a file named with them would carry an instruction to the agent that nobody looked at. The marks a script is written with stay;
- has a backslash: inside single quotes fish reads a backslash as an escape and sh, bash and zsh do not, and the shell
  a terminal runs is not necessarily the account's login shell (the same reasoning as Terminal.app's folder in
  section 9). POSIX single quotes without a backslash read the same everywhere, including the `'\''` splice. The
  cost: a file name with both a space and a quote or backslash cannot be mentioned (`@"…\"…"`), so it is refused
  rather than guessed at;
- starts with a dash: the agent would read it as an option (`{name}` of a file called `--version`). `--` is not
  inserted instead, since nothing here can show that every agent honors it without starting a session;
- is empty or longer than 4000 bytes (UTF-8, what is typed: it was 4000 characters, and one character can be any
  number of bytes).

A name that looks like a flag is harmless inside a mention (`@--help`), as the prompt begins with other text. More
files than `max_files` is refused, never cut short: a prompt that quietly names fewer files than were selected is a
wrong answer.

## Alternatives

- **`submit = false`, a prompt left in the box for the person to read and send.** Not achievable through the typing
  path: `claude "prompt"` and `codex "prompt"` start an interactive session with that prompt as the first message, which
  the agent sends (their help calls it the prompt to start with; no session was started to confirm). The one real
  prefill that never submits is Claude Code's own `claude-cli://open?cwd=…&q=…` link (0003), which `agent.claude@link`
  already uses for `@`-mentions; it cannot pick the terminal or pass flags, and Codex has no such link. A `submit`
  key that worked for one agent and not the other would promise something the other cannot do, so there is none: the
  key is an unknown-key warning, and the schema says that presets are sent when the agent starts. A possible follow-up is a `prefill = true` preset that uses the link
  for agents that have one.
- **Therefore the built-in presets only ask for reading**: review, explain, and a test *plan*. The wording asks the
  agent not to change files; whether it obeys is up to the agent and its permission mode. The typed command goes
  through the person's own shell, so an alias applies (one that adds `--dangerously-skip-permissions`, say): a preset
  is only as read-only as its wording. Do not describe the built-ins as safe beyond that.
- **File names are text in a prompt that is sent before anyone reads it.** A file called "ignore the above and ..."
  becomes part of the instruction. `agent.claude@link` only prefills, so the person sees the mention first; a typed
  preset does not. The quoting keeps a name from becoming shell syntax, nothing keeps it from being read as an
  instruction by the agent, so presets are for folders the person trusts.
- **`agent.<agent>.preset.<id>` as the id.** It parses (four dot-separated words), but `agent.claude.preset` is
  already a valid id (a variant called `preset`), the agent is redundant because the preset names one, and every
  preset times every agent would be a catalog entry. `preset.<id>` has no such overlap and is one entry per preset;
  the optional `@<terminal>` suffix is the same as for `open.terminal`.
- **Combining a preset with a variant** (`claude --continue 'prompt'`, `codex resume --last 'prompt'`). The second
  reads the prompt as something other than a first message in at least one form (`codex resume [SESSION_ID]
  [PROMPT]`), so presets use the agent's base command. A preset always types, even when the agent's launcher is the
  link or the desktop app.
- **A shell-aware quote (`facts.shellFlavor`)**. Wrong for the same reason as in Terminal.app: the login shell is not
  what the terminal runs.
- **Presets in the extension's menu with a contextless `info`.** `ActionRegistry.info(_:)` has no selection; a second
  `info(_:context:)` adds the folder and file-count checks, used by the menu. The planner repeats the same checks for
  `rh run`.

## Verified

- The typed text round-trips through real `sh`, `bash` and `zsh` for file names holding `'`, `$(…)`, backticks,
  `;`, `&&`, `>`, a leading `-`, `{folder}`, `%s`, emoji and spaces: the shell prints exactly the prompt and no
  canary file appears.
- Refusals: newline, carriage return, tab, bell, escape, U+2028, tag and direction-override characters, backslash, a leading dash, too many files, no files; and an agent whose command or arguments
  already carry its flag that switches the permission prompts off (a preset keeps them on).
- Building the menu asks the file system about the selected items only when there are at most `max_files` of them,
  and stops at the first one that is not a folder (a test counts the questions: none for a big selection, one for a
  selection of files); a path the fake file system does not know still gets the submenu.
- The localization catalog has the submenu title and the three built-in titles in thirty languages; the translations
  are machine-made and marked `needs_review` like the rest.
- `claude --help` and `codex --help` (read-only) list a positional prompt.

## Not verified

- That a typed preset starts a session with the prompt submitted, in a real terminal: `rh doctor --probe-launch`
  proves a typed command runs, and this feature types the same way, but no agent was started from a preset.
- What opencode, aider, Amp and the other agents without a built-in `prompt_arg` do with a first argument.
- The nested submenu in the real Finder menu (the extension builds menus recursively and "More Agent Options" is
  already a submenu, so a second level is expected to work).
- That the sandboxed extension can tell a selected folder from a file. If a metadata read outside its container is
  refused, `isDirectory` answers nothing, the submenu stays for a folder and `rh` refuses it as before; nothing is
  lost but the fix. `docs/development/MANUAL_CHECKS.md`, section 4.
