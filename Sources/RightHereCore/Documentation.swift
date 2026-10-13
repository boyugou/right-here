import Foundation

/// Built-in documentation, printed by `rh docs` and served by the MCP server.
public enum Documentation {
    public static let actions = """
    # Action ids

    `rh run <id>` runs an action. `rh actions` lists the ones available on this machine.

        copy-path.<style>              copy the path of the selection (or the folder)
                                       styles: \(PathStyle.allCases.map(\.rawValue).joined(separator: ", "))
        open.terminal[@<terminal>]     open the folder in the default terminal, or in <terminal>
        open.editor                    open the selection in the default editor
        open.app.<app>                 open the selection with any app (see `rh apps`)
        agent.<agent>[.<variant>][@<launcher>]
                                       start an AI agent in the folder (see `rh agents`)
                                       launcher: a terminal id, "default" (the default terminal),
                                       "link" (the agent's own terminal deep link, reuses its
                                       last terminal) or "desktop" (its desktop app)
        preset.<id>[@<terminal>]       send a prompt preset, with the selected files as @-mentions, to its
                                       agent in a terminal (config `[[preset]]`; built in: review, explain, tests).
                                       The agent starts working on the prompt at once.
        new-file.<template>            create an empty file next to the selection or in the folder
        reveal                         select the items in Finder

    Examples:

        rh run copy-path.git-relative src/main.swift
        rh run agent.claude.continue@ghostty ~/code/project
        rh run agent.codex@desktop ~/code/project
        rh run preset.review src/main.swift src/util.swift
        rh run new-file.md --container ~/notes

    Add --dry-run to see the plan without running it, and --json for machine-readable output.

    `rh actions` marks an action available when it can run on this machine (the terminal or app is
    installed, the terminal can run commands). It does not check that an agent's own command is
    installed: `rh agents` shows which agent commands your login shell finds.
    """

    public static let agentSetup = """
    # Setting up Right Here (for AI agents)

    Goal: leave the person with a working Finder menu without making them click through settings.

    1. Run `rh doctor --json`. Fix every entry whose status is "fail" using its "fix" text. Entries with
       status "needs-user" are things only the person can do (for example switching a Finder extension on
       in System Settings); tell them exactly what the entry says.
    2. Run `rh init` if there is no config file, then read it. It is TOML with comments.
    3. Edit `config.toml` to match what the person asked for. `rh docs config` lists every key.
       Prefer small edits; never delete the person's comments.
    4. Run `rh config validate --json --strict`. Fix every error and every warning: an unknown key is
       only a warning because the rest of the file still applies, but it is almost always a typo, and
       whatever it was meant to set is then silently missing. The `replacement` field of a diagnostic
       is the likely fix. `--strict` exits with status 1 until the file is clean.
    5. Run `rh menu --container <a folder>` to preview the menu and confirm it matches the request.
    6. To test an action without side effects, use `rh run <action> --dry-run --json`.
    7. The Finder menu reads the config each time it opens, so menu edits take effect at once. Quick
       Actions (Services) are files written by `rh install --services`: run it after changing
       `[services]` or the menu titles, and check `rh doctor` afterwards.
    8. Only if the person wants agents to start in a terminal, and agrees to a window opening and closing for
       a second, run `rh doctor --probe-launch`: the Finder extension starts a throwaway terminal session
       and proves a typed command runs there. The first time, macOS asks whether Right Here may control
       the terminal; tell the person to click Allow and run it again if it reports "needs-user".

    Rules of thumb:
    - Agents start in the folder that was right-clicked. The command typed is the agent's own command, so
      the person's PATH, version managers and aliases apply.
    - Paths with line breaks or control characters are refused for typed launches.
    - Use ids from `rh actions`; `rh docs actions` explains the grammar.
    - When something does not work (no menu, a click that does nothing, a permission prompt), read
      `rh docs troubleshooting` before guessing.
    """

