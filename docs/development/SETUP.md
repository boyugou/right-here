# Building, installing, testing

Requirements: macOS 26 or later on Apple silicon, Xcode 26 or later (27 works), `xcodegen`
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
- Test an action without side effects with `rh run <id> --dry-run`.
- Point a command at a throwaway config with `RH_CONFIG_DIR=/tmp/x`.
