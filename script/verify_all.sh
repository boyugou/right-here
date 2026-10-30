#!/usr/bin/env bash
#
# Everything CI runs, locally (plus the app build): build, tests, the localization catalog, the window's control styles, the config schema, the docs
# check (commands and links), the evaluation doc against its harness, and the public-safety check.
# Nothing here touches your home directory, Finder or installed apps.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Say what is missing before the long steps, not after the build and the tests.
command -v uv >/dev/null || { echo "error: uv is not installed, and the checks after the tests run on it. Install it with: brew install uv" >&2; exit 1; }
# `xcodebuild` exists on every Mac, as a shim that fails unless a full Xcode is selected, so ask it for its version.
xcodebuild -version >/dev/null 2>&1 && have_xcode=1 || have_xcode=0

swift build
swift test
# The app and the Finder extension are not part of the package: build them too (ad hoc signed, into dist/), so a
# broken target, project setting or entitlement file fails here and not at the next local install.
if command -v xcodegen >/dev/null && [[ "$have_xcode" == 1 ]]; then
    ./script/build_app.sh >/dev/null
    # CI builds with the oldest supported Xcode; build with it here too when it is installed.
    ./script/build_floor.sh
else
    echo "note: xcodegen or a full Xcode (not only the Command Line Tools) is missing, so the app and extension were not built" >&2
fi
uv run script/verify_localizations.py
uv run script/verify_window_styles.py
uv run script/verify_config_schema.py
uv run script/compile_docs.py --check
uv run script/verify_docs.py
uv run script/setup_evaluation.py check
uv run script/verify_version.py
uv run script/mutation_check.py --check
./script/verify_public_safety.sh
