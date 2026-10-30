# 0031: Right Here reads no settings from the folder it acts on

Date: 2026-10-29. Status: decided; project-local settings (a `.right-here.toml` at the git root behind a step of trust) were considered and
are not built.

## Decision

Right Here keeps one config, the person's own (and the layers it names, ADR 0026). A file in the folder that is right-clicked, or at
its git root, is never read for settings. The ROADMAP's ranked idea is taken off it, and this record says why.

## What such a file could have changed

The Finder extension builds its menu from a cached read of the person's config and does nothing else (hard rule 5), so it cannot read
a file of the folder it is showing the menu for. A project file could only change what a click does once `rh` runs, never what the
menu shows. Every item names what it does: "Open in Ghostty", "Open in Visual Studio Code", an agent by name, a preset by its title, a
variant in the agent's submenu. Sorted by what is left:

- **The terminal, the editor, an agent's command or terminal, a preset's prompt, an `[[app]]`.** The item would say one thing and do
  another: "Open in Visual Studio Code" opening Cursor because a repository said so. Out, whatever the trust.
- **An agent's arguments, environment or `bypass_permissions`.** The item stays true, but these run code: `--mcp-config ./x`, or the
  flag that lets an agent act without asking, set by a repository someone cloned, is a way to run that repository's programs with the
  agent's rights. They need the step of trust, and the step is weaker than it reads (below). The agents that would take them already
  read settings of their own from the project, behind their own rules: Claude Code reads `.claude/settings.json`
  ([settings](https://docs.anthropic.com/en/docs/claude-code/settings)), Gemini CLI reads `.gemini/settings.json`
  ([configuration](https://geminicli.com/docs/get-started/configuration/)). A second layer in Right Here would be a second place for
  the same choice.
- **`terminal_placement`.** Harmless and true to its item. It is the whole of what remains, and a tab or a window per project does
  not pay for reading a file that a stranger can write into the folder, a parser fed with it on every click, and its tests.

## The step of trust, had it been built

Trust pinned to the bytes of the file and to its resolved path, stored under the person's state (never in the repository), a changed
file ignored with a notice while the click goes on with the person's config, and a symlinked or oversized file refused: this would
hold against a file that changes. It would not hold against who grants it. The MCP server can be kept
from granting it, as `ConfigTrust` keeps it from other changes. An agent running in a terminal can run `rh trust` itself, and a check
for a terminal does not stop it, since agents are given one. A protection that an agent in the same folder
can switch off is not one to build a reversal of a safety rule on.

## Alternatives

- **A harmless subset without trust** (only `terminal_placement`): safe, and too small to be worth a file format.
- **Per-folder settings in the person's own config** (a table keyed by a folder): no stranger writes it, and the extension knows the
  folder it builds the menu for, so it could even name the right app. Not built because nobody has asked for a per-project terminal
  or editor; it is the shape to start from if someone does.
- **Reading the file only for items that say nothing of what they run** (a placement): the same as the first.

## Consequences

- The ROADMAP's "Ideas, ranked" is empty until the next idea earns its place.
- DESIGN section 9 keeps its rule 4, that configuration is never loaded from the folder being acted on; no mutation entries are
  needed for a reader that does not exist.
