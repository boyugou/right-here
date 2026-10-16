# 0025: The flags a built-in terminal adapter uses are the ones the terminal documents

Date: 2026-10-16. Status: decided.

## The problem

WezTerm, kitty and iTerm2 had adapters written from memory of their command lines, and Alacritty, Warp and cmux were handed the folder with `open`; no terminal of those has been
run on a Mac that Right Here was written on, and nothing recorded where a flag came from. ADR 0024 did this for the agents; this is the same read for the terminals, on 2026-10-16,
by a reader who ran nothing and used each terminal's own documentation, its man page or the Homebrew cask metadata (53 points: 40 confirmed, 2 wrong, 11 not confirmable).

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
- **Not confirmed, so said so:** that the whole chain `open -n -b <id> --args ...` works (each link is documented, no source shows the invocation as a whole); iTerm2's tab placement
  (it assumes a new tab becomes the current one, which the documentation does not say) and its split placement; what `open` does with a folder for iTerm2, Warp and cmux; kitty's
  `macos-launch-services-cmdline` file, which kitty merges into what `open` passes. `rh doctor --probe-launch` is how a person checks a terminal, and MANUAL_CHECKS lists them.

## Licence

Several of these terminals are GPL (kitty, iTerm2, cmux). The reader was told to use documentation; where it also read a source file to check that a flag exists, nothing was copied and
nothing from those files is in this repository (hard rule 1): this record cites documentation, man pages and cask metadata only.

## Consequences

- The command-capable terminals are Ghostty, Terminal, iTerm2, WezTerm, kitty and Alacritty; the doctor's advice names all six.
- Alacritty is no longer a Homebrew cask (disabled on 2026-09-01, `fails_gatekeeper_check`), which TROUBLESHOOTING says.
- A terminal that was never run is listed in `docs/development/MANUAL_CHECKS.md`; a person with one of them is who settles the rest.
