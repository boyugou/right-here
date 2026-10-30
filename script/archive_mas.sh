#!/usr/bin/env bash
# archive_mas.sh - Build and package the macOS Mac App Store / TestFlight artifact.
#
# Usage:
#   ./script/archive_mas.sh --preflight
#   MAS_APP_SIGN_IDENTITY="<MAS-App-Sign-Identity>" \
#   MAS_INSTALLER_SIGN_IDENTITY="<MAS-Installer-Sign-Identity>" \
#   ASC_API_KEY_ID="KEY_ID" ASC_API_ISSUER_ID="ISSUER_UUID" \
#     ./script/archive_mas.sh --validate
#   ASC_API_KEY_ID="KEY_ID" ASC_API_ISSUER_ID="ISSUER_UUID" \
#     ./script/archive_mas.sh --upload
#
# Environment variables:
#   ASC_API_KEY_ID, ASC_API_ISSUER_ID   the App Store Connect API key for --validate and --upload. Its AuthKey_<id>.p8
#                                file is where altool looks (~/.private_keys or ~/.appstoreconnect/private_keys). No password is used.
#   MAS_APP_SIGN_IDENTITY         "Apple Distribution: ..." or "3rd Party Mac Developer Application: ..."
#   MAS_INSTALLER_SIGN_IDENTITY   "3rd Party Mac Developer Installer: ..."
#   MAS_APP_PROVISIONING_PROFILE  Path to .provisionprofile for com.boyugou.righthere (optional for local ad-hoc)
#   MAS_EXT_PROVISIONING_PROFILE  Path to .provisionprofile for com.boyugou.righthere.FinderExtension (optional)
#   MAS_PKG_PATH                  Custom path for output .pkg (default: dist/RightHere-MAS-<version>.pkg)

set -Eeuo pipefail
trap 'echo "archive_mas.sh: line $LINENO failed: $BASH_COMMAND" >&2' ERR

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DIST="$ROOT/dist"
DERIVED="$ROOT/.build/xcode-mas"
APP_NAME="Right Here.app"
APP="$DIST/$APP_NAME"
VERSION="$(awk '/MARKETING_VERSION:/ { print $2; exit }' "$ROOT/project.yml")"
[[ -n "$VERSION" ]] || { echo "No MARKETING_VERSION in project.yml." >&2; exit 1; }
BUILD_NUMBER="2"
PKG_PATH="${MAS_PKG_PATH:-"$DIST/RightHere-macOS-MAS-$VERSION+$BUILD_NUMBER.pkg"}"
APP_ENTITLEMENTS="$ROOT/Apps/RightHere/RightHereAppStore.entitlements"
EXT_ENTITLEMENTS="$ROOT/Apps/FinderExtension/FinderExtensionAppStore.entitlements"

log() { printf '\n==> %s\n' "$1" >&2; }

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "error: missing required environment variable: $name" >&2
    exit 2
  fi
}

require_tool() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "error: missing required tool: $name" >&2
    exit 2
  fi
}

preflight() {
  log "Preflight checking tools and prerequisites"
  require_tool productbuild
  require_tool productsign
  require_tool xcrun
  require_tool codesign
  require_tool xcodegen
  require_tool xcodebuild

  [[ -f "$APP_ENTITLEMENTS" ]] || { echo "error: missing $APP_ENTITLEMENTS" >&2; exit 1; }
  [[ -f "$EXT_ENTITLEMENTS" ]] || { echo "error: missing $EXT_ENTITLEMENTS" >&2; exit 1; }
  [[ -f "Apps/RightHere/PrivacyInfo.xcprivacy" ]] || { echo "error: missing main app PrivacyInfo.xcprivacy" >&2; exit 1; }
  [[ -f "Apps/FinderExtension/PrivacyInfo.xcprivacy" ]] || { echo "error: missing extension PrivacyInfo.xcprivacy" >&2; exit 1; }

  echo "MAS archive preflight passed"
}

