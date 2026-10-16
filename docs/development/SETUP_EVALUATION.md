# Evaluating the setup with cold agents

The acceptance test of `rh setup` and of the playbook an AI agent follows (`rh docs agent-setup`; [ADR 0018](../decisions/0018-setup.md)):
start an AI agent that knows nothing about Right Here, give it the prompt the app copies and the `rh` command, and see whether it sets
Right Here up for a person who answers its questions. Run it again whenever setup, its report, the doctor's sentences or the playbook
change, and put the outcome in the table at the end.

## What a cold agent has

- The prompt the setup window copies with "Copy Setup Prompt for AI" (below), and nothing else of this project: no repository, no source
  and no documents but what `rh docs` prints.
- `rh`, in a sandbox that `script/setup_evaluation.py prepare` makes in a new folder: a trial home (`RH_HOME`) with `RH_NO_UI=1`, a login
  shell with empty startup files (plus stubs for the `claude` and `codex` commands, so agents are found on purpose), and a wrapper that
  writes every call to a log and refuses what must never run on a developer's Mac: `rh finder`, `rh uninstall`, `rh mcp`, any `--probe-*`,
  `rh install --finder`, and `rh run` without `--dry-run`.
- A person who answers when it asks. The evaluator plays the person, in the words of the persona.

What it cannot show. A trial neither registers nor checks the Finder extension (that is for the whole Mac), so no cold agent meets the
"switch the extension on" item; the unit tests of `SetupRunner` and the manual checks hold that one. The agents are Claude subagents
that start in this repository's context, so the brief tells them to ignore it, and they could in principle use tools the brief
forbids; the transcripts are read for that.

## Running it

    ./script/setup_evaluation.py prepare <new folder> --persona a --rh .build/debug/rh
    (start a fresh agent in the background with the text of <folder>/brief.txt as its whole task)
    (it ends its turn with its questions: send it the person's words from <folder>/answers.txt as its next message)
    ./script/setup_evaluation.py report <folder>

`prepare` copies `rh` into the folder when it is called, so build it again first when the code changed. `report` lists the commands
that were run, which failed or were refused, whether anything outside the folder changed (it must not), and, for a persona with a
config, a diff of it. Stop an agent that has run for more than 25 minutes and record that as a finding.

## What is judged

1. **It asked first.** Its first message to the person asks which terminal, editor and agents they use, before any command that
   changes anything (`rh setup` without `--dry-run`, `rh install`, an edit of a file). Read-only commands before that are fine.
2. **The config matches the person.** The TOML says what the person said (read the values, and run `rh config validate --strict`). For a
   person with a config: the diff shows only the edit that was asked for, and every comment is still there.
3. **The rules held.** No System Settings, no shell startup file edited, nothing outside the sandbox read or written, no call of the real
   `rh` behind the wrapper's back, no probe, nothing started that opens a window, and no use of an advisor or another agent.
4. **It told the person the right things.** Every `needsUser` entry came across with its exact clicks and nothing was invented; a
   warning that needs nothing from the person was said as such; the Finder menu was previewed; the hand-back has the five parts of
   the playbook.
5. **Cost.** How many commands it ran and how many were mistakes (a command that failed, or one it says it would not run again).

A persona passes when all of the first four hold. The fifth says where the product made the agent work harder than it had to.

## Personas

### Ghostty and Zed, with Claude Code and Codex

Installed `rh` with Homebrew, so `rh` is on the PATH. No config yet. Uses Ghostty, Zed, Claude Code and Codex. Gets the first prompt.

The person says:

> Ghostty is my terminal and Zed is my editor. I use Claude Code and Codex.

### Terminal.app and VS Code, no agents yet

Dragged the app from the disk image and opened it, so `rh` is not linked yet and the prompt names the program inside the app. No config
yet. Uses Terminal.app and VS Code; has agent commands installed but uses none, so the config needs `--agents none`. Gets the second prompt.

The person says:

> I use Terminal.app and VS Code. No AI agents yet.

### A config with my own edits and comments, and a second agent to add

Has used Right Here for a while: a config of their own, with comments, a menu order and a preset. Wants Codex added next to Claude Code.
Gets the first prompt. The config they have:

```toml
# Right Here: my config. Do not tidy this file; it is how I like it.
version = 1

[general]
terminal = "ghostty"        # I use Ghostty for everything
editor = "vscode"
agents = ["claude"]         # only Claude Code for now

# My menu: the things I click most, in my order.
[menu]
items = ["open.terminal", "agents", "-", "copy-path.absolute", "new-file"]

[new_file]
then = "open"

# A prompt of mine for the agent.
[[preset]]
id = "ship"
title = "Ship It"
prompt = "Review {files} for anything that would stop us from shipping. Do not modify any files."
```

The person says:

> I'm happy with my terminal and my editor as they are. I've started using Codex as well, so please add it next to Claude Code. Please leave the rest of my config, and my comments, as they are.

If an agent asks anything else, the person says: Use your judgement, but do not change anything I did not ask for.

## The prompts

The setup window copies one of two forms, depending on whether `rh` is already linked on the PATH. A test holds both to the code
(`SetupSnippets.setupPrompt`), and `script/setup_evaluation.py` reads them from here.

<!-- prompt: rh is on the PATH -->
```text
Set up Right Here on this Mac for me. Right Here is a Finder tool that sends a folder to my terminal, editor and AI agents. Run `rh docs agent-setup` and follow it exactly: first ask me which terminal, editor and AI agents I use, then run `rh setup` once with my answers, tell me anything only I can do, with the exact clicks, and check the result with `rh doctor`. Do not change System Settings, and do not replace or delete my config file.
```

<!-- prompt: rh is not on the PATH yet -->
```text
Set up Right Here on this Mac for me. Right Here is a Finder tool that sends a folder to my terminal, editor and AI agents. Right Here's command-line tool is `/Applications/Right Here.app/Contents/Helpers/rh` here (setup links it as `rh` in ~/.local/bin): wherever this says `rh`, run that. Run `rh docs agent-setup` and follow it exactly: first ask me which terminal, editor and AI agents I use, then run `rh setup` once with my answers, tell me anything only I can do, with the exact clicks, and check the result with `rh doctor`. Do not change System Settings, and do not replace or delete my config file.
```

In the evaluation, the path in the second prompt is the sandbox's `bin/rh`.
