# 0024: A built-in field of an agent is confirmed by the tool, or it is not there

Date: 2026-10-16. Status: decided.

## The problem

The catalog of built-in agents (`AgentDescriptor.swift`) names, for each tool, the command, the flag that gives it a first prompt (presets), the flag that switches its permission
prompts off, the arguments that continue a session, and a few more facts. Six agents were added together with Claude Code's and Codex's (which were read from their `--help` on a Mac that
has them), from the tools' documentation as it was remembered, and the records said so ("not verified here"). A review of the public website found that the website's text about
presets was two agents out of date; looking for where the catalog's values came from found that nothing recorded it. The audit on 2026-10-16 read every field of every agent against the
tool's own documentation (or its source), and `agy --help` on this Mac: of 60 fields, 40 were confirmed, 12 wrong and 8 not confirmable.

What was wrong was not harmless. A flag that does not exist makes the tool refuse to start from the menu entry (Muse Code's `--auto-approve`); `-p` in a first-prompt field (Kimi Code) runs
the prompt once and exits, and presets offered "Review" that never opened a session; Goose has no positional prompt, and its bare command prints help (`goose session` starts one);
Gemini CLI's `-y` is documented as deprecated for `--approval-mode=yolo`; the continue arguments of Goose and Muse Code did not exist; the instruction file of four agents
(`KIMI.md`, `MUSE.md`, `GOOSE.md`, and Cody's) was a guess, and nothing read the field at all.

## Decision

- **A field of a built-in agent is there only when the tool's own documentation, its source or its `--help` says so.** Otherwise it is absent, and the config says it
  (`prompt_arg`, `bypass_permission_arg`, a variant's `arguments`). An absent field costs a feature (presets for that agent, a "Continue" entry); a wrong one costs a launch that
  fails or does something else. `ShellQuoting` and the planner do not change: the values are typed as written.
- **What the audit changed:** Gemini CLI takes its prompt with `-i` and its approvals off with `--approval-mode=yolo`; GitHub Copilot takes `-i`; opencode's `--prompt` is not built
  in (its documentation says "Prompt to use" and not whether the session starts on it, and the positional argument is the project folder); Kimi Code's approvals flag is `--yolo` and it has no first-prompt flag (`-p` runs once); Goose starts with `goose session` and has no
  prompt, no continue entry and no bypass; Muse Code has nothing but its command (the tool's documentation, beyond its landing page, could not be read, and its flags are known only
  from a third party's capture of `muse --help`); Cody left the catalog (its free and pro plans ended in July 2025, and its command line is an experimental, enterprise-only, one-shot
  chat, not a session in a folder). Antigravity's `-i` stays: the audit could only find it in a third party's list, and `agy --help` here says
  "-i: Short alias for --prompt-interactive: Run an initial prompt interactively and continue the session" (and `-p`, `--print` and `--prompt` run once and exit).
- **What the documentation names is added:** GitHub Copilot gets `--continue` and `--resume`, Kimi Code `--resume` (the "Continue Last Session" and "Resume a Session…" entries of More Agent Options).
- **`instructionFile` is gone**: nothing read it.
- **A command with an argument of its own is looked up by its first word** everywhere, the first run's detection included (`AgentDescriptor.executable`; the doctor and `rh agents` already did).
- **Codex's flag is `--dangerously-bypass-approvals-and-sandbox`, and it does what it says:** the documentation says it also runs without sandboxing. `bypass_permissions` is worded as the
  prompts being off; the schema text says that for Codex the sandbox is off too.
- **A guard in the tests** pins each prompt argument and says why (`-p`, `--print` and an agent's own `--prompt` alias run once and exit in several of these tools), so that a
  one-shot flag does not come back as a first-prompt flag.

## Evidence

Sources: each tool's own documentation or source (Claude Code, Codex, Antigravity, Gemini CLI, opencode, Kimi Code, Goose, GitHub Copilot, aider, Amp, Sourcegraph's Cody CLI and Muse Code
where readable), read on 2026-10-16 by a researcher who installed and ran nothing; the bundle identifiers of `Claude.app`, `Codex.app` and `Antigravity.app` were read here with `mdls`
(`com.anthropic.claudefordesktop`, `com.openai.codex`, `com.google.antigravity`: all three right). The audit's table is not kept in the repository (the pages move); what it
found is in the decision above.

Not confirmed, so not built in: Muse Code's prompt, bypass and continue arguments; Goose's "continue the latest session" (one page of its documentation says `goose session -r`, another says
`--resume` needs a name or an id); whether opencode's `--prompt` submits at once or only fills the input; Amp's flag for a first prompt.

## The editors and terminals

The same rule for the apps: the bundle identifiers of the 29 built-in terminals and editors were compared with Homebrew's cask metadata on 2026-10-16 (a maintained list of what
each app quits as). 26 are confirmed there; the alternates of Trae (`cn.trae.app`, `com.byteplus.trae`) and Positron (`co.posit.positron`) are not in a cask, and only cost a detection
that never matches. Fleet was removed: JetBrains no longer makes it (Homebrew disabled its cask on 2025-12-22) and its identifier was in no cask.

## Consequences

- The built-in entries that remain were each seen in the tool's documentation, source or help; the next agent added to the catalog needs the same, and the review of the catalog is a
  reading of the tool's current documentation, not a memory of it.
- Presets are offered for five agents (Claude Code, Codex, Antigravity, Gemini CLI, GitHub Copilot); the config makes a preset available for any other with `prompt_arg`.
- The site said two; it says five (the strings were changed with the page).
