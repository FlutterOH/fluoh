import 'version_rules.dart';
import 'yaml_utils.dart';

/// Current schema version for Source root and Manifest YAML files.
const sourceManifestSchema = 1;

/// Parsed root `fluoh.yaml` for a FlutterOH Source repository.
///
/// A Source repository owns SDK releases and routes to package Manifest files.
class SourceRootManifest {
  const SourceRootManifest({
    required this.schemaVersion,
    required this.name,
    required this.manifests,
    required this.sdkRepository,
    required this.sdkReleases,
    this.description,
    this.repositoryGitUrl,
    this.fluohConstraint,
  });

  /// Schema version from the root `fluoh.yaml`.
  final int schemaVersion;

  /// Source name, such as `flutteroh`.
  final String name;

  /// Optional human-readable Source description.
  final String? description;

  /// Git URL for the Source repository itself.
  final String? repositoryGitUrl;

  /// Manifest routes registered by this Source.
  final List<SourceManifestRoute> manifests;

  /// Git repository that contains FlutterOH SDK releases.
  final String? sdkRepository;

  /// SDK releases advertised by this Source.
  final List<SdkRelease> sdkReleases;

  /// Optional version constraint for compatible `fluoh` clients.
  final String? fluohConstraint;

  /// SDK-only view of this Source.
  SdkIndex get sdkIndex =>
      SdkIndex(schemaVersion: schemaVersion, releases: sdkReleases);
}

/// Data used to generate a Source root `fluoh.yaml` template.
class SourceRootManifestTemplate {
  /// Creates data for a Source root manifest template.
  const SourceRootManifestTemplate({
    required this.name,
    this.description,
    this.repositoryGitUrl,
    this.fluohConstraint,
    this.manifests = const <SourceManifestRoute>[],
    this.sdkRepository,
    this.sdkReleases = const <SdkRelease>[],
  });

  /// Source name written to the generated root manifest.
  final String name;

  /// Optional human-readable Source description.
  final String? description;

  /// Optional Git URL for the Source repository itself.
  final String? repositoryGitUrl;

  /// Optional compatible fluoh version constraint.
  final String? fluohConstraint;

  /// Package Manifest routes written under `manifests`.
  final List<SourceManifestRoute> manifests;

  /// Optional SDK repository URL written under `sdk.git.url`.
  final String? sdkRepository;

  /// SDK releases listed in the generated root manifest.
  final List<SdkRelease> sdkReleases;
}

/// Route from a Source root to one package Manifest file.
class SourceManifestRoute {
  /// Creates a route to `manifests/<name>/fluoh.yaml`.
  const SourceManifestRoute({required this.name});

  /// Manifest route name.
  final String name;
}

/// Parsed SDK release index.
class SdkIndex {
  /// Creates an SDK release index.
  const SdkIndex({required this.schemaVersion, required this.releases});

  /// Schema version used by the source data.
  final int schemaVersion;

  /// SDK releases sorted and merged from configured Sources.
  final List<SdkRelease> releases;
}

/// Backwards-compatible alias for SDK index data.
typedef SourceSdkIndex = SdkIndex;

/// FlutterOH SDK release advertised by Source data.
class SdkRelease {
  /// Creates an SDK release record.
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

  /// FlutterOH SDK package version.
  final String version;

  /// Version line, such as `3.35`.
  final String versionSeries;

  /// Upstream Flutter version this SDK line is based on.
  final String flutterVersion;

  /// Release channel, such as `stable`.
  final String channel;

  /// Git repository containing the SDK source.
  final String repository;

  /// Git tag used to install this SDK.
  final String tag;

  /// Optional publish timestamp from Source metadata.
  final String? publishedAt;

  /// Source name that provided this release after merge.
  final String? sourceName;

  /// Source priority used to resolve overlapping releases.
  final int sourcePriority;

  /// Returns a copy annotated with Source merge metadata.
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

/// Parsed package Manifest file from `manifests/<name>/fluoh.yaml`.
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

  /// Schema version from the Manifest file.
  final int schemaVersion;

  /// Manifest name.
  final String name;

