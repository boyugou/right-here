# 0024: A built-in field of an agent is confirmed by the tool, or it is not there

Date: 2026-10-16. Status: decided.

## The problem

The catalog of built-in agents (`AgentDescriptor.swift`) names, for each tool, the command, the flag that gives it a first prompt (presets), the flag that switches its permission
prompts off, the arguments that continue a session, and a few more facts. Six agents were added together with Claude Code's and Codex's (which were read from their `--help` on a Mac that
has them) without a recorded source, and the records said so ("not verified here"). A review of the public website found that the website's text about
presets was two agents out of date; looking for where the catalog's values came from found that nothing recorded it. The audit on 2026-10-16 read every field of every agent against the
tool's own documentation, and `agy --help` on a Mac that has Antigravity: of 60 fields, 40 were confirmed, 12 wrong and 8 not confirmable.

What was wrong was not harmless. A flag that does not exist makes the tool refuse to start from the menu entry (Muse Code's `--auto-approve`); `-p` in a first-prompt field (Kimi Code) runs
the prompt once and exits, and presets offered "Review" that never opened a session; Goose has no positional prompt, and its bare command prints help (`goose session` starts one);
Gemini CLI's `-y` is documented as deprecated for `--approval-mode=yolo`; the continue arguments of Goose and Muse Code did not exist; the instruction file of four agents
(`KIMI.md`, `MUSE.md`, `GOOSE.md`, and Cody's) was a guess, and nothing read the field at all.

## Decision

- **A field of a built-in agent is there only when the tool's own documentation or its `--help` says so.** Otherwise it is absent, and the config says it
  (`prompt_arg`, `bypass_permission_arg`, a variant's `arguments`). An absent field costs a feature (presets for that agent, a "Continue" entry); a wrong one costs a launch that
  fails or does something else. `ShellQuoting` and the planner do not change: the values are typed as written.
- **What the audit changed:** Gemini CLI takes its prompt with `-i` and its approvals off with `--approval-mode=yolo`; GitHub Copilot takes `-i`; opencode's `--prompt` is not built
  in (its documentation says "Prompt to use" and not whether the session starts on it, and the positional argument is the project folder); Kimi Code's approvals flag is `--yolo` and it has no first-prompt flag (`-p` runs once); Goose starts with `goose session` and has no
  prompt, no continue entry and no bypass; Muse Code has nothing but its command (the tool's documentation, beyond its landing page, could not be read, and its flags are known only
  from a third party's capture of `muse --help`); Cody left the catalog (its command line does not start a session in a folder). Antigravity's `-i` stays: the audit could only find it in a third party's list,
  and `agy --help` describes it as the short form of `--prompt-interactive`, which starts the session with a first prompt and keeps it open (`-p`, `--print` and `--prompt`
  run once and exit).
- **What the documentation names is added:** GitHub Copilot gets `--continue` and `--resume`, Kimi Code `--resume` (the "Continue Last Session" and "Resume a Session…" entries of More Agent Options).
- **`instructionFile` is gone**: nothing read it.
- **A command with an argument of its own is looked up by its first word** everywhere, the first run's detection included (`AgentDescriptor.executable`; the doctor and `rh agents` already did).
- **Codex's flag is `--dangerously-bypass-approvals-and-sandbox`, and it does what it says:** the documentation says it also runs without sandboxing. `bypass_permissions` is worded as the
  prompts being off; the schema text says that for Codex the sandbox is off too.
- **A guard in the tests** pins each prompt argument and says why (`-p`, `--print` and an agent's own `--prompt` alias run once and exit in several of these tools), so that a
  one-shot flag does not come back as a first-prompt flag.

## Evidence

Sources: each tool's own documentation (Claude Code, Codex, Antigravity, Gemini CLI, opencode, Kimi Code, Goose, GitHub Copilot, aider, Amp, Sourcegraph's Cody CLI and Muse Code
where readable), read on 2026-10-16 without installing or running any of them, and the `--help` named above; the bundle identifiers of `Claude.app`, `Codex.app` and `Antigravity.app` were read with `mdls` from installed copies
(`com.anthropic.claudefordesktop`, `com.openai.codex`, `com.google.antigravity`: all three right). The audit's table is not kept in the repository (the pages move); what it
found is in the decision above.

Not confirmed, so not built in: Muse Code's prompt, bypass and continue arguments; Goose's "continue the latest session" (one page of its documentation says `goose session -r`, another says
`--resume` needs a name or an id); whether opencode's `--prompt` submits at once or only fills the input; Amp's flag for a first prompt.

## The editors and terminals

The same rule for the apps: the bundle identifiers of the 29 built-in terminals and editors were compared with Homebrew's cask metadata on 2026-10-16 (a maintained list of what
each app quits as). 26 are confirmed there; the alternates of Trae (`cn.trae.app`, `com.byteplus.trae`) and Positron (`co.posit.positron`) are not in a cask, and only cost a detection
that never matches. Fleet was removed from the catalog: its identifier was in no cask.

## Consequences

- The built-in entries that remain were each seen in the tool's documentation or help; the next agent added to the catalog needs the same, and a review of the catalog is a
  reading of the tool's current documentation.
- After this audit presets were offered for five agents (Claude Code, Codex, Antigravity, Gemini CLI, GitHub Copilot), and for nine after the four agents of 2026-10-29 below;
  the config makes a preset available for any other with `prompt_arg`.
- The website said two; its text was changed to match the catalog.

## The install pages (2026-10-22)

The Agents page links an agent that the login shell does not find to the agent's own install page (`AgentDescriptor.installPage`). Each
page was opened on 2026-10-22 and answered with HTTP 200 (`curl -L`); where it redirected, the page it ended on is the one written down
(Claude Code's setup page is now on code.claude.com, and Goose's repository moved to aaif-goose). Muse Code has no page that could be
confirmed, so it has none.

## Four more agents (2026-10-29)

Cursor CLI, Qwen Code, Factory Droid and Kiro CLI were added, each field from the tool's own documentation as read on 2026-10-29 (the
install pages answered 200, Factory's after a redirect to docs.factory.com/droid-cli/quickstart):

- **Cursor CLI** (cursor.com/docs/cli): the command is `agent`, the only name the documentation gives; a positional prompt under
  "Interactive mode" (`-p`/`--print` run once); `--force`, "Force allow commands unless explicitly denied" (`--yolo` is its alias);
  `--continue`, "alias for `--resume=-1`". What a bare `--resume` does is not said, so there is no "Resume a Session…". Its icon is the
  Cursor app's, when that is installed.
- **Qwen Code** (github.com/QwenLM/qwen-code, qwenlm.github.io/qwen-code-docs): `qwen`; `-i`/`--prompt-interactive` "Starts an
  interactive session with the provided prompt" (`-p` runs once); `--yolo`. `--continue` and `--resume` are documented on the page for
  headless runs only, so it has no variants.
- **Factory Droid** (docs.factory.com/reference/cli-reference): `droid "query"`, "Start REPL with initial prompt" (`droid exec` runs
  once); `-r, --resume [sessionId]`, the last modified session without an id. `--skip-permissions-unsafe` is shown only with
  `droid exec`, so there is no built-in flag; the config can give one.
- **Kiro CLI** (kiro.dev/docs/reference/cli-commands; it was Amazon Q Developer CLI): `kiro-cli chat`, since "the `kiro` command
  launches Kiro IDE"; `[INPUT]`, "The first question to ask (positional argument)" (`--no-interactive` runs once);
  `--trust-all-tools`; `--resume`, "Resume the previous conversation from this directory", and `--resume-picker`.

Other agents can be added through the config.

Presets are now offered for nine agents: the five above, and Cursor CLI, Qwen Code, Factory Droid and Kiro CLI.
