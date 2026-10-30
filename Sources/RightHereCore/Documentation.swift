import Foundation

/// Built-in documentation, printed by `rh docs` and served by the MCP server.
public enum Documentation {
    public static let actions = """
    # Actions

    Each action has an id. `rh run <id>` runs an action. `rh actions` lists the actions that can run on this Mac.

    ## The ids

        copy-path.<style>              copy the path of the selection, or of the folder
                                       styles: \(PathStyle.allCases.map(\.rawValue).joined(separator: ", "))
        open.terminal[@<terminal>]     open the folder in the default terminal, or in <terminal>
        open.editor                    open the selection in the default editor
        open.app.<app>                 open the selection in an app (`rh apps` lists the apps)
        agent.<agent>[.<variant>][@<launcher>]
                                       start an AI agent in the folder (`rh agents` lists the agents)
                                       launcher: a terminal id, "default" (the default terminal),
                                       "link" (the agent's own link, which opens its last terminal)
                                       or "desktop" (the agent's desktop app)
        preset.<id>[@<terminal>]       start the agent of a preset with its prompt and the selected
                                       files as @ mentions (built in: review, explain, tests; your
                                       own: `[[preset]]` in the config). The agent starts at once.
        new-file.<template>            make an empty file next to the selection, or in the folder
        reveal                         select the items in Finder
        repository.copy-link           copy the page of the selection on the git host of its repository
                                       (GitHub, GitLab, Codeberg, Bitbucket), at the checked-out commit
        repository.open-page           open that page in the browser (one item)

    Examples:

        rh run copy-path.git-relative src/main.swift
        rh run agent.claude.continue@ghostty ~/code/project
        rh run agent.codex@desktop ~/code/project
        rh run preset.review src/main.swift src/util.swift
        rh run new-file.md --container ~/notes
        rh run repository.copy-link src/main.swift

    Add `--dry-run` to see the plan and run nothing. Add `--json` to get the plan as data.

    `rh actions` shows an action when it can run on this Mac: its terminal or app is installed, and the terminal can
    run commands. It does not check that the command of an agent is installed. `rh agents` shows which agent commands
    your login shell finds. `rh actions --all` also lists the other actions, each with the reason that it cannot run.

    ## Read a plan

    `rh run <action> --dry-run` prints what the action would do, and runs nothing.

    - The first line says what the action is.
    - Each numbered step says what it does. The lines under it give its values:
      - `open <bundle id>`, `reveal`: a `target:` line for each path.
      - `AppleScript controlling <app>`: an `arguments:` line with the values that the script gets, in order. The
        script is in `--json` (`source`). The values are never part of the script.
      - `run "<program>" "<argument>" ...`: the program and each of its arguments.
      - `copy <n> characters to the clipboard`: a `text:` line with the whole text.
      - `create "<path>"`: a `contents:` line.
    - A `note:` line says what the plan changed or left out. For example: a default app that is not installed and the
      app that is used instead, a new file that is selected and not opened, or an agent command that the login shell
      did not find.

    Each value is a quoted string, as JSON writes it: `\\"` is a quote, `\\\\` a backslash, `\\n` a line break, and a
    control character is an escape such as `\\u001b`. Nothing is cut short. `--json` holds the same plan as data
    (`steps`, `notices`), for a program or an agent to read.

    ## Options for an agent

    These options work with an agent or a preset. With any other action, they are an error.

    - `--worktree` starts the agent in a new git worktree of the repository, on a new branch, in the folder that the
      request names. `--branch <name>` names the branch, or uses a branch that exists.
      - Right Here makes the plan before the worktree. So a refused request leaves nothing behind.
      - If the run fails and nothing in the worktree changed, Right Here removes the worktree again.
      - `rh worktree list`, `rh worktree add <branch>` and `rh worktree remove <name>` manage the worktrees.
        `remove` refuses work that is not committed, unless you add `--force`. It removes only the worktrees that
        Right Here made.
    - `--bypass-permissions` starts the agent without its permission prompts. It uses the agent's own flag for this
      (`bypass_permission_arg`, built in for the agents that have one). `--safe` starts the agent with the prompts,
      whatever the config says. Both are for an agent (`agent.<id>`). A preset always keeps the prompts, because its
      prompt contains the names of the files.
    - `--arg <argument>` adds one argument after the command of the agent. You can repeat it. It works for an agent
      or a preset.

    ## Pinned and recent folders

    - `rh pin [folder]` adds a folder to the list that `rh pins` prints. `rh unpin <folder>` removes it.
    - `rh recents` prints the folders that you used with Right Here. `rh recents --clear` empties the list.

    Both lists are in the state file next to the config. They are not part of the config, so they are never synced.

    ## Notes

    - If presets belong to more than one agent, the menu shows the name of the agent before the title of each preset
      (`Codex: Security review`).
    - If `copy_path.styles` has one entry, it is not a submenu. Its item is at the top level of the menu. Its title
      is `Copy Path` for the full path, and `Copy Path: <style>` for another style (`Copy Path: Path from Home (~)`).
    - A preset names a file outside the folder of its selection with an `@` mention of the full path. If the path has
      a space, the mention is quoted (`@"..."`).
    - For tests: `RH_NO_UI` turns off alerts, and stops `rh` from starting `open` or `osascript`. With `RH_NO_UI` set
      and no `RH_HOME`, the commands that set up (`setup`, `install`, `uninstall`) refuse to change your real home
      folder. Unset `RH_NO_UI`, or give them an `RH_HOME`.
    - `RH_HOME` moves every path of the user (config, log, runner script, Services, command link) into the folder
      that it names. The login shell that `setup`, `init`, `agents` and `doctor` start does not move, so it runs your
      own startup files. This is also true for `run <agent> --dry-run`, which asks the shell whether it finds the
      command, and for `setup --dry-run` when a choice is left out.
    """

