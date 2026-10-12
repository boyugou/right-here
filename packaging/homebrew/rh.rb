# Homebrew formula for the command-line tool alone, built from source. It covers every action, the
# MCP server and Quick Actions; the Finder menu needs the app (see right-here.rb). A formula cannot
# write to $HOME, so the per-user setup is a separate command: `rh install --scripts --cli --services`.
class Rh < Formula
  desc "Send a folder or Finder selection to terminals, editors and AI agents"
  homepage "https://github.com/boyugou/right-here"
  url "https://github.com/boyugou/right-here/archive/refs/tags/v0.1.0.tar.gz"
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
      Set up the Finder side for your user:

        rh install --scripts --cli --services

      Then check everything with `rh doctor`. The Finder menu needs the Right Here app.
    EOS
  end

  test do
    assert_match(/\d+\.\d+\.\d+/, shell_output("#{bin}/rh --version"))
    assert_match "Copy path", shell_output("#{bin}/rh run copy-path.name --dry-run #{testpath}/a.txt")
  end
end
