#!/usr/bin/env bash
#
# Everything CI runs, locally: build, tests, the localization catalog, the config schema, the docs check (commands and links)
# and the public-safety check.
# Nothing here touches your home directory, Finder or installed apps.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

swift build
swift test
uv run script/verify_localizations.py
uv run script/verify_config_schema.py
uv run script/compile_docs.py --check
uv run script/verify_docs.py
./script/verify_public_safety.sh
