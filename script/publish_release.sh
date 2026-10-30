#!/usr/bin/env bash
#
# Publish the version in AppIdentity.version as a GitHub release: a notarized, stapled DMG and its checksum, with the release notes taken from
# CHANGELOG.md. Run it from main, after the gate and after the version was raised (docs/development/RELEASING.md, steps 1 to 3).
#
#   NOTARY_PROFILE=<keychain profile> ./script/publish_release.sh     build, notarize, tag, publish, and update the cask and the formula
#   ./script/publish_release.sh --dry-run                             every check, and the release notes it would publish; nothing is built or sent
#
# Environment:
#   NOTARY_PROFILE   the notarytool keychain profile (xcrun notarytool store-credentials ...). Required for a real run.
#   RELEASE_TITLE    the release's title. Default: "Right Here <version>" (the tag is shown beside it).
#   SUPERSEDES       an older tag whose release notes get a "superseded" banner pointing here (for example v0.2.0).
#   SUPERSEDES_NOTE  one more sentence for that banner: what is wrong with the older build.
#   TAP              the Homebrew tap that gets the cask and the formula. Default: <owner of this repository>/homebrew-tap.
#
# It refuses to run unless the working tree is clean, HEAD is main and is what origin/main has, `verify_version.py` agrees, the top numbered
# section of CHANGELOG.md is this version and is not empty, neither the tag nor a release of that name exists, `gh` is signed in and the notarytool profile works.
# The tag is annotated and pushed before the release is created. It writes the version and the checksums into the cask and the formula of
# packaging/homebrew, copies both to the tap and pushes the tap; the change to packaging/homebrew is left for you to commit and push.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
[[ $# -le 1 && ( $# -eq 0 || "$1" == "--dry-run" ) ]] || { echo "usage: $0 [--dry-run]" >&2; exit 2; }

fail() { echo "error: $*" >&2; exit 1; }
log() { printf '\n==> %s\n' "$1" >&2; }

VERSION="$(sed -nE 's/.*static let version = "([^"]+)".*/\1/p' Sources/RightHereCore/AppIdentity.swift)"
[[ -n "$VERSION" ]] || fail "AppIdentity.version not found"
TAG="v$VERSION"

log "Checking $TAG"
[[ -z "$(git status --porcelain)" ]] || fail "the working tree is not clean"
[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || fail "HEAD is not main"
git fetch origin main --quiet
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "HEAD is not what origin/main has: push (after the gate) or pull first"
./script/verify_version.py >&2
command -v gh >/dev/null || fail "gh is not installed"
gh auth status >/dev/null 2>&1 || fail "gh is not signed in"
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "the tag $TAG exists"
! git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1 || fail "the tag $TAG exists on origin"
! gh release view "$TAG" >/dev/null 2>&1 || fail "a release $TAG exists"
TAP="${TAP:-$(gh repo view --json owner -q .owner.login)/homebrew-tap}"
gh repo view "$TAP" >/dev/null 2>&1 || fail "the tap $TAP cannot be read"

# GitHub shows each line break of release notes as one, where a Markdown file joins wrapped lines: join the lines of a paragraph or a
# list item, keep blank lines, headings, tables, quotes and the start of each item.
join_wrapped_lines() {
  awk '
    /^$/ { if (buf != "") print buf; buf = ""; print ""; next }
    /^(- |\* |#|\||> |[0-9]+\. )/ { if (buf != "") print buf; buf = $0; next }
    { line = $0; sub(/^ +/, "", line); buf = (buf == "" ? line : buf " " line) }
    END { if (buf != "") print buf }
  '
}

# The notes: the CHANGELOG section of this version, without its heading.
NOTES="$(mktemp -t right-here-notes)"
TAP_DIR=""
trap 'rm -f "$NOTES"; [[ -z "$TAP_DIR" ]] || rm -rf "$TAP_DIR"' EXIT
awk -v heading="## $VERSION" 'index($0, heading) == 1 { found = 1; next } found && /^## / { exit } found { print }' CHANGELOG.md \
  | sed -e '/./,$!d' | join_wrapped_lines > "$NOTES"
# A link to a file of the repository (docs/decisions/…) is relative to the release page there, where it leads nowhere: point it at the tag.
REPO_URL="$(gh repo view --json url -q .url)"
sed -i '' -E "s#\]\(([^):\#][^):]*)\)#](${REPO_URL}/blob/${TAG}/\1)#g" "$NOTES"
[[ -s "$NOTES" ]] || fail "the CHANGELOG section of $VERSION is empty or missing"
TITLE="${RELEASE_TITLE:-Right Here $VERSION}"
# What every release says beside its own changes: who can run it and how to update.
printf '\n%s\n' "Needs a Mac with Apple silicon and macOS 26 or later. To update, replace the app in Applications with the one in the DMG (or run \`brew upgrade --cask right-here\`), then open Right Here and press Install or Repair." >> "$NOTES"

if [[ "$DRY_RUN" == 1 ]]; then
  echo "title: $TITLE"
  echo "supersedes: ${SUPERSEDES:-nothing}"
  echo "would build and notarize dist/Right-Here-$VERSION.dmg, tag $TAG at $(git rev-parse --short HEAD), publish the release, update the cask and the formula and copy them to $TAP. The notes:"
  echo "-----"
  cat "$NOTES"
  echo "-----"
  exit 0
fi

[[ -n "${NOTARY_PROFILE:-}" ]] || fail "NOTARY_PROFILE is not set: a release is notarized"
# Before the build, which takes minutes: a profile that is gone (it was once, between two releases) is found at once.
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "the notarytool profile $NOTARY_PROFILE does not work (xcrun notarytool history --keychain-profile $NOTARY_PROFILE says why): store it again with xcrun notarytool store-credentials, then run this again"

log "Building, notarizing and verifying the DMG"
DMG="$ROOT/dist/Right-Here-$VERSION.dmg"
[[ ! -e "$DMG" ]] || fail "$DMG exists: remove it first"
./script/package_dmg.sh >&2
[[ -f "$DMG" && -f "$DMG.sha256" ]] || fail "package_dmg.sh did not leave the DMG and its checksum"
# The DMG must be notarized and stapled: a release that Gatekeeper would refuse is not published.
xcrun stapler validate "$DMG" >&2 || fail "the DMG is not stapled"

log "Tagging and publishing $TAG"
git tag -a "$TAG" -m "Right Here $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$DMG" "$DMG.sha256" --title "$TITLE" --notes-file "$NOTES" --latest

if [[ -n "${SUPERSEDES:-}" ]]; then
  log "Marking $SUPERSEDES as superseded"
  OLD="$(mktemp -t right-here-old-notes)"
  gh release view "$SUPERSEDES" --json body -q .body > "$OLD"
  BANNER="> **Superseded by [$TAG]($(gh repo view --json url -q .url)/releases/tag/$TAG).** Download that one: it has everything below, and the fixes listed in its notes.${SUPERSEDES_NOTE:+ $SUPERSEDES_NOTE}"
  if ! grep -qF "Superseded by" "$OLD"; then
    { printf '%s\n\n' "$BANNER"; cat "$OLD"; } > "$OLD.new"
    gh release edit "$SUPERSEDES" --notes-file "$OLD.new" --latest=false
    rm -f "$OLD.new"
  fi
  rm -f "$OLD"
fi

log "Filling the cask and the formula"
SUM="$(cut -d' ' -f1 "$DMG.sha256")"
sed -i '' -E "s/^( *version )\"[^\"]+\"/\\1\"$VERSION\"/; s/^( *sha256 )\"[0-9a-f]{64}\"/\\1\"$SUM\"/" packaging/homebrew/right-here.rb
# The formula builds from the source archive GitHub makes of the tag, which exists only now that the tag is pushed.
SOURCE="$(gh repo view --json url -q .url)/archive/refs/tags/$TAG.tar.gz"
SOURCE_SUM="$(curl -fsSL "$SOURCE" | shasum -a 256 | cut -d' ' -f1)"
[[ "$SOURCE_SUM" =~ ^[0-9a-f]{64}$ ]] || fail "no checksum of $SOURCE"
sed -i '' -E "s#/archive/refs/tags/v[^\"]+\\.tar\\.gz\"#/archive/refs/tags/$TAG.tar.gz\"#; s/^( *sha256 )\"[0-9a-f]{64}\"/\\1\"$SOURCE_SUM\"/" packaging/homebrew/rh.rb
grep -qF "\"$SUM\"" packaging/homebrew/right-here.rb && grep -qF "\"$SOURCE_SUM\"" packaging/homebrew/rh.rb && grep -qF "/$TAG.tar.gz\"" packaging/homebrew/rh.rb \
  || fail "the cask or the formula did not take the new version and checksums"

log "Copying the cask and the formula to $TAP"
TAP_DIR="$(mktemp -d -t right-here-tap)"
gh repo clone "$TAP" "$TAP_DIR" -- --quiet --depth 1
mkdir -p "$TAP_DIR/Casks" "$TAP_DIR/Formula"
cp packaging/homebrew/right-here.rb "$TAP_DIR/Casks/right-here.rb"
cp packaging/homebrew/rh.rb "$TAP_DIR/Formula/rh.rb"
git -C "$TAP_DIR" add Casks/right-here.rb Formula/rh.rb
# The tap's commits carry this repository's identity, not the global one.
git -C "$TAP_DIR" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" commit --quiet -m "right-here and rh $VERSION"
git -C "$TAP_DIR" push --quiet origin HEAD

echo "published: $(gh release view "$TAG" --json url -q .url)"
echo "$TAP has right-here and rh $VERSION. packaging/homebrew has them too: look at the change, commit it and push." >&2
