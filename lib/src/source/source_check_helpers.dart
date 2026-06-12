part of 'source_check_command.dart';

Directory _resolveDirectory(Directory workingDirectory, String path) {
  final directory = Directory(path);
  return directory.isAbsolute
      ? directory
      : Directory('${workingDirectory.path}/$path');
}

String _resolveRepositoryUrl(Directory source, String url) {
  final local = localSourceDirectoryFromUrl(url);
  if (local != null) {
    return local.isAbsolute
        ? local.path
        : Directory('${source.path}/${local.path}').path;
  }
  final directory = Directory(url);
  if (directory.isAbsolute || _looksLikeRemoteGitUrl(url)) {
    return url;
  }
  return Directory('${source.path}/$url').path;
}

List<String> _filterNames(List<String> names, Set<String> filters) {
  if (filters.isEmpty) {
    return names;
  }
  return names.where(filters.contains).toList(growable: false)..sort();
}

void _sortPlannedReleaseChecks(List<_PlannedReleaseCheck> items) {
  items.sort(_comparePlannedReleaseChecks);
}

void _sortSkippedReleaseChecks(List<_SkippedReleaseCheck> items) {
  items.sort(
    (a, b) => _comparePlannedReleaseChecks(a.check, b.check) != 0
        ? _comparePlannedReleaseChecks(a.check, b.check)
        : a.skipReason.compareTo(b.skipReason),
  );
}

int _comparePlannedReleaseChecks(
  _PlannedReleaseCheck a,
  _PlannedReleaseCheck b,
) {
  final fields = [
    a.manifestName.compareTo(b.manifestName),
    a.package.name.compareTo(b.package.name),
    a.sdk.sdkLine.compareTo(b.sdk.sdkLine),
    a.tag.compareTo(b.tag),
    a.reason.compareTo(b.reason),
  ];
  return fields.firstWhere((value) => value != 0, orElse: () => 0);
}

bool _looksLikeRemoteGitUrl(String value) {
  return RegExp(r'^(https?|ssh|git)://').hasMatch(value) ||
      RegExp(r'^[A-Za-z0-9_.-]+@[^:]+:.+').hasMatch(value);
}

String _releaseTag(
  String packageName,
  String sdkLine,
  SourceManifestRelease release,
) {
  return packageReleaseTagForPackage(
    packageName: packageName,
    upstreamVersion: release.upstreamVersion,
    sdkVersion: '$sdkLine.0-ohos-0.0.0',
    releaseVersion: release.version,
  );
}

String _releaseFingerprint(SourceManifestRelease release) {
  return [
    release.version,
    release.upstreamVersion,
    release.upstreamRef ?? '',
    release.upstreamCommit,
    release.status,
  ].join('\u{1f}');
}

String _sdkReleaseVersions(SourceRootManifest manifest) {
  return (manifest.sdkReleases.map((release) => release.version).toList()
        ..sort())
      .join('\u{1f}');
}

String _rootManifestRoutes(SourceRootManifest manifest) {
  return (manifest.manifests.map((route) => route.name).toList()..sort()).join(
    '\u{1f}',
  );
}

String _rootManifestMetadataFingerprint(SourceRootManifest manifest) {
  return [
    manifest.schemaVersion,
    manifest.name,
    manifest.description ?? '',
    manifest.repositoryGitUrl ?? '',
  ].join('\u{1f}');
}

String _sourceManifestMetadataFingerprint(SourceManifest manifest) {
  final package = manifest.package;
  return [
    manifest.schemaVersion,
    manifest.name,
    manifest.repositoryGitUrl,
    manifest.upstreamGitUrl,
    package.name,
    package.path,
  ].join('\u{1f}');
}

Map<String, String> _manifestReleaseFingerprints(SourceManifest manifest) {
  final releases = <String, String>{};
  final package = manifest.package;
  final sdks = package.sdks.values.toList(growable: false)
    ..sort((a, b) => a.sdkLine.compareTo(b.sdkLine));
  for (final sdk in sdks) {
    for (final release in sdk.releases) {
      final tag = _releaseTag(package.name, sdk.sdkLine, release);
      releases['${package.name}\u{1e}${sdk.sdkLine}\u{1e}$tag'] =
          _releaseFingerprint(release);
    }
  }
  return releases;
}

String _advisoryMaintenanceFingerprint(SourceManifest manifest) {
  final package = manifest.package;
  final maintenance = package.maintenance;
  final advisory = package.advisory;
  return [
    package.name,
    if (maintenance == null) '' else maintenance.frozen ? 'frozen' : 'active',
    maintenance?.note ?? '',
    advisory?.message ?? '',
    if (advisory != null)
      for (final alternative in advisory.alternatives)
        [
          alternative.name,
          alternative.reason ?? '',
          alternative.url ?? '',
        ].join('\u{1d}'),
  ].join('\u{1e}');
}

List<String> _splitCommand(String value) {
  final args = <String>[];
  final buffer = StringBuffer();
  String? quote;
  var escaping = false;
  for (final codeUnit in value.runes) {
    final char = String.fromCharCode(codeUnit);
    if (escaping) {
      buffer.write(char);
      escaping = false;
      continue;
    }
    if (char == '\\') {
      escaping = true;
      continue;
    }
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        buffer.write(char);
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char.trim().isEmpty) {
      if (buffer.isNotEmpty) {
        args.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) {
    args.add(buffer.toString());
  }
  return args;
}
