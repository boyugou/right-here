# Security

Right Here turns file names and configuration into commands, so it takes care over what may become
shell or AppleScript text. The rules are in [`docs/DESIGN.md`](docs/DESIGN.md), section 9, and the review that
shaped them in [`docs/decisions/0008-independent-review.md`](docs/decisions/0008-independent-review.md).

Supported versions: the latest release.

## Reporting a problem

Please report a vulnerability privately, through GitHub's "Report a vulnerability" button on the repository's
Security tab, rather than in a public issue. Include the macOS version, the command or Finder action, and the
file name or config that triggers it. A file name that makes a copied path run a command, an action that opens
or runs the wrong thing, an MCP call that does more than its arguments say, a `rh config sync pull` that takes
a terminal template or an agent command from the sync folder without `--allow-commands`, and a file in the sync folder
that makes `rh` read or parse more than a config can be (it is never read past 1 MiB) are all in scope.

## What is not a vulnerability

- Anything that needs write access to the person's own config file, `~/.config/right-here`, or the Application
  Scripts folder: the person owns those, and `rh` runs commands they configured. The sync folder is different:
  whatever can write it (another machine, a sync service, a shared drive) reaches this Mac only through
  `rh config sync pull`, which refuses a config that adds or changes a launch command until `--allow-commands`
  says the person read it.
- An AI agent that runs `right_here_run` when the person told it to. What a call opens or creates is budgeted per
  minute (a document, a Finder window or a new file is one unit, a started command three, twenty-four in all) and
  arguments are validated and capped, but an agent the person trusts with a terminal is trusted with a terminal.
