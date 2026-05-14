import 'version_rules.dart';
import 'yaml_utils.dart';

const sourceManifestSchema = 1;

class SourceRootManifest {
  const SourceRootManifest({
    required this.schemaVersion,
    required this.name,
    required this.repositoryGitUrl,
    required this.manifests,
    required this.sdkRepository,
    required this.sdkReleases,
    this.description,
    this.fluohConstraint,
  });

  final int schemaVersion;
  final String name;
  final String? description;
  final String repositoryGitUrl;
  final List<SourceManifestRoute> manifests;
  final String? sdkRepository;
  final List<SdkRelease> sdkReleases;
  final String? fluohConstraint;

  SdkIndex get sdkIndex =>
      SdkIndex(schemaVersion: schemaVersion, releases: sdkReleases);
}

class SourceRootManifestTemplate {
  const SourceRootManifestTemplate({
    required this.name,
    required this.repositoryGitUrl,
    this.description,
    this.fluohConstraint,
    this.manifests = const <SourceManifestRoute>[],
    this.sdkRepository,
    this.sdkReleases = const <SdkRelease>[],
  });

  final String name;
  final String? description;
  final String repositoryGitUrl;
  final String? fluohConstraint;
  final List<SourceManifestRoute> manifests;
  final String? sdkRepository;
  final List<SdkRelease> sdkReleases;
}

class SourceManifestRoute {
  const SourceManifestRoute({required this.name});

  final String name;
}

class SdkIndex {
  const SdkIndex({required this.schemaVersion, required this.releases});

  final int schemaVersion;
  final List<SdkRelease> releases;
}

typedef SourceSdkIndex = SdkIndex;

class SdkRelease {
  const SdkRelease({
    required this.version,
    required this.versionSeries,
    required this.flutterVersion,
    required this.channel,
    required this.repository,
    required this.tag,
    this.publishedAt,
    this.sourceName,
    this.sourcePriority = 0,
  });

  final String version;
  final String versionSeries;
  final String flutterVersion;
  final String channel;
  final String repository;
  final String tag;
  final String? publishedAt;
  final String? sourceName;
  final int sourcePriority;

  SdkRelease withSource(String name, int priority) {
    return SdkRelease(
      version: version,
      versionSeries: versionSeries,
      flutterVersion: flutterVersion,
      channel: channel,
      repository: repository,
      tag: tag,
      publishedAt: publishedAt,
      sourceName: name,
      sourcePriority: priority,
    );
  }
}

class SourceManifest {
  const SourceManifest({
    required this.schemaVersion,
    required this.name,
    required this.repositoryGitUrl,
    required this.upstreamGitUrl,
    required this.upstreamBranch,
    required this.packages,
    this.repositoryPath = '.',
    this.upstreamPath = '.',
  });

  final int schemaVersion;
  final String name;
  final String repositoryGitUrl;
  final String repositoryPath;
  final String upstreamGitUrl;
  final String upstreamBranch;
  final String upstreamPath;
  final Map<String, SourceManifestPackage> packages;
}

class SourceManifestPackage {
  const SourceManifestPackage({
    required this.name,
    required this.repositoryPath,
    required this.upstreamPath,
    required this.sdks,
    this.maintenance,
    this.advisory,
  });

  final String name;
  final String repositoryPath;
  final String upstreamPath;
  final SourcePackageMaintenance? maintenance;
  final SourcePackageAdvisory? advisory;
  final Map<String, SourceManifestSdk> sdks;
}

class SourceManifestSdk {
  const SourceManifestSdk({required this.sdkLine, required this.releases});

  final String sdkLine;
  final List<SourceManifestRelease> releases;
}

class SourceManifestRelease {
  const SourceManifestRelease({
    required this.version,
    required this.upstreamVersion,
    this.status = 'compatible',
  });

  final String version;
  final String upstreamVersion;
  final String status;
}

class SourcePackageMaintenance {
  const SourcePackageMaintenance({required this.status, this.reason});

  final String status;
  final String? reason;
}

class SourcePackageAdvisory {
  const SourcePackageAdvisory({
    this.message,
    this.alternatives = const <SourcePackageAlternative>[],
  });

