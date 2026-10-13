# 0003: Start agents by typing into the user's shell

Date: 2026-10-11. Status: accepted.

## Decision

To run `claude` or another agent in a terminal, set the working directory with the terminal's own
mechanism and type the agent's command into the new interactive login shell. Ghostty: `initial working
directory` plus `initial input`. Terminal.app: `do script "cd <quoted dir> && claude"`. Terminals that
cannot do this only open the folder, and agents are not offered through them.

## Why

- GUI apps start with a minimal PATH. With a common setup, `claude` and `codex` come from nvm, which is
  initialized in `.zshrc`: `zsh -lc` does not find them, `zsh -lic` does. Typed text gets that setup for
  free, honors shell aliases (a person may alias `claude` with extra flags) and leaves the shell open when
  the agent exits.
- Commands passed through a terminal's `command` or `-e` are exec'd without any of that.
- Quoting layers are the usual source of injection. Here the AppleScript is constant and the directory
  and typed text arrive as `on run argv` arguments. Typed text may not contain line breaks or control
  characters.

## Alternatives kept as launchers

- `agent.claude@link`: Claude Code's own `claude-cli://open?cwd=…&q=…`. No permission prompt, reuses the
  last terminal, prefills (never submits) a prompt, so selected files become `@` mentions. It cannot pass
  flags or pick the terminal.
- `agent.<agent>@desktop`: the agent's desktop app through its deep link.

## Verified

`rh doctor --probe-launch` runs the whole chain through the Finder extension: a throwaway Ghostty session
in a folder named with spaces, quotes, `$` and a backtick types a command that writes a file and exits.
The file appears in that folder, written by the login shell: the linefeed presses Return, the working
directory is honored, and no quoting was needed. The macOS Automation prompt names the Finder extension
(the process macOS holds responsible), which is why the extension carries the apple-events entitlement.

## Not yet verified

The first-ever permission prompt on a system that never allowed the control. A cold start of the
terminal may add an empty startup window.
