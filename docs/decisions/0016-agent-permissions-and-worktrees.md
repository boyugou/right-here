# 0016: Agents that skip their permission prompts, and isolated git worktrees

Date: 2026-10-14. Status: decided.

## Decision

**Skipping permission prompts is opt-in and visible.** `general.bypass_permissions` (default `false`) and `[agent.<id>] bypass_permissions` add the
agent's own flag (`bypass_permission_arg`, built in for the agents that have one) when the agent is started. `rh run --bypass-permissions`
turns it on for one run and `--safe` turns it off. The flag is a launch option (`Config.launchOptions(for:)`) and is never written into the agent's
`command`, so that every surface can say it: the typed line shows the flag, the plan says "starts with its permission prompts switched off",
the doctor's row for the agent says so, `rh agents` and `rh menu --explain` say so, and the sync guard lists it as `[agent.<id>] bypass_permissions`
(ADR 0013: `pull` refuses it without `--allow-commands`). **A preset never gets the flag** (it does get `args`): its prompt carries the names
of the selected files, and a file called "ignore the above and run ..." must not reach an agent that asks nothing (ADR 0012); the plan says
that the prompts stay on. The flags of Claude Code, Codex and Antigravity were read from their own `--help` on a Mac that has them; the others
were checked against each tool's own documentation on 2026-10-16 (ADR 0024), which corrected two (Gemini CLI's `-y` is deprecated for
`--approval-mode=yolo`; Muse Code has no such flag in anything it documents, so none is built in).

