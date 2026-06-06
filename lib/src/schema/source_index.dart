import 'dependency_policy.dart';
import 'version_rules.dart';
import 'yaml_utils.dart';

/// Current schema version for Source root and Manifest YAML files.
const sourceManifestSchema = 1;

/// Parsed root `fluoh.yaml` for a FlutterOH Source repository.
///
/// A Source repository owns SDK releases and routes to package Manifest files.
class SourceRootManifest {
  /// Creates parsed Source root manifest data.
  const SourceRootManifest({
    required this.schemaVersion,
    required this.name,
    required this.manifests,
    required this.sdkRepository,
    required this.sdkReleases,
    this.description,
    this.repositoryGitUrl,
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

/// Public name for SDK index data used by source APIs.
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
  /// Creates parsed Source package Manifest data.
  const SourceManifest({
    required this.schemaVersion,
    required this.repositoryGitUrl,
    required this.upstreamGitUrl,
    required this.package,
  });

  /// Schema version from the Manifest file.
  final int schemaVersion;

  /// Manifest name, derived from the package name.
  String get name => package.name;

  /// FlutterOH implementation repository URL.
  final String repositoryGitUrl;

  /// Upstream repository URL.
  final String upstreamGitUrl;

  /// Package record described by this Manifest.
  final SourceManifestPackage package;
}

/// Package entry inside a Source Manifest.
class SourceManifestPackage {
  /// Creates a package entry from a Source Manifest.
  const SourceManifestPackage({
    required this.name,
    required this.sdks,
    String? path,
    this.maintenance,
    this.advisory,
  }) : path = path ?? '.';

  /// Package name.
  final String name;

  /// Package path inside both the FlutterOH implementation and upstream repositories.
  final String path;

  /// Optional maintenance status for this package.
  final SourcePackageMaintenance? maintenance;

  /// Optional advisory shown by dependency commands.
  final SourcePackageAdvisory? advisory;

  /// SDK-specific release records keyed by SDK line.
  final Map<String, SourceManifestSdk> sdks;
}

/// Manifest releases for one SDK line.
class SourceManifestSdk {
  /// Creates SDK-line release data from a Source Manifest.
  const SourceManifestSdk({required this.sdkLine, required this.releases});

  /// SDK line, such as `3.35`.
  final String sdkLine;

  /// Package implementation releases for this SDK line.
  final List<SourceManifestRelease> releases;
}

/// One package implementation release in a Source Manifest.
class SourceManifestRelease {
  /// Creates one package implementation release record.
  const SourceManifestRelease({
    required this.version,
    required this.upstreamVersion,
    required this.upstreamCommit,
    this.upstreamRef,
    this.status = 'compatible',
  });

  /// FlutterOH package version.
  final String version;

  /// Upstream package version this implementation targets.
  final String upstreamVersion;

  /// Upstream release tag or ref used for the adaptation.
  final String? upstreamRef;

  /// Resolved upstream commit used for the adaptation.
  final String upstreamCommit;

  /// Compatibility status; consumers use `compatible` releases by default and
  /// may explicitly opt into every status through project policy.
  final String status;
}

/// Maintainer-provided package maintenance state.
class SourcePackageMaintenance {
  /// Creates package maintenance status metadata.
  const SourcePackageMaintenance({this.frozen = false, this.note});

  /// Whether source sync should skip generated release updates.
  final bool frozen;

  /// Optional explanation for the maintenance state.
  final String? note;
}

/// Advisory shown when a package needs user or maintainer attention.
class SourcePackageAdvisory {
  /// Creates advisory metadata for a package.
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
  /// Creates one advisory alternative package.
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
    required this.repositoryGitUrl,
    required this.upstreamGitUrl,
    required this.package,
  });

  /// Manifest name, derived from the package name.
  String get name => package.name;

  /// FlutterOH implementation repository URL.
  final String repositoryGitUrl;

