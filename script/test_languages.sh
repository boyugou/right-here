#!/bin/sh
# Runs the test bundles with the system language and locale (dates, numbers) set to each language given (default: de and ar), to find a test that holds only
# on an English Mac. Build them first with `swift build --build-tests`. The CLI bundle is left out: run it through `swift test`,
# whose harness sets RH_NO_UI and RH_HOME.
#   ./script/test_languages.sh            de and ar
#   ./script/test_languages.sh ja he      the languages given
set -u
cd "$(dirname "$0")/.."
helper="$(dirname "$(xcrun -f swift)")/../libexec/swift/pm/swiftpm-testing-helper"
platform="$(xcrun --show-sdk-platform-path)/Developer"
[ "$#" -eq 0 ] && set -- de ar
status=0
for language in "$@"; do
    for bundle in AppModelTests RightHereKitTests RightHereCoreTests RightHereMCPTests; do
        binary="$PWD/.build/debug/$bundle.xctest/Contents/MacOS/$bundle"
        # The helper is run directly: a wrapper such as `timeout` drops the DYLD_ variables, and the bundle cannot load XCTest then.
        output="$(DYLD_FRAMEWORK_PATH="$platform/Library/Frameworks" DYLD_LIBRARY_PATH="$platform/usr/lib" \
            "$helper" --test-bundle-path "$binary" "$binary" --testing-library swift-testing -AppleLanguages "($language)" -AppleLocale "$language" 2>&1)"
        summary="$(printf '%s\n' "$output" | grep -E 'Test run with' | tail -1)"
        echo "$language $bundle: ${summary:-no summary}"
        if printf '%s\n' "$output" | grep -q '✘'; then
            printf '%s\n' "$output" | grep -E '✘ Test.*recorded' | head -20
            status=1
        fi
    done
done
exit $status