  final String? message;
  final List<SourcePackageAlternative> alternatives;

  Map<String, Object?> toJson() {
    return {
      if (message != null) 'message': message,
      if (alternatives.isNotEmpty)
        'alternatives': [
          for (final alternative in alternatives) alternative.toJson(),
        ],
    };
  }
}

class SourcePackageAlternative {
  const SourcePackageAlternative({required this.name, this.reason, this.url});

  final String name;
  final String? reason;
  final String? url;

  Map<String, Object?> toJson() {
    return {
      'name': name,
      if (reason != null) 'reason': reason,
      if (url != null) 'url': url,
    };
  }
}

class SourceManifestTemplate {
  const SourceManifestTemplate({
    required this.name,
    required this.repositoryGitUrl,
    required this.upstreamGitUrl,
    required this.packages,
    this.repositoryPath = '.',
    this.upstreamBranch = 'main',
    this.upstreamPath = '.',
  });

  final String name;
  final String repositoryGitUrl;
  final String repositoryPath;
  final String upstreamGitUrl;
  final String upstreamBranch;
  final String upstreamPath;
  final List<SourceManifestPackageTemplate> packages;
}

class SourceManifestPackageTemplate {
  const SourceManifestPackageTemplate({
    required this.name,
    required this.repositoryPath,
    required this.upstreamPath,
    required this.upstreamVersion,
    required this.sdkLine,
    required this.version,
    this.status = 'compatible',
  });

  final String name;
  final String repositoryPath;
  final String upstreamPath;
  final String upstreamVersion;
  final String sdkLine;
  final String version;
  final String status;
}

class PackageIndex {
  const PackageIndex({required this.schemaVersion, required this.packages});

  final int schemaVersion;
  final Map<String, PackageEntry> packages;
}

class PackageEntry {
  const PackageEntry({
    required this.repository,
    required this.upstream,
    required this.implementations,
    this.repositoryPath,
    this.upstreamPath,
    this.upstreamBranch = 'main',
    this.compatibility = const <SourceCompatibilityStatus>[],
    this.advisory,
    this.maintenance,
  });

  final String repository;
  final String upstream;
  final String? repositoryPath;
  final String? upstreamPath;
  final String upstreamBranch;
  final List<PackageImplementation> implementations;
  final List<SourceCompatibilityStatus> compatibility;
  final SourcePackageAdvisory? advisory;
  final SourcePackageMaintenance? maintenance;
}

class PackageImplementation {
  const PackageImplementation({
    required this.sdkLine,
    required this.upstreamVersion,
    required this.repository,
    required this.tag,
    required this.version,
    this.path,
    this.upstreamPath,
    this.upstreamBranch = 'main',
    this.sourceName,
    this.sourcePriority = 0,
  });

  final String sdkLine;
  final String upstreamVersion;
  final String repository;
  final String tag;
  final String version;
  final String? path;
  final String? upstreamPath;
  final String upstreamBranch;
  final String? sourceName;
  final int sourcePriority;

  String get sdkVersion => sdkLine;

  PackageImplementation withSource(String name, int priority) {
    return PackageImplementation(
      sdkLine: sdkLine,
      upstreamVersion: upstreamVersion,
      repository: repository,
      tag: tag,
      version: version,
      path: path,
      upstreamPath: upstreamPath,
      upstreamBranch: upstreamBranch,
      sourceName: name,
      sourcePriority: priority,
    );
  }
}

class SourceCompatibilityStatus {
  const SourceCompatibilityStatus({
    required this.sdkLine,
    required this.upstreamVersion,
    required this.status,
  });

  final String sdkLine;
  final String upstreamVersion;
  final String status;

  String get sdkVersion => sdkLine;
}

class SourcePackageManifest {
  const SourcePackageManifest({
    required this.name,
    required this.repository,
    required this.upstream,
    required this.implementations,
    required this.compatibility,
    this.repositoryPath,
    this.upstreamPath,
    this.upstreamBranch = 'main',
    this.maintenance,
    this.advisory,
  });

  final String name;
  final String repository;
  final String upstream;
  final String? repositoryPath;
  final String? upstreamPath;
  final String upstreamBranch;
  final List<PackageImplementation> implementations;
  final List<SourceCompatibilityStatus> compatibility;
  final SourcePackageMaintenance? maintenance;
  final SourcePackageAdvisory? advisory;
}

