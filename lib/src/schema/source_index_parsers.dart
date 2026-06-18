part of 'source_index.dart';

/// Parses a Source root `fluoh.yaml`.
SourceRootManifest parseSourceRootManifest(String content) {
  final yaml = parseYamlMap(content, label: 'fluoh.yaml');
  _ensureSourceSchema(yaml, 'fluoh.yaml');
  ensureAllowedKeys(yaml, 'fluoh.yaml', {
    'schema',
    'kind',
    'name',
    'description',
    'repository',
    'sdk',
    'manifests',
  });
  _requireKind(yaml, 'source', 'fluoh.yaml');
  final sourceName = requiredString(yaml, 'name');
  _validateSourceName(sourceName, label: 'fluoh.yaml name');

  final repository = optionalObjectMap(yaml['repository'], 'repository');
  String? repositoryGitUrl;
  if (repository != null) {
    ensureAllowedKeys(repository, 'repository', {'git'});
    final repositoryGit = objectMap(repository['git'], 'repository.git');
    ensureAllowedKeys(repositoryGit, 'repository.git', {'url'});
    repositoryGitUrl = requiredString(repositoryGit, 'url');
  }

  final sdkSource = _readFlutterOhosSdkSource(yaml['sdk']);
  final manifests = _readManifestRoutes(yaml['manifests']);

  return SourceRootManifest(
    schemaVersion: yaml['schema'] as int,
    name: sourceName,
    description: optionalString(yaml, 'description'),
    repositoryGitUrl: repositoryGitUrl,
    manifests: manifests,
    sdkRepository: sdkSource?.repository,
    sdkReleases: sdkSource?.releases ?? const <SdkRelease>[],
  );
}

/// Parses the SDK release index from a Source root `fluoh.yaml`.
SdkIndex parseSourceSdkIndex(String content) {
  return parseSourceRootManifest(content).sdkIndex;
}

/// Parses a package Manifest file.
SourceManifest parseSourceManifest({
  required String content,
  required String label,
}) {
  final yaml = parseYamlMap(content, label: label);
  _ensureSourceSchema(yaml, label);
  if (yaml.containsKey('packages')) {
    throw FluohSchemaException(
      '$label must use package; multi-package Source Manifests are no longer '
      'supported.',
    );
  }
  ensureAllowedKeys(yaml, label, {
    'schema',
    'kind',
    'repository',
    'origin',
    'upstream',
    'package',
  });
  _requireKind(yaml, 'manifest', label);

  final repository = objectMap(yaml['repository'], '$label repository');
  ensureAllowedKeys(repository, '$label repository', {'git'});
  final repositoryGit = objectMap(repository['git'], '$label repository.git');
  ensureAllowedKeys(repositoryGit, '$label repository.git', {'url'});
  final repositoryGitUrl = requiredString(repositoryGit, 'url');

  final origin = objectMap(yaml['origin'], '$label origin');
  ensureAllowedKeys(origin, '$label origin', {'kind'});
  final originKind = _sourceOriginKind(requiredString(origin, 'kind'), label);

  final upstream = optionalObjectMap(yaml['upstream'], '$label upstream');
  Map<String, Object?>? upstreamGit;
  if (originKind == packageOriginPorted) {
    if (upstream == null) {
      throw FluohSchemaException(
        '$label upstream is required for ported packages.',
      );
    }
    ensureAllowedKeys(upstream, '$label upstream', {'git'});
    upstreamGit = objectMap(upstream['git'], '$label upstream.git');
    ensureAllowedKeys(upstreamGit, '$label upstream.git', {'url'});
  } else if (upstream != null) {
    throw FluohSchemaException(
      '$label upstream must be omitted for created packages.',
    );
  }

  final packageYaml = objectMap(yaml['package'], '$label package');
  final packageName = requiredString(packageYaml, 'name');
  validateDartPackageName(packageName, label: '$label package.name');

  return SourceManifest(
    schemaVersion: yaml['schema'] as int,
    originKind: originKind,
    repositoryGitUrl: repositoryGitUrl,
    upstreamGitUrl: upstreamGit == null
        ? repositoryGitUrl
        : requiredString(upstreamGit, 'url'),
    package: _readManifestPackage(
      packageName,
      packageYaml,
      '$label package',
      originKind: originKind,
    ),
  );
}

/// Expands a Source Manifest into package-specific records.
List<SourcePackageManifest> sourcePackageManifestsFromManifest(
  SourceManifest manifest, {
  Set<String>? packageNames,
  Set<String> releaseStatuses = compatibleDependencyReleaseStatuses,
}) {
  final package = manifest.package;
  if (packageNames != null && !packageNames.contains(package.name)) {
    return const <SourcePackageManifest>[];
  }

  final implementations = <PackageImplementation>[];
  final compatibility = <SourceCompatibilityStatus>[];
  final packagePath = normalizeManifestPath(
    package.path,
    label: 'Source Manifest package.path',
  );
  for (final sdk in package.sdks.values) {
    for (final release in sdk.releases) {
      if (!releaseStatuses.contains(release.status)) {
        continue;
      }
      implementations.add(
        PackageImplementation(
          sdkLine: sdk.sdkLine,
          upstreamVersion: release.sourceVersion,
          repository: manifest.repositoryGitUrl,
          tag: release.tag,
          version: release.version,
          path: packagePath,
          status: release.status,
        ),
      );
      compatibility.add(
        SourceCompatibilityStatus(
          sdkLine: sdk.sdkLine,
          upstreamVersion: release.sourceVersion,
          status: release.status == 'compatible'
              ? 'implemented'
              : release.status,
        ),
      );
    }
  }

  return [
    SourcePackageManifest(
      name: package.name,
      repository: manifest.repositoryGitUrl,
      upstream: manifest.upstreamGitUrl,
      implementations: implementations,
      compatibility: compatibility,
      maintenance: package.maintenance,
      advisory: package.advisory,
    ),
  ];
}

String _sourceOriginKind(String kind, String label) {
  if (const {packageOriginCreated, packageOriginPorted}.contains(kind)) {
    return kind;
  }
  throw FluohSchemaException('$label origin.kind must be created or ported.');
}
