# Homebrew templates

`right-here.rb` (a cask for the app) and `rh.rb` (a formula for the command-line tool alone) are templates for a
tap. The formula's checksum is a placeholder (`REPLACE_WITH_THE_SHA256_OF_THE_SOURCE_ARCHIVE`); the cask carries the version and checksum
of the latest release's DMG, which `script/publish_release.sh` fills in when it publishes a release. See
[`docs/development/RELEASING.md`](../../docs/development/RELEASING.md).
