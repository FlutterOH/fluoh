String sdkLineFromTag(String tag) {
  final match = RegExp(r'^(\d+)\.(\d+)\.\d+-ohos-.+$').firstMatch(tag);
  if (match == null) {
    throw FormatException('Invalid Flutter OHOS SDK tag: $tag');
  }

  return '${match.group(1)}.${match.group(2)}';
}

class SdkIndex {
  const SdkIndex({required this.schemaVersion, required this.releases});

  factory SdkIndex.fromJson(Map<String, Object?> json) {
    final releases = json['releases'];
    if (releases is! List) {
      throw const FormatException('SDK index releases must be a list.');
    }

    return SdkIndex(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      releases: releases
          .cast<Map<String, Object?>>()
          .map(SdkRelease.fromJson)
          .toList(growable: false),
    );
  }

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

  factory SdkRelease.fromJson(Map<String, Object?> json) {
    final tag = _requiredString(json, 'tag');

    return SdkRelease(
      version: _requiredString(json, 'version'),
      flutterVersion: _requiredString(json, 'flutterVersion'),
      channel: _requiredString(json, 'channel'),
      repository: _requiredString(json, 'repository'),
      tag: tag,
      line: json['line'] as String? ?? sdkLineFromTag(tag),
      publishedAt: json['publishedAt'] as String?,
    );
  }

  final String version;
  final String flutterVersion;
  final String channel;
  final String repository;
  final String tag;
  final String line;
  final String? publishedAt;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected "$key" to be a non-empty string.');
  }
  return value;
}
