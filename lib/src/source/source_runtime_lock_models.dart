part of 'source_runtime.dart';

const _sourceSnapshotStateFileName = '.fluoh-source-state.json';
const _sourceSnapshotStateVersion = 1;

class _ResolvedSourceLock {
  const _ResolvedSourceLock({
    required this.fingerprint,
    required this.sdkIndex,
    required this.packageRoutes,
  });

  final Map<String, Object?> fingerprint;
  final SdkIndex sdkIndex;
  final _PackageRouteLock packageRoutes;

  Map<String, Object?> toJson() {
    return {
      'fingerprint': fingerprint,
      'sdk': {
        'sources': _sdkSourcesToJson(sdkIndex.releases),
        'versions': {
          for (final release in _sortedSdkReleases(sdkIndex.releases))
            release.version: _sdkReleaseToJson(release),
        },
      },
      'packageRoutes': packageRoutes.toJson(),
    };
  }
}

_ResolvedSourceLock _resolvedSourceLockFromJson(Map<String, Object?> json) {
  return _ResolvedSourceLock(
    fingerprint: _jsonObject(
      json['fingerprint'],
      'sources.lock.json fingerprint',
    ),
    sdkIndex: _sdkIndexFromLock(json),
    packageRoutes: _packageRouteLockFromJson(json['packageRoutes']),
  );
}

class _PackageRouteLock {
  const _PackageRouteLock({required this.packages});

  final Map<String, Map<String, List<String>>> packages;

  Set<String>? manifestNamesForSource(
    String sourceName,
    Set<String>? packageNames,
  ) {
    if (packageNames == null) {
      return null;
    }
    final sourcePackages = packages[sourceName];
    if (sourcePackages == null) {
      return <String>{};
    }
    return {
      for (final packageName in sourcePackages.keys)
        if (packageNames.contains(packageName)) packageName,
    };
  }

  Map<String, Object?> toJson() {
    return {
      for (final sourceEntry in packages.entries)
        sourceEntry.key: {
          for (final packageEntry in sourceEntry.value.entries)
            packageEntry.key: packageEntry.value,
        },
    };
  }
}

_PackageRouteLock _packageRouteLockFromJson(Object? value) {
  final packages = _jsonObject(value, 'sources.lock.json packageRoutes');
  return _PackageRouteLock(
    packages: {
      for (final sourceEntry in packages.entries)
        sourceEntry.key: _packageSdkLinesFromJson(
          sourceEntry.value,
          'sources.lock.json packageRoutes.${sourceEntry.key}',
        ),
    },
  );
}

Map<String, List<String>> _packageSdkLinesFromJson(
  Object? value,
  String label,
) {
  final json = _jsonObject(value, label);
  return {
    for (final entry in json.entries)
      entry.key: _jsonStringList(entry.value, '$label.${entry.key}'),
  };
}

Map<String, Object?> _sdkReleaseToJson(SdkRelease release) {
  final sourceName = release.sourceName;
  if (sourceName == null) {
    throw StateError(
      'Source lock SDK release ${release.version} is missing source metadata.',
    );
  }
  return {
    'source': sourceName,
    if (release.versionSeries !=
        sdkVersionSeriesFromSdkVersion(release.version))
      'versionSeries': release.versionSeries,
    if (release.flutterVersion != flutterVersionFromSdkVersion(release.version))
      'flutterVersion': release.flutterVersion,
    if (release.channel != 'stable') 'channel': release.channel,
    if (release.tag != release.version) 'tag': release.tag,
    if (release.publishedAt != null) 'publishedAt': release.publishedAt,
  };
}

Map<String, Object?> _sdkSourcesToJson(Iterable<SdkRelease> releases) {
  final repositories = <String, String>{};
  for (final release in releases) {
    final sourceName = release.sourceName;
    if (sourceName == null) {
      throw StateError(
        'Source lock SDK release ${release.version} is missing source metadata.',
      );
    }
    final existing = repositories[sourceName];
    if (existing != null && existing != release.repository) {
      throw StateError(
        'Source lock SDK source $sourceName has multiple repositories.',
      );
    }
    repositories[sourceName] = release.repository;
  }
  return {
    for (final sourceName in _sortedStrings(repositories.keys))
      sourceName: {
        'git': {'url': repositories[sourceName]},
      },
  };
}

