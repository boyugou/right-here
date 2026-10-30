# 0025: The flags a built-in terminal adapter uses are the ones the terminal documents

Date: 2026-10-16. Status: decided.

## The problem

WezTerm, kitty and iTerm2 had adapters whose flags had no recorded source, and Alacritty, Warp and cmux were handed the folder with `open`; none of those terminals had been
tried with Right Here on a real Mac, and nothing recorded where a flag came from. ADR 0024 did this for the agents; this is the same read for the terminals, on 2026-10-16,
without running any of them, from each terminal's own documentation, its man page or the Homebrew cask metadata (53 points: 40 confirmed, 2 wrong, 11 not confirmable).

## Decision

- **A flag is in an adapter when the terminal's own documentation or man page gives it.** Confirmed that way: `open(1)`'s `-n`, `-b` and `--args` (Apple's man page: `--args` hands the rest
  to the app's argv), WezTerm's `start --cwd <dir>` and the program after `--` (wezterm.org/cli/start.html; the app's executable is `wezterm-gui`, which the `start` subcommand is part of; a
  running WezTerm takes the request and the new process leaves), kitty's `--directory` and the program after the options (sw.kovidgoyal.net/kitty/invocation), and Alacritty's
  `--working-directory` and `-e`, which must come last (its man page).
- **Alacritty gets an adapter of its own.** It was handed the folder with `open -b org.alacritty <folder>`, but its Info.plist declares no document types, so nothing says the folder is
  used as the working directory, and it ranks fifth among the default terminals: a Mac with Alacritty and nothing better could have got a window in the wrong folder. It now starts as
  `open -n -b org.alacritty --args --working-directory <folder> [-e <shell> -lic '<command>; exec <shell> -l']`, the same shape as WezTerm's.
- **kitty is told to quit with its last window** (`-o macos_quit_when_last_window_closed=yes`, documented): `open -n` starts a separate kitty each time, and kitty stays running on macOS
  with no window by default, so each launch would leave an idle process and a Dock icon behind.
- **WezTerm is never handed a folder with `open`**: its handler for an opened file types the path into a new shell as a command, so the folder would be run (hard rule 3). Its comment
  said it always opens a window; it opens a tab when the person's config says `prefer_to_spawn_tabs` and a WezTerm is already running.
- **Not confirmed, so said so:** that the whole chain `open -n -b <id> --args ...` works (each link is documented, no documentation shows the invocation as a whole); iTerm2's tab placement
  (it assumes a new tab becomes the current one, which the documentation does not say) and its split placement; what `open` does with a folder for iTerm2, Warp and cmux; kitty's
  `macos-launch-services-cmdline` file, which kitty merges into what `open` passes. `rh doctor --probe-launch` is how a person checks a terminal, and MANUAL_CHECKS lists them.

## Warp and cmux, read again (2026-10-29)

- **Warp documents a folder, not a command.** Its URI Scheme page (docs.warp.dev/terminal/more-features/uri-scheme) gives
  `warp://action/new_window?path=<path_to_folder>` and `warp://action/new_tab?path=<path_to_folder>`, and lists what the scheme does
  not do, among them running "a shell command, script, or agent prompt in the new tab or window". A layout that runs commands is a
  saved Tab Config, opened with `warp://tab_config/<name>`, which is a file in Warp's own configuration (the older Launch
  Configurations, `warp://launch/<path>`, are files too). Warp Preview takes `warppreview://`; its bundle identifier,
  `dev.warp.Warp-Preview`, is the one its Homebrew cask (`warp@preview`) names.
- **So Warp gets an adapter of its own** (`WarpAdapter`): `open -b dev.warp.Warp-Stable warp://action/new_window?path=…`, or `new_tab`
  for a tab; a split opens a window. It still refuses agents. The page does not say whether `path` is percent-decoded or how Warp
  applies it, so every byte outside RFC 3986's unreserved characters and `/` is percent-encoded (an `&`, `#` or `=` in a name cannot
  add to the request; tested by parsing the link back) and a folder with a control character is refused, as for a terminal that
  types the folder. Not confirmed: that Warp decodes the path, and what it does when it is not running. MANUAL_CHECKS, section 2.
- **`open` runs in `/`.** Its man page says a URL that also matches a file path is opened as that file unless `-u` is given, and
  `warp://action/…` read as a path is `warp:/action/…` under the working directory, which a cloned repository could hold; `rh` run
  there would hand Warp a file. Every `open` of the executor now runs in `/`, where no such folder can be made without an
  administrator (`LiveExecutorTests`). This was found by an independent review of the adapter.
- **Agents in Warp are not built.** A Tab Config per start would be a file written into Warp's configuration with the command in it,
  for a path nobody here can run.
- **cmux stays handed the folder.** Its CLI reference (cmux.com/docs/api) documents `new-workspace` with no folder, `new-split
  --command`, and a socket that by default takes only programs started inside cmux; another program needs the person to set
  `CMUX_SOCKET_MODE`. Nothing documents opening a folder.

## Licence

Several of these terminals are GPL (kitty, iTerm2, cmux). This record cites documentation, man pages and cask metadata only, and no code from these projects is in
this repository (hard rule 1).

## Consequences

- The command-capable terminals are Ghostty, Terminal, iTerm2, WezTerm, kitty and Alacritty; the doctor's advice names all six.
- Alacritty is no longer a Homebrew cask (disabled on 2026-09-01, `fails_gatekeeper_check`); TROUBLESHOOTING says where to get it.
- A terminal that was never run is listed in `docs/development/MANUAL_CHECKS.md`; a person with one of them is who settles the rest.
