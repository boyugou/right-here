# frozen_string_literal: true

# Homebrew cask for the app (Finder extension, rh inside). The source of Casks/right-here.rb in the tap
# boyugou/homebrew-tap: script/publish_release.sh fills the version and the DMG's checksum and copies the file there.
cask "right-here" do
  version "1.2.14"
  sha256 "115a4c83cb015b250c8dc85ea9648fd72590391ddb8d4c9ce152c77526461294"

  url "https://github.com/boyugou/right-here/releases/download/v#{version}/Right-Here-#{version}.dmg"
  name "Right Here"
  desc "Send a folder or Finder selection to terminals, editors and AI agents"
  homepage "https://github.com/boyugou/right-here"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Right Here.app"
  binary "#{appdir}/Right Here.app/Contents/Helpers/rh"

  zap trash: [
    "~/.config/right-here",
    "~/.local/bin/rh",
    "~/Library/Application Scripts/com.boyugou.righthere.FinderExtension",
    "~/Library/Containers/com.boyugou.righthere.FinderExtension",
    "~/Library/Logs/right-here",
    "~/Library/Preferences/com.boyugou.righthere.plist",
    "~/Library/Services/Right Here - *.workflow",
  ]

  caveats <<~EOS
    Set Right Here up (config file, runner script, Quick Actions and the Finder extension) by opening the app and pressing Set Up, or with:

      rh setup

    Then switch on Right Here under System Settings > General > Login Items & Extensions > Finder.
    `rh setup` can be run again at any time, and `rh doctor` checks everything.

    After an upgrade, open Right Here once: replacing the app makes macOS forget the Finder extension,
    and the app registers it again, with your choice to use it or not.
  EOS
end
