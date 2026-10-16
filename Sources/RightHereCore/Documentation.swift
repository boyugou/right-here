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

    ## How to read a plan

    `rh run <action> --dry-run` prints what the action would do and runs nothing. The first line says
    what it is; each numbered step says what it does, and the lines under it give its values:

    - `open <bundle id>`, `reveal`: a `target:` line for each path, one to a line.
    - `AppleScript controlling <app>`: an `arguments:` line, the values the script receives, in order. The
      script itself is in `--json` (`source`); the values are never part of it.
    - `run "<program>" "<argument>" ...`: the program and each of its arguments.
    - `copy <n> characters to the clipboard`: a `text:` line with the whole text.
    - `create "<path>"`: a `contents:` line.

    Every value is a quoted string, as JSON writes one: `\\"` is a quote, `\\\\` a backslash, `\\n` a line break,
    and a control character is an escape such as `\\u001b`. Nothing is cut short. A `note:` line says what
    the plan changed or left out: a default app that is not installed and the one used instead, a new file
    that is selected rather than opened, the agent's command that the login shell did not find. `--json`
    holds the same plan as data (`steps`, `notices`), for a program or an agent to read.

    ## Starting an agent: options

    - `--worktree` starts the agent in an isolated git worktree of the repository, on a new branch, in the same
      folder the request names. `--branch <name>` names the branch, or attaches an existing one. The plan is
      made before the worktree is, so a refused request leaves nothing behind; a run that fails removes the
      worktree again when nothing in it changed. `rh worktree list`, `rh worktree add <branch>` and
      `rh worktree remove <name>` manage them: remove refuses uncommitted work unless `--force` is given, and
      only touches worktrees Right Here made.
    - `--bypass-permissions` starts the agent with its own flag that switches its permission prompts off (the
      agent's `bypass_permission_arg`, built in for the agents that have one). `--safe` starts it with the
      prompts on, whatever the config says. Both are for an agent (`agent.<id>`): a preset keeps its prompts
      on, since its prompt carries the names of the files.
    - `--arg <argument>` adds one argument after the agent's command. It can be repeated, and it is for an agent
      or a preset.

    These options apply to an agent or a preset and are an error for any other action.

    ## Pinned and recent folders

    `rh pin [folder]` keeps a folder in the list `rh pins` prints (`rh unpin <folder>` removes it), and `rh recents`
    prints the folders used with Right Here (`rh recents --clear` empties the list). They live in the state file
    next to the config. They are not part of the config, so they are never synced.

    ## Notes

    - With presets belonging to more than one agent, the menu title of a preset gets the agent's name in front
      (`Codex: Security review`).
    - A single entry in `copy_path.styles` is not a submenu: its item is on the menu's top level, titled `Copy Path` for
      the absolute path, and `Copy Path: <style>` for another style (`Copy Path: Path from Home (~)`).
    - `rh actions` prints the actions that can run on this machine, with no status column; `--all` adds the others, each
      with the reason it cannot run.
    - `RH_NO_UI` turns off alerts and stops `rh` from starting `open` or `osascript`; it is for tests, and with it set and no `RH_HOME` the commands that set up
      (`setup`, `install`, `uninstall`) refuse to change your real home folder (unset it, or give them an `RH_HOME`). `RH_HOME` moves every
      per-user path (config, log, runner script, Services, command link) under the folder it names; the login
      shell that `setup`, `init`, `agents` and `doctor` start (and `run <agent> --dry-run`, to see whether the agent's command is found,
      and `setup --dry-run` when a choice is left out) is not moved, so it runs the person's own startup files.
    - A file outside the folder of a preset's selection is named in its prompt as an absolute `@` mention, quoted
      (`@"..."`) when its path has a space.
    """

    /// What a newcomer does, in the order they need it. The first topic `rh docs` lists.
    public static let start = """
    # Quick start

    Right Here puts terminals, editors and AI agents in the Finder menu, and runs the same actions from the command line.

    1. Set it up: `rh setup` does the whole job in order, and can be run again at any time. It writes a commented
       config file (`~/.config/right-here/config.toml`) from what is installed on this Mac, puts the runner script
       and the `rh` link in place, installs the Quick Actions, registers the Finder extension, and ends with the
       checks of `rh doctor`. Say what you use with `--terminal`, `--editor` and `--agents` (for example
       `rh setup --terminal ghostty --editor zed --agents claude,codex`); a config that exists is never rewritten.
       `rh setup --dry-run` shows what it would do.
    2. Switch the extension on: the one thing setup cannot do for you. Under System Settings, General, Login Items
       & Extensions, Finder, switch on Right Here. `rh setup` says when it is still needed.
    3. See the menu before you use it: `rh menu --container <a folder>`. `--explain` also says what it leaves
       out and why.
    4. Check the setup: `rh doctor` gives a line for each thing, and a fix for each problem. `rh doctor --report`
       writes the same as Markdown, for a bug report.
    5. Try an action without doing it: `rh actions` lists them, and `rh run <action> --dry-run <path>` shows
       the plan (`rh docs actions` explains how to read it).
    6. Then `rh docs config` lists every setting, `rh docs sync` keeps the config on several Macs, and
       `rh docs troubleshooting` is for when something does not work.

    AI agents that set Right Here up for a person read `rh docs agent-setup`; agents that use it as a tool read
    `rh docs mcp`.
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
      out of those lists. A preset whose agent is disabled is dropped, with a note in `rh config validate` (not a
      warning, so `--strict` still passes); if it replaced a built-in preset, the built-in one is back. An id that
      does not exist here is skipped, so a shared config may name apps this Mac lacks. Disabling every template the
      shared config defines brings the built-in txt and md back. `disabled` does nothing in `config.toml` and is
      reported there.

    Example, a work laptop without Codex and with another default terminal:

        disabled = ["codex"]
        [general]
        terminal = "terminal"

    A problem in either file is reported with its own file name (`rh config validate`, `rh doctor`). `rh config validate`
    also reads `config.toml` on its own, as other Macs do, and reports an error that the overlay hides on this Mac (the
    overlay sets the same key); `rh config sync push` refuses that file for the same error. A key named like a credential
    in `config.toml` is an error there too, because `push` refuses it.
    `rh config show` prints both files, each under a header line that names it (`config.toml`, then `config.local.toml`
    when it exists), and `rh config path --all` lists their paths; there is no merged text, and `rh menu` shows what
    the two make of the menu.
    Per-machine differences need no overlay when they are only missing software: an app that is not installed is
    skipped by the menu (a default terminal or editor gives way to the first installed one). An agent is not: the menu
    cannot look, which takes a shell, so it still lists an agent whose command is not found (`rh agents` says
    `enabled, not found`). Use `disabled` for what is installed but should not be offered.

    ## Sync through a folder

    The config is copied, not linked. A symlink to iCloud Drive does not work here: the Finder extension is
    sandboxed and can read only its own config folder, not what a link points at, and iCloud can replace a file it
    has not downloaded with a placeholder that looks like a missing file through a link. So each Mac keeps an
    ordinary file, and `rh config sync` moves content between it and a folder.

        rh config sync enable                     choose the folder (default: iCloud Drive, folder "Right Here")
        rh config sync enable --folder ~/Sync/rh  any folder works: Dropbox, a git checkout, a network share
        rh config sync push                       send this Mac's config to the folder (creates its last folder, not its parents)
        rh config sync pull                       take the folder's config (refused, with a list, if it adds programs)
        rh config sync pull --allow-commands      take it although it adds or changes terminal templates or agent commands
        rh config sync status                     in-sync, local-ahead, remote-ahead, diverged, remote-missing or remote-evicted
        rh config sync disable                    forget the folder; both copies stay

    The state (the folder and a hash of what was last synced) is in `sync.toml` next to the config.
    A second Mac runs `rh config sync enable` and `rh config sync pull` (with `--allow-commands` when the config has
    programs of its own: see the rules below).

    Rules, all enforced:
    - `pull` refuses when this Mac's config changed since the last sync, and `push` refuses when the folder's copy
      did, unless `--force`. A forced replacement saves the old file as `config.toml.bak-<date>` first.
    - Both refuse a config that does not validate (a name or title with a control character in it does not), is over
      1 MiB, or has key names that look like secrets (token, secret, password, api_key). Keep credentials in the
      environment or the keychain.
    - A config carries programs, and the folder can be written by other Macs, a sync service or a shared drive, so
      `pull` also refuses, and lists them, when the folder's copy would add or change something Right Here starts: a
      terminal template (`open_args`, `run_args`), an agent's `command`, a variant's `arguments` or its `prompt_arg`,
      its `args` or `bypass_permissions` (permission prompts switched off), a default terminal that starts through a
      template, or a terminal app given another `role` (it would be handed files, which a terminal runs). Read the
      list; if it is yours, run
      `rh config sync pull --allow-commands` (a separate flag from `--force`; they combine). `status` and `enable`
      show the same list, `rh doctor` has a row for it, and a first pull on a new Mac asks only about programs of your
      own, never about the built-in apps and agents.
    - A copy iCloud has not downloaded (`remote-evicted`) is never read as missing and never overwritten. A file past
      the size limit (this Mac's config or the copy) is not read at all: the copy shows up as `remote-evicted` with its
      size, and `push` and `pull` never write over a file they did not read.
    - Writes are atomic (a temporary file beside the destination, then a rename), and nothing is deleted.
    - `rh doctor` adds checks while sync is on: the folder is reachable, the copy is downloaded and valid, how the
      two compare, and conflict copies such as `config 2.toml` that a sync service leaves when two Macs wrote at once.

    ## Dotfiles, Dropbox and git

    - A dotfiles manager may keep `config.toml` as a symlink into its repository: `rh` follows it, and the Finder
      extension may not be able to (`rh doctor` warns); copy the file instead. `rh config sync pull` writes into
      the file a link points at and leaves the link. A `config.toml` that is a link inside the sync folder is
      treated the same way by `push`, but only when the link leads to a file inside that folder; one that leaves the
      folder or points nowhere is refused, because anything that can write the folder could plant it.
    - Dropbox or any synced folder: `rh config sync enable --folder <folder>`.
    - A git repository: make it the folder, and commit there; Right Here only reads and writes `config.toml` in it.
    - Keep per-machine differences in `config.local.toml`, and out of the repository or the folder.
    """

    public static let config = ConfigSchema.markdown() + "\n\nOne config on several Macs, and per-machine settings in config.local.toml: `rh docs sync`.\n"

    /// The topics, in the order they are listed, with a one-line summary each. Every surface that names topics
    /// (`rh docs`, the MCP docs tool) takes them from here.
    public static let topicSummaries: [(name: String, summary: String)] = [
        ("start", "the first steps, in the order a newcomer needs them"),
        ("actions", "the action id grammar, how to read a plan, the options that start an agent"),
        ("config", "every setting in config.toml, with defaults and examples"),
        ("sync", "keep the config in sync across Macs: config.local.toml and rh config sync"),
        ("agent-setup", "how an AI agent should set up Right Here"),
        ("mcp", "Right Here as an MCP server for AI agents: setup, the tools, the framing"),
        ("troubleshooting", "the menu does not appear, a click does nothing, permission prompts")
    ]

    /// The topic served by `RightHereMCP` (its tool list is read from the code, which Core cannot see). `Guides` serves every topic.
    public static let mcpTopic = "mcp"

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
        case "sync": return sync
        case "start": return start
        default: return guides[topic]
        }
    }
}