  /// FlutterOH implementation repository URL.
  final String repositoryGitUrl;

  /// Package root inside the FlutterOH implementation repository.
  final String repositoryPath;

  /// Upstream repository URL.
  final String upstreamGitUrl;

  /// Upstream branch used by package sync.
  final String upstreamBranch;

  /// Package root inside the upstream repository.
  final String upstreamPath;

  /// Package records keyed by package name.
  final Map<String, SourceManifestPackage> packages;
}

/// Package entry inside a Source Manifest.
class SourceManifestPackage {
  const SourceManifestPackage({
    required this.name,
    required this.repositoryPath,
    required this.upstreamPath,
    required this.sdks,
    this.maintenance,
    this.advisory,
  });

  /// Package name.
  final String name;

  /// Package path inside the FlutterOH implementation repository.
  final String repositoryPath;

  /// Package path inside the upstream repository.
  final String upstreamPath;

  /// Optional maintenance status for this package.
  final SourcePackageMaintenance? maintenance;

  /// Optional advisory shown by dependency commands.
  final SourcePackageAdvisory? advisory;

  /// SDK-specific release records keyed by SDK line.
  final Map<String, SourceManifestSdk> sdks;
}

/// Manifest releases for one SDK line.
class SourceManifestSdk {
  const SourceManifestSdk({required this.sdkLine, required this.releases});

  /// SDK line, such as `3.35`.
  final String sdkLine;

  /// Package implementation releases for this SDK line.
  final List<SourceManifestRelease> releases;
}

/// One package implementation release in a Source Manifest.
class SourceManifestRelease {
  const SourceManifestRelease({
    required this.version,
    required this.upstreamVersion,
    this.tag,
    this.status = 'compatible',
  });

  /// FlutterOH package version.
  final String version;

  /// Upstream package version this implementation targets.
  final String upstreamVersion;

  /// Optional implementation repository tag.
  final String? tag;

  /// Compatibility status; only `compatible` releases are used by consumers.
  final String status;
}

/// Maintainer-provided package maintenance state.
class SourcePackageMaintenance {
  const SourcePackageMaintenance({required this.status, this.reason});

  /// Maintenance status, for example `maintained` or `deprecated`.
  final String status;

  /// Optional explanation for the status.
  final String? reason;
}

/// Advisory shown when a package needs user or maintainer attention.
class SourcePackageAdvisory {
  const SourcePackageAdvisory({
    this.message,
    this.alternatives = const <SourcePackageAlternative>[],
  });

  /// Human-readable advisory message.
  final String? message;

  /// Suggested alternative packages.
  final List<SourcePackageAlternative> alternatives;

  /// Converts this advisory to JSON for command output.
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

/// Alternative package suggested by a Source advisory.
class SourcePackageAlternative {
  const SourcePackageAlternative({required this.name, this.reason, this.url});

  /// Alternative package name.
  final String name;

  /// Optional reason why this package is suggested.
  final String? reason;

  /// Optional URL for the alternative.
  final String? url;

  /// Converts this alternative to JSON for command output.
  Map<String, Object?> toJson() {
    return {
      'name': name,
      if (reason != null) 'reason': reason,
      if (url != null) 'url': url,
    };
  }
}

/// Data used to generate a package Manifest template.
class SourceManifestTemplate {
  /// Creates data for a Source package Manifest template.
  const SourceManifestTemplate({
    required this.name,
    required this.repositoryGitUrl,
    required this.upstreamGitUrl,
    required this.packages,
    this.repositoryPath = '.',
    this.upstreamBranch = 'main',
    this.upstreamPath = '.',
  });

  /// Manifest name.
  final String name;

  /// FlutterOH implementation repository URL.
  final String repositoryGitUrl;

  /// Default package path inside the implementation repository.
  final String repositoryPath;

  /// Upstream repository URL.
  final String upstreamGitUrl;

  /// Upstream branch used by package sync.
  final String upstreamBranch;

  /// Default package path inside the upstream repository.
  final String upstreamPath;

