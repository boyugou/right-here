# 0016: Agents that skip their permission prompts, and isolated git worktrees

Date: 2026-10-14. Status: decided.

## Decision

**Skipping permission prompts is opt-in and visible.** `general.bypass_permissions` (default `false`) and `[agent.<id>] bypass_permissions` add the
agent's own flag (`bypass_permission_arg`, built in for the agents that have one) when the agent is started. `rh run --bypass-permissions`
turns it on for one run and `--safe` turns it off. The flag is a launch option (`Config.launchOptions(for:)`) and is never written into the agent's
`command`, so that every surface can say it: the typed line shows the flag, the plan says "starts with its permission prompts switched off",
the doctor's row for the agent says so, `rh agents` and `rh menu --explain` say so, and the sync guard lists it as `[agent.<id>] bypass_permissions`
(ADR 0013: `pull` refuses it without `--allow-commands`). **A preset never gets the flag** (it does get `args`): its prompt carries the names
of the selected files, and a file called "ignore the above and run ..." must not reach an agent that asks nothing (ADR 0012); the plan says
that the prompts stay on. The flags of Claude Code, Codex and Antigravity were read from their own `--help` on a Mac that has them; the others
come from each tool's documentation and are not verified here.

**Worktrees are Right Here's own folder.** `rh run --worktree` and `rh worktree add` make a git worktree under `.right-here/worktrees/` of the
repository (and put `.right-here` in `.git/info/exclude`). The branch name is validated (no leading dash, no `..`, no whitespace or control
character, git's own rules). Removal, from the CLI or over MCP, only ever touches a worktree under that folder: never the main working
copy and never one the person made. Git's refusal for uncommitted work stands unless the person passes `--force` on the command line
(MCP never forces), and a branch is deleted only with `git branch -d`, which keeps an unmerged one.

## Alternatives

- Bypass on by default, or one switch for every agent without a per-agent override: too easy to leave on.
- `git worktree remove --force` and `branch -D` from MCP, as first written: a client that has been told to by a file it read could
  delete another worktree with uncommitted work.