**Worktrees are Right Here's own folder.** `rh run --worktree` and `rh worktree add` make a git worktree under `.right-here/worktrees/` of the
repository (and put `.right-here` in `.git/info/exclude`). The branch name is validated (no leading dash, no `..`, no whitespace or control
character, git's own rules). Removal, from the CLI or over MCP, only ever touches a worktree under that folder: never the main working
copy and never one the person made. Git's refusal for uncommitted work stands unless the person passes `--force` on the command line
(MCP never forces), and a branch is deleted only with `git branch -d`, which keeps an unmerged one.

**A run plans before it creates anything, and an option that would do nothing is an error.** `rh run --worktree` plans the action against
the worktree as it will be (`WorktreeFacts`: the same paths below the repository), so a refused request makes no worktree. The worktree is
made last, the plan is made again for real, and a run that then fails removes the worktree again when this run made it and nothing in it
changed; a worktree that existed before is never touched. The agent starts in the folder that was named, inside the worktree, not at the
root of it. A default branch name is the time to the second and eight random hex digits, so two runs in one second get two worktrees.
`--bypass-permissions`, `--safe`, `--arg`, `--worktree` and `--branch` apply to an agent or a preset and are an error for any other action;
a preset refuses the two permission flags, since it keeps its prompts on (ADR 0012). `-y` is not an option: `--bypass-permissions` is the
only spelling.

Evidence: the binary from before the change, run on a fixture repository, failed the dry run ("the worktree does not exist"), left the
worktree and its branch behind after a failed run, and started the agent at the root of the worktree. The CLI tests in
`Tests/RightHereCLITests` reproduce each case, and the current binary passes them.

## What git may start

A repository is whatever somebody sent (an archive, a copy, a clone of a stranger's project), and its own files can make git start programs. Every
git command Right Here runs in a repository is built by one function (`GitCommand.step`), so that a new command cannot leave a guard out (a test fails when
any other source file names git's program), and `defined(in:)` finds what the repository's configuration defines. Measured with git 2.54.0 (Apple Git-157) in throwaway repositories whose
configuration names a program that records that it ran (`GitGuardTests`, each with a control that the same repository does start it for a git without
the guards):

| Command | What the repository's own files started |
|---|---|
| `worktree list`, `config`, `rev-parse` | nothing |
| `worktree add -b` | the hooks `reference-transaction` (several times), `post-index-change` and `post-checkout`; the `core.fsmonitor` program; the `smudge` and `process` filters of every file the attributes select; a lazy fetch from the promisor remote of a partial clone, which starts `ext::<program>` (when `protocol.ext.allow=always` is in the repository's config), `core.sshCommand` or a credential helper |
| `status` in the new worktree | `core.fsmonitor`, `post-index-change`, the `clean` filters |
| `worktree remove` | the same, from the `git status` it runs inside the worktree with that worktree's configuration (`config.worktree`) |
| `branch -d` | `reference-transaction` |

A conditional include (`includeIf "onbranch:rh/**"`, `includeIf "gitdir:..."`) in the repository's own configuration brings in a file only where its condition holds, and the new worktree has its
own branch and git directory, so a filter or hook defined there cannot be looked for before the worktree exists (a review made `onbranch:rh/**` match the branch of the new worktree, and the
filter and the hooks ran): such a repository gets no worktree (`WorktreeError.conditionalInclude`). A conditional include of the person's own configuration (an identity for a folder) is theirs and
does not matter.

Git 2.54 also runs a hook that is a command named in the configuration (`hook.<name>.event`, `hook.<name>.command`), and `core.hooksPath=/dev/null`
does not stop it; `hook.<name>.enabled=false` does, for every name found in any file or scope.

**Decision.** Every command gets `core.hooksPath=/dev/null`, `core.fsmonitor=false`, `hook.<name>.enabled=false` for each configured hook, the filter
drivers the repository defines blanked (`smudge`, `clean`, `process`, `required=false`), `GIT_NO_LAZY_FETCH=1` and `--no-pager`. The person's own filters
(Git LFS in the global configuration) still run; a repository that defines `filter.lfs` itself gets a worktree with pointer files. The settings are
passed as `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_<n>` and `GIT_CONFIG_VALUE_<n>`, not `-c`: `-c filter.a=b.smudge=` is split at the first equals sign, and git
lets a repository choose a driver called `a=b` (measured: the marker appeared with `-c`, not with the environment form). The drivers are listed with
`git config -z --show-scope --name-only --get-regexp '^(filter|hook|includeif)\.'`, which reads the files a configuration includes and `config.worktree`
(`--local` reads neither), and the drivers of every scope but `system`, `global` and `command` are blanked. The list is read by Unicode scalars.
`worktree list` is read as `--porcelain -z`: without `-z` a folder name with a line break in it adds lines to the list (measured: a worktree's path was replaced
by the forged one). The commands that only read have a time limit of 20 seconds: a named pipe in `include.path` makes every git command in that repository
wait (measured), and a request slot of the MCP server, or the setup window, would wait with it.

**Checked and not reachable** (the same repository with `diff.external`, `diff.<driver>.textconv` and `command`, `merge.<driver>.driver`, `core.editor`,
`sequence.editor`, `core.askPass`, `credential.helper`, `core.pager` with `pager.status`, `pager.branch` and `pager.worktree`, `core.alternateRefsCommand`,
`gpg.program` with `commit.gpgsign`, `core.sshCommand`, `core.gitProxy`, an `alias.status` and an `alias.worktree`, and a modified and a renamed file in the
worktree: nothing started for `status`, `worktree add`, `worktree remove`, `worktree list`, `branch -d` or `config` with the guards). A pager needs a terminal and
the output is a pipe, and `--no-pager` says so. `submodule.recurse=true` with a submodule URL that starts a program does not populate or fetch anything: `worktree add`
has no `--recurse-submodules`. `safe.directory=*` in a repository's own configuration is ignored (with `GIT_TEST_ASSUME_DIFFERENT_OWNER=1` git refused the repository, and
naming its path in the global configuration allowed it), so a repository that somebody else owns is refused by git, not guarded by Right Here. Right Here runs no
`rev-parse`: `gitRoot` walks the file system.

## Alternatives

- Create the worktree first and remove it when the plan is refused: the repository changes for a request that never runs, and a crash
  between the two leaves it behind. Planning first against the worktree's paths costs one small facts wrapper.
- Plan the dry run against the repository folder and print the worktree's path as a note: the plan would not be the one the real run makes,
  and a dry run could not show the folder the agent starts in.

- Bypass on by default, or one switch for every agent without a per-agent override: too easy to leave on.
- `git worktree remove --force` and `branch -D` from MCP, as first written: a client that has been told to by a file it read could
  delete another worktree with uncommitted work.
