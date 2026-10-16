# 0021: One setup at a time, the state file in one step, and each Quick Action replaced on its own

Date: 2026-10-15. Status: decided.

## Decision

1. **A setup takes a lock.** `SetupRunner.run` takes an advisory lock, `flock` on `.setup.lock` in the config folder, for every run that
   is not a dry run, and holds it until the report is done (the doctor included). The setup window, `rh setup` in a terminal, `rh init`,
   `rh install` and an AI agent's setup therefore take turns: the second waits (it polls every 100 ms without holding a thread, for at most
   two minutes) and then finds every piece in place and says so. After two minutes it stops with "another setup is running ... run `rh setup`
   again". A dry run writes nothing, so it neither waits nor makes the file.
2. **The state file is changed in one step.** `StateStore.update` takes `.state.lock`, reads `state.toml`, applies the change, and writes it
   (only when something changed). `rh pin`, `rh unpin`, `rh recents --clear`, the recent folder that every `rh run` records and the setup
   window's buttons all use it; the recording of a recent folder waits half a second at most and is skipped after that, a click does not
   wait for a bookkeeping file. It is a lock of its own: pinning a folder does not wait for a setup that takes seconds.
3. **Each Quick Action takes the place of the one of its name in one step.** `Installer.installServices` stages every bundle, then puts each
   in place with `renamex_np`: `RENAME_EXCL` for a name that is free, `RENAME_SWAP` for one that is taken (the old bundle ends in the staging
   folder, which is removed). What the config no longer asks for is removed after the new ones are in. A name is never without its bundle, a
   kill in the middle leaves a complete bundle for every name, and two installs at once cannot make each other fail. Where the file system has
   no swap (`ENOTSUP`) the old bundle is removed and the new one moved in, for that one bundle.
4. **A lock that cannot be made is not held, and is no error.** The folder is not writable, the name is a link or a folder, or the file
   system has no locks: the work goes on as it did before the lock existed (config creation is exclusive by `link`, the runner script and the
   state are written by rename, the Quick Actions are replaced one by one), only less tidily. The lock file is opened with `O_NOFOLLOW`
   and `O_CLOEXEC`, must be a regular file, and is never removed.

## Why

- Two `rh setup` at once, six rounds on one empty `RH_HOME`: in four of them one printed "Quick Actions: failed (… couldn't be moved to
  Services …)" and exited 1, and in one only five of six Quick Actions were on disk after both ended. A probe that calls
  `installServices` from two threads twenty times failed 19 times. The config survived (it is created with `link`, ADR 0018); the
  Quick Actions did not, since an install removed every bundle and then moved them in, one by one, over what the other had just made.
- Twenty `rh pin` started together kept twelve: the state is read, changed and written, the write is atomic, and the three together are not.
- A lock alone would leave the Installer unsafe against any caller that does not take it, and a replacement per bundle alone would leave
  two setups both reporting "created" and both doing the work; each is cheap, and the two together make "run it twice at once" boring.

## Measured

On macOS 27.2, APFS (`statfs` says `apfs`), 2026-10-15, by a small program of its own and by the tests:

- `flock` belongs to the open file description: two `open`s of one file in one process contend (the second gets `EWOULDBLOCK` while the first
  holds the lock, and takes it when the first is closed). So threads of one process take turns as processes do, and the probe of two installs
  in one process is a fair test of two programs.
- A process that holds the lock and is killed with SIGKILL: the next attempt takes the lock at once. There is no stale lock to detect.
- A child that this process starts with Foundation's `Process` does not keep the lock when the parent closes its descriptor, with or without
  `O_CLOEXEC` (Foundation does not pass the descriptor on). The flag stays for every other way of starting a process.
- `renamex_np` on directories: `RENAME_EXCL` onto a directory that exists fails with `EEXIST`, onto a free name it works; `RENAME_SWAP` of two
  directories works and leaves the old one at the staged path; `RENAME_SWAP` with a name that is not there fails with `ENOENT` (the case of an
  install that finds a name taken and then free again is tried again); a plain `rename` of a directory onto a directory that has files fails
  with `ENOTEMPTY`, which is why it cannot do this.
- Not measured, for there is no such volume here: a file system without locks (some network shares), where `flock` may fail with `ENOTSUP` or
  `ENOLCK`. The code treats any failure but "held by somebody else" as "no lock" (item 4).

## Alternatives

- **One lock file for setup and for the state.** Pinning a folder, or the click that records a recent one, would wait for a setup of several
  seconds.
- **A lock file made with `O_EXCL` and removed when done**, with a rule for a stale one: it needs a way to tell that its owner is gone, and a
  crash leaves it. CLAUDE.md says the same of `unlink` as a claim; `flock` is released by the system when its holder ends.
- **A blocking `flock(LOCK_EX)`**: it holds a thread of the cooperative pool for as long as the other setup runs, and cannot give up.
- **Only the lock around `SetupRunner.run`**, or **only the replacement per bundle**: see "Why".
- **Locking only the runs that make the config**: `rh install --scripts` would then be unprotected, and the rule would depend on which pieces
  are asked for. Every run that is not a dry run takes its turn; the cost is that `rh install --scripts` makes `.config/right-here/.setup.lock`
  on a Mac that has no config yet.

## Checked

`FileLockTests` (the contention, the wait that gives up, a wait that is cancelled, a lock that cannot be made, sixteen threads taking turns,
and a holder in another process that is killed), `StateStoreUpdateTests` (sixty rounds of eight pins at once; pins, unpins and recents at
once), the installer tests of two installs at once (twenty rounds) and of a Quick Action that is never missing while it is replaced (a
reader against sixty installs), `SetupRunnerTests` (a setup waits for the lock a test holds; two setups at once, the second finding everything
in place; the error after the wait; a dry run that does not wait), and, with the real `rh`, `SetupCommandTests` (six rounds of two `rh setup`
at once, `rh setup` waiting for a lock the test holds) and twenty `rh pin` at once. Each fails against the code before this change.
