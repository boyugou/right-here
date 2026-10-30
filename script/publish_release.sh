#!/usr/bin/env bash
#
# Publish the version in AppIdentity.version as a GitHub release: a notarized, stapled DMG and its checksum, with the release notes taken from
# CHANGELOG.md. Run it from main, after the gate and after the version was raised (docs/development/RELEASING.md, steps 1 to 3).
#
#   NOTARY_PROFILE=<keychain profile> ./script/publish_release.sh     build, notarize, tag, publish, and fill the cask's checksum
#   ./script/publish_release.sh --dry-run                             every check, and the release notes it would publish; nothing is built or sent
#
# Environment:
#   NOTARY_PROFILE   the notarytool keychain profile (xcrun notarytool store-credentials ...). Required for a real run.
#   RELEASE_TITLE    what follows "v<version>: " in the release's title. Default: "Right Here <version>".
#   SUPERSEDES       an older tag whose release notes get a "superseded" banner pointing here (for example v0.2.0).
#   SUPERSEDES_NOTE  one more sentence for that banner: what is wrong with the older build.
#
# It refuses to run unless the working tree is clean, HEAD is main and is what origin/main has, `verify_version.py` agrees, the top numbered
# section of CHANGELOG.md is this version and is not empty, neither the tag nor a release of that name exists, `gh` is signed in and the notarytool profile works.
# The tag is annotated and pushed before the release is created. It edits the cask (version and checksum) and leaves that change for you to commit and push.

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

# The notes: the CHANGELOG section of this version, without its heading.
NOTES="$(mktemp -t right-here-notes)"
trap 'rm -f "$NOTES"' EXIT
awk -v heading="## $VERSION" 'index($0, heading) == 1 { found = 1; next } found && /^## / { exit } found { print }' CHANGELOG.md \
  | sed -e '/./,$!d' > "$NOTES"
[[ -s "$NOTES" ]] || fail "the CHANGELOG section of $VERSION is empty or missing"
TITLE="$TAG: ${RELEASE_TITLE:-Right Here $VERSION}"

if [[ "$DRY_RUN" == 1 ]]; then
  echo "title: $TITLE"
  echo "supersedes: ${SUPERSEDES:-nothing}"
  echo "would build and notarize dist/Right-Here-$VERSION.dmg, tag $TAG at $(git rev-parse --short HEAD), publish the release and fill the cask. The notes:"
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

log "Filling the cask"
SUM="$(cut -d' ' -f1 "$DMG.sha256")"
sed -i '' -E "s/^( *version )\"[^\"]+\"/\\1\"$VERSION\"/; s/^( *sha256 )\"[0-9a-f]{64}\"/\\1\"$SUM\"/" packaging/homebrew/right-here.rb

echo "published: $(gh release view "$TAG" --json url -q .url)"
echo "packaging/homebrew/right-here.rb now has $VERSION and $SUM: look at it, commit it and push." >&2