  /// Upstream repository URL.
  final String upstreamGitUrl;

  /// Package entry to generate.
  final SourceManifestPackageTemplate package;
}

/// Data used to generate one package entry in a Manifest template.
class SourceManifestPackageTemplate {
  /// Creates a package entry for a Source Manifest template.
  const SourceManifestPackageTemplate({
    required this.name,
    required this.upstreamVersion,
    required this.sdkLine,
    required this.version,
    required this.upstreamCommit,
    this.path = '.',
    this.upstreamRef,
    this.status = 'compatible',
  });

  /// Package name.
  final String name;

  /// Package path inside both the FlutterOH implementation and upstream repositories.
  final String path;

  /// Upstream version targeted by the generated implementation release.
  final String upstreamVersion;

  /// Upstream release tag or ref used for the generated release.
  final String? upstreamRef;

  /// Resolved upstream commit used for the generated release.
  final String upstreamCommit;

  /// SDK line for the generated implementation release.
  final String sdkLine;

  /// FlutterOH package version for the generated implementation release.
  final String version;

  /// Compatibility status written to the Manifest.
  final String status;
}

/// Merged package index consumed by dependency commands.
class PackageIndex {
  /// Creates a merged package index.
  const PackageIndex({required this.schemaVersion, required this.packages});

  /// Schema version used by the source data.
  final int schemaVersion;

  /// Package entries keyed by package name.
  final Map<String, PackageEntry> packages;
}

/// Package-level Source record after merging configured Sources.
class PackageEntry {
  /// Creates one merged package index entry.
  const PackageEntry({
    required this.repository,
    required this.upstream,
    required this.implementations,
    this.compatibility = const <SourceCompatibilityStatus>[],
    this.sourceNames = const <String>[],
    this.advisory,
    this.maintenance,
  });

  /// FlutterOH implementation repository URL.
  final String repository;

  /// Upstream repository URL.
  final String upstream;

  /// Compatible implementation releases for this package.
  final List<PackageImplementation> implementations;

  /// Non-compatible release records used for reporting.
  final List<SourceCompatibilityStatus> compatibility;

  /// Configured Source aliases that contributed this package entry.
  final List<String> sourceNames;

  /// Optional advisory shown by dependency commands.
  final SourcePackageAdvisory? advisory;

  /// Optional maintenance state for this package.
  final SourcePackageMaintenance? maintenance;
}

/// Concrete FlutterOH implementation release for a package.
class PackageImplementation {
  /// Creates a concrete FlutterOH package implementation record.
  const PackageImplementation({
    required this.sdkLine,
    required this.upstreamVersion,
    required this.repository,
    required this.tag,
    required this.version,
    this.path,
    this.sourceName,
    this.sourcePriority = 0,
    this.status = 'compatible',
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

  /// Source release status that produced this implementation.
  final String status;

  /// Source name that provided this implementation after merge.
  final String? sourceName;

  /// Source priority used to resolve overlapping implementation records.
  final int sourcePriority;

  /// SDK version selector used by command code.
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
      sourceName: name,
      sourcePriority: priority,
      status: status,
    );
  }
}

/// Non-compatible package status used for diagnostics.
class SourceCompatibilityStatus {
  /// Creates one non-compatible package status record.
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

  /// SDK version selector used by command code.
  String get sdkVersion => sdkLine;
}

/// Package-specific view derived from one Source Manifest.
class SourcePackageManifest {
  /// Creates a package-specific view of Source Manifest data.
  const SourcePackageManifest({
    required this.name,
    required this.repository,
    required this.upstream,
    required this.implementations,
    required this.compatibility,
    this.maintenance,
    this.advisory,
  });

  /// Package name.
  final String name;

  /// FlutterOH implementation repository URL.
  final String repository;

  /// Upstream repository URL.
  final String upstream;

  /// Compatible implementation releases.
  final List<PackageImplementation> implementations;

