class Fluoh < Formula
  desc "FlutterOH SDK and OHOS package implementation command-line tools"
  homepage "https://github.com/FlutterOH/fluoh"
  url "https://pub.dev/api/archives/fluoh-0.1.0.tar.gz"
  sha256 :no_check
  version "0.1.0"
  license "MIT"

  depends_on "dart-sdk" => :build

  def install
    system "dart", "pub", "get"
    system "dart", "compile", "exe", "bin/fluoh.dart", "-o", bin/"fluoh"
    system "dart", "compile", "exe", "bin/fluohf.dart", "-o", bin/"fluohf"
  end

  test do
    assert_match "fluoh #{version}", shell_output("#{bin}/fluoh --version")
    assert_match "Usage: fluohf <args>", shell_output("#{bin}/fluohf --help")
  end
end
