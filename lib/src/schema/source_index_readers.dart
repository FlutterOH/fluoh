part of 'source_index.dart';

List<String> _sortedPackageNames(List<String>? packages) {
  if (packages == null || packages.isEmpty) {
    return const <String>[];
  }
  return packages.toSet().toList(growable: false)..sort();
}

List<SourceManifestRoute> _readManifestRoutes(Object? value) {
  final items = _objectList(value, 'manifests', allowNull: true);
  final names = <String>{};
  final routes = <SourceManifestRoute>[];
  for (var index = 0; index < items.length; index += 1) {
    final item = items[index];
    ensureAllowedKeys(item, 'manifests[$index]', {'name'});
    final name = requiredString(item, 'name');
    validateDartPackageName(name, label: 'manifests[$index].name');
    if (!names.add(name)) {
      throw FluohSchemaException('Duplicate manifest name "$name".');
    }
    routes.add(SourceManifestRoute(name: name));
  }
  _ensureManifestRoutesAscending(routes);
  return routes;
}

void _ensureManifestRoutesAscending(List<SourceManifestRoute> routes) {
  for (var index = 1; index < routes.length; index += 1) {
    final previous = routes[index - 1].name;
    final current = routes[index].name;
    if (previous.compareTo(current) > 0) {
      throw const FluohSchemaException(
        'manifests must be sorted by name in ascending order.',
      );
    }
  }
}

_FlutterOhosSdkSource? _readFlutterOhosSdkSource(Object? value) {
  if (value == null) {
    return null;
  }
  final sdk = objectMap(value, 'sdk');
  ensureAllowedKeys(sdk, 'sdk', {'git', 'versions'});
  final git = objectMap(sdk['git'], 'sdk.git');
  ensureAllowedKeys(git, 'sdk.git', {'url'});
  final repository = requiredString(git, 'url');
  final versions = _stringList(
    sdk['versions'],
    'sdk versions',
    allowNull: true,
  );
  final seenVersions = <String>{};
  for (final version in versions) {
    if (!seenVersions.add(version)) {
      throw FluohSchemaException('Duplicate SDK version "$version".');
    }
  }
  _ensureSdkVersionsAscending(versions);

  return _FlutterOhosSdkSource(
    repository: repository,
    releases: versions
        .map((version) {
          sdkVersionSeriesFromSdkVersion(version);
          return SdkRelease(
            version: version,
            versionSeries: sdkVersionSeriesFromSdkVersion(version),
            flutterVersion: flutterVersionFromSdkVersion(version),
            channel: 'stable',
            repository: repository,
            tag: version,
          );
        })
        .toList(growable: false),
  );
}

void _ensureSdkVersionsAscending(List<String> versions) {
  for (var index = 1; index < versions.length; index += 1) {
    final previous = versions[index - 1];
    final current = versions[index];
    if (comparePubVersionsAscending(previous, current) > 0) {
      throw const FluohSchemaException(
        'sdk.versions must be sorted in ascending semantic version order. '
        'Append newer SDK versions after older versions.',
      );
    }
  }
}

SourceManifestPackage _readManifestPackage(
  String packageName,
  Map<String, Object?> yaml,
  String label, {
  required String originKind,
}) {
  ensureAllowedKeys(yaml, label, {
    'name',
    'path',
    'maintenance',
    'advisory',
    'sdks',
  });
  final sdks = objectMap(yaml['sdks'], '$label sdks');
  if (sdks.isEmpty) {
    throw FluohSchemaException('$label sdks must not be empty.');
  }
  final parsedSdks = <MapEntry<String, SourceManifestSdk>>[];
  String? previousSdkLine;
  for (final entry in sdks.entries) {
    final parsedSdkLine = _sdkLine(entry.key, '$label SDK line');
    if (previousSdkLine != null &&
        _compareSdkLinesAscending(previousSdkLine, parsedSdkLine) > 0) {
      throw FluohSchemaException(
        '$label sdks must be sorted by SDK line in ascending order.',
      );
    }
    previousSdkLine = parsedSdkLine;
    parsedSdks.add(
      MapEntry(
        parsedSdkLine,
        _readManifestSdk(
          parsedSdkLine,
          objectMap(entry.value, '$label sdks.$parsedSdkLine'),
          '$label sdks.$parsedSdkLine',
          originKind: originKind,
        ),
      ),
    );
  }
  return SourceManifestPackage(
    name: packageName,
    path: normalizeManifestPath(
      optionalString(yaml, 'path'),
      label: '$label path',
    ),
    maintenance: _readMaintenance(yaml['maintenance'], '$label maintenance'),
    advisory: _readAdvisory(yaml['advisory'], '$label advisory'),
    sdks: Map.fromEntries(parsedSdks),
  );
}

