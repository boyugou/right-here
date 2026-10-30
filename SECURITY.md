# Security

Right Here turns file names and settings into commands. A mistake there can start a program that the person did not choose.

- [`docs/DESIGN.md`](docs/DESIGN.md), section 9, lists the safety rules.
- [`docs/decisions/0008-independent-review.md`](docs/decisions/0008-independent-review.md) tells how a review shaped them.

Only the latest release gets fixes.

## Report a vulnerability

1. Open the **Security** tab of the repository on GitHub.
2. Press **Report a vulnerability**. Do not open a public issue.
3. Give the macOS version, the version of Right Here, and the command or the Finder action.
4. Give the file name or the config that causes the problem.

If the button is not there, open an issue that asks for a private way to report, without the details. Do not post the details in a
public place.

## In scope

For example:

- A file name that makes a copied path run a command.
- An action that opens or runs something other than what the menu says.
- An MCP call that does more than its arguments say.
- An AI assistant that changes which program a click starts, or turns off an agent's permission prompts, without the person's
  approval.
- `rh config pending apply` that applies a change that `rh config pending show` did not show.
- `rh config sync pull` that takes a terminal template or an agent command from the sync folder without `--allow-commands`.
- A repository whose own files make git start a program while Right Here makes, checks or removes a worktree in it. See
  [ADR 0016](docs/decisions/0016-agent-permissions-and-worktrees.md).
- A request through the runner script of the Finder extension that starts more than a menu click can.
- A file in the sync folder that makes `rh` read more than 1 MiB of it.

## Not a vulnerability

- **A change that needs write access to the person's own files.** These are the config file, `~/.config/right-here` and the
  Application Scripts folder. The person owns them, and `rh` runs the commands that the person configured.
- **The sync folder is different.** Another Mac, a sync service or a shared drive can write it. Its files reach this Mac only
  through `rh config sync pull`. A pull refuses a config that adds or changes a launch command. The person must read the change and
  pass `--allow-commands`.
- **An AI agent that runs `right_here_run` because the person told it to.** The MCP server checks and limits the arguments. It also
  limits what the calls open or create: 24 units a minute. A document, a Finder window or a new file is one unit. A started command
  is three units. But an agent that the person trusts with a terminal is trusted with a terminal.
