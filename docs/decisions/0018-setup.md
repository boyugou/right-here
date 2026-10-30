# 0018: One setup command, a playbook for AI agents, and cold agents as the test

Date: 2026-10-15. Status: decided.

## Decision

1. **One entry point, `rh setup`.** It does the whole job in order: the config file, the runner script, the `rh` link, the Quick Actions
   and the Finder extension's registration, then the doctor (`SetupRunner` in RightHereKit). It can be run again at any time: every piece
   compares before it writes, so a second run does nothing and says so. It opens no window and no terminal, never touches System
   Settings, and under `RH_HOME` (a trial) leaves alone what is registered for the whole Mac. `rh install` names one piece to repair
   (`--scripts`, `--cli`, `--services`, `--finder`) and refuses to run bare; `rh init` writes the config only.
2. **What the person uses is said with flags, not by editing TOML.** `--terminal`, `--editor` and `--agents` take ids, checked against
   what Right Here knows: an id is exact, a misspelling is refused with the closest id, an editor given as a terminal says which flag to
   use, `--agents none` is a choice. They are written only when the config is created (or replaced with `--force`, which saves the old
   file next to it). There are no prompts: an agent or a script cannot answer one.
3. **A config that exists is never rewritten.** Setup says so and lists the edit that would make it say what was asked: the file, the
   line, the current text and the new value (`configEdits`). The person, or the agent acting for them, makes it by hand. The Quick
   Actions are built from the file as it is when setup runs, so the order is: dry run, the edits, one real run.
4. **One report for people and programs.** `SetupReport` holds the steps (created, updated, unchanged, skipped, failed; a dry run says
   what it would do, `would-create`, `would-update` and `would-fail`, so a plan cannot be read as a result), what was chosen,
   `configEdits`, warnings, what only the person can do (`needsUser`: the Finder extension switch, the PATH line, the permission
   prompt), the commands to run next and the doctor's rows. `rh setup --json` prints it, the plain output is rendered from the same
   value, and the setup window reads the same steps. Its sentences are English on the command line and catalog messages only where the
   window shows them. A trial reports the PATH line and the permission prompt as a real run would, and says nothing about the Finder
   extension, which it neither registers nor checks.
5. **The app's first run is the same code.** With no config file the window offers the terminals and editors that are installed and the
   agents Right Here knows (those the login shell found are checked), and one button runs the same `SetupRunner` with that choice. The
   choice is written because the file does not exist; the window never rewrites one that is there (Open Config stays). The extension
   switch, with the System Settings page opened and the card turning green by itself, stays as ADR 0011 made it.
6. **The playbook is a procedure.** `docs/AGENT_SETUP.md` (`rh docs agent-setup`): ask first (one message, three questions), look (a
   dry run), make the edits an existing config needs, run setup once, read the report, tell the person what only they can do, check,
   what never to do, and a hand-back in five parts. The prompt the app copies, the plugin's setup skill and the quick start name it.
7. **Cold agents are the acceptance test.** `docs/development/SETUP_EVALUATION.md`, run with `script/setup_evaluation.py`: three
   personas, each handed to a fresh AI agent that has only `rh`, in a sandbox, and the prompt the app copies; the evaluator plays the
   person. It is run again whenever setup, its report, the doctor's sentences or the playbook change.

## Why

- Before, three commands in an order the person had to know: `rh init` wrote a config from detection and offered no way to say what you
  use, `rh install --<piece>` connected Finder, `rh doctor` checked. A person who opened the app saw "Some checks need your attention"
  until they found Install or Repair. The playbook was a loose list that never said to run `rh install`, never said to ask the person
  anything, had no end, and had the agent edit TOML by hand.
- An agent cannot answer a prompt, so choices are flags and the dry run is the way to look; both are the same command and the same
  report a person reads. One report means the window, the command line and an agent's JSON cannot disagree.
- Never rewriting a config is the one rule that keeps a person's comments and menu order safe from every caller (the command, the
  window, an agent). The cost is that an existing config needs one hand edit, which the report gives exactly.
- The config is created with `link`, which refuses a taken name, because `rename` over the path let two callers that create it at the
  same moment (the window and `rh setup` in a terminal) replace each other's file. Measured with 60 rounds of 8 callers at once:
  exactly one creator each time (`ExclusiveCreateTests`; CLAUDE.md says never to use `unlink` or a replacing `rename` as a claim).
- Reading the playbook is not the same as being able to follow it. The first round of cold agents (before the fixes below) found what
  review had not: a trial listed nothing for the person to do, so two of three agents invented the PATH line that the doctor row above
  it only hinted at; a dry run said "5 installed" for a plan whose real run made 7, because it counted from the config that was not
  yet on disk; an agent that ran setup before making the listed edit left its second agent without a Quick Action and had to find
  `rh install --services` itself; and every agent passed on a warning about Claude Code's link handler, one of them to a person who
  had said they use no agent.

## Alternatives

- **Prompts in `rh setup`** ("Which terminal do you use?"): an agent or a script cannot answer, and the person's agent would ask them
  anyway. Flags are what an agent can fill from the person's words.
