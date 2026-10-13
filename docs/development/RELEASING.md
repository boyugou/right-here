# Releasing

1. `./script/verify_all.sh` passes and the working tree is clean.
2. Raise the version in `Sources/rh/RH.swift` (`RightHereInfo.version`) and `MARKETING_VERSION` in
   `project.yml`.
3. Store notarization credentials once per machine (skip this if a notarytool keychain profile for the same team is
   already there; `xcrun notarytool history --keychain-profile <name>` shows whether it works):

   ```sh
   xcrun notarytool store-credentials RightHereNotary --apple-id <id> --team-id <team> --password <app-specific-password>
   ```

4. Build the release:

   ```sh
   NOTARY_PROFILE=RightHereNotary ./script/package_dmg.sh
   ```

   It builds, signs inside-out (hardened runtime, secure timestamp), notarizes and staples the app, wraps it
   in a DMG, signs, notarizes and staples that, and verifies it with Gatekeeper. The output is
   `dist/Right-Here-<version>.dmg` and its `.sha256`.

   If codesign reports "timestamps differ", the system clock is wrong: turn on Date & Time > Set time and
   date automatically.

5. Tag `v<version>`, create a GitHub release with the DMG and its checksum, then update
   `packaging/homebrew/right-here.rb` (version, `sha256`) and `rh.rb` in the tap.
6. After installing from the DMG on a clean user, run `rh install` and `rh doctor --probe-launch` (a terminal window opens and closes; macOS asks once to allow Right Here to control it).

Releases are arm64 only, macOS 26 and later.