class CompatibilityMatrix {
  const CompatibilityMatrix({
    required this.schemaVersion,
    required this.sdkVersions,
  });

  final int schemaVersion;
  final Map<String, CompatibilityVersion> sdkVersions;
}

class CompatibilityVersion {
  const CompatibilityVersion({
    required this.native,
    required this.implemented,
    required this.blocked,
  });

  final List<String> native;
  final List<String> implemented;
  final List<String> blocked;
}

SourceRootManifest parseSourceRootManifest(String content) {
  final yaml = parseYamlMap(content, label: 'fluoh.yaml');
  _ensureSourceSchema(yaml, 'fluoh.yaml');
  ensureAllowedKeys(yaml, 'fluoh.yaml', {
    'schema',
    'kind',
    'name',
    'description',
    'repository',
    'environment',
    'sdk',
    'manifests',
  });
  _requireKind(yaml, 'source', 'fluoh.yaml');

  final repository = objectMap(yaml['repository'], 'repository');
  ensureAllowedKeys(repository, 'repository', {'git'});
  final repositoryGit = objectMap(repository['git'], 'repository.git');
  ensureAllowedKeys(repositoryGit, 'repository.git', {'url'});

  final environment = optionalObjectMap(yaml['environment'], 'environment');
  if (environment != null) {
    ensureAllowedKeys(environment, 'environment', {'fluoh'});
  }
  final sdkSource = _readFlutterOhosSdkSource(yaml['sdk']);
  final manifests = _readManifestRoutes(yaml['manifests']);

  return SourceRootManifest(
    schemaVersion: yaml['schema'] as int,
    name: requiredString(yaml, 'name'),
    description: optionalString(yaml, 'description'),
    repositoryGitUrl: requiredString(repositoryGit, 'url'),
    manifests: manifests,
    sdkRepository: sdkSource?.repository,
    sdkReleases: sdkSource?.releases ?? const <SdkRelease>[],
    fluohConstraint: optionalString(environment ?? const {}, 'fluoh'),
  );
}

SdkIndex parseSourceSdkIndex(String content) {
  return parseSourceRootManifest(content).sdkIndex;
}

SourceManifest parseSourceManifest({
  required String content,
  required String label,
}) {
  final yaml = parseYamlMap(content, label: label);
  _ensureSourceSchema(yaml, label);
  ensureAllowedKeys(yaml, label, {
    'schema',
    'kind',
    'name',
    'repository',
    'upstream',
    'packages',
  });
  _requireKind(yaml, 'manifest', label);

  final repository = objectMap(yaml['repository'], '$label repository');
  ensureAllowedKeys(repository, '$label repository', {'git'});
  final repositoryGit = objectMap(repository['git'], '$label repository.git');
  ensureAllowedKeys(repositoryGit, '$label repository.git', {'url', 'path'});

  final upstream = objectMap(yaml['upstream'], '$label upstream');
  ensureAllowedKeys(upstream, '$label upstream', {'git'});
  final upstreamGit = objectMap(upstream['git'], '$label upstream.git');
  ensureAllowedKeys(upstreamGit, '$label upstream.git', {
    'url',
    'branch',
    'path',
  });

  final packagesMap = objectMap(yaml['packages'], '$label packages');
  if (packagesMap.isEmpty) {
    throw FluohSchemaException('$label packages must not be empty.');
  }

  return SourceManifest(
    schemaVersion: yaml['schema'] as int,
    name: requiredString(yaml, 'name'),
    repositoryGitUrl: requiredString(repositoryGit, 'url'),
    repositoryPath: _manifestPath(optionalString(repositoryGit, 'path')),
    upstreamGitUrl: requiredString(upstreamGit, 'url'),
    upstreamBranch: optionalString(upstreamGit, 'branch') ?? 'main',
    upstreamPath: _manifestPath(optionalString(upstreamGit, 'path')),
    packages: packagesMap.map((name, value) {
      final packageName = _nonEmptyString(name, '$label package name');
      return MapEntry(
        packageName,
        _readManifestPackage(
          packageName,
          objectMap(value, '$label packages.$packageName'),
          '$label packages.$packageName',
          defaultRepositoryPath: _manifestPath(
            optionalString(repositoryGit, 'path'),
          ),
          defaultUpstreamPath: _manifestPath(
            optionalString(upstreamGit, 'path'),
          ),
        ),
      );
    }),
  );
}

