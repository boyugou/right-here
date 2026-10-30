# 0022: A process a test started cannot change the real home

Date: 2026-10-16. Status: decided.

## The problem

The mutation check (`script/mutation_check.py`) removes each protection in a throwaway clone and runs the tests, which must fail. A mutant that removes "an id that is not a
known terminal is refused" lets the test that passes `rh setup --terminal "no\u{1b}[2Jsuch"` and expects a refusal run a full `rh setup`. That test gave `rh` a config folder
(`RH_CONFIG_DIR`) and no trial home (`RH_HOME`), so the setup went to the real home of the person who ran the check: the runner script the Finder extension runs, the command
link `~/.local/bin/rh` and the seven Quick Actions were replaced by ones that pointed into the throwaway clone, which was deleted when the run ended. The Finder menu of that Mac
stopped working until `rh setup` was run again from the installed app. Nothing reported it at the time: the Checks page showed it afterwards ("the runner script runs
…/rh-mutation-…/clone/…, which does not exist").

In 116 of the 143 places where the command-line tests start `rh` (the others, 27, give it a trial home) it has none. They were safe because the commands they run are refused, or read only. A protection that is removed, or a bug,
makes them unsafe, and the mutation check removes protections on purpose.

## Decision

**`rh` refuses to change the real home when a test started it.** A process that carries `RH_NO_UI` (what the command-line harness sets, and no person does) and has no `RH_HOME`
cannot write the runner script, the command link or the Quick Actions (`Installer`, which asks `RealHomeGuard` first in every function that writes or removes), and cannot register,
unregister or switch off the Finder extension, or restart it for a launch probe (`FinderExtensionManager`, `ExtensionProbe`), which are changes to the whole Mac. A test that
means to write has a trial home. The refusal is a sentence that says so.

**The mutation check stops at the first mutant that changes the real home.** Before the run and after each mutant it takes the modification times and link targets of the runner
script, the command link and the Quick Actions of the account (not the extension's registration, which `pluginkit` keeps elsewhere), and stops with the sentence that says how to repair it (`Right Here.app/Contents/Helpers/rh setup`).

**What stays as it is.** The tests that start `rh` keep their config folder and log folder as before; nothing about what they check changes. The guard only has an effect where a
test would have written the real home. A test of the guard itself must not be able to do the damage it guards against, so it is a unit test (the real home is a temporary folder
that the test names, the environment is the one the test hands over) and not a run of the real `rh`.

## Alternatives

- **Give every command-line test a trial home.** It is right for the tests that write, which already have one (27). For the others it changes what `rh` says (a trial prints notes,
  the Finder extension is skipped) and every expected sentence with it, and it fixes the tests one by one while the next one written without it is as unsafe as these were.
- **Run the mutation check under `sandbox-exec` with writes to the home denied.** It would cover everything, including a Kit test that writes where it should not; it is
  deprecated, would need the caches of the build and `git` allowed by hand, and cannot stop what `pluginkit` and `pbs` do through their daemons. The guard is where the
  writes are made.
- **Only the fingerprint in the mutation check.** It notices after the fact, and leaves a plain `swift test` of a bug as unsafe as before.

## Evidence

`RealHomeGuardTests` (every function of `Installer` that writes refuses and leaves the home empty; the same installer writes with a trial home, without `RH_NO_UI`, and for another
home; `FinderExtensionManager` and `ExtensionProbe` start nothing) and the mutation entries "a test changes the real home as soon as a protection it is for is gone" and the five
after it. The 138 command-line tests pass with the guard and leave the real runner script, link and Quick Actions as they were (their times were read before and after).

Added later, for the writes that were not covered: `ConfigService` asks `RealHomeGuard.checkWriting` before it writes a config file, and `ConfigSync` before `enable` and `disable` change the settings
of the sync, before `pull` makes its lock or replaces the config (or the file the config is a link to), and before `push` makes a folder or writes the copy; a push asks for the record of the sync
first, so that a refused push has written nothing. `ConfigSyncRealHomeTests` name a home as the real one, and the mutation entries remove each of those questions.

A later review found one more writer outside the guard: `ConfigStore.initialize`, which writes the config of `rh init` and `rh setup`. A test that ran the real `rh init` without `RH_HOME`
would have made or replaced the person's config. It now asks `RealHomeGuard.checkWriting` before it makes the folder of the config; `ConfigStoreInitializeGuardTests` name a home as
the real one, and a mutation entry removes the question.
