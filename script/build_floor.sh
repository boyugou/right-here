#!/usr/bin/env bash
#
# Build the package with its tests, and the app, with the oldest Xcode the project supports (26) when one is installed beside a newer
# selected Xcode. CI builds with that Xcode, and its Swift can crash on or reject code that a newer Swift compiles: Swift 6.3 crashed on
# a method passed as a SwiftUI binding's setter, which Swift 6.4 compiled. Without such an Xcode it prints a note and succeeds.
# Its output goes under .build/floor and .build/floor-xcode, apart from the selected Xcode's.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

FLOOR=26
major() { defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null | cut -d. -f1; }

selected="$(xcode-select -p 2>/dev/null || true)"
selected_app="${selected%/Contents/Developer}"
if [[ -d "$selected_app" && "$(major "$selected_app")" == "$FLOOR" ]]; then
  echo "note: the selected Xcode is Xcode $FLOOR, which the other checks already built with" >&2
  exit 0
fi

floor_app=""
while IFS= read -r app; do
  [[ -n "$app" && "$(major "$app")" == "$FLOOR" ]] && { floor_app="$app"; break; }
done < <({ mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null; ls -d /Applications/Xcode*.app 2>/dev/null; } | sort -u)
if [[ -z "$floor_app" ]]; then
  echo "note: no Xcode $FLOOR is installed, so nothing was built with it; CI does" >&2
  exit 0
fi

export DEVELOPER_DIR="$floor_app/Contents/Developer"
echo "==> Building with $(xcodebuild -version | head -n 1) ($floor_app)" >&2
swift build --scratch-path .build/floor --build-tests
command -v xcodegen >/dev/null || { echo "note: xcodegen is missing, so the app was not built with Xcode $FLOOR" >&2; exit 0; }
xcodegen generate --quiet
LOG=.build/floor-xcode.log
mkdir -p .build
if ! xcodebuild -project RightHere.xcodeproj -scheme RightHere -configuration Release -derivedDataPath .build/floor-xcode \
  CODE_SIGNING_ALLOWED=NO build > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" >&2 || true
  echo "error: the app does not build with Xcode $FLOOR. The end of $LOG:" >&2
  tail -n 40 "$LOG" >&2
  exit 1
fi
echo "ok: the package, its tests and the app build with Xcode $FLOOR" >&2
