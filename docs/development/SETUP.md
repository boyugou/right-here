# Building, installing, testing

## What you need

- A Mac with Apple silicon and macOS 26 or later, and `git`.
- Xcode 26 or later: the full app, not only the Command Line Tools.
- `xcodegen` (`brew install xcodegen`).
- `uv` (`brew install uv`). It runs the checks of `./script/verify_all.sh`.
- Optional: `fish`, `dash` and `ksh`. The quoting tests also try them when they are installed.

With only the Command Line Tools, you can read and edit the code and run `swift build`. `swift test`, the app build and the gate need Xcode
(Swift Testing and `xcodebuild`). If you have only the Command Line Tools, say so in the pull request, and a maintainer runs the gate.

## Build and install

```sh
swift build                # the libraries and rh (run it as .build/debug/rh; a trial: RH_HOME=/tmp/trial .build/debug/rh setup)
swift test                 # all unit tests; no test touches your home folder or Finder
./script/build_app.sh      # dist/Right Here.app: the app, the Finder extension and rh (Contents/Helpers/rh)
./script/install_local.sh  # builds, copies to ~/Applications, runs `rh setup`
```

`install_local.sh` signs with the first "Developer ID Application" identity in your keychain, or ad hoc when there is none.
`SIGN_IDENTITY` overrides it. It does not notarize.

## What `rh setup` does

`rh setup` puts everything in place, and you can run it again at any time. In this order, it:

1. makes the config from what it finds, or from `--terminal`, `--editor` and `--agents` (it never rewrites a config that exists);
2. writes the runner script;
3. links `rh` into `~/.local/bin`;
4. makes the Quick Actions;
5. registers the Finder extension and asks macOS to use it;
6. runs the checks of `rh doctor`, and says what only you can do (turn on the extension in System Settings).

`rh setup --dry-run` shows what it would do. `rh install --finder` (or `--scripts`, `--cli`, `--services`) does one step again.
`rh uninstall` removes everything except the config. The setup window runs the same code: with no config file, it first offers the choice of
terminal, editor and agents.

## Things that will bite

- **Two registrations of the extension.** Xcode registers its own build product with LaunchServices. A second registration of the Finder
  extension makes macOS drop it, so `build_app.sh` unregisters the copy in the build folder.
- **The clock.** codesign with a secure timestamp fails with "timestamps differ" when the clock of the Mac is wrong. Local builds skip the
  timestamp. Release builds need a correct clock.
- **App Translocation.** macOS runs a downloaded app that was not moved yet from a temporary copy. `rh setup` refuses there, because the
  runner script and the Quick Actions would point into a folder that goes away when the app quits. Move Right Here.app into Applications
  first.
- **A trial home.** `RH_HOME=/tmp/trial rh setup` writes the config, the runner script, the command link and the Quick Actions in that folder,
  not in your home. The registration of the Finder extension is for the whole Mac, so a trial leaves it alone.
  - `rh uninstall` with the same `RH_HOME` undoes the trial.
  - `rh doctor` with it says so on standard error, because its rows mix that home's files with the real registration of the extension.
  - An empty `RH_HOME` (or `RH_CONFIG`, `RH_CONFIG_DIR`, `RH_LOG_DIR`) stops `rh` with status 64. It is what `RH_HOME=$TRIAL rh setup`
    becomes when `$TRIAL` is not set, and "not set" would mean your real home.
- **Changes to setup.** After a change to setup, its report, a sentence of the doctor or the playbook (`docs/AGENT_SETUP.md`), run the
  evaluation with new agents ([`SETUP_EVALUATION.md`](SETUP_EVALUATION.md)). New AI agents set Right Here up for five personas, in a sandbox
  that cannot touch your Mac.
- **A test that holds only on an English Mac.** `./script/test_languages.sh` runs the test bundles with the system language set to German and
  Arabic (or the languages you name), after `swift build --build-tests`.
- **An action without side effects:** `rh run <id> --dry-run`.
- **A throwaway config:** `RH_CONFIG_DIR=/tmp/x`.
