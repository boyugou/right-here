#!/usr/bin/env bash
#
# Build Right Here.app: the SwiftUI app, the Finder extension, and the rh command-line tool inside
# it (Contents/Helpers/rh). The result is dist/Right Here.app, signed inside-out.
#
# Environment:
#   SIGN_IDENTITY   Signing identity (name or SHA-1). Default: the first "Developer ID Application"
#                   identity in the keychain, or ad hoc ("-") when there is none.
#   CONFIGURATION   Release (default) or Debug.
#   SECURE_TIMESTAMP  Set to 1 to add Apple's secure timestamp (needed for notarization). If codesign
#                   says "timestamps differ", the system clock is off: switch on Date & Time >
#                   Set time and date automatically.
#
# Nothing here is notarized; see script/package_dmg.sh for release builds.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-Release}"
DIST="$ROOT/dist"
DERIVED="$ROOT/.build/xcode"
APP_NAME="Right Here.app"
APP="$DIST/$APP_NAME"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

log() { printf '\n==> %s\n' "$1" >&2; }

# Fail early, and say what to do, when something the build needs is missing.
need() { command -v "$1" >/dev/null 2>&1 || { echo "error: $1 not found. $2" >&2; exit 1; }; }
need swift "Install Xcode 26 or later (the App Store or developer.apple.com)."
# `xcodebuild` is on every Mac as a shim that fails unless a full Xcode is selected (the Command Line Tools alone are not enough).
xcodebuild -version >/dev/null 2>&1 || { echo "error: a full Xcode is needed; xcodebuild does not work with only the Command Line Tools. Install Xcode 26 or later, then: sudo xcode-select -s /Applications/Xcode.app" >&2; exit 1; }
need xcodegen "Install it with: brew install xcodegen"
[[ "$(uname -m)" == "arm64" ]] || { echo "error: Right Here is built for Apple silicon (arm64) only." >&2; exit 1; }
[[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 26 ]] || { echo "error: macOS 26 or later is required (this is $(sw_vers -productVersion))." >&2; exit 1; }

resolve_identity() {
  if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    printf '%s' "$SIGN_IDENTITY"
    return
  fi
  local found
  found="$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -n 1 \
    | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-F]+)[[:space:]]+".*"$/\1/' || true)"
  printf '%s' "${found:--}"
}

IDENTITY="$(resolve_identity)"
if [[ "${SECURE_TIMESTAMP:-0}" == "1" && "$IDENTITY" != "-" ]]; then
  SIGN_FLAGS=(--force --options runtime --timestamp)
else
  SIGN_FLAGS=(--force --options runtime --timestamp=none)
fi

log "Building rh (release, arm64)"
swift build -c release --arch arm64 --product rh
RH_BINARY="$(swift build -c release --arch arm64 --show-bin-path)/rh"

log "Generating the Xcode project"
xcodegen generate --quiet

log "Building the app and the Finder extension ($CONFIGURATION)"
mkdir -p "$DERIVED"
XCODEBUILD_LOG="$DERIVED/xcodebuild.log"
if ! xcodebuild -project RightHere.xcodeproj -scheme RightHere -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build > "$XCODEBUILD_LOG" 2>&1; then
  grep -E "error:" "$XCODEBUILD_LOG" >&2 || true
  # A compiler that crashes prints a stack dump and no "error:" line, so show how the log ends as well.
  echo "error: xcodebuild failed. The end of $XCODEBUILD_LOG:" >&2
  tail -n 40 "$XCODEBUILD_LOG" >&2
  exit 1
fi
grep -E "warning: .*(sign|entitle)|BUILD SUCCEEDED" "$XCODEBUILD_LOG" || true
BUILT_APP="$DERIVED/Build/Products/$CONFIGURATION/$APP_NAME"
[[ -d "$BUILT_APP" ]] || { echo "Build did not produce $BUILT_APP" >&2; exit 1; }

log "Assembling $APP_NAME"
rm -rf "$APP"
mkdir -p "$DIST"
cp -R "$BUILT_APP" "$APP"
# Xcode registers its own build product with LaunchServices; a second registration of the same
# Finder extension makes macOS drop it, so remove that one.
"$LSREGISTER" -u "$BUILT_APP" >/dev/null 2>&1 || true
mkdir -p "$APP/Contents/Helpers"
cp "$RH_BINARY" "$APP/Contents/Helpers/rh"
# The MIT license of a bundled dependency asks that its notice travels with binaries.
mkdir -p "$APP/Contents/Resources"
cp LICENSE NOTICE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"

log "Signing with: $IDENTITY"
codesign "${SIGN_FLAGS[@]}" --sign "$IDENTITY" "$APP/Contents/Helpers/rh"
codesign "${SIGN_FLAGS[@]}" --sign "$IDENTITY" --entitlements Apps/FinderExtension/FinderExtension.entitlements \
  "$APP/Contents/PlugIns/FinderExtension.appex"
codesign "${SIGN_FLAGS[@]}" --sign "$IDENTITY" --entitlements Apps/RightHere/RightHere.entitlements "$APP"

log "Verifying"
codesign --verify --deep --strict "$APP"
# rh's alerts read the app's icon from this file (FailureAlert.iconFile): without it they show the icon of the Helpers folder.
[[ -f "$APP/Contents/Resources/AppIcon.icns" ]] || { echo "error: $APP has no Contents/Resources/AppIcon.icns" >&2; exit 1; }
codesign -d --entitlements - --xml "$APP/Contents/PlugIns/FinderExtension.appex" 2>/dev/null | plutil -p - | sed 's/^/    /'
"$APP/Contents/Helpers/rh" --version | sed 's/^/rh /'
echo "$APP"
