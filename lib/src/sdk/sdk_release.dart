class SdkIndex {
  const SdkIndex({required this.schemaVersion, required this.releases});

  final int schemaVersion;
  final List<SdkRelease> releases;
}

class SdkRelease {
  const SdkRelease({
    required this.version,
    required this.versionSeries,
    required this.flutterVersion,
    required this.channel,
    required this.repository,
    required this.tag,
    this.publishedAt,
  });

  final String version;
  final String versionSeries;
  final String flutterVersion;
  final String channel;
  final String repository;
  final String tag;
  final String? publishedAt;
}