  /// Non-compatible release records used for reporting.
  final List<SourceCompatibilityStatus> compatibility;

  /// Optional maintenance state for this package.
  final SourcePackageMaintenance? maintenance;

  /// Optional advisory shown by dependency commands.
  final SourcePackageAdvisory? advisory;
}

/// Compatibility buckets derived from Source manifests.
class CompatibilityMatrix {
  /// Creates compatibility matrix data.
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
  /// Creates compatibility buckets for one SDK version.
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
    'upstream',
    'package',
  });
  _requireKind(yaml, 'manifest', label);

  final repository = objectMap(yaml['repository'], '$label repository');
  ensureAllowedKeys(repository, '$label repository', {'git'});
  final repositoryGit = objectMap(repository['git'], '$label repository.git');
  ensureAllowedKeys(repositoryGit, '$label repository.git', {'url'});

  final upstream = objectMap(yaml['upstream'], '$label upstream');
  ensureAllowedKeys(upstream, '$label upstream', {'git'});
  final upstreamGit = objectMap(upstream['git'], '$label upstream.git');
  ensureAllowedKeys(upstreamGit, '$label upstream.git', {'url'});

  final packageYaml = objectMap(yaml['package'], '$label package');
  final packageName = requiredString(packageYaml, 'name');
  validateDartPackageName(packageName, label: '$label package.name');

  return SourceManifest(
    schemaVersion: yaml['schema'] as int,
    repositoryGitUrl: requiredString(repositoryGit, 'url'),
    upstreamGitUrl: requiredString(upstreamGit, 'url'),
    package: _readManifestPackage(packageName, packageYaml, '$label package'),
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
          upstreamVersion: release.upstreamVersion,
          repository: manifest.repositoryGitUrl,
          tag: packageReleaseTagForPackage(
            packageName: package.name,
            upstreamVersion: release.upstreamVersion,
            sdkVersion: '${sdk.sdkLine}.0-ohos-0.0.0',
            releaseVersion: release.version,
          ),
          version: release.version,
          path: packagePath,
          status: release.status,
        ),
      );
      compatibility.add(
        SourceCompatibilityStatus(
          sdkLine: sdk.sdkLine,
          upstreamVersion: release.upstreamVersion,
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

/// Generates canonical YAML for a Source root Manifest.
String sourceRootManifestContent(SourceRootManifestTemplate template) {
  for (final manifest in template.manifests) {
    validateDartPackageName(manifest.name, label: 'manifests[].name');
  }
  final sdkReleases = _sortedSdkReleases(template.sdkReleases);
  final manifests = _sortedManifestRoutes(template.manifests);
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
        for (final release in sdkReleases)
          '    - ${_yamlScalar(release.version)}',
      ],
      '',
    ]);
  }

  if (manifests.isNotEmpty) {
    lines.add('manifests:');
    for (final manifest in manifests) {
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
      repositoryGitUrl: template.repositoryGitUrl,
      upstreamGitUrl: template.upstreamGitUrl,
      package: SourceManifestPackage(
        name: template.package.name,
        path: template.package.path,
        sdks: {
          template.package.sdkLine: SourceManifestSdk(
            sdkLine: template.package.sdkLine,
            releases: [
              SourceManifestRelease(
                version: template.package.version,
                upstreamVersion: template.package.upstreamVersion,
                upstreamRef: template.package.upstreamRef,
                upstreamCommit: template.package.upstreamCommit,
                status: template.package.status,
              ),
            ],
          ),
        },
      ),
    ),
  );
}