package_mas() {
  preflight

  local app_identity="${MAS_APP_SIGN_IDENTITY:-}"
  local installer_identity="${MAS_INSTALLER_SIGN_IDENTITY:-}"

  if [[ -z "$app_identity" ]]; then
    app_identity="$(security find-identity -v -p codesigning 2>/dev/null | grep -E "3rd Party Mac Developer Application|Apple Distribution" | head -n 1 \
      | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-F]+)[[:space:]]+".*"$/\1/' || true)"
  fi
  if [[ -z "$installer_identity" ]]; then
    installer_identity="$(security find-identity -v -p basic 2>/dev/null | grep "3rd Party Mac Developer Installer" | head -n 1 \
      | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-F]+)[[:space:]]+".*"$/\1/' || true)"
  fi

  app_identity="${app_identity:--}"
  log "Using App Signing Identity: $app_identity"

  log "Building rh command line tool (release, arm64)"
  swift build -c release --arch arm64 --product rh
  RH_BINARY="$(swift build -c release --arch arm64 --show-bin-path)/rh"

  log "Regenerating Xcode project"
  xcodegen generate --quiet

  log "Building Release app and extension"
  rm -rf "$DERIVED"
  xcodebuild -project RightHere.xcodeproj -scheme RightHere -configuration Release \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build | { grep -E "error:|warning: .*(sign|entitle)|BUILD (SUCCEEDED|FAILED)" || true; }

  BUILT_APP="$DERIVED/Build/Products/Release/$APP_NAME"
  [[ -d "$BUILT_APP" ]] || { echo "error: build did not produce $BUILT_APP" >&2; exit 1; }

  log "Assembling Mac App Store bundle"
  rm -rf "$APP"
  mkdir -p "$DIST"
  cp -R "$BUILT_APP" "$APP"

  mkdir -p "$APP/Contents/Helpers"
  cp "$RH_BINARY" "$APP/Contents/Helpers/rh"
  mkdir -p "$APP/Contents/Resources"
  cp LICENSE NOTICE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"

  # Embed provisioning profiles if provided
  if [[ -n "${MAS_APP_PROVISIONING_PROFILE:-}" && -f "$MAS_APP_PROVISIONING_PROFILE" ]]; then
    log "Embedding App provisioning profile"
    cp "$MAS_APP_PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
  fi
  if [[ -n "${MAS_EXT_PROVISIONING_PROFILE:-}" && -f "$MAS_EXT_PROVISIONING_PROFILE" ]]; then
    log "Embedding Extension provisioning profile"
    cp "$MAS_EXT_PROVISIONING_PROFILE" "$APP/Contents/PlugIns/FinderExtension.appex/Contents/embedded.provisionprofile"
  fi

  log "Signing app and extension with App Store entitlements"
  local sign_flags=(--force --options runtime --timestamp=none)
  if [[ "$app_identity" != "-" ]]; then
    sign_flags=(--force --options runtime --timestamp)
  fi

  # Sign inside out
  codesign "${sign_flags[@]}" --sign "$app_identity" "$APP/Contents/Helpers/rh"
  codesign "${sign_flags[@]}" --sign "$app_identity" --entitlements "$EXT_ENTITLEMENTS" "$APP/Contents/PlugIns/FinderExtension.appex"
  codesign "${sign_flags[@]}" --sign "$app_identity" --entitlements "$APP_ENTITLEMENTS" "$APP"

  codesign --verify --deep --strict "$APP"
  echo "Codesign verification succeeded"

  if [[ -n "$installer_identity" && "$installer_identity" != "-" ]]; then
    log "Packaging signed installer package with $installer_identity"
    productbuild --component "$APP" /Applications --sign "$installer_identity" "$PKG_PATH"
  else
    log "Packaging installer package (ad hoc / test)"
    productbuild --component "$APP" /Applications "$PKG_PATH"
  fi

  log "MAS artifact produced at: $PKG_PATH"
}

validate_mas() {
  require_env ASC_API_KEY_ID
  require_env ASC_API_ISSUER_ID
  [[ -f "$PKG_PATH" ]] || { echo "error: $PKG_PATH not found; run --package first" >&2; exit 1; }
  log "Validating package with Apple App Store Connect: $PKG_PATH"
  xcrun altool --validate-app -f "$PKG_PATH" -t osx --apiKey "$ASC_API_KEY_ID" --apiIssuer "$ASC_API_ISSUER_ID"
}

upload_mas() {
  require_env ASC_API_KEY_ID
  require_env ASC_API_ISSUER_ID
  [[ -f "$PKG_PATH" ]] || { echo "error: $PKG_PATH not found; run --package first" >&2; exit 1; }
  log "Uploading package to Apple App Store Connect / TestFlight: $PKG_PATH"
  xcrun altool --upload-app -f "$PKG_PATH" -t osx --apiKey "$ASC_API_KEY_ID" --apiIssuer "$ASC_API_ISSUER_ID"
}

case "${1:-}" in
  --preflight) preflight ;;
  --package) package_mas ;;
  --validate) validate_mas ;;
  --upload) upload_mas ;;
  *)
    echo "Usage: $0 [--preflight | --package | --validate | --upload]" >&2
    exit 1
    ;;
esac