  /// Package entries to generate.
  final List<SourceManifestPackageTemplate> packages;
}

/// Data used to generate one package entry in a Manifest template.
class SourceManifestPackageTemplate {
  /// Creates a package entry for a Source Manifest template.
  const SourceManifestPackageTemplate({
    required this.name,
    required this.repositoryPath,
    required this.upstreamPath,
    required this.upstreamVersion,
    required this.sdkLine,
    required this.version,
    this.tag,
    this.status = 'compatible',
  });

  /// Package name.
  final String name;

  /// Package path inside the FlutterOH implementation repository.
  final String repositoryPath;

  /// Package path inside the upstream repository.
  final String upstreamPath;

  /// Upstream version targeted by the generated implementation release.
  final String upstreamVersion;

  /// SDK line for the generated implementation release.
  final String sdkLine;

  /// FlutterOH package version for the generated implementation release.
  final String version;

  /// Optional implementation repository tag.
  final String? tag;

  /// Compatibility status written to the Manifest.
  final String status;
}

/// Merged package index consumed by dependency commands.
class PackageIndex {
  const PackageIndex({required this.schemaVersion, required this.packages});

  /// Schema version used by the source data.
  final int schemaVersion;

  /// Package entries keyed by package name.
  final Map<String, PackageEntry> packages;
}

/// Package-level Source record after merging configured Sources.
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

  /// FlutterOH implementation repository URL.
  final String repository;

  /// Upstream repository URL.
  final String upstream;

  /// Package path inside the implementation repository.
  final String? repositoryPath;

  /// Package path inside the upstream repository.
  final String? upstreamPath;

  /// Upstream branch used by package sync.
  final String upstreamBranch;

  /// Compatible implementation releases for this package.
  final List<PackageImplementation> implementations;

  /// Non-compatible compatibility records retained for reporting.
  final List<SourceCompatibilityStatus> compatibility;

  /// Optional advisory shown by dependency commands.
  final SourcePackageAdvisory? advisory;

  /// Optional maintenance state for this package.
  final SourcePackageMaintenance? maintenance;
}

/// Concrete FlutterOH implementation release for a package.
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

  /// SDK line this implementation supports.
  final String sdkLine;

  /// Upstream package version this implementation targets.
  final String upstreamVersion;

  /// Implementation repository URL.
  final String repository;

  /// Implementation repository tag.
  final String tag;

  /// FlutterOH package version.
  final String version;

  /// Package path inside the implementation repository.
  final String? path;

  /// Package path inside the upstream repository.
  final String? upstreamPath;

  /// Upstream branch used by package sync.
  final String upstreamBranch;

  /// Source name that provided this implementation after merge.
  final String? sourceName;

  /// Source priority used to resolve overlapping implementation records.
  final int sourcePriority;

  /// Alias kept for command code that treats SDK line as a version selector.
  String get sdkVersion => sdkLine;

  /// Returns a copy annotated with Source merge metadata.
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

/// Non-compatible package status retained for diagnostics.
class SourceCompatibilityStatus {
  const SourceCompatibilityStatus({
    required this.sdkLine,
    required this.upstreamVersion,
    required this.status,
  });

  /// SDK line this status applies to.
  final String sdkLine;

  /// Upstream package version this status applies to.
  final String upstreamVersion;

  /// Status such as `experimental` or `broken`.
  final String status;

  /// Alias kept for command code that treats SDK line as a version selector.
  String get sdkVersion => sdkLine;
}

/// Package-specific view derived from one Source Manifest.
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

  /// Package name.
  final String name;

  /// FlutterOH implementation repository URL.
  final String repository;

  /// Upstream repository URL.
  final String upstream;

  /// Package path inside the implementation repository.
  final String? repositoryPath;

  /// Package path inside the upstream repository.
  final String? upstreamPath;

  /// Upstream branch used by package sync.
  final String upstreamBranch;

  /// Compatible implementation releases.
  final List<PackageImplementation> implementations;

  /// Non-compatible compatibility records retained for reporting.
  final List<SourceCompatibilityStatus> compatibility;

  /// Optional maintenance state for this package.
  final SourcePackageMaintenance? maintenance;

  /// Optional advisory shown by dependency commands.
  final SourcePackageAdvisory? advisory;
}