    /// What a newcomer does, in the order they need it. The first topic `rh docs` lists.
    public static let start = """
    # Quick start

    Right Here adds terminals, editors and AI agents to the Finder menu. The same actions run from the command line.

    1. **Set up.** Run `rh setup`. It makes a commented config file (`~/.config/right-here/config.toml`) from what is
       installed on this Mac. It installs the runner script, the `rh` link and the Quick Actions, and registers the
       Finder extension. Then it runs the checks of `rh doctor`.
       - To choose your apps, add `--terminal`, `--editor` and `--agents`:
         `rh setup --terminal ghostty --editor zed --agents claude,codex`.
       - `rh setup --dry-run` shows what it would do.
       - Setup never rewrites a config file that exists. You can run it again at any time.
    2. **Turn on the Finder extension.** Setup cannot do this for you. In System Settings › General › Login Items &
       Extensions › Finder, turn on Right Here. `rh setup` tells you when this step is still open.
    3. **Look at the menu.** `rh menu --container <a folder>` prints the Finder menu for that folder. `--explain` also
       says what the menu leaves out, and why.
    4. **Check the setup.** `rh doctor` prints a line for each part, and a fix for each problem. `rh doctor --report`
       prints the same as Markdown, for a bug report.
    5. **Try an action.** `rh actions` lists the actions. `rh run <action> --dry-run <path>` shows what an action would
       do, and does nothing. `rh docs actions` explains the output.
    6. **Read more.** `rh docs config` lists every setting. `rh docs sync` keeps the config the same on several Macs.
       `rh docs troubleshooting` helps when something does not work.

    An AI agent that sets Right Here up for a person reads `rh docs agent-setup`. An agent that uses Right Here as a
    tool reads `rh docs mcp`.
    """