List<SourcePackageManifest> sourcePackageManifestsFromManifest(
  SourceManifest manifest, {
  Set<String>? packageNames,
}) {
  final manifests = <SourcePackageManifest>[];
  for (final package in manifest.packages.values) {
    if (packageNames != null && !packageNames.contains(package.name)) {
      continue;
    }

    final implementations = <PackageImplementation>[];
    final compatibility = <SourceCompatibilityStatus>[];
    for (final sdk in package.sdks.values) {
      for (final release in sdk.releases) {
        if (release.status != 'compatible') {
          continue;
        }
        implementations.add(
          PackageImplementation(
            sdkLine: sdk.sdkLine,
            upstreamVersion: release.upstreamVersion,
            repository: manifest.repositoryGitUrl,
            tag: pubReleaseTagForPackage(
              packageName: package.name,
              upstreamVersion: release.upstreamVersion,
              sdkVersion: '${sdk.sdkLine}.0-ohos-0.0.0',
              releaseVersion: release.version,
            ),
            version: release.version,
            path: _manifestPath(package.repositoryPath),
            upstreamPath: _manifestPath(package.upstreamPath),
            upstreamBranch: manifest.upstreamBranch,
          ),
        );
        compatibility.add(
          SourceCompatibilityStatus(
            sdkLine: sdk.sdkLine,
            upstreamVersion: release.upstreamVersion,
            status: 'implemented',
          ),
        );
      }
    }

    manifests.add(
      SourcePackageManifest(
        name: package.name,
        repository: manifest.repositoryGitUrl,
        upstream: manifest.upstreamGitUrl,
        repositoryPath: package.repositoryPath,
        upstreamPath: package.upstreamPath,
        upstreamBranch: manifest.upstreamBranch,
        implementations: implementations,
        compatibility: compatibility,
        maintenance: package.maintenance,
        advisory: package.advisory,
      ),
    );
  }
  return manifests;
}

String sourceRootManifestContent(SourceRootManifestTemplate template) {
  final lines = [
    'schema: $sourceManifestSchema',
    'kind: source',
    'name: ${_yamlScalar(template.name)}',
    if (template.description != null)
      'description: ${_yamlScalar(template.description!)}',
    '',
    'repository:',
    '  git:',
    '    url: ${_yamlScalar(template.repositoryGitUrl)}',
    '',
    if (template.fluohConstraint != null) ...[
      'environment:',
      '  fluoh: ${_yamlScalar(template.fluohConstraint!)}',
      '',
    ],
  ];

  if (template.sdkRepository != null) {
    lines.addAll([
      'sdk:',
      '  git:',
      '    url: ${_yamlScalar(template.sdkRepository!)}',
      if (template.sdkReleases.isEmpty)
        '  versions: []'
      else ...[
        '  versions:',
        for (final release in template.sdkReleases)
          '    - ${_yamlScalar(release.version)}',
      ],
      '',
    ]);
  }

  if (template.manifests.isNotEmpty) {
    lines.add('manifests:');
    for (final manifest in template.manifests) {
      lines.add('  - name: ${_yamlScalar(manifest.name)}');
    }
    lines.add('');
  } else if (template.sdkRepository == null) {
    lines.addAll(['manifests: []', '']);
  }

  return lines.join('\n');
}

String sourceManifestContent(SourceManifestTemplate template) {
  return sourceManifestToContent(
    SourceManifest(
      schemaVersion: sourceManifestSchema,
      name: template.name,
      repositoryGitUrl: template.repositoryGitUrl,
      repositoryPath: template.repositoryPath,
      upstreamGitUrl: template.upstreamGitUrl,
      upstreamBranch: template.upstreamBranch,
      upstreamPath: template.upstreamPath,
      packages: {
        for (final package in template.packages)
          package.name: SourceManifestPackage(
            name: package.name,
            repositoryPath: package.repositoryPath,
            upstreamPath: package.upstreamPath,
            sdks: {
              package.sdkLine: SourceManifestSdk(
                sdkLine: package.sdkLine,
                releases: [
                  SourceManifestRelease(
                    version: package.version,
                    upstreamVersion: package.upstreamVersion,
                    status: package.status,
                  ),
                ],
              ),
            },
          ),
      },
    ),
  );
}