SourceManifestSdk _readManifestSdk(
  String sdkLine,
  Map<String, Object?> yaml,
  String label, {
  required String originKind,
}) {
  ensureAllowedKeys(yaml, label, {'releases'});
  final releases = _objectList(yaml['releases'], '$label releases');
  if (releases.isEmpty) {
    throw FluohSchemaException('$label releases must not be empty.');
  }
  final parsedReleases = <SourceManifestRelease>[];
  final seenReleaseKeys = <String>{};
  for (var index = 0; index < releases.length; index += 1) {
    final release = _readManifestRelease(
      releases[index],
      '$label releases[$index]',
      originKind: originKind,
    );
    final key = release.tag;
    if (!seenReleaseKeys.add(key)) {
      throw FluohSchemaException(
        '$label releases contains duplicate tag ${release.tag}.',
      );
    }
    parsedReleases.add(release);
  }
  _ensureManifestReleasesAscending(parsedReleases, label);
  return SourceManifestSdk(sdkLine: sdkLine, releases: parsedReleases);
}

void _ensureManifestReleasesAscending(
  List<SourceManifestRelease> releases,
  String label,
) {
  for (var index = 1; index < releases.length; index += 1) {
    final previous = releases[index - 1];
    final current = releases[index];
    if (_compareManifestReleasesAscending(previous, current) > 0) {
      throw FluohSchemaException(
        '$label releases must be sorted by tag in ascending order.',
      );
    }
  }
}

SourceManifestRelease _readManifestRelease(
  Map<String, Object?> yaml,
  String label, {
  required String originKind,
}) {
  ensureAllowedKeys(yaml, label, {'version', 'tag', 'upstream', 'status'});
  final status = optionalString(yaml, 'status') ?? 'compatible';
  if (!const {'compatible', 'experimental', 'broken'}.contains(status)) {
    throw FluohSchemaException(
      '$label status must be compatible, experimental, or broken.',
    );
  }
  final version = _requiredScalarString(yaml, 'version');
  validateReleaseVersion(version, label: '$label version');
  final tag = _requiredScalarString(yaml, 'tag');
  parsePackageReleaseTag(tag);
  final upstreamYaml = optionalObjectMap(yaml['upstream'], '$label upstream');
  if (originKind == packageOriginPorted && upstreamYaml == null) {
    throw FluohSchemaException(
      '$label upstream is required for ported packages.',
    );
  }
  if (originKind == packageOriginCreated && upstreamYaml != null) {
    throw FluohSchemaException(
      '$label upstream must be omitted for created packages.',
    );
  }
  if (upstreamYaml != null) {
    ensureAllowedKeys(upstreamYaml, '$label upstream', {
      'version',
      'ref',
      'commit',
    });
  }
  return SourceManifestRelease(
    version: version,
    tag: tag,
    upstreamVersion: upstreamYaml == null
        ? null
        : _manifestPubVersion(
            _requiredScalarString(upstreamYaml, 'version'),
            label: '$label upstream.version',
          ),
    upstreamRef: switch (upstreamYaml == null
        ? null
        : optionalString(upstreamYaml, 'ref')) {
      final ref? => normalizeGitRef(ref, label: '$label upstream.ref'),
      null => null,
    },
    upstreamCommit: upstreamYaml == null
        ? null
        : normalizeGitCommitHash(
            _requiredScalarString(upstreamYaml, 'commit'),
            label: '$label upstream.commit',
          ),
    status: status,
  );
}

SourcePackageMaintenance? _readMaintenance(Object? value, String label) {
  if (value == null) {
    return null;
  }
  final yaml = objectMap(value, label);
  ensureAllowedKeys(yaml, label, {'frozen', 'note'});
  final frozen = yaml['frozen'];
  if (frozen != null && frozen is! bool) {
    throw FluohSchemaException('$label frozen must be a boolean.');
  }
  final note = optionalString(yaml, 'note');
  return SourcePackageMaintenance(frozen: frozen as bool? ?? false, note: note);
}

SourcePackageAdvisory? _readAdvisory(Object? value, String label) {
  if (value == null) {
    return null;
  }
  final yaml = objectMap(value, label);
  ensureAllowedKeys(yaml, label, {'message', 'alternatives'});
  return SourcePackageAdvisory(
    message: optionalString(yaml, 'message'),
    alternatives: [
      for (final alternative in _objectList(
        yaml['alternatives'],
        '$label alternatives',
        allowNull: true,
      ))
        _readAlternative(alternative, '$label alternatives[]'),
    ],
  );
}

SourcePackageAlternative _readAlternative(
  Map<String, Object?> yaml,
  String label,
) {
  ensureAllowedKeys(yaml, label, {'name', 'reason', 'url'});
  final name = requiredString(yaml, 'name');
  validateDartPackageName(name, label: '$label name');
  return SourcePackageAlternative(
    name: name,
    reason: optionalString(yaml, 'reason'),
    url: optionalString(yaml, 'url'),
  );
}

List<String> _advisoryLines(SourcePackageAdvisory advisory) {
  final lines = <String>['  advisory:'];
  if (advisory.message != null) {
    lines.add('    message: ${_yamlScalar(advisory.message!)}');
  }
  if (advisory.alternatives.isNotEmpty) {
    lines.add('    alternatives:');
    for (final alternative in advisory.alternatives) {
      lines.add('      - name: ${_yamlScalar(alternative.name)}');
      if (alternative.reason != null) {
        lines.add('        reason: ${_yamlScalar(alternative.reason!)}');
      }
      if (alternative.url != null) {
        lines.add('        url: ${_yamlScalar(alternative.url!)}');
      }
    }
  }
  return lines;
}
