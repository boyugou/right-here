# 0014: An agent launch is resolved once

Date: 2026-10-13. Status: decided.

## Decision

`AgentLaunchResolution.resolve(agent:hasVariant:explicit:config:facts:)` is the one place that decides how an agent
action, or a preset, starts on this machine. It applies the rule that a variant or a preset is typed (so only a
terminal can take it), then checks what the launcher needs: the agent's terminal link or desktop link, the desktop
app, or the terminal (the named one, or the default for commands), whether it is installed, whether its adapter can run
a command at all, and whether this machine blocks it (a Ghostty older than 1.3). The answer is a route (desktop link,
terminal link, or a terminal with its adapter) or an `Unavailable` that carries its English sentence.

- The planner builds the plan from the route. `ActionRegistry` describes the action from the same answer, so a
  menu entry is offered exactly when `rh run` can plan it, and `rh actions` and `rh run` use the same words.
- `DefaultApps` picks the default terminal and editor (the configured one as it is, else the first installed in the
  order of the catalog's `defaultRank`) for the planner, the registry, the menu and `rh probe`.
- A terminal adapter owns the sentence for "cannot run commands" (`commandRefusal`); the resolution reports it and
  `steps` still throws it.
- How a terminal is started (`driver`: Ghostty, Terminal.app, hand it the folder, or an argument vector from
  `open_args` and `run_args`) and where it stands in the default order are columns of its catalog row, so a new
  built-in terminal or editor is one row. An `[[app]]` that reuses a built-in id with the same role keeps that row's
  driver and rank unless it brings launch arguments of its own.

## Why

The registry used to repeat the planner's checks in different words, and the two had drifted: a desktop launch was
offered only when the agent's app was installed but planned either way, `rh actions` said "No terminal is installed"
for a default the config had made unusable, and each cannot-run-commands refusal had two sentences. A table test over
every agent, variant, launcher and terminal on ten machines and sixteen configs (`AgentLaunchAgreementTests`) found the
desktop difference and now holds the two together.

## Alternatives

- Keep two paths and test that they agree. That finds drift after the fact and leaves two sets of sentences.
- Have the registry ask the planner. Planning needs a folder and looks at the paths; building a menu does neither
  (hard rule 5).
- Return `PlanError` from the resolution. It also holds path and context errors, which the menu cannot know.

## Consequences

When a typed launch has an unusable terminal and an unsafe folder name at once, the terminal is reported first; the
folder name is still refused before anything starts. A desktop launch is refused at planning time, with the menu's
sentence, when the agent's app is not installed.