String sourceManifestToContent(SourceManifest manifest) {
  final lines = [
    'schema: $sourceManifestSchema',
    'kind: manifest',
    'name: ${_yamlScalar(manifest.name)}',
    '',
    'repository:',
    '  git:',
    '    url: ${_yamlScalar(manifest.repositoryGitUrl)}',
    if (manifest.repositoryPath != '.')
      '    path: ${_yamlScalar(manifest.repositoryPath)}',
    '',
    'upstream:',
    '  git:',
    '    url: ${_yamlScalar(manifest.upstreamGitUrl)}',
    if (manifest.upstreamBranch != 'main')
      '    branch: ${_yamlScalar(manifest.upstreamBranch)}',
    if (manifest.upstreamPath != '.')
      '    path: ${_yamlScalar(manifest.upstreamPath)}',
    '',
    'packages:',
  ];

  for (final package in manifest.packages.values) {
    lines.addAll([
      '  ${package.name}:',
      if (package.repositoryPath != manifest.repositoryPath) ...[
        '    repository:',
        '      path: ${_yamlScalar(package.repositoryPath)}',
      ],
      if (package.upstreamPath != manifest.upstreamPath) ...[
        '    upstream:',
        '      path: ${_yamlScalar(package.upstreamPath)}',
      ],
      if (package.maintenance != null) ...[
        '    maintenance:',
        '      status: ${package.maintenance!.status}',
        if (package.maintenance!.reason != null)
          '      reason: ${_yamlScalar(package.maintenance!.reason!)}',
      ],
      if (package.advisory != null) ..._advisoryLines(package.advisory!),
      '    sdks:',
    ]);
    for (final sdk in package.sdks.values) {
      lines.addAll(['      "${sdk.sdkLine}":', '        releases:']);
      for (final release in sdk.releases) {
        validateReleaseVersion(release.version, label: 'release version');
        lines.addAll([
          '          - version: ${_yamlScalar(release.version)}',
          '            upstreamVersion: ${_yamlScalar(release.upstreamVersion)}',
          if (release.status != 'compatible')
            '            status: ${release.status}',
        ]);
      }
    }
  }
  lines.add('');
  return lines.join('\n');
}

PackageIndex packageIndexFromManifests(Iterable<SourcePackageManifest> items) {
  final packages = <String, PackageEntry>{};
  for (final manifest in items) {
    final existing = packages[manifest.name];
    if (existing == null) {
      packages[manifest.name] = PackageEntry(
        repository: manifest.repository,
        upstream: manifest.upstream,
        repositoryPath: manifest.repositoryPath,
        upstreamPath: manifest.upstreamPath,
        upstreamBranch: manifest.upstreamBranch,
        implementations: manifest.implementations,
        compatibility: manifest.compatibility,
        advisory: manifest.advisory,
        maintenance: manifest.maintenance,
      );
      continue;
    }
    packages[manifest.name] = PackageEntry(
      repository: existing.repository,
      upstream: existing.upstream,
      repositoryPath: existing.repositoryPath,
      upstreamPath: existing.upstreamPath,
      upstreamBranch: existing.upstreamBranch,
      implementations: [
        ...existing.implementations,
        ...manifest.implementations,
      ],
      compatibility: [...existing.compatibility, ...manifest.compatibility],
      advisory: existing.advisory ?? manifest.advisory,
      maintenance: existing.maintenance ?? manifest.maintenance,
    );
  }
  return PackageIndex(schemaVersion: 1, packages: packages);
}

