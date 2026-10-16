# Releasing

1. `./script/verify_all.sh` passes and the working tree is clean.
2. Raise the version in `Sources/RightHereCore/AppIdentity.swift` (`AppIdentity.version`), `MARKETING_VERSION` in
   `project.yml`, the top heading of `CHANGELOG.md`, the two files under `packaging/homebrew` and the `version` of
   `plugins/right-here/.claude-plugin/plugin.json`;
   `./script/verify_version.py` checks that they agree.
3. Store notarization credentials once per machine (skip this if a notarytool keychain profile for the same team is
   already there; `xcrun notarytool history --keychain-profile <name>` shows whether it works):

   ```sh
   xcrun notarytool store-credentials RightHereNotary --apple-id <id> --team-id <team> --password <app-specific-password>
   ```

4. Push the commit that raises the version (after the gate), then publish from `main`:

   ```sh
   ./script/publish_release.sh --dry-run        # every check, and the release notes it would publish
   NOTARY_PROFILE=<profile> SUPERSEDES=v<older> RELEASE_TITLE="<what is new>" ./script/publish_release.sh
   ```

   It refuses to run unless the tree is clean, HEAD is `main` and equals `origin/main`, the versions agree, the top numbered section of
   `CHANGELOG.md` is this version, and neither the tag nor the release exists. Then it builds with `script/package_dmg.sh` (signs inside-out
   with the hardened runtime and a secure timestamp, notarizes and staples the app, wraps it in a DMG, signs, notarizes and staples that, and
   verifies it with Gatekeeper; the output is `dist/Right-Here-<version>.dmg` and its `.sha256`), tags `v<version>`, creates the GitHub release
   with the DMG, the checksum and the section of `CHANGELOG.md` as its notes, puts a "superseded" banner on the release named in `SUPERSEDES`,
   and writes the new version and checksum into `packaging/homebrew/right-here.rb`. Look at that change, commit it and push it, and update
   `rh.rb` in the tap.

   `NOTARY_PROFILE=… ./script/package_dmg.sh` alone builds the DMG without publishing it, and without `NOTARY_PROFILE` it builds a signed DMG
   that is not notarized (with `SECURE_TIMESTAMP=0` it needs no network: a dry run of the packaging).

   If codesign reports "timestamps differ", the system clock is wrong: turn on Date & Time > Set time and
   date automatically.

5. Keep the releases page current: when a fix that people running the released build need lands on `main`, raise the patch version and publish
   again (steps 2 and 4), and let the notes of the release it replaces say which one to download.
6. After installing from the DMG on a clean user, open the app and press Set Up (on a clean user there is no config yet, so the window asks first; or run `rh setup`), then `rh doctor --probe-launch` (a terminal window opens and closes; macOS asks once to allow Right Here to control it).

Releases are arm64 only, macOS 26 and later.

## Before the first public push

`script/verify_public_safety.sh` checks the working tree only. Scan the whole history as well, because a file that
was committed once and removed later is still in every clone:

```sh
git log -p --all | grep -n -E '/Users/|@[A-Za-z0-9.-]+\.(com|edu|org)'
```

If anything shows up that must not be public, rewrite the history on a fresh clone rather than in the working
repository, then publish from the clone:

```sh
git clone --no-local --no-hardlinks <repository> clean && cd clean
git filter-repo --path <offending path> --invert-paths
```

Check the clone with the same scan, and publish it as a new repository or force-push it only when everyone who has
the old history knows. Every commit hash changes.