SdkIndex _sdkIndexFromLock(Map<String, Object?> json) {
  final sdk = _jsonObject(json['sdk'], 'sources.lock.json sdk');
  final sources = _sdkSourceRepositoriesFromLock(sdk['sources']);
  final versions = _jsonObject(
    sdk['versions'],
    'sources.lock.json sdk.versions',
  );
  return SdkIndex(
    schemaVersion: 1,
    releases: [
      for (final entry in versions.entries)
        _sdkReleaseFromLock(entry.key, entry.value, sources),
    ],
  );
}

Map<String, String> _sdkSourceRepositoriesFromLock(Object? value) {
  final sources = _jsonObject(value, 'sources.lock.json sdk.sources');
  return {
    for (final entry in sources.entries)
      entry.key: _requiredString(
        _jsonObject(
          _jsonObject(
            entry.value,
            'sources.lock.json sdk.sources.${entry.key}',
          )['git'],
          'sources.lock.json sdk.sources.${entry.key}.git',
        )['url'],
        'sources.lock.json sdk.sources.${entry.key}.git.url',
      ),
  };
}

SdkRelease _sdkReleaseFromLock(
  String version,
  Object? value,
  Map<String, String> sourceRepositories,
) {
  final json = _jsonObject(value, 'sources.lock.json sdk.versions.$version');
  final sourceName = _requiredString(
    json['source'],
    'sources.lock.json sdk.versions.$version.source',
  );
  final repository = sourceRepositories[sourceName];
  if (repository == null) {
    throw FormatException(
      'sources.lock.json sdk.versions.$version.source must reference '
      'sdk.sources.',
    );
  }
  return SdkRelease(
    version: version,
    versionSeries:
        _optionalString(json['versionSeries']) ??
        sdkVersionSeriesFromSdkVersion(version),
    flutterVersion:
        _optionalString(json['flutterVersion']) ??
        flutterVersionFromSdkVersion(version),
    channel: _optionalString(json['channel']) ?? 'stable',
    repository: repository,
    tag: _optionalString(json['tag']) ?? version,
    publishedAt: _optionalString(json['publishedAt']),
    sourceName: sourceName,
    sourcePriority: _optionalInt(json['priority']) ?? 0,
  );
}

CompatibilityMatrix _compatibilityMatrixFromPackageIndex(PackageIndex index) {
  final versions = <String, List<String>>{};
  for (final entry in index.packages.entries) {
    for (final status in entry.value.compatibility) {
      if (status.status != 'implemented') {
        continue;
      }
      versions.putIfAbsent(status.sdkLine, () => <String>[]).add(entry.key);
    }
  }
  return CompatibilityMatrix(
    schemaVersion: 1,
    sdkVersions: versions.map(
      (sdkLine, packageNames) => MapEntry(
        sdkLine,
        CompatibilityVersion(
          native: const <String>[],
          implemented: packageNames.toSet().toList(growable: false)..sort(),
          blocked: const <String>[],
        ),
      ),
    ),
  );
}

List<SdkRelease> _sortedSdkReleases(Iterable<SdkRelease> releases) {
  return releases.toList(growable: false)..sort((a, b) {
    final version = comparePubVersionsAscending(a.version, b.version);
    if (version != 0) {
      return version;
    }
    return a.repository.compareTo(b.repository);
  });
}

List<SourcePackageRouteManifest> _sortedRouteManifests(
  Map<String, SourcePackageRouteManifest> manifests,
) {
  return manifests.values.toList(growable: false)
    ..sort((a, b) => a.name.compareTo(b.name));
}

List<MapEntry<String, List<String>>> _sortedPackageRoutes(
  Map<String, List<String>> packages,
) {
  return packages.entries.toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));
}

List<String> _sortedStrings(Iterable<String> values) {
  return values.toSet().toList(growable: false)..sort();
}