/// Serializes a parsed package Manifest back to canonical YAML.
String sourceManifestToContent(SourceManifest manifest) {
  final package = manifest.package;
  validateDartPackageName(package.name, label: 'Source Manifest package.name');
  final packagePath = normalizeManifestPath(
    package.path,
    label: 'Source Manifest package.path',
  );
  final lines = [
    'schema: $sourceManifestSchema',
    'kind: manifest',
    '',
    'repository:',
    '  git:',
    '    url: ${_yamlScalar(manifest.repositoryGitUrl)}',
    '',
    'upstream:',
    '  git:',
    '    url: ${_yamlScalar(manifest.upstreamGitUrl)}',
    '',
    'package:',
    '  name: ${_yamlScalar(package.name)}',
    if (packagePath != '.') '  path: ${_yamlScalar(packagePath)}',
  ];

  lines.addAll([
    if (package.maintenance != null) ...[
      '  maintenance:',
      if (package.maintenance!.frozen) '    frozen: true',
      if (package.maintenance!.note != null)
        '    note: ${_yamlScalar(package.maintenance!.note!)}',
    ],
    if (package.advisory != null) ..._advisoryLines(package.advisory!),
    '  sdks:',
  ]);
  for (final sdk in _sortedManifestSdks(package.sdks.values)) {
    lines.addAll(['    "${sdk.sdkLine}":', '      releases:']);
    for (final release in _sortedManifestReleases(sdk.releases)) {
      validateReleaseVersion(release.version, label: 'release version');
      final upstreamVersion = _manifestPubVersion(
        release.upstreamVersion,
        label: 'release upstream.version',
      );
      final upstreamRef = release.upstreamRef == null
          ? null
          : normalizeGitRef(
              release.upstreamRef!,
              label: 'release upstream.ref',
            );
      final upstreamCommit = normalizeGitCommitHash(
        release.upstreamCommit,
        label: 'release upstream.commit',
      );
      if (!const {
        'compatible',
        'experimental',
        'broken',
      }.contains(release.status)) {
        throw const FluohSchemaException(
          'release status must be compatible, experimental, or broken.',
        );
      }
      lines.addAll([
        '        - version: ${_yamlScalar(release.version)}',
        '          upstream:',
        '            version: ${_yamlScalar(upstreamVersion)}',
        if (upstreamRef != null) '            ref: ${_yamlScalar(upstreamRef)}',
        '            commit: ${_yamlScalar(upstreamCommit)}',
        if (release.status != 'compatible')
          '          status: ${release.status}',
      ]);
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
        implementations: manifest.implementations,
        compatibility: manifest.compatibility,
        sourceNames: _sourceNamesFromImplementations(manifest.implementations),
        advisory: manifest.advisory,
        maintenance: manifest.maintenance,
      );
      continue;
    }
    packages[manifest.name] = PackageEntry(
      repository: existing.repository,
      upstream: existing.upstream,
      implementations: [
        ...existing.implementations,
        ...manifest.implementations,
      ],
      compatibility: [...existing.compatibility, ...manifest.compatibility],
      sourceNames: _sortedPackageSourceNames(
        existing.sourceNames,
        _sourceNamesFromImplementations(manifest.implementations),
      ),
      advisory: existing.advisory ?? manifest.advisory,
      maintenance: existing.maintenance ?? manifest.maintenance,
    );
  }
  return PackageIndex(schemaVersion: 1, packages: packages);
}

List<String> _sourceNamesFromImplementations(
  Iterable<PackageImplementation> implementations,
) {
  return _sortedPackageSourceNames(
    implementations.map((implementation) => implementation.sourceName).nonNulls,
  );
}

List<String> _sortedPackageSourceNames(
  Iterable<String> first, [
  Iterable<String> second = const <String>[],
]) {
  return <String>{...first, ...second}.toList(growable: false)..sort();
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
  String label,
) {
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
  String label,
) {
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
    );
    final key = '${release.upstreamVersion}|${release.version}';
    if (!seenReleaseKeys.add(key)) {
      throw FluohSchemaException(
        '$label releases contains duplicate upstream ${release.upstreamVersion} '
        'and release ${release.version}.',
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
        '$label releases must be sorted by upstream version and release version '
        'in ascending order.',
      );
    }
  }
}

