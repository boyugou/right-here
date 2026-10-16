#!/usr/bin/env bash
#
# Everything CI runs, locally (plus the app build): build, tests, the localization catalog, the config schema, the docs check (commands and links),
# the evaluation doc against its harness, and the public-safety check.
# Nothing here touches your home directory, Finder or installed apps.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

swift build
swift test
# The app and the Finder extension are not part of the package: build them too (ad hoc signed, into dist/), so a
# broken target, project setting or entitlement file fails here and not at the next local install.
if command -v xcodegen >/dev/null && command -v xcodebuild >/dev/null; then
    ./script/build_app.sh >/dev/null
else
    echo "note: xcodegen or xcodebuild is missing, so the app and extension were not built" >&2
fi
uv run script/verify_localizations.py
uv run script/verify_config_schema.py
uv run script/compile_docs.py --check
uv run script/verify_docs.py
uv run script/setup_evaluation.py check
uv run script/verify_version.py
./script/verify_public_safety.sh