/// Legacy compatibility matrix shape retained for schema parsing tests.
class CompatibilityMatrix {
  const CompatibilityMatrix({
    required this.schemaVersion,
    required this.sdkVersions,
  });

  /// Schema version for the matrix data.
  final int schemaVersion;

  /// Compatibility data keyed by SDK version.
  final Map<String, CompatibilityVersion> sdkVersions;
}

/// Package compatibility buckets for one SDK version.
class CompatibilityVersion {
  const CompatibilityVersion({
    required this.native,
    required this.implemented,
    required this.blocked,
  });

  /// Packages with native upstream support.
  final List<String> native;

  /// Packages with FlutterOH implementations.
  final List<String> implemented;

  /// Packages that are known blockers.
  final List<String> blocked;
}

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
    'environment',
    'sdk',
    'manifests',
  });
  _requireKind(yaml, 'source', 'fluoh.yaml');

  final repository = optionalObjectMap(yaml['repository'], 'repository');
  String? repositoryGitUrl;
  if (repository != null) {
    ensureAllowedKeys(repository, 'repository', {'git'});
    final repositoryGit = objectMap(repository['git'], 'repository.git');
    ensureAllowedKeys(repositoryGit, 'repository.git', {'url'});
    repositoryGitUrl = requiredString(repositoryGit, 'url');
  }

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
    repositoryGitUrl: repositoryGitUrl,
    manifests: manifests,
    sdkRepository: sdkSource?.repository,
    sdkReleases: sdkSource?.releases ?? const <SdkRelease>[],
    fluohConstraint: optionalString(environment ?? const {}, 'fluoh'),
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

/// Expands a Source Manifest into package-specific records.
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
            tag:
                release.tag ??
                packageReleaseTagForPackage(
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

/// Generates canonical YAML for a Source root Manifest.
String sourceRootManifestContent(SourceRootManifestTemplate template) {
  final lines = [
    'schema: $sourceManifestSchema',
    'kind: source',
    'name: ${_yamlScalar(template.name)}',
    if (template.description != null)
      'description: ${_yamlScalar(template.description!)}',
    '',
    if (template.repositoryGitUrl != null) ...[
      'repository:',
      '  git:',
      '    url: ${_yamlScalar(template.repositoryGitUrl!)}',
      '',
    ],
    if (template.fluohConstraint != null) ...[
      'environment:',
      '  fluoh: ${_singleQuotedYamlScalar(template.fluohConstraint!)}',
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

/// Generates canonical YAML for a package Manifest template.
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
                    tag: package.tag,
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

/// Serializes a parsed package Manifest back to canonical YAML.
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
        final canonicalTag = packageReleaseTagForPackage(
          packageName: package.name,
          upstreamVersion: release.upstreamVersion,
          sdkVersion: '${sdk.sdkLine}.0-ohos-0.0.0',
          releaseVersion: release.version,
        );
        lines.addAll([
          '          - version: ${_yamlScalar(release.version)}',
          '            upstreamVersion: ${_yamlScalar(release.upstreamVersion)}',
          if (release.tag != null && release.tag != canonicalTag)
            '            tag: ${_yamlScalar(release.tag!)}',
          if (release.status != 'compatible')
            '            status: ${release.status}',
        ]);
      }
    }
  }
  lines.add('');
  return lines.join('\n');
}

/// Builds the merged package index consumed by dependency commands.
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

/// Builds a compatibility matrix from package Manifest records.
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
  ensureAllowedKeys(yaml, label, {
    'version',
    'upstreamVersion',
    'tag',
    'status',
  });
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
    tag: optionalString(yaml, 'tag'),
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

String _singleQuotedYamlScalar(String value) {
  return "'${value.replaceAll("'", "''")}'";
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
  if (schema > sourceManifestSchema) {
    throw FluohSchemaException('$label schema $schema requires a newer fluoh.');
  }
  if (schema < sourceManifestSchema) {
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
