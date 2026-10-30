#!/usr/bin/env bash
#
# Build Right Here.app and install it for the current user: ~/Applications/Right Here.app, then `rh setup`: the config, the
# runner script, the rh link in ~/.local/bin, the Quick Actions and the Finder extension. For daily use on this Mac.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
DEST="$HOME/Applications/Right Here.app"

"$ROOT/script/build_app.sh" >&2

echo "==> Installing $DEST" >&2
mkdir -p "$HOME/Applications"
# Copied beside the old app and moved over it, so a failed copy leaves the installed app in place.
STAGE="$DEST.new"
rm -rf "$STAGE"
cp -R "$ROOT/dist/Right Here.app" "$STAGE"
rm -rf "$DEST"
mv "$STAGE" "$DEST"
"$LSREGISTER" -u "$ROOT/dist/Right Here.app" >/dev/null 2>&1 || true
"$LSREGISTER" -f -R "$DEST"
"$DEST/Contents/Helpers/rh" setup