CompatibilityMatrix compatibilityMatrixFromManifests(
  Iterable<SourcePackageManifest> items,
) {
  final versions = <String, List<String>>{};
  for (final manifest in items) {
    for (final status in manifest.compatibility) {
      if (status.status != 'implemented') {
        continue;
      }
      versions.putIfAbsent(status.sdkLine, () => []).add(manifest.name);
    }
  }

  return CompatibilityMatrix(
    schemaVersion: 1,
    sdkVersions: versions.map(
      (sdkLine, packages) => MapEntry(
        sdkLine,
        CompatibilityVersion(
          native: const <String>[],
          implemented: _sortedPackageNames(packages),
          blocked: const <String>[],
        ),
      ),
    ),
  );
}

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
    if (!names.add(name)) {
      throw FluohSchemaException('Duplicate manifest name "$name".');
    }
    routes.add(SourceManifestRoute(name: name));
  }
  return routes;
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

SourceManifestPackage _readManifestPackage(
  String packageName,
  Map<String, Object?> yaml,
  String label, {
  required String defaultRepositoryPath,
  required String defaultUpstreamPath,
}) {
  ensureAllowedKeys(yaml, label, {
    'repository',
    'upstream',
    'maintenance',
    'advisory',
    'sdks',
  });
  final repository = optionalObjectMap(yaml['repository'], '$label repository');
  final upstream = optionalObjectMap(yaml['upstream'], '$label upstream');
  if (repository != null) {
    ensureAllowedKeys(repository, '$label repository', {'path'});
  }
  if (upstream != null) {
    ensureAllowedKeys(upstream, '$label upstream', {'path'});
  }
  final sdks = objectMap(yaml['sdks'], '$label sdks');
  if (sdks.isEmpty) {
    throw FluohSchemaException('$label sdks must not be empty.');
  }
  return SourceManifestPackage(
    name: packageName,
    repositoryPath: _manifestPath(
      optionalString(repository ?? const {}, 'path') ?? defaultRepositoryPath,
    ),
    upstreamPath: _manifestPath(
      optionalString(upstream ?? const {}, 'path') ?? defaultUpstreamPath,
    ),
    maintenance: _readMaintenance(yaml['maintenance'], '$label maintenance'),
    advisory: _readAdvisory(yaml['advisory'], '$label advisory'),
    sdks: sdks.map((sdkLine, value) {
      final parsedSdkLine = _sdkLine(sdkLine, '$label SDK line');
      return MapEntry(
        parsedSdkLine,
        _readManifestSdk(
          parsedSdkLine,
          objectMap(value, '$label sdks.$parsedSdkLine'),
          '$label sdks.$parsedSdkLine',
        ),
      );
    }),
  );
}

SourceManifestSdk _readManifestSdk(
  String sdkLine,
  Map<String, Object?> yaml,
  String label,
) {
  ensureAllowedKeys(yaml, label, {'releases'});
  final releases = _objectList(yaml['releases'], '$label releases');
  if (releases.isEmpty) {
    throw FluohSchemaException('$label releases must not be empty.');
  }
  return SourceManifestSdk(
    sdkLine: sdkLine,
    releases: [
      for (var index = 0; index < releases.length; index += 1)
        _readManifestRelease(releases[index], '$label releases[$index]'),
    ],
  );
}

SourceManifestRelease _readManifestRelease(
  Map<String, Object?> yaml,
  String label,
) {
  ensureAllowedKeys(yaml, label, {'version', 'upstreamVersion', 'status'});
  final status = optionalString(yaml, 'status') ?? 'compatible';
  if (!const {'compatible', 'experimental', 'broken'}.contains(status)) {
    throw FluohSchemaException(
      '$label status must be compatible, experimental, or broken.',
    );
  }
  final version = _requiredScalarString(yaml, 'version');
  validateReleaseVersion(version, label: '$label version');
  return SourceManifestRelease(
    version: version,
    upstreamVersion: requiredString(yaml, 'upstreamVersion'),
    status: status,
  );
}

SourcePackageMaintenance? _readMaintenance(Object? value, String label) {
  if (value == null) {
    return null;
  }
  final yaml = objectMap(value, label);
  ensureAllowedKeys(yaml, label, {'status', 'reason'});
  final status = requiredString(yaml, 'status');
  if (!const {'active', 'frozen'}.contains(status)) {
    throw FluohSchemaException('$label status must be active or frozen.');
  }
  return SourcePackageMaintenance(
    status: status,
    reason: optionalString(yaml, 'reason'),
  );
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
  return SourcePackageAlternative(
    name: requiredString(yaml, 'name'),
    reason: optionalString(yaml, 'reason'),
    url: optionalString(yaml, 'url'),
  );
}

