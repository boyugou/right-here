#!/usr/bin/env bash
#
# Build Right Here.app and install it for the current user: ~/Applications/Right Here.app, the
# runner script, the rh link in ~/.local/bin and the Finder extension. For daily use on this Mac.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
DEST="$HOME/Applications/Right Here.app"

"$ROOT/script/build_app.sh" >&2

echo "==> Installing $DEST" >&2
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$ROOT/dist/Right Here.app" "$DEST"
"$LSREGISTER" -u "$ROOT/dist/Right Here.app" >/dev/null 2>&1 || true
"$LSREGISTER" -f -R "$DEST"
"$DEST/Contents/Helpers/rh" install
