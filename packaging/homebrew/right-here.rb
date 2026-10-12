# Homebrew cask for the app (Finder extension, rh inside). Copy to a tap's Casks folder and fill in the
# version and checksum from script/package_dmg.sh. The official cask repository requires a
# Developer-ID-signed, notarized app; a personal tap does not enforce that.
cask "right-here" do
  version "0.1.0"
  sha256 "REPLACE_WITH_THE_SHA256_OF_THE_DMG"

  url "https://github.com/boyugou/right-here/releases/download/v#{version}/Right-Here-#{version}.dmg"
  name "Right Here"
  desc "Send a folder or Finder selection to terminals, editors and AI agents"
  homepage "https://github.com/boyugou/right-here"

  depends_on arch: :arm64
  depends_on macos: ">= :tahoe"

  app "Right Here.app"
  binary "#{appdir}/Right Here.app/Contents/Helpers/rh"

  zap trash: [
    "~/.config/right-here",
    "~/.local/bin/rh",
    "~/Library/Application Scripts/com.boyugou.righthere.FinderExtension",
    "~/Library/Logs/right-here",
    "~/Library/Services/Right Here - *.workflow",
  ]

  caveats <<~EOS
    Run once to connect Finder (runner script, config, Quick Actions and the Finder extension):

      rh install

    Then check everything with `rh doctor`.
  EOS
end
