# 0033: A file's link on its git host, copied or opened

Date: 2026-10-29. Status: decided, not built yet.

## Decision

Two actions give the web page of the selected file or folder on the host of its git repository:

- **Copy Repository Link** (`repository.copy-link`) copies it; with several items selected, one link per line, each from its own
  repository.
- **Open Repository Page** (`repository.open-page`) opens it in the default browser; it takes one item, and refuses more rather than
  opening a tab for each.

They are not in the default menu: the menu editor lists them under the actions that are not in the menu, and `menu.items` takes their
ids. They are actions of their own, not a style of Copy Path, because the Finder extension renders Copy Path's styles itself
(`FinderSyncExtension`), and it may read nothing but its cached config (hard rule 5); these two run `rh`, which reads the repository
when the item is clicked. For the same reason the titles name the repository, not GitHub: the menu cannot know the host.

## How the link is made

- **The remote**: the upstream of the checked-out branch, else `origin`, else the only remote. Several remotes and none of these: the
  action stops and says so. Its URL comes from `git remote get-url <name>`, which applies the person's `url.<base>.insteadOf`
  (measured: `gh:owner/repo` with `insteadOf = gh:` gives `https://github.com/owner/repo`, where `git config --get` gives `gh:owner/repo`,
  which no host has).
- **The URL is parsed, never passed on.** `https://host/owner/repo(.git)`, `ssh://user@host[:port]/owner/repo.git` and
  `user@host:owner/repo.git` are understood; a user name or a password in it (`https://user:password@host/owner/repo`) is dropped and never
  reaches the clipboard, the browser or the log. Every segment of the owner and repository path must be letters, digits, `-`, `_` and
  `.`, and not `.` or `..`. Anything else stops the action.
- **The hosts**: github.com, gitlab.com, codeberg.org and bitbucket.org, each with its own form. Tried on public repositories on
  2026-10-29 with a commit's full hash; all answered 200, except where the table says otherwise:

  | Host | File | Folder | Repository root |
  | --- | --- | --- | --- |
  | github.com | `/<owner>/<repo>/blob/<commit>/<path>` | `/tree/<commit>/<path>` | `/tree/<commit>` |
  | gitlab.com (groups may nest) | `/<group…>/<repo>/-/blob/<commit>/<path>` | `/-/tree/<commit>/<path>` | `/-/tree/<commit>` |
  | codeberg.org | `/<owner>/<repo>/src/commit/<commit>/<path>` | the same (not measured: the host answered 429) | the same, no path (not measured) |
  | bitbucket.org | `/<owner>/<repo>/src/<commit>/<path>` | the same | `/src/<commit>/` |

  Another host (a company's GitHub Enterprise or GitLab) stops the action with a sentence that names the host. A setting that maps such
  a host to one of the four forms is the shape to add when someone asks.
- **The commit**: the link names the checked-out commit (`git rev-parse HEAD`), so it shows the lines the person sees and stays right
  when the branch moves. It never falls back to a branch name, which would show other lines under the same link.
- **No link to a page that is not there.** The action stops, and says what to do, when:
  - the commit is not on the chosen remote: `git rev-list -n1 HEAD --not --remotes=<remote>` prints it (measured: empty when a branch of
    that remote contains the commit, the commit when only a local branch does; the same under `GIT_NO_LAZY_FETCH=1`). Another remote
    holding it does not count, since the link goes to this one;
  - the item is not in that commit: `git cat-file -e HEAD:<path>` fails (exit 128), as for a new or untracked file. The `HEAD:` prefix
    keeps a name that starts with `-` a path (measured). A file with uncommitted changes links to its committed version; the page shows
    the commit, and the sentence of the copy says so.
- **The path** is the item's path from the git root, in Unicode NFC (Finder can hand over decomposed names; git on macOS stores
  precomposed ones, `core.precomposeunicode`, and found the decomposed `é.txt` at `HEAD` when measured), each segment percent-encoded.
  The root itself is the repository's page at that commit.

## What git may start

Measured with git 2.54 in a repository whose files and configuration name a program for every hook (files and `hook.<name>.command`),
`core.fsmonitor`, a filter driver for every file (`smudge`, `clean`, `process`), `core.pager`, `pager.<command>` and `core.sshCommand`:
`rev-parse HEAD`, `rev-parse --abbrev-ref --symbolic-full-name @{upstream}`, `remote`, `remote get-url`, `config --get`, `rev-list -n1 HEAD
--not --remotes=<name>` and `cat-file -e HEAD:<path>` started none of them. `ls-files` started the fsmonitor and `commit` the filters,
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

- Two action ids, two titles and the sentences of the refusals in every language; the actions in the docs and the menu's catalog.
- DESIGN section 9 gains the rule that a link is built only from parsed parts, with mutation entries for the scheme, the user name and
  the segment check.