List<String> _advisoryLines(SourcePackageAdvisory advisory) {
  final lines = <String>['    advisory:'];
  if (advisory.message != null) {
    lines.add('      message: ${_yamlScalar(advisory.message!)}');
  }
  if (advisory.alternatives.isNotEmpty) {
    lines.add('      alternatives:');
    for (final alternative in advisory.alternatives) {
      lines.add('        - name: ${_yamlScalar(alternative.name)}');
      if (alternative.reason != null) {
        lines.add('          reason: ${_yamlScalar(alternative.reason!)}');
      }
      if (alternative.url != null) {
        lines.add('          url: ${_yamlScalar(alternative.url!)}');
      }
    }
  }
  return lines;
}

String _yamlScalar(String value) {
  if (!_shouldQuoteYamlScalar(value)) {
    return value;
  }
  final escaped = value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');
  return '"$escaped"';
}

bool _shouldQuoteYamlScalar(String value) {
  if (value.isEmpty) {
    return true;
  }
  if (value.startsWith(RegExp(r'''[-?:,[\]{}#&*!|>@`"']'''))) {
    return true;
  }
  if (value.contains(RegExp(r'[\s:]'))) {
    return true;
  }
  if (const {'true', 'false', 'null', '~'}.contains(value.toLowerCase())) {
    return true;
  }
  return false;
}

List<String> _stringList(
  Object? value,
  String label, {
  bool allowNull = false,
}) {
  if (value == null && allowNull) {
    return const <String>[];
  }
  if (value is! List) {
    throw FluohSchemaException('$label must be a YAML list.');
  }
  return value
      .map((item) => _nonEmptyString(item, '$label[]'))
      .toList(growable: false);
}

List<Map<String, Object?>> _objectList(
  Object? value,
  String label, {
  bool allowNull = false,
}) {
  if (value == null && allowNull) {
    return const <Map<String, Object?>>[];
  }
  if (value is! List) {
    throw FluohSchemaException('$label must be a YAML list.');
  }
  return [
    for (var index = 0; index < value.length; index += 1)
      objectMap(value[index], '$label[$index]'),
  ];
}

String _nonEmptyString(Object? value, String label) {
  if (value == null || '$value'.isEmpty) {
    throw FluohSchemaException('$label must be a non-empty string.');
  }
  return '$value';
}

String _requiredScalarString(Map<String, Object?> yaml, String key) {
  final value = yaml[key];
  if (value == null || '$value'.isEmpty) {
    throw FluohSchemaException('Expected "$key" to be a non-empty value.');
  }
  return '$value';
}

String _sdkLine(Object? value, String label) {
  final text = _nonEmptyString(value, label);
  if (!RegExp(r'^\d+\.\d+$').hasMatch(text)) {
    throw FluohSchemaException('$label must use <major>.<minor>, got $text.');
  }
  return text;
}

String _manifestPath(String? path) {
  if (path == null || path.isEmpty || path == '.') {
    return '.';
  }
  return path;
}

void _ensureSourceSchema(Map<String, Object?> yaml, String label) {
  final schema = yaml['schema'];
  if (schema == null) {
    throw FluohSchemaException('$label missing "schema".');
  }
  if (schema is! int) {
    throw FluohSchemaException('$label schema must be an integer.');
  }
  if (schema != sourceManifestSchema) {
    throw FluohSchemaException(
      '$label schema $schema is not supported. Expected schema '
      '$sourceManifestSchema.',
    );
  }
}

void _requireKind(Map<String, Object?> yaml, String expected, String label) {
  final kind = yaml['kind'];
  if (kind != expected) {
    throw FluohSchemaException('$label kind must be "$expected".');
  }
}

class _FlutterOhosSdkSource {
  const _FlutterOhosSdkSource({
    required this.repository,
    required this.releases,
  });

  final String repository;
  final List<SdkRelease> releases;
}
