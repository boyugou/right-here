# Building, installing, testing

Requirements: macOS 26 or later on Apple silicon, `git`, Xcode 26 or later (the full app, not only the Command Line Tools),
`xcodegen` (`brew install xcodegen`) and `uv` (`brew install uv`, runs the checks of `./script/verify_all.sh`). Optional: `fish`, `dash`
and `ksh`, which the quoting tests also round-trip through when they are installed.

With only the Command Line Tools you can read and edit the code and run `swift build`; `swift test`, the app build and the gate
need Xcode (Swift Testing and `xcodebuild`; a contributor with only the Command Line Tools found that `swift test` could not run).
Say so in the pull request, and a maintainer runs the gate.

```sh
swift build                # the libraries and rh (run it as .build/debug/rh; a trial: RH_HOME=/tmp/trial .build/debug/rh setup)
swift test                 # all unit tests; no test touches your home directory or Finder
./script/build_app.sh      # dist/Right Here.app: app, Finder extension and rh (Contents/Helpers/rh)
./script/install_local.sh  # build, copy to ~/Applications, run `rh setup`
```

`install_local.sh` signs with the first "Developer ID Application" identity in your keychain, or ad hoc
when there is none (`SIGN_IDENTITY` overrides). It does not notarize.

`rh setup` is the one command that puts everything in place, and it can be run again at any time: it creates the config from
what it finds (or from `--terminal`, `--editor` and `--agents`; an existing config is never rewritten), writes the runner
script, links `rh` into `~/.local/bin`, makes the Quick Actions, registers and enables the Finder extension, and ends with the
checks of `rh doctor` and what only you can do (switching the extension on in System Settings). `rh setup --dry-run` shows
what it would do. `rh install --finder` (or `--scripts`, `--cli`, `--services`) redoes one piece; `rh uninstall` removes it all
(the config stays). The setup window runs the same code: with no config file it offers the choice of terminal, editor and
agents first.

## Things that will bite

- Xcode registers its own build product with LaunchServices. A second registration of the Finder
  extension makes macOS drop it, so `build_app.sh` unregisters the build folder copy.
- codesign with a secure timestamp fails with "timestamps differ" when the system clock is off.
  Local builds skip the timestamp; release builds need a correct clock.
- A downloaded app that was not moved yet runs from a temporary copy (App Translocation). `rh setup`
  refuses there, because the runner script and the Services would point into a folder that disappears
  when the app quits. Move Right Here.app into Applications first.
- Try a setup without touching your own: `RH_HOME=/tmp/trial rh setup` writes the config,
  runner script, command link and Services under that folder (the Finder extension's registration is
  system-wide, so a trial leaves it alone). `rh uninstall` under the same `RH_HOME` undoes it. `rh doctor` under it says
  so on standard error, since its rows mix that home's files with the real extension registration.
- Changed setup, its report, a sentence of the doctor or the agent playbook (`docs/AGENT_SETUP.md`)? Run the cold-agent
  evaluation (`docs/development/SETUP_EVALUATION.md`): fresh AI agents set Right Here up for three personas in a sandbox that cannot
  touch your Mac.
- Test an action without side effects with `rh run <id> --dry-run`.
- Point a command at a throwaway config with `RH_CONFIG_DIR=/tmp/x`.