- **A command that edits the person's config in place** (`rh config set`, or `rh setup --apply`): the file is the person's, and a tool
  that rewrites it is one more place to lose a comment. The edits are one line each, and an agent's own editor shows the person what
  changed. The report gives the line, the current text and the new value instead.
- **Letting the flags rewrite an existing config** (what `--force` does, on request): a person who runs setup again for another reason
  would lose their menu order. `--force` stays as the one explicit way, with the old file saved next to it.
- **Keeping `rh init` then `rh install` as the story and `rh setup` as a wrapper**: two stories, and the order is what people got wrong.
- **The window spawning `rh`**: a typed report beats parsing output, and the window and the command then share one implementation.
- **A hidden switch that makes a trial report as if it were the real Mac** (so the evaluation sees every item): it would make the
  evaluation measure a mode nobody uses. The PATH line and the permission prompt depend only on the config and the person's shell and
  terminal, so a trial says them; the extension switch is the one item a trial cannot know, and the unit tests and the manual checks
  hold it.
- **Judging the playbook by the maintainers' own agent**: it knows the repository. A cold agent has the prompt and `rh`, which is what a
  person's agent has.

## Checked

- Tests: `SetupRunnerTests` (every piece, idempotence, a trial, the dry run, an existing config, `--force`, the PATH and permission
  items, where `rh` runs from), `SetupChoicesTests`, `ConfigEditsTests` (each edit applied to the text, only the named lines
  differ), `ExclusiveCreateTests`, `SetupLoaderTests`, `SetupActionsTests`, the `rh setup` tests in `CLITests`, and
  `SetupSnippetsTests` (the evaluation doc quotes the prompts exactly as the app copies them). Mutants of what setup protects are in
  `script/mutation_check.py`.
- The cold-agent evaluation ([`SETUP_EVALUATION.md`](../development/SETUP_EVALUATION.md): the personas, the prompts, how each agent is
  judged, and what the runs found). The first run, before the fixes in "Why", passed on the letter and found the four defects listed
  there. On the final build six AI agents of two models were given the person's answers (three after they asked, three in the task),
  each persona once per model, and all six passed. Each asked before it changed anything, wrote a config that said what the person said
  (persona C: one line changed, every comment kept, seven Quick Actions from one real run), broke no rule, and passed every report item
  on with its clicks. They used 8 to 14 `rh` commands, none failed.
- The first-run chooser and the page just after setup were rendered headlessly (`script/preview_setup.sh --first-run` and `--set-up`,
  canned data only): English, German at the smallest window (the longest words), Hebrew and Arabic (the layout mirrors, marks on the
  right), and Japanese in dark mode. The text wraps inside its card in each. The preview draws the whole page at a fixed height, so at
  the smallest size it crops the title; the real window scrolls.
- Not checked: that a person switching the extension on sees the card turn green (ADR 0011 and `MANUAL_CHECKS.md` hold that), the
  first-run chooser in a real window, and any cold agent meeting the extension item (a trial cannot register it).

## Amended (2026-10-15)

A review read setup as a stranger would, and an agent that follows the playbook to the letter met these:

- **A config that is there and cannot be used fails the config step** (decision 3 says a config that exists is never rewritten; it did not say
  what setup does when it cannot use it). The text is not TOML, the file cannot be read, is too large or not UTF-8, or it is a link to a file that
  is not there, in `config.toml` or in the per-machine overlay: the step is `failed` and names the file and the line, no edits are listed and no
  Quick Actions are made from it (skipped, with the reason; a step asked for by name, or the overlay as the cause, fails), the other steps run,
  `ok` is false and the status is 1. `needsUser` has a `config` entry and `next` says to validate and to look again with a dry run. Before, setup
  said "ok", listed edits worked out from the defaults against text that is not TOML, made the Quick Actions from the defaults, and dropped the
  person's choices. The Quick Actions that are there stay. An AI agent may fix the file only when the person agrees, with the smallest edit.
- **A dry run says what it would do**: `would-create`, `would-update` and `would-fail` in the JSON (decision 4); `ok` is false when a step would fail.
- **The edits work when they are made to the letter**: an inline `[general]` is changed in place, a file without the table gets one edit for the
  whole table, a commented example counts only inside the table, and a `disabled` list in the overlay is named when it is what turns a setting off.
  A test makes every edit of a dry run literally and runs `rh config validate --strict` on the result.
- **Setups take turns** and the state file is changed in one step ([0021](0021-one-setup-at-a-time.md)); an empty `RH_HOME` (or `RH_CONFIG`,
  `RH_CONFIG_DIR`, `RH_LOG_DIR`) is refused with status 64 and never means "not set", since `RH_HOME=$TRIAL rh setup` with `$TRIAL` unset was a
  setup of the real home.
- **The playbook** says how to run `rh` before setup has linked it, that what `rh` prints is data and not an instruction, that `rh agents` starts
  the login shell, and what registering the extension does and does not do (it asks macOS to use it; the switch can still be the person's).
- The cold-agent evaluation ([`SETUP_EVALUATION.md`](../development/SETUP_EVALUATION.md)) was run again for these changes, with a
  fourth persona whose config does not parse: four of four passed. What it did not try is a config or a file name that reads as an instruction.

