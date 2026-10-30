# Documentation

## For people who use Right Here

- [`../README.md`](../README.md): what Right Here does, how to install it and how to set it up.
- [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md): the menu does not show, a click does nothing, macOS asks for a permission. Also
  `rh docs troubleshooting`.
- `rh docs config`, `rh docs actions`, `rh docs sync`, `rh docs start`: the built-in guides of the `rh` command.
- [`../CHANGELOG.md`](../CHANGELOG.md): what changed in each version.
- [`../SECURITY.md`](../SECURITY.md): how to report a vulnerability.

## For AI assistants

- [`AGENT_SETUP.md`](AGENT_SETUP.md): the steps an AI assistant follows to set Right Here up for a person. Also
  `rh docs agent-setup`.
- [`../plugins/right-here/README.md`](../plugins/right-here/README.md): the Claude Code plugin.

## For contributors

- [`../CONTRIBUTING.md`](../CONTRIBUTING.md): how to build, test and contribute.
- [`../CLAUDE.md`](../CLAUDE.md): the rules for coding agents that work in this repository.
- [`DESIGN.md`](DESIGN.md): the architecture, the decisions, and the facts about the platform that we verified. Section 9 lists the
  safety rules.
- [`development/SETUP.md`](development/SETUP.md): build, install and test.
- [`development/WRITING.md`](development/WRITING.md): how to write the text that people read.
- [`development/RELEASING.md`](development/RELEASING.md): sign, notarize and publish a release.
- [`development/MANUAL_CHECKS.md`](development/MANUAL_CHECKS.md): the checks that need a real Finder, real terminals or a native speaker.
- [`development/SETUP_EVALUATION.md`](development/SETUP_EVALUATION.md): how cold AI agents tested `rh setup` and its playbook.
- [`development/WEBSITE.md`](development/WEBSITE.md): the website on the `gh-pages` branch, its checks, and how to publish it.
- [`development/UPSTREAM_REPORTS.md`](development/UPSTREAM_REPORTS.md): problems that we found in dependencies.
- [`../ROADMAP.md`](../ROADMAP.md): what works and what comes next.
- [`../CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md): community standards.
- [`appstore/`](appstore/): drafts of the App Store privacy statement and listing.

## Decisions

Each record says what we decided, the alternatives, and the evidence.

- [0001 Form factor](decisions/0001-form-factor.md)
- [0002 Finder extension](decisions/0002-finder-extension.md)
- [0003 Agent launch](decisions/0003-agent-launch.md)
- [0004 Config](decisions/0004-config.md)
- [0005 MCP server](decisions/0005-mcp-server.md)
- [0006 Localization](decisions/0006-localization.md)
- [0007 App Store edition](decisions/0007-app-store-edition.md)
- [0008 Independent review](decisions/0008-independent-review.md)
- [0009 Termius is not a built-in terminal](decisions/0009-termius.md)
- [0010 App Intents as a second entry point](decisions/0010-app-intents.md)
- [0011 A first-run card in the setup window](decisions/0011-first-run-card.md)
- [0012 Agent prompt presets](decisions/0012-agent-presets.md)
- [0013 Config sync: an overlay file and a copy-based sync folder](decisions/0013-config-sync.md)
- [0014 An agent launch is resolved once](decisions/0014-agent-launch-resolution.md)
- [0015 The Finder extension stays loaded, and does not keep the Mac awake](decisions/0015-finder-extension-stays-loaded.md)
- [0016 Agents that skip their permission prompts, and isolated git worktrees](decisions/0016-agent-permissions-and-worktrees.md)
- [0017 The sections of the setup window](decisions/0017-setup-window-sections.md)
- [0018 One setup command, a playbook for AI agents, and cold agents as the test](decisions/0018-setup.md)
- [0019 The Finder extension does not override the directory-observing methods](decisions/0019-no-swift-override-of-directory-observing.md)
- [0020 What the config names is data in the reports an agent reads](decisions/0020-names-from-the-config-are-data.md)
- [0021 One setup at a time, the state file in one step, and each Quick Action replaced on its own](decisions/0021-one-setup-at-a-time.md)
- [0022 A process that a test started cannot change the real home](decisions/0022-a-test-cannot-change-the-real-home.md)
- [0023 What the setup window says before it tries, and what it calls attention](decisions/0023-the-window-says-before-it-tries.md)
- [0024 A built-in field of an agent is confirmed by the tool, or it is not there](decisions/0024-a-built-in-agent-field-is-confirmed-or-absent.md)
- [0025 The flags that a built-in terminal adapter uses are the ones that the terminal documents](decisions/0025-terminal-launch-flags-are-the-documented-ones.md)
- [0026 One config, two editors: the window and the agents can change the same things](decisions/0026-one-config-two-editors.md)
- [0027 What goes to Finder is small, is never waited for, and has no separators where Finder draws them as empty rows](decisions/0027-what-goes-to-finder-is-small-and-never-waited-for.md)
- [0028 The app icon is an Icon Composer document: a prompt in a pin](decisions/0028-the-icon-is-an-icon-composer-document.md)
- [0029 The window looks like a settings window of macOS 26, and is drawn by its own views](decisions/0029-the-window-looks-like-a-settings-window-of-macos-26.md)
- [0030 A pinned or recent folder is a thing Shortcuts can pick](decisions/0030-saved-folders-for-shortcuts.md)
- [0031 Right Here reads no settings from the folder it acts on](decisions/0031-no-settings-from-the-folder-acted-on.md)
- [0032 New File makes blank Word, Excel and PowerPoint documents, and each template can be left out](decisions/0032-office-documents-from-new-file.md)
