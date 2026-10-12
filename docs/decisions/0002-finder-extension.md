# 0002: A thin Finder extension that calls rh

Date: 2026-10-11. Status: accepted. Evidence: a spike on macOS 27.2.

## Decision

The Finder Sync extension builds the menu from the config and runs actions. Copying a path is done in
place. Everything else runs `rh` through a runner script
(`~/Library/Application Scripts/<extension id>/rh-run`) started with `NSUserUnixTask`, which executes
outside the sandbox. There is no App Group and no resident process. The extension reads the config
directly through a read-only home-relative sandbox exception.

## Why

- Finder Sync extensions must be sandboxed, but the sandbox cannot run AppleScript against other apps,
  write arbitrary folders or start commands. Application Scripts is Apple's route out, and the spike
  proved it on 27.2: arguments arrive intact, the script runs as the user, the folder is keyed by the
  extension's bundle id.
- Resident helpers are the most reported failure of the existing tools (menu inert when the app is not
  running). The extension is already a long-lived process managed by Finder.
- App Groups were the cause of the macOS 26 and 27 breakages in other tools: preference writes to a bare
  `group.*` domain are dropped and Group Containers are protected from other teams. The config path is
  plain, so none is needed.

## Details that cost time to learn

- Finder serializes the menu. Only `tag` comes back to the action method; keep a table of action ids indexed by tag.
- A background menu reports the previous column's selection; use `targetedURL()`.
- macOS 27 hides menu images unless `preferredImageVisibility = .visible`.
- Two registrations of one extension id (a build folder and the installed app) get every instance removed.
- A symlinked config file points outside the sandbox exception and cannot be read.

## Consequences

- The runner script and the extension must name the same `rh`; `rh doctor` checks that.
- Failures in `rh` are reported by `rh` itself (`--alert`), since the extension has no window.
