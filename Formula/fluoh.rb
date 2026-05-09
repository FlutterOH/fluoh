class Fluoh < Formula
  desc "FlutterOH SDK and package adapter command-line tools"
  homepage "https://github.com/FlutterOH/fluoh"
  url "https://pub.dev/api/archives/fluoh-0.0.1.tar.gz"
  sha256 :no_check
  version "0.0.1"
  license "MIT"

  depends_on "dart-sdk"

  def install
    pub_cache = libexec/"pub-cache"
    ENV["PUB_CACHE"] = pub_cache

    system "dart", "pub", "global", "activate", "--source", "path", "."
    bin.install_symlink pub_cache/"bin/fluoh"
    bin.install_symlink pub_cache/"bin/fluohf"
  end

  test do
    assert_match "fluoh #{version}", shell_output("#{bin}/fluoh --version")
    assert_match "Usage: fluohf <args>", shell_output("#{bin}/fluohf --help")
  end
end
