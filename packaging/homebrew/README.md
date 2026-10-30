# Homebrew

`right-here.rb` (a cask for the app) and `rh.rb` (a formula for the command-line tool alone, built from source) are the sources of the
tap [boyugou/homebrew-tap](https://github.com/boyugou/homebrew-tap):

```sh
brew install --cask boyugou/tap/right-here
brew install boyugou/tap/rh
```

One or the other: the cask links the app's `rh` into Homebrew's `bin` too. Homebrew's `conflicts_with formula:` in a cask is not
checked (only casks are), so the files cannot say it; the tap's README does.

Edit them here, never in the tap. `script/publish_release.sh` writes each release's version and checksums into them and copies them to the
tap. See [`docs/development/RELEASING.md`](../../docs/development/RELEASING.md).
