# 0033: A file's link on its git host, copied or opened

Date: 2026-10-29. Status: shipped in 1.1.0; listed under Not in the Menu from 1.1.1. The Codeberg folder and root forms were measured on
2026-10-30.

## Decision

Two actions give the web page of the selected file or folder on the host of its git repository:

- **Copy Repository Link** (`repository.copy-link`) copies it; with several items selected, one link per line, each from its own
  repository.
- **Open Repository Page** (`repository.open-page`) opens it in the default browser; it takes one item, and refuses more rather than
  opening a tab for each. The menu does not offer it for a selection of several (counted, not looked at).

They are not in the default menu: the menu editor lists them under Not in the Menu, where one check adds each, and `menu.items` takes
their ids. They are actions of their own, not a style of Copy Path, because the Finder extension renders Copy Path's styles itself
(`FinderSyncExtension`), and it may read nothing but its cached config (hard rule 5); these two run `rh`, which reads the repository
when the item is clicked. For the same reason the titles name the repository, not GitHub: the menu cannot know the host.

## How the link is made

- **The repository** is the one git finds (`rev-parse --show-toplevel`, run in the item's folder), not the nearest `.git` entry: an empty
  `.git` folder is no repository to git. The item's path is taken from that top folder, the folders above it with their links followed
  and their names in the disk's case. `rh` may have been started with `GIT_DIR` and its kin (from a hook, by another git command):
  `GitCommand` takes them out of git's environment, so the repository is always the one `-C` names.
- **The remote**: the first of the branch's upstream (`symbolic-ref`, since `rev-parse --abbrev-ref` says `heads/main` beside a tag
  called main), its push remote (`branch.<b>.pushRemote`, `remote.pushDefault`), `origin` and the only remote that has the commit, else
  the first of them; a fork that has the commit while the upstream does not is linked. A name with a slash is a remote; one that starts
  with `-` or holds a glob character is never used. Several remotes and none of these: the action stops and says so. Its URL comes from `git remote get-url <name>`, which applies the person's `url.<base>.insteadOf`
  (measured: `gh:owner/repo` with `insteadOf = gh:` gives `https://github.com/owner/repo`, where `git config --get` gives `gh:owner/repo`,
  which no host has).
- **The URL is parsed, never passed on.** `https://host/owner/repo(.git)`, `ssh://user@host[:port]/owner/repo.git` and
  `user@host:owner/repo.git` are understood; a user name or a password in it (`https://user:password@host/owner/repo`) is dropped and never
  reaches the clipboard, the browser or the log. Every segment of the owner and repository path must be letters, digits, `-`, `_` and
  `.`, and not `.` or `..`. Anything else stops the action.
- **The hosts**: github.com, gitlab.com, codeberg.org and bitbucket.org, each with its own form. Tried on public repositories on
  2026-10-29 and 2026-10-30 with a commit's full hash; every form answered 200. Only a name that reads as a host is shown in a
  refusal: what is left of a token whose `@` ended the user part (`ghp_…:x@host/…` without a scheme) is not repeated. An owner or
  repository segment that starts with `-` is refused (GitLab's `/-/` starts a page's part of a URL), and `.git` is dropped in any case:

  | Host | File | Folder | Repository root |
  | --- | --- | --- | --- |
  | github.com | `/<owner>/<repo>/blob/<commit>/<path>` | `/tree/<commit>/<path>` | `/tree/<commit>` |
  | gitlab.com (groups may nest) | `/<group…>/<repo>/-/blob/<commit>/<path>` | `/-/tree/<commit>/<path>` | `/-/tree/<commit>` |
  | codeberg.org | `/<owner>/<repo>/src/commit/<commit>/<path>` | the same | the same, no path |
  | bitbucket.org | `/<owner>/<repo>/src/<commit>/<path>` | the same | `/src/<commit>/` |

  Another host (a company's GitHub Enterprise or GitLab) stops the action with a sentence that names the host. A setting that maps such
  a host to one of the four forms is the shape to add when someone asks.
- **The commit**: the link names the checked-out commit (`git rev-parse HEAD`), so it shows the lines the person sees and stays right
  when the branch moves. It never falls back to a branch name, which would show other lines under the same link.
- **No link to a page that is not there.** The action stops, and says what to do, when:
  - the commit is not on the chosen remote: `git rev-list -n1 HEAD --not --remotes=<remote>` prints it (measured: empty when a branch of
    that remote contains the commit, the commit when only a local branch does; the same under `GIT_NO_LAZY_FETCH=1`). Another remote
    holding it does not count, since the link goes to this one;
  - the item is not in that commit, as a new or untracked file is not: `git cat-file --batch-check=%(objecttype) -Z` gets
    `<commit>:<path>` for every item on its input, NUL-separated, and says blob, tree or commit (a submodule, which has its own sentence:
    its pages are in its own repository). On the input, not as arguments: `Process` hands arguments over decomposed, and git that does not
    precompose them (`core.precomposeunicode=false`) would look up a name the commit has precomposed (measured). Whether the link is a
    file's or a folder's comes from the commit too: a committed link to a folder is a file there. Replace refs are off
    (`GIT_NO_REPLACE_OBJECTS`), so the commit read is the one the host has. A file with uncommitted changes links to its committed
    version; the page shows the commit, and the sentence of the copy says so.
  - git cannot read the repository (a `.git` file naming a folder that is not there, a repository of another owner): its own first line
    is what the person is told.
- **The path** is the item's path from the git root, in Unicode NFC (Finder can hand over decomposed names; git on macOS stores
  precomposed ones, `core.precomposeunicode`, and found the decomposed `é.txt` at `HEAD` when measured), each segment percent-encoded.
  The root itself is the repository's page at that commit.

