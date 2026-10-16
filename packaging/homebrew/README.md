# Homebrew templates

`right-here.rb` (a cask for the app) and `rh.rb` (a formula for the command-line tool alone) are templates for a
tap. The formula's checksum is a placeholder (`REPLACE_WITH_THE_SHA256_OF_THE_SOURCE_ARCHIVE`); the cask carries the checksum of the
v0.2.0 DMG, which is private until the first public release. Fill in the version and `sha256` from the release's `.sha256` file when
publishing a release. See
[`docs/development/RELEASING.md`](../../docs/development/RELEASING.md).
