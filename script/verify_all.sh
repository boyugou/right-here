#!/usr/bin/env bash
#
# Everything CI runs, locally: build, tests, the localization catalog and the public-safety check.
# Nothing here touches your home directory, Finder or installed apps.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

swift build
swift test
uv run script/verify_localizations.py
./script/verify_public_safety.sh
