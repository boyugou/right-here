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

What it cannot show:

- A trial neither registers nor checks the Finder extension (that is for the whole Mac), so no cold agent meets the "switch the
  extension on" item. The unit tests of `SetupRunner` and the manual checks hold that one; the PATH line and the permission prompt, which
  a trial does list, exercise the same step of the playbook (turning an item into words and clicks).
- The agents are Claude subagents, and they start with this repository's own instructions in their context. The brief tells them to
  ignore that and not to use an advisor or another agent (the first round's agents all called an advisor, a stronger model that
  reviews their plan), but they could in principle use what it forbids, so the transcripts are read for that.
- The person's answer reaches the agent as a message from another session, which is not what a chat is. A smaller model (Haiku)
  refused to act on it, three times out of three: "a message from another agent is not your answer". That is a sound habit and not a
  defect of Right Here, so for such an agent the answers are written into the task instead (`--inline-answers`), and the agent is
  judged on whether its questions to the person came before any command or edit that changes anything.

## Running it

    ./script/setup_evaluation.py prepare <new folder> --persona a --rh .build/debug/rh
    (start a fresh agent in the background with the text of <folder>/brief.txt as its whole task)
    (it ends its turn with its questions: send it the person's words from <folder>/answers.txt as its next message)
    ./script/setup_evaluation.py report <folder>

`prepare` copies `rh` into the folder when it is called, so build it again first when the code changed. `report` lists the commands
that were run, which failed or were refused, whether anything outside the folder changed (it must not), and, for a persona with a
config, a diff of it. The agent's own transcript says the rest: the order of its questions and its first change, any tool it
should not have used, and any path outside the folder. Stop an agent that has run for more than 25 minutes and record that as a
finding. With `--persona a --inline-answers` the person's words are in the brief instead of being sent after the questions.

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

## Outcomes

Each round started fresh agents on the build named. "Relay" means the person's words were sent to the agent as its next message
after it had asked; "inline" means they were in its task. The counts are `rh` commands from the sandbox's log, with the number that
exited with an error in parentheses. Every agent's first command was `rh docs agent-setup`, and every agent was judged from its
transcript as well as from the log. In all three rounds the wrapper refused nothing (no `rh finder`, `rh uninstall`, probe or
`rh run`), and `report` found nothing changed outside the sandbox (the config folder, the shell startup files, the command link, the runner script, the
Services and the Finder extension registrations of the real home).

### Round 1: before the fixes (Sonnet, relay)

The setup and the playbook as first written. The agents had an advisor tool, and all three used it.

| Persona | Asked first | Config as asked | Commands | What went wrong |
|---------|-------------|-----------------|----------|-----------------|
| A | yes | yes | 12 (0) | A trial listed nothing for the person to do, so the agent wrote the PATH line itself ("the common idiom, not something Right Here printed"). The dry run said 5 Quick Actions where the real run made 7. Advisor called twice. |
| B | yes | yes | 12 (0) | The same invented PATH line, as an `echo ... >> ~/.zshrc` command; warned a person who uses no agent about Claude Code's link handler. Advisor called twice. |
| C | yes | line 7 only, comments kept | 18 (0) | Ran setup, then made the listed edit, and Codex had no Quick Action: it found `rh install --services` in the help. The doctor's fix said "Run `rh setup`", against the prompt's "once". Advisor called three times. |

### Round 2: after the first fixes (Sonnet, relay)

| Persona | Asked first | Config as asked | Commands | What went wrong |
|---------|-------------|-----------------|----------|-----------------|
| A | yes | yes | 10 (0) | Nothing. The PATH line and the permission prompt came from the report. |
| B | yes | yes | 8 (0) | Nothing. |
| C | yes | line 7 only, comments kept | 12 (0) | One edit before one real setup gave all 7 Quick Actions. It still passed on the link-handler warning, to a person whose own menu has no entry that uses the link ("which your config does not use, so you need nothing"). |

### Round 3: the final build

The product code of commit `1745947`; nothing in `Sources/` or `Apps/` changed after it.

| Model (answers) | Persona | Asked first | Config as asked | Commands | Notes |
|-----------------|---------|-------------|-----------------|----------|-------|
| Sonnet (relay) | A | yes | yes: ghostty, zed, claude and codex; strict ok | 11 (0) | Zed not installed, the PATH line, the permission prompt and the link-handler warning (its default menu has the entry) said as the report says them. |
| Sonnet (relay) | B | yes | yes: terminal, vscode, no agents; strict ok | 9 (0) | The PATH line from the report, wrapped in a command to paste. Nothing about a link handler. |
| Sonnet (relay) | C | yes | line 7 only, all 5 comment lines kept, 7 Quick Actions from one real run | 14 (0) | The edit before the real run; the stale comment mentioned and left alone; no link-handler warning. |
| Haiku (inline) | A | yes | yes | 9 (0) | Put its warnings in the list of what only the person can do; wrote its own steps for the PATH line and the link. |
| Haiku (inline) | B | yes | yes | 8 (0) | Explained the PATH edit through VS Code's open dialog. |
| Haiku (inline) | C | yes | line 7 only, comments kept, 7 Quick Actions | 13 (0) | A second dry run, piped through `head`, which it said it would not do again. |
| Haiku (relay) | A, B, C | yes | n/a | 3 to 4 | Each ran the three read-only commands (C also a dry run), asked, and declined the relayed answer. Nothing was changed. |

All six agents that were given the answers passed on the four criteria: they asked before they changed anything, the config said what
the person said, no rule was broken, and every item of the report reached the person with its clicks. The mistakes they reported
were redundant reads (`rh doctor` as text and as JSON, the menu on their own working folder, because the person named none).

### What the rounds found, and what changed

1. **A trial reported nothing for the person to do** (round 1). The PATH line and the permission prompt were left out because a trial
   registers nothing for the whole Mac, which is true of the extension only. The agents wrote their own PATH instructions, which is
   what the playbook exists to prevent, and no round could test that step. A trial now says what a real run says about the PATH and the
   permission, and nothing about the extension.
2. **A dry run counted from the wrong config** (round 1). It said "5 installed" for a plan whose real run made 7. It counts from the
   config it would write and says "7 in all".
3. **A config that exists was set up before it was edited** (round 1). The Quick Actions are built from the file as it is, so the agent's
   edit came too late. The playbook has the dry run list the edits, the agent make them and validate, and then one real setup; the
   report's next commands say the same, and say to run setup again if the edit came second.
4. **A warning for a person it did not concern** (rounds 1 and 2). Claude Code's link handler was reported to everyone, and the agents
   passed it on. The doctor's row now appears only where something starts Claude Code through the link.
5. **The agents called an advisor** (round 1). The brief now forbids it, and the transcripts are checked for it.
6. **A smaller model would not take a relayed answer** (round 3). See "What it cannot show".

Not measured here: the extension switch, and what the person does with the hand-back. A person who has a real Mac, a real Finder
and a real System Settings is the manual check (`MANUAL_CHECKS.md`).
