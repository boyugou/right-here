# Releasing

Releases are for Apple silicon only, macOS 26 and later.

## Steps

1. **Pass the gate.** `./script/verify_all.sh` must pass, and the working tree must be clean.
   - After a change to the MCP server, also run `./script/verify_mcp_protocol.py`. It checks the server's answers against the schemas of
     every protocol version that it claims. It needs `swift build` and, the first time, the network.
   - `./script/verify_macos_wording.py` checks our names for the System Settings panes and the Finder menu items against the macOS that it
     runs on. CI runs it on the macOS 26 image.
2. **Raise the version** in all of these places:
   - `Sources/RightHereCore/AppIdentity.swift` (`AppIdentity.version`),
   - `MARKETING_VERSION` in `project.yml`,
   - the top heading of `CHANGELOG.md` (rename `## Unreleased` to `## <version> (<date>)`),
   - the two files in `packaging/homebrew`,
   - the `version` in `plugins/right-here/.claude-plugin/plugin.json`.

   `./script/verify_version.py` checks that they agree.
3. **Store the notarization credentials** once for each Mac. Skip this if a notarytool keychain profile of the same team is there:
   `xcrun notarytool history --keychain-profile <name>` shows whether it works.

   ```sh
   xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team> --password <app-specific-password>
   ```

4. **Push the commit** that raises the version, after the gate. Then publish from `main`:

   ```sh
   ./script/publish_release.sh --dry-run        # every check, and the release notes that it would publish
   NOTARY_PROFILE=<profile> SUPERSEDES=v<older> RELEASE_TITLE="<what is new>" ./script/publish_release.sh
   ```

5. **Commit the cask and the formula.** The script writes the new version and checksums into `packaging/homebrew` and pushes both files
   to the tap, [boyugou/homebrew-tap](https://github.com/boyugou/homebrew-tap), whose CI then installs them as a person would. Look at
   the change, commit it and push it. Change the "latest is" line of `ROADMAP.md` in the same commit.
6. **Keep the releases page current.** When a fix that people with the released build need lands on `main`, raise the patch version and
   publish again (steps 2 and 4). The notes of the release that it replaces then say which one to download.
7. **Update the screenshots.** They show the version in the sidebar of the window. Render them again ([`WEBSITE.md`](WEBSITE.md) lists the
   flags): the three of the website, each light and dark, and the one of the README. Resize them to 800 px. Push `gh-pages`.
8. **Try the DMG on a new user account.** Open the app and press Set Up (with no config, the window asks first), or run `rh setup`. Then run
   `rh doctor --probe-launch`: a terminal window opens and closes, and macOS asks once whether Right Here may control it.

## What `publish_release.sh` checks and does

It refuses to run unless all of these are true:

- the tree is clean, HEAD is `main`, and HEAD equals `origin/main`;
- the versions agree, and the top numbered section of `CHANGELOG.md` is this version;
- neither the tag nor the release exists;
- `gh` is signed in;
- `xcrun notarytool history --keychain-profile <profile>` works. So a profile that is gone is found before the build;
- the tap can be read.

Then it does these steps, and stops if a notarization fails or is not accepted:

1. It builds with `script/package_dmg.sh`. That script signs inside-out, with the hardened runtime and a secure timestamp. It notarizes and
   staples the app, puts it in a DMG whose window shows the app beside the Applications folder (laid out by dmgbuild from
   `script/dmg_settings.py`; `uvx` fetches it the first time), signs, notarizes and staples the DMG, and checks it with Gatekeeper. The
   output is `dist/Right-Here-<version>.dmg` and its `.sha256`.
2. It tags `v<version>`.
3. It makes the GitHub release, with the DMG, the checksum and the section of `CHANGELOG.md` as its notes.
4. It puts a "superseded" banner on the release that `SUPERSEDES` names.
5. It writes the new version and the DMG's checksum into `packaging/homebrew/right-here.rb`, and the tag and the checksum of GitHub's
   source archive of the tag into `rh.rb`.
6. It copies both to the tap (`TAP`, by default `<owner>/homebrew-tap`) and pushes it, with this repository's git identity.

If the copy to the tap fails, the release is already public and its tag cannot be moved, so do not run the script again: copy
`packaging/homebrew/right-here.rb` to the tap's `Casks/` and `rh.rb` to its `Formula/` by hand, commit with this repository's identity
and push, then commit `packaging/homebrew` here.

`NOTARY_PROFILE=… ./script/package_dmg.sh` alone builds the DMG and does not publish it. Without `NOTARY_PROFILE`, it builds a signed DMG
that is not notarized. With `SECURE_TIMESTAMP=0` as well, it needs no network once `uv` has dmgbuild: a dry run of the packaging.

If codesign says "timestamps differ", the clock of the Mac is wrong. Turn on Date & Time › Set time and date automatically.

## What the repository protects

Two rulesets keep what has been published: `main` cannot be force-pushed or deleted, and a `v*` tag cannot be moved or deleted. A release
that fails after its tag was pushed is fixed with the next patch version, not by moving the tag.

Before pushing anything that was written outside this repository, scan it for what must not be public, as `script/verify_public_safety.sh`
does for the working tree: a file committed once stays in every clone even after it is removed.
