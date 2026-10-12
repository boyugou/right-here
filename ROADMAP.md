# Roadmap

## Working

- Core: actions, planner, config, menu, catalogs, path styles, quoting (with real-shell tests).
- `rh`: run, actions, menu, agents, apps, config, init, install, uninstall, docs, doctor, finder, mcp.
- Terminal adapters: Ghostty, Terminal.app. Agent launchers: typed, terminal link, desktop app.
- The app and the Finder extension; installer; `rh doctor`.
- Finder Services (Quick Actions) generated from the config.
- MCP server and the Claude Code plugin (setup, open-here and review-changes skills).
- Thirty languages for the menu, the app and alerts (machine-translated, awaiting review).

## Next

- Confirm the typed agent launch from a real Finder click (the chain up to the Apple event is verified by
  `rh doctor --probe-extension`), and the first-ever Automation prompt on a clean machine.
- Notarized DMG, Homebrew cask and formula (`script/package_dmg.sh`).
- App icon.
- Adapters for iTerm2, WezTerm, kitty, Alacritty, Warp, cmux (documented, to be checked on real installs);
  possibly a generic config-defined adapter (an argv template with a login-shell wrapper).
- Native-speaker review of the translations.
- A menu-only App Store build.

## Open

- Whether Quick Actions appear on a folder background.
- The items, sidebar and toolbar menus on a real run.
