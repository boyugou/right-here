#!/usr/bin/env bash
#
# Everything CI runs, locally: build, tests, the localization catalog, the config schema and the public-safety check.
# Nothing here touches your home directory, Finder or installed apps.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

swift build
swift test
uv run script/verify_localizations.py
uv run script/verify_config_schema.py
./script/verify_public_safety.sh