    public static let sync = """
    # Keep your config in sync

    Use one config on several Macs, and keep what differs on each Mac. There are two parts:

    1. `config.local.toml`, the settings of this Mac only. You can leave it out.
    2. A copy of `config.toml` in a folder that your Macs share.

    ## Settings for this Mac only: config.local.toml

    `config.local.toml` is next to `config.toml`. `rh` and the Finder menu read both files. Right Here never syncs
    `config.local.toml`. Put in it what differs on this Mac. When the two files set the same thing:

    - A setting in `config.local.toml` replaces the shared setting (`[general] terminal`, `[new_file] then`, ...).
    - A list replaces the shared list as a whole. Right Here does not merge lists: `menu.items`, `services.items`,
      `copy_path.styles`, `general.agents`.
    - Entries with an id merge by id. An `[[app]]`, `[[preset]]`, `[[new_file.template]]` or
      `[[agent.<id>.variant]]` in `config.local.toml` replaces the shared entry with the same id. An entry with a new
      id is added. So a preset in `config.local.toml` adds to the shared presets, and does not replace them all. Two
      entries with the same id in `config.local.toml` are a duplicate. Right Here reports it and uses the first.
    - `[agent.<id>]` merges one key at a time. So `config.local.toml` can change the `command` of an agent and keep
      its start options.
    - `disabled = ["id", ...]` removes ids on this Mac:
      - Apps, also the built-in ones. Right Here does not offer a disabled terminal, an action id cannot name it, and
        it is no longer the default.
      - New File templates. If you disable every template of the shared config, the built-in txt and md come back.
      - Agents, and their entries in `general.agents`, `menu.items` and `services.items`. A built-in agent is only
        taken out of those lists.
      - A preset whose agent is disabled is dropped. `rh config validate` gives a note, not a warning, so `--strict`
        still passes. If the preset replaced a built-in preset, the built-in one comes back.
      - An id that does not exist on this Mac is skipped. So a shared config can name apps that this Mac does not
        have.
      - `disabled` does nothing in `config.toml`, and Right Here reports it there.

    For example, a work laptop without Codex, with Terminal as its default terminal:

        disabled = ["codex"]
        [general]
        terminal = "terminal"

    Right Here reports a problem in either file with the name of that file (`rh config validate`, `rh doctor`).

    - `rh config validate` also reads `config.toml` alone, as your other Macs read it. It reports an error that
      `config.local.toml` hides on this Mac by setting the same key. `rh config sync push` refuses such a file.
    - A key in `config.toml` with the name of a credential is an error there, because `push` refuses it.
    - `rh config show` prints both files, each under a line with its name. `rh config path --all` lists their paths.
      There is no merged text. `rh menu` shows the menu that the two files make.

    Software that is missing needs no `config.local.toml`. The menu skips an app that is not installed, and a default
    terminal or editor that is not installed gives way to the first installed one. An agent is different. The menu
    cannot ask a shell whether its command is installed, so it still lists the agent, and `rh agents` says
    `enabled, not found`. Use `disabled` for an app or an agent that is installed but must not be offered.

    ## Sync through a folder

    Right Here copies the config. It does not link it. A symlink to iCloud Drive does not work here:

    - The Finder extension is sandboxed. It can read only its own config folder, not the target of a link.
    - iCloud can replace a file that it did not download with a placeholder. Through a link, the placeholder looks
      like a missing file.

    So each Mac keeps an ordinary file, and `rh config sync` copies it to and from a folder.

        rh config sync enable                     choose the folder (default: iCloud Drive, folder "Right Here")
        rh config sync enable --folder ~/Sync/rh  any folder works: Dropbox, a git checkout, a network share
        rh config sync push                       send this Mac's config to the folder (makes its last folder, not its parents)
        rh config sync pull                       take the config from the folder (refused, with a list, if it adds programs)
        rh config sync pull --allow-commands      take it, although it adds or changes terminal templates or agent commands
        rh config sync status                     in-sync, local-ahead, remote-ahead, diverged, remote-missing or remote-evicted
        rh config sync disable                    forget the folder; both copies stay

    The state (the folder, and a hash of what was last synced) is in `sync.toml` next to the config.

    On a second Mac, run `rh config sync enable` and then `rh config sync pull`. Add `--allow-commands` if the config
    has programs of its own (see the rules below).

    ## The rules

    Right Here enforces each of these rules.

    - `pull` refuses if this Mac's config changed since the last sync. `push` refuses if the copy in the folder
      changed. `--force` replaces the file anyway, and saves the old file as `config.toml.bak-<date>` first.
    - Both refuse a config that is not valid, is larger than 1 MiB, or has key names that look like secrets (token,
      secret, password, api_key). A name or a title with a control character is not valid. Keep credentials in the
      environment or in the keychain.
    - A config carries programs, and other Macs, a sync service or a shared drive can write the folder. So `pull`
      also refuses, and lists what it found, if the copy adds or changes something that Right Here starts:
      - a terminal template (`open_args`, `run_args`), or a terminal app with another `role` (a terminal runs a
        file that it gets)
      - a terminal that starts through a template, chosen as the default terminal, for an agent, or in the Finder
        menu or the Quick Actions
      - the `command`, `args` or `prompt_arg` of an agent, the `arguments` of a start option,
        `bypass_permissions` or `bypass_permission_arg`
      - an agent that the copy puts in the menu or the Quick Actions while it starts without its permission prompts
      - the contents of a New File template (a file that something on this Mac may run)

      Right Here reads the copy with this Mac's own `config.local.toml`, as a click reads it. Read the list. If the
      changes are yours, run `rh config sync pull --allow-commands`. This flag is separate from `--force`, and you
      can use both. `status` and `enable` show the same list, and `rh doctor` has a row for it. A first pull on a new
      Mac asks only about programs of your own, never about the built-in apps and agents.
    - `pull` waits while another change of the config is in progress: in the window, with `rh config`, or through an
      assistant. If it cannot wait longer, it says so.
    - Right Here never reads a copy that iCloud did not download (`remote-evicted`) as missing, and never overwrites
      it. Right Here does not read a file that is larger than the limit, on this Mac or in the folder. Such a copy
      shows as `remote-evicted`, with its size. `push` and `pull` never write over a file that they did not read.
    - Each write is atomic: a temporary file next to the destination, then a rename. Nothing is deleted.
    - While sync is on, `rh doctor` adds checks: the folder can be reached, the copy is downloaded and valid, how the
      two files compare, and conflict copies such as `config 2.toml`. A sync service leaves such a copy when two
      Macs write at the same time.

    ## Dotfiles, Dropbox and git

    - A dotfiles manager can keep `config.toml` as a symlink into its repository. `rh` follows the link, but the
      Finder extension may not be able to (`rh doctor` warns). So copy the file instead.
      - `rh config sync pull` writes into the file that a link points to, and keeps the link.
      - `push` treats a `config.toml` that is a link inside the sync folder in the same way, but only if the link
        leads to a file inside that folder. Right Here refuses a link that leaves the folder or points to nothing,
        because anything that can write the folder could plant it.
    - Dropbox, or any other synced folder: `rh config sync enable --folder <folder>`.
    - A git repository: make it the folder, and commit there. Right Here only reads and writes `config.toml` in it.
    - Keep the settings of each Mac in `config.local.toml`, out of the repository or the folder.
    """

    public static let config = ConfigSchema.markdown() + "\n\nTo use one config on several Macs, with settings for each Mac in config.local.toml, read `rh docs sync`.\n"

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