## What git may start

Measured by hand with Homebrew's git 2.54.0, and by the tests with the git the product starts (`/usr/bin/git`: Apple's 2.54.0 with
Xcode 27.1 and 2.50.1 with Xcode 26.6, which CI uses; the tests pass with both), in a repository whose files and configuration name a
program for every hook (files and `hook.<name>.command`),
`core.fsmonitor`, a filter driver for every file (`smudge`, `clean`, `process`), `core.pager`, `pager.<command>` and `core.sshCommand`:
`rev-parse --show-toplevel`, `rev-parse --verify HEAD^{commit}`, `symbolic-ref -q HEAD`, `config --get`, `remote`, `remote get-url`,
`rev-list -n1 <commit> --not --remotes=<name>` and `cat-file --batch-check -Z` started none of them (the tests run each against such a
repository). `ls-files` started the fsmonitor and `commit` the filters,
so neither is used. The commands still run through `GitCommand`, with its guards and the reading time limit, like the worktree commands
(ADR 0016).

## Safety

- The link is built from the parsed host, owner, repository, commit (40 or 64 hexadecimal digits) and the encoded path, always as
  `https://`. Nothing of the remote URL is copied into it as text, so a remote such as `ext::sh -c ...` or `file:///etc` cannot become a
  link. `open` gets it as one argument and runs in `/` (`PlanExecutor.openDirectory`).
- The pure part (parse the remote, build the link) is in RightHereCore with tests; the git commands are in RightHereKit, tested with
  fake runners and once against a real repository in a temporary folder.

## Alternatives

- **A style of Copy Path**: the item would sit where people look for it, but the extension copies styles itself and cannot read the
  repository, and a style cannot fail where every other one cannot.
- **A branch link** (`/blob/main/<path>`): it works before a push, but shows whatever the branch holds when it is opened, which may not
  be the lines that were selected. Hosts offer the commit link ("permalink") for the same reason.
- **Detect the host in the extension and title the item "Open on GitHub"**: hard rule 5.
- **Pass the remote URL through when the host is unknown**: a remote URL is text from the repository and can be any scheme; it is not
  a web page.

## Consequences

- Two action ids and their two titles in every language; the refusals are English, as every sentence of `rh` that reaches an alert
  is. The actions in the docs and the menu's catalog.
- An independent review (2026-10-30) found the wrong repository (an empty `.git` folder, an inherited `GIT_DIR`), a token's remnant
  in a refusal, replace refs, the upstream missed beside a tag, decomposed names, the kind taken from the disk and refusals with the
  wrong reason; each is fixed with a test that fails without the fix and a mutation entry.
- DESIGN section 9 gains the rule that a link is built only from parsed parts, with mutation entries for the scheme, the user name and
  the segment check.
