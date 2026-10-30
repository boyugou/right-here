# Homebrew cask for the app (Finder extension, rh inside). Copy to a tap's Casks folder and fill in the
# version and checksum from script/package_dmg.sh. The official cask repository requires a
# Developer-ID-signed, notarized app; a personal tap does not enforce that.
cask "right-here" do
  version "1.0.0"
  sha256 "8f30e8cd8501fc3332a305e1f361c030177d03c8f002e14ec9978c3c283aea14"

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
    Set Right Here up (config file, runner script, Quick Actions and the Finder extension) by opening the app and pressing Set Up, or with:

      rh setup

    Then switch on Right Here under System Settings > General > Login Items & Extensions > Finder.
    `rh setup` can be run again at any time, and `rh doctor` checks everything.
  EOS
end
