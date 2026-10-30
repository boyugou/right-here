# Homebrew formula for the command-line tool alone, built from source. It covers every action, the
# MCP server and Quick Actions; the Finder menu needs the app (see right-here.rb). A formula cannot
# write to $HOME, so the per-user setup is a separate command: `rh setup`.
class Rh < Formula
  desc "Send a folder or Finder selection to terminals, editors and AI agents"
  homepage "https://github.com/boyugou/right-here"
  url "https://github.com/boyugou/right-here/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "REPLACE_WITH_THE_SHA256_OF_THE_SOURCE_ARCHIVE"
  license "Apache-2.0"

  depends_on macos: :tahoe
  depends_on xcode: ["26.0", :build]

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release", "--product", "rh", "--arch", "arm64"
    bin.install ".build/arm64-apple-macosx/release/rh"
    # The man page comes from the same argument definitions as `rh --help` (swift-argument-parser's plugin).
    mkdir "man"
    system "swift", "package", "--disable-sandbox", "plugin", "--allow-writing-to-directory", "man",
           "generate-manual", "--output-directory", "man"
    man1.install "man/rh.1"
    generate_completions_from_executable(bin/"rh", "--generate-completion-script", shell_parameter_format: :arg,
                                         shells: [:bash, :zsh, :fish])
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
    assert_match "does not exist", shell_output("#{bin}/rh run copy-path.name --dry-run #{testpath}/missing.txt 2>&1", 1)
  end
end