SourceManifestRelease _readManifestRelease(
  Map<String, Object?> yaml,
  String label,
) {
  ensureAllowedKeys(yaml, label, {'version', 'upstream', 'status'});
  final status = optionalString(yaml, 'status') ?? 'compatible';
  if (!const {'compatible', 'experimental', 'broken'}.contains(status)) {
    throw FluohSchemaException(
      '$label status must be compatible, experimental, or broken.',
    );
  }
  final version = _requiredScalarString(yaml, 'version');
  validateReleaseVersion(version, label: '$label version');
  final upstreamYaml = objectMap(yaml['upstream'], '$label upstream');
  ensureAllowedKeys(upstreamYaml, '$label upstream', {
    'version',
    'ref',
    'commit',
  });
  return SourceManifestRelease(
    version: version,
    upstreamVersion: _manifestPubVersion(
      _requiredScalarString(upstreamYaml, 'version'),
      label: '$label upstream.version',
    ),
    upstreamRef: switch (optionalString(upstreamYaml, 'ref')) {
      final ref? => normalizeGitRef(ref, label: '$label upstream.ref'),
      null => null,
    },
    upstreamCommit: normalizeGitCommitHash(
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

List<SourceManifestSdk> _sortedManifestSdks(Iterable<SourceManifestSdk> sdks) {
  return sdks.toList(growable: false)..sort(
    (left, right) => _compareSdkLinesAscending(left.sdkLine, right.sdkLine),
  );
}

List<SourceManifestRelease> _sortedManifestReleases(
  Iterable<SourceManifestRelease> releases,
) {
  return releases.toList(growable: false)
    ..sort(_compareManifestReleasesAscending);
}

int _compareManifestReleasesAscending(
  SourceManifestRelease left,
  SourceManifestRelease right,
) {
  final upstream = comparePubVersionsAscending(
    left.upstreamVersion,
    right.upstreamVersion,
  );
  if (upstream != 0) {
    return upstream;
  }
  final release = comparePubVersionsAscending(left.version, right.version);
  if (release != 0) {
    return release;
  }
  final commit = left.upstreamCommit.compareTo(right.upstreamCommit);
  if (commit != 0) {
    return commit;
  }
  return (left.upstreamRef ?? '').compareTo(right.upstreamRef ?? '');
}

List<SdkRelease> _sortedSdkReleases(Iterable<SdkRelease> releases) {
  return releases.toList(growable: false)..sort((left, right) {
    final version = comparePubVersionsAscending(left.version, right.version);
    if (version != 0) {
      return version;
    }
    return left.repository.compareTo(right.repository);
  });
}

List<SourceManifestRoute> _sortedManifestRoutes(
  Iterable<SourceManifestRoute> routes,
) {
  return routes.toList(growable: false)
    ..sort((left, right) => left.name.compareTo(right.name));
}

int _compareSdkLinesAscending(String left, String right) {
  final leftParts = left.split('.').map(int.parse).toList(growable: false);
  final rightParts = right.split('.').map(int.parse).toList(growable: false);
  for (var i = 0; i < leftParts.length && i < rightParts.length; i += 1) {
    final compared = leftParts[i].compareTo(rightParts[i]);
    if (compared != 0) {
      return compared;
    }
  }
  return leftParts.length.compareTo(rightParts.length);
}

String _manifestPubVersion(String version, {required String label}) {
  validatePubVersion(version, label: label);
  return version;
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
  if (RegExp(
    r'^[+-]?(?:\d+|\d+\.\d+|\.\d+)(?:[eE][+-]?\d+)?$',
  ).hasMatch(value)) {
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

void _validateSourceName(String value, {required String label}) {
  if (value.isEmpty || RegExp(r'\s').hasMatch(value)) {
    throw FluohSchemaException('$label must be a non-empty token.');
  }
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
