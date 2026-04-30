String sdkLineFromTag(String tag) {
  final match = RegExp(r'^(\d+)\.(\d+)\.\d+-ohos-.+$').firstMatch(tag);
  if (match == null) {
    throw FormatException('Invalid Flutter OHOS SDK tag: $tag');
  }

  return '${match.group(1)}.${match.group(2)}';
}

class SdkIndex {
  const SdkIndex({required this.schemaVersion, required this.releases});

  final int schemaVersion;
  final List<SdkRelease> releases;
}

class SdkRelease {
  const SdkRelease({
    required this.version,
    required this.flutterVersion,
    required this.channel,
    required this.repository,
    required this.tag,
    required this.line,
    this.publishedAt,
  });

  final String version;
  final String flutterVersion;
  final String channel;
  final String repository;
  final String tag;
  final String line;
  final String? publishedAt;
}
