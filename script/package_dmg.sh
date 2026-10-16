#!/usr/bin/env bash
#
# Build the release artifact: a Developer-ID-signed, notarized and stapled "Right Here" DMG.
#
#   1. Build the app (rh inside), signed inside-out with the hardened runtime and a secure timestamp.
#   2. Notarize and staple the app.
#   3. Wrap it in a DMG with an Applications link, sign, notarize and staple the DMG.
#   4. Verify with Gatekeeper and write a SHA-256 next to it.
#
# Environment:
#   SIGN_IDENTITY   Developer ID Application identity (name or SHA-1). Default: the first one in the keychain.
#   SECURE_TIMESTAMP  1 (default) adds Apple's secure timestamp, which notarization requires. 0 is for
#                   testing this script on a machine whose clock is off; the result cannot be notarized.
#   NOTARY_PROFILE  notarytool keychain profile. Create it once with
#                     xcrun notarytool store-credentials <name> --apple-id <id> --team-id <team> --password <app-specific>
#                   Without it the DMG is built and signed but not notarized.
#
# codesign's secure timestamp needs a correct system clock; "timestamps differ" means the clock is
# off (System Settings > General > Date & Time > set automatically).
#
# Output: dist/Right-Here-<version>.dmg and dist/Right-Here-<version>.dmg.sha256

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Right Here.app"
APP="$ROOT/dist/$APP_NAME"
log() { printf '\n==> %s\n' "$1" >&2; }

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -n 1 \
  | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-F]+)[[:space:]]+".*"$/\1/' || true)}"
[[ -n "$IDENTITY" ]] || { echo "No Developer ID Application identity found. Set SIGN_IDENTITY." >&2; exit 1; }

TS="${SECURE_TIMESTAMP:-1}"
if [[ "$TS" == 1 ]]; then DMG_TIMESTAMP="--timestamp"; else DMG_TIMESTAMP="--timestamp=none"; fi

log "Building and signing the app"
SIGN_IDENTITY="$IDENTITY" SECURE_TIMESTAMP="$TS" "$ROOT/script/build_app.sh" >&2

VERSION="$("$APP/Contents/Helpers/rh" --version)"
DMG="$ROOT/dist/Right-Here-$VERSION.dmg"
[[ -e "$DMG" ]] && { echo "$DMG already exists; bump the version or remove it." >&2; exit 1; }

notarize() { # path
  local target="$1"
  [[ -n "${NOTARY_PROFILE:-}" ]] || { echo "NOTARY_PROFILE is not set: skipping notarization of $(basename "$target")" >&2; return 1; }
  log "Notarizing $(basename "$target")"
  xcrun notarytool submit "$target" --keychain-profile "$NOTARY_PROFILE" --wait
}

# Everything temporary lives under one folder that is removed however the script ends, and a DMG mounted for
# verification is unmounted first, so a failed run leaves neither files nor a mounted volume behind.
WORK="$(mktemp -d)"
MOUNT="$WORK/mount"
cleanup() {
  if [[ -d "$MOUNT" ]]; then
    # `detach` unmounts the volume and releases the image; `diskutil unmount` alone would leave the image attached.
    hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || diskutil unmount force "$MOUNT" >/dev/null 2>&1 || true
    # Never delete through a volume that is still mounted: a different device number means it is.
    if [[ "$(stat -f %d "$MOUNT")" != "$(stat -f %d "$WORK")" ]]; then
      echo "warning: $MOUNT is still mounted; eject it with: diskutil eject '$MOUNT'" >&2
      return
    fi
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

NOTARIZED=0
ZIP="$WORK/app.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
if notarize "$ZIP"; then
  xcrun stapler staple "$APP"
  NOTARIZED=1
fi

log "Creating the DMG"
STAGE="$WORK/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Right Here" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >&2
codesign --force --sign "$IDENTITY" "$DMG_TIMESTAMP" "$DMG"
if [[ "$NOTARIZED" == 1 ]] && notarize "$DMG"; then
  xcrun stapler staple "$DMG"
fi

log "Verifying"
hdiutil verify "$DMG" >&2
codesign --verify --strict "$DMG"
mkdir -p "$MOUNT"
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT" >/dev/null
codesign --verify --deep --strict "$MOUNT/$APP_NAME"
"$MOUNT/$APP_NAME/Contents/Helpers/rh" --version >&2
# A volume that was just mounted can stay busy for a moment (an indexer, a verification still letting go of a file), and a failed
# eject here ended a release run before its checksum was written: detach a few times, then force it.
for _ in 1 2 3 4 5; do hdiutil detach "$MOUNT" >/dev/null 2>&1 && break; sleep 2; done
hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
if [[ "$NOTARIZED" == 1 ]]; then
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

# The checksum names the file without its folder, so `shasum -c` works where it is downloaded and the
# developer's paths stay out of a file that is published.
( cd "$(dirname "$DMG")" && shasum -a 256 "$(basename "$DMG")" | tee "$(basename "$DMG").sha256" )
echo "$DMG"
