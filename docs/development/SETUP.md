# Building, installing, testing

Requirements: macOS 26 or later on Apple silicon, Xcode 26 or later, `xcodegen`
(`brew install xcodegen`).

```sh
swift build                # the libraries and rh
swift test                 # all unit tests; no test touches your home directory or Finder
./script/build_app.sh      # dist/Right Here.app: app, Finder extension and rh (Contents/Helpers/rh)
./script/install_local.sh  # build, copy to ~/Applications, run `rh install`
```

`install_local.sh` signs with the first "Developer ID Application" identity in your keychain, or ad hoc
when there is none (`SIGN_IDENTITY` overrides). It does not notarize.

`rh install` writes the runner script, links `rh` into `~/.local/bin`, creates the config from what it
finds, and registers and enables the Finder extension. `rh doctor` checks all of it; `rh uninstall`
removes it (the config stays).

## Things that will bite

- Xcode registers its own build product with LaunchServices. A second registration of the Finder
  extension makes macOS drop it, so `build_app.sh` unregisters the build folder copy.
- codesign with a secure timestamp fails with "timestamps differ" when the system clock is off.
  Local builds skip the timestamp; release builds need a correct clock.
- A downloaded app that was not moved yet runs from a temporary copy (App Translocation). `rh install`
  refuses there, because the runner script and the Services would point into a folder that disappears
  when the app quits. Move Right Here.app into Applications first.
- Try an install without touching your own: `RH_HOME=/tmp/trial rh install --skip-finder` writes the config,
  runner script, command link and Services under that folder (the Finder extension's registration is
  system-wide, so a trial leaves it alone). `rh uninstall` under the same `RH_HOME` undoes it.
- Test an action without side effects with `rh run <id> --dry-run`.
- Point a command at a throwaway config with `RH_CONFIG_DIR=/tmp/x`.