    public static let sync = """
    # Keep your config in sync

    One config on several Macs, with the differences kept per machine. Two parts: an optional per-machine
    overlay, and a copy of the config in a plain folder.

    ## The per-machine overlay: config.local.toml

    `config.local.toml` sits next to `config.toml` and is read with it, by `rh` and by the Finder menu. It is never
    synced. It holds what differs on this Mac. Where it and `config.toml` meet:

    - A setting the overlay sets replaces the shared one (`[general] terminal`, `[new_file] then`, ...).
    - A list is replaced as a whole, never merged: `menu.items`, `services.items`, `copy_path.styles`, `general.agents`.
    - Entries with an id merge by id: an `[[app]]`, `[[preset]]`, `[[new_file.template]]` or `[[agent.<id>.variant]]`
      in the overlay replaces the shared entry with that id, and one with a new id is added (so an overlay preset adds
      to the shared ones instead of replacing them all). Two entries with one id inside the overlay are a duplicate,
      reported like any other (the first is used).
    - `[agent.<id>]` merges key by key, so the overlay can change one agent's `command` and keep its variants.
    - `disabled = ["id", ...]` removes ids from the result on this Mac: apps (the built-in ones too: a disabled
      terminal is not offered, cannot be named in an action id and is no longer the default), new-file templates and
      agents, and their entries in `general.agents`, `menu.items` and `services.items`. A built-in agent is only taken
      out of those lists. A preset whose agent is disabled is dropped, with a warning; if it replaced a built-in preset,
      the built-in one is back. An id that does not exist here is skipped, so a shared config may name apps this Mac
      lacks. Disabling every template the shared config defines brings the built-in txt and md back. `disabled` does
      nothing in `config.toml` and is reported there.

    Example, a work laptop without Codex and with another default terminal:

        disabled = ["codex"]
        [general]
        terminal = "terminal"

    A problem in either file is reported with its own file name (`rh config validate`, `rh doctor`).
    Per-machine differences need no overlay when they are only missing software: an app or agent that is not
    installed is skipped by the menu; use `disabled` for what is installed but should not be offered.

    ## Sync through a folder

    The config is copied, not linked. A symlink to iCloud Drive does not work here: the Finder extension is
    sandboxed and can read only its own config folder, not what a link points at, and iCloud can replace a file it
    has not downloaded with a placeholder that looks like a missing file through a link. So each Mac keeps an
    ordinary file, and `rh config sync` moves content between it and a folder.

        rh config sync enable                     choose the folder (default: iCloud Drive, folder "Right Here")
        rh config sync enable --folder ~/Sync/rh  any folder works: Dropbox, a git checkout, a network share
        rh config sync push                       send this Mac's config to the folder (creates the folder)
        rh config sync pull                       take the folder's config (refused, with a list, if it adds programs)
        rh config sync pull --allow-commands      take it although it adds or changes terminal templates or agent commands
        rh config sync status                     in-sync, local-ahead, remote-ahead, diverged, remote-missing or remote-evicted
        rh config sync disable                    forget the folder; both copies stay

    The state (the folder and a hash of what was last synced) is in `sync.toml` next to the config.
    A second Mac runs `rh config sync enable` and `rh config sync pull`.

    Rules, all enforced:
    - `pull` refuses when this Mac's config changed since the last sync, and `push` refuses when the folder's copy
      did, unless `--force`. A forced replacement saves the old file as `config.toml.bak-<date>` first.
    - Both refuse a config that does not validate, is over 1 MiB, or has key names that look like secrets
      (token, secret, password, api_key). Keep credentials in the environment or the keychain.
    - A config carries programs, and the folder can be written by other Macs, a sync service or a shared drive, so
      `pull` also refuses, and lists them, when the folder's copy would add or change something Right Here starts: a
      terminal template (`open_args`, `run_args`), an agent's `command`, a variant's `arguments` or its `prompt_arg`, or
      a default terminal that starts through a template. Read the list; if it is yours, run
      `rh config sync pull --allow-commands` (a separate flag from `--force`; they combine). `status` and `enable`
      show the same list, `rh doctor` has a row for it, and a first pull on a new Mac asks only about programs of your
      own, never about the built-in apps and agents.
    - A copy iCloud has not downloaded (`remote-evicted`) is never read as missing and never overwritten.
    - Writes are atomic (a temporary file beside the destination, then a rename), and nothing is deleted.
    - `rh doctor` adds checks while sync is on: the folder is reachable, the copy is downloaded and valid, how the
      two compare, and conflict copies such as `config 2.toml` that a sync service leaves when two Macs wrote at once.

    ## Dotfiles, Dropbox and git

    - A dotfiles manager may keep `config.toml` as a symlink into its repository: `rh` follows it, and the Finder
      extension may not be able to (`rh doctor` warns); copy the file instead. `rh config sync pull` writes into
      the file a link points at and leaves the link.
    - Dropbox or any synced folder: `rh config sync enable --folder <folder>`.
    - A git repository: make it the folder, and commit there; Right Here only reads and writes `config.toml` in it.
    - Keep per-machine differences in `config.local.toml`, and out of the repository or the folder.
    """

    public static let config = ConfigSchema.markdown() + "\n\nOne config on several Macs, and per-machine settings in config.local.toml: `rh docs sync`.\n"

    /// The topics, in the order they are listed, with a one-line summary each. Every surface that names topics
    /// (`rh docs`, the MCP docs tool) takes them from here.
    public static let topicSummaries: [(name: String, summary: String)] = [
        ("config", "every setting in config.toml, with defaults and examples"),
        ("sync", "keep the config in sync across Macs: config.local.toml and rh config sync"),
        ("actions", "the action id grammar"),
        ("agent-setup", "how an AI agent should set up Right Here"),
        ("troubleshooting", "the menu does not appear, a click does nothing, permission prompts")
    ]

    public static let topics = topicSummaries.map(\.name)

    /// The topic list `rh docs` prints without an argument.
    public static var listing: String {
        "Topics:\n" + topicSummaries.map { "  " + $0.name.padding(toLength: 17, withPad: " ", startingAt: 0) + $0.summary }.joined(separator: "\n")
    }

    /// The topic a mistyped word most likely meant.
    public static func closestTopic(to word: String) -> String? {
        let word = word.lowercased()
        return topics.first { !word.isEmpty && ($0.hasPrefix(word) || word.hasPrefix($0)) }
    }

    public static func text(for topic: String) -> String? {
        switch topic {
        case "config": return config
        case "actions": return actions
        case "agent-setup": return agentSetup
        case "sync": return sync
        default: return guides[topic]
        }
    }
}
