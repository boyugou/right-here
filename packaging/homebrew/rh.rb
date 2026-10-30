# frozen_string_literal: true

# Homebrew formula for the command-line tool alone, built from source. It covers every action, the
# MCP server and Quick Actions; the Finder menu needs the app (see right-here.rb). A formula cannot
# write to $HOME, so the per-user setup is a separate command: `rh setup`.
# The source of Formula/rh.rb in the tap boyugou/homebrew-tap: script/publish_release.sh fills the tag and the
# checksum of its source archive and copies the file there.
class Rh < Formula
  desc "Send a folder or Finder selection to terminals, editors and AI agents"
  homepage "https://github.com/boyugou/right-here"
  url "https://github.com/boyugou/right-here/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "4ceb22a68879dde3b4d09540474c0812fa7ae3b20921dd80772885c267aad761"
  license "Apache-2.0"

  depends_on xcode: ["26.0", :build]
  depends_on macos: :tahoe

  def install
    args = ["--disable-sandbox", "-c", "release", "--product", "rh", "--arch", "arm64"]
    system "swift", "build", *args
    # Where the product lands depends on the toolchain's build system (Swift 6.4: .build/out/Products/Release).
    bin.install "#{Utils.safe_popen_read("swift", "build", *args, "--show-bin-path").chomp}/rh"
    # The man page comes from the same argument definitions as `rh --help` (swift-argument-parser's plugin).
    mkdir "man"
    system "swift", "package", "--disable-sandbox", "plugin", "--allow-writing-to-directory", "man",
           "generate-manual", "--output-directory", "man"
    man1.install "man/rh.1"
    # The shell is a plain argument: rh --generate-completion-script bash.
    generate_completions_from_executable(bin/"rh", "--generate-completion-script")
  end

  def caveats
    <<~EOS
      Set Right Here up for your user (config file, runner script, command link, Quick Actions):

        rh setup

      It can be run again at any time, and `rh doctor` checks everything. The Finder menu needs the Right Here app (the cask);
      Quick Actions work without it.
    EOS
  end

  test do
    assert_match(/\d+\.\d+\.\d+/, shell_output("#{bin}/rh --version"))
    # A path that is not there is refused, so the test makes the file it names.
    (testpath/"a.txt").write("x")
    assert_match "Copy path", shell_output("#{bin}/rh run copy-path.name --dry-run #{testpath}/a.txt")
    assert_match "does not exist",
                 shell_output("#{bin}/rh run copy-path.name --dry-run #{testpath}/missing.txt 2>&1", 1)
  end
end
