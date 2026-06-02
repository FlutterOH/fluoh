import 'pubspec.dart';
import 'version_rules.dart';
import 'yaml_utils.dart';

/// Current `fluoh.yaml` schema version for package repositories.
const packageManifestSchema = 1;

/// Initial FlutterOH adaptation release version for newly added packages.
const initialPackageReleaseVersion = '0.1.0';

/// Default upstream branch used when `fluoh.yaml` omits `upstream.git.branch`.
const defaultUpstreamBranch = 'main';

/// Parsed `fluoh.yaml` manifest for a FlutterOH package repository.
///
/// The manifest tracks the source SDK, the FlutterOH implementation repository,
/// the upstream package repository, and one or more package release entries.
class PackageManifest {
  /// Creates an immutable package repository manifest.
  const PackageManifest({
    required this.name,
    required this.sdkVersion,
    required this.repositoryUrl,
    required this.repositoryBranch,
    required this.upstreamUrl,
    required this.packages,
    this.repositoryPath = '.',
    this.upstreamBranch = defaultUpstreamBranch,
    this.upstreamPath = '.',
  });

  /// Parses and validates `fluoh.yaml` content.
  factory PackageManifest.parse(String content) {
    final yaml = parseYamlMap(content, label: 'fluoh.yaml');
    _ensurePackageManifestSchema(yaml);

    ensureAllowedKeys(yaml, 'fluoh.yaml', {
      'schema',
      'name',
      'sdk',
      'repository',
      'upstream',
      'packages',
    });
    final sdk = objectMap(yaml['sdk'], 'fluoh.yaml sdk');
    final repository = objectMap(yaml['repository'], 'fluoh.yaml repository');
    final repositoryGit = objectMap(
      repository['git'],
      'fluoh.yaml repository.git',
    );
    final upstream = objectMap(yaml['upstream'], 'fluoh.yaml upstream');
    final upstreamGit = objectMap(upstream['git'], 'fluoh.yaml upstream.git');
    final packagesMap = objectMap(yaml['packages'], 'fluoh.yaml packages');

    ensureAllowedKeys(sdk, 'fluoh.yaml sdk', {'version'});
    ensureAllowedKeys(repository, 'fluoh.yaml repository', {'git'});
    ensureAllowedKeys(repositoryGit, 'fluoh.yaml repository.git', {
      'url',
      'branch',
      'path',
    });
    ensureAllowedKeys(upstream, 'fluoh.yaml upstream', {'git'});
    ensureAllowedKeys(upstreamGit, 'fluoh.yaml upstream.git', {
      'url',
      'branch',
      'path',
    });

    final packages = <PackageManifestPackage>[];
    for (final entry in packagesMap.entries) {
      final name = entry.key;
      final value = entry.value;
      if (name.trim().isEmpty || value is! Map<String, Object?>) {
        throw const FluohSchemaException(
          'fluoh.yaml packages must map names to maps.',
        );
      }
      packages.add(
        _readPackageManifest(
          name,
          value,
          defaultRepositoryPath: optionalString(repositoryGit, 'path') ?? '.',
          defaultUpstreamPath: optionalString(upstreamGit, 'path') ?? '.',
        ),
      );
    }
    if (packages.isEmpty) {
      throw const FluohSchemaException(
        'fluoh.yaml must register at least one package.',
      );
    }

    final sdkVersion = requiredString(sdk, 'version');
    flutterVersionFromSdkVersion(sdkVersion);

    return PackageManifest(
      name: requiredString(yaml, 'name'),
      sdkVersion: sdkVersion,
      repositoryUrl: requiredString(repositoryGit, 'url'),
      repositoryBranch: requiredString(repositoryGit, 'branch'),
      repositoryPath: _manifestPath(optionalString(repositoryGit, 'path')),
      upstreamUrl: requiredString(upstreamGit, 'url'),
      upstreamBranch:
          optionalString(upstreamGit, 'branch') ?? defaultUpstreamBranch,
      upstreamPath: _manifestPath(optionalString(upstreamGit, 'path')),
      packages: packages,
    );
  }

  /// Human-readable repository or package group name.
  final String name;

  /// Full FlutterOH SDK tag used by this adaptation branch.
  final String sdkVersion;

  /// Git URL for the FlutterOH package implementation repository.
  final String repositoryUrl;

  /// Git branch that owns this adaptation manifest.
  final String repositoryBranch;

  /// Default package path inside the FlutterOH implementation repository.
  final String repositoryPath;

  /// Git URL for the upstream Flutter package repository.
  final String upstreamUrl;

  /// Upstream branch tracked by `fluoh package sync`.
  final String upstreamBranch;

  /// Default package path inside the upstream repository.
  final String upstreamPath;

  /// Packages registered in this adaptation repository.
  final List<PackageManifestPackage> packages;

  /// Dependency URL used when rewriting consumer pubspec files.
  String get dependencyUrl =>
      dependencyUrlForImplementationRepository(repositoryUrl);

  /// Branch alias used by package repository commands.
  String get branch => repositoryBranch;

  /// Resolves a package by name, or the only package when there is one.
  PackageManifestPackage packageForName(String? packageName) {
    if (packageName != null && packageName.trim().isNotEmpty) {
      final name = packageName.trim();
      for (final package in packages) {
        if (package.name == name) {
          return package;
        }
      }
      throw FluohSchemaException(
        'Package $name is not registered in fluoh.yaml.',
      );
    }
    if (packages.length == 1) {
      return packages.single;
    }
    throw const FluohSchemaException(
      'Multiple packages are registered in fluoh.yaml. Pass '
      '"--package <name>".',
    );
  }

  /// Primary package for single-package compatibility helpers.
  PackageManifestPackage get primaryPackage => packageForName(null);

  /// Primary package name.
  String get packageName => primaryPackage.name;

  /// Primary package upstream version.
  String get upstreamVersion => primaryPackage.upstreamVersion;

  /// Primary package FlutterOH adaptation release version.
  String get releaseVersion => primaryPackage.version;

  /// Primary package release tag for [sdkVersion].
  String get releaseTag => primaryPackage.releaseTag(sdkVersion);

  /// Primary package path in the upstream repository.
  String get upstreamPackagePath => primaryPackage.upstreamPath;

  /// Primary package path in the FlutterOH implementation repository.
  String get repositoryPackagePath => primaryPackage.repositoryPath;

  /// Dependency path used by package dependency rewrites.
  String get dependencyPath => primaryPackage.repositoryPath;

  /// Primary package release status, or `null` when compatible.
  String? get status => primaryPackage.status;
}

/// Release metadata for one package entry in `fluoh.yaml`.
class PackageManifestPackage {
  /// Creates an immutable package manifest entry.
  const PackageManifestPackage({
    required this.name,
    required this.upstreamVersion,
    required this.version,
    this.repositoryPath = '.',
    this.upstreamPath = '.',
    this.status,
  });

  /// Package name from the upstream pubspec.
  final String name;

  /// Upstream package version targeted by this adaptation.
  final String upstreamVersion;

  /// FlutterOH adaptation release version.
  final String version;

  /// Package path inside the FlutterOH implementation repository.
  final String repositoryPath;

  /// Package path inside the upstream repository.
  final String upstreamPath;

  /// Release status; `null` means compatible.
  final String? status;

  /// Alias for the adaptation release version.
  String get releaseVersion => version;

  /// Alias for the implementation repository package path.
  String get dependencyPath => repositoryPath;

  /// Computes the release tag for this package and SDK version.
  String releaseTag(String sdkVersion) {
    validateReleaseVersion(version);
    return packageReleaseTagForPackage(
      packageName: name,
      upstreamVersion: upstreamVersion,
      sdkVersion: sdkVersion,
      releaseVersion: version,
    );
  }

  /// Returns whether [tag] matches this package's release tag format.
  bool matchesReleaseTag(String sdkVersion, String tag) {
    validateReleaseVersion(version);
    return _releaseTagCandidates(sdkVersion).contains(tag);
  }

  Set<String> _releaseTagCandidates(String sdkVersion) {
    return {
      packageReleaseTagForPackage(
        packageName: name,
        upstreamVersion: upstreamVersion,
        sdkVersion: sdkVersion,
        releaseVersion: version,
      ),
    };
  }

  /// Creates a copy with selected release metadata fields changed.
  PackageManifestPackage copyWith({
    String? upstreamVersion,
    String? version,
    String? repositoryPath,
    String? upstreamPath,
    String? status,
    bool clearStatus = false,
  }) {
    return PackageManifestPackage(
      name: name,
      upstreamVersion: upstreamVersion ?? this.upstreamVersion,
      version: version ?? this.version,
      repositoryPath: repositoryPath ?? this.repositoryPath,
      upstreamPath: upstreamPath ?? this.upstreamPath,
      status: clearStatus ? null : status ?? this.status,
    );
  }
}

/// Creates the initial `fluoh.yaml` manifest for a package repository.
PackageManifest createPackageManifest({
  required PubspecPackage package,
  required String upstream,
  required String packagePath,
  required String sdkVersion,
  required String branch,
  required String repositoryUrl,
  String? name,
  String upstreamBranch = defaultUpstreamBranch,
  String? repositoryPath,
  String? upstreamPath,
  String releaseVersion = initialPackageReleaseVersion,
  String status = 'experimental',
}) {
  final repositoryPackagePath = _manifestPath(repositoryPath ?? packagePath);
  return PackageManifest(
    name: name ?? package.name,
    sdkVersion: sdkVersion,
    repositoryBranch: branch,
    upstreamUrl: upstream,
    upstreamBranch: upstreamBranch,
    repositoryUrl: repositoryUrl,
    packages: [
      PackageManifestPackage(
        name: package.name,
        upstreamVersion: package.version,
        version: releaseVersion,
        repositoryPath: repositoryPackagePath,
        upstreamPath: _manifestPath(upstreamPath ?? packagePath),
        status: status,
      ),
    ],
  );
}

/// Adds another package entry to an existing package repository manifest.
PackageManifest addPackageToManifest({
  required PackageManifest manifest,
  required PubspecPackage package,
  required String packagePath,
  String releaseVersion = initialPackageReleaseVersion,
  String status = 'experimental',
}) {
  if (manifest.packages.any((existing) => existing.name == package.name)) {
    throw FluohSchemaException(
      'Package ${package.name} is already registered in fluoh.yaml.',
    );
  }
  return PackageManifest(
    name: manifest.name,
    sdkVersion: manifest.sdkVersion,
    repositoryBranch: manifest.repositoryBranch,
    repositoryUrl: manifest.repositoryUrl,
    repositoryPath: manifest.repositoryPath,
    upstreamUrl: manifest.upstreamUrl,
    upstreamBranch: manifest.upstreamBranch,
    upstreamPath: manifest.upstreamPath,
    packages: [
      ...manifest.packages,
      PackageManifestPackage(
        name: package.name,
        upstreamVersion: package.version,
        version: releaseVersion,
        repositoryPath: _manifestPath(packagePath),
        upstreamPath: _manifestPath(packagePath),
        status: status,
      ),
    ],
  );
}

/// Updates upstream versions for all packages in a manifest.
PackageManifest updatePackageManifestUpstreamVersions({
  required PackageManifest manifest,
  required Map<String, String> packageVersions,
}) {
  for (final package in manifest.packages) {
    if (!packageVersions.containsKey(package.name)) {
      throw FluohSchemaException(
        'Missing upstream version for ${package.name}.',
      );
    }
  }
  return PackageManifest(
    name: manifest.name,
    sdkVersion: manifest.sdkVersion,
    repositoryBranch: manifest.repositoryBranch,
    repositoryUrl: manifest.repositoryUrl,
    repositoryPath: manifest.repositoryPath,
    upstreamUrl: manifest.upstreamUrl,
    upstreamBranch: manifest.upstreamBranch,
    upstreamPath: manifest.upstreamPath,
    packages: [
      for (final package in manifest.packages)
        package.copyWith(upstreamVersion: packageVersions[package.name]),
    ],
  );
}

/// Updates release version or status metadata for one package entry.
///
/// Passing `status: 'compatible'` clears the status field because compatible is
/// represented by omission in generated `fluoh.yaml` files.
PackageManifest updatePackageManifestRelease({
  required PackageManifest manifest,
  required String packageName,
  String? version,
  String? status,
}) {
  if (!manifest.packages.any((package) => package.name == packageName)) {
    throw FluohSchemaException(
      'Package $packageName is not registered in fluoh.yaml.',
    );
  }
  if (version != null) {
    validateReleaseVersion(
      version,
      label: 'fluoh.yaml packages.$packageName.version',
    );
  }
  if (status != null) {
    _releaseStatus(status);
  }
  return PackageManifest(
    name: manifest.name,
    sdkVersion: manifest.sdkVersion,
    repositoryBranch: manifest.repositoryBranch,
    repositoryUrl: manifest.repositoryUrl,
    repositoryPath: manifest.repositoryPath,
    upstreamUrl: manifest.upstreamUrl,
    upstreamBranch: manifest.upstreamBranch,
    upstreamPath: manifest.upstreamPath,
    packages: [
      for (final package in manifest.packages)
        if (package.name == packageName)
          package.copyWith(
            version: version,
            status: status == 'compatible' ? null : status,
            clearStatus: status == 'compatible',
          )
        else
          package,
    ],
  );
}

/// Renders a package repository manifest to canonical `fluoh.yaml` content.
String packageManifestContent(PackageManifest manifest) {
  for (final package in manifest.packages) {
    validateReleaseVersion(
      package.version,
      label: 'fluoh.yaml packages.${package.name}.version',
    );
  }
  return [
    'schema: $packageManifestSchema',
    'name: ${_yamlScalar(manifest.name)}',
    '',
    '# Complete Flutter OHOS SDK tag used by this adaptation branch.',
    'sdk:',
    '  version: ${manifest.sdkVersion}',
    '',
    '# FlutterOH adaptation repository. Branches normally follow ohos/<sdkLine>.',
    'repository:',
    '  git:',
    '    url: ${_yamlScalar(manifest.repositoryUrl)}',
    '    branch: ${_yamlScalar(manifest.repositoryBranch)}',
    if (manifest.repositoryPath != '.')
      '    path: ${_yamlScalar(manifest.repositoryPath)}',
    '',
    '# Upstream package repository tracked by fluoh package sync.',
    'upstream:',
    '  git:',
    '    url: ${_yamlScalar(manifest.upstreamUrl)}',
    if (manifest.upstreamBranch != defaultUpstreamBranch)
      '    branch: ${_yamlScalar(manifest.upstreamBranch)}',
    if (manifest.upstreamPath != '.')
      '    path: ${_yamlScalar(manifest.upstreamPath)}',
    '',
    '# Package release metadata. Update version/status before fluoh package check and release.',
    '# Omit status when the package is complete and compatible.',
    'packages:',
    for (final package in manifest.packages) ...[
      '  ${package.name}:',
      if (package.repositoryPath != manifest.repositoryPath) ...[
        '    # Dependency path inside this FlutterOH repository.',
        '    repository:',
        '      path: ${_yamlScalar(package.repositoryPath)}',
      ],
      if (package.upstreamPath != manifest.upstreamPath) ...[
        '    # Package path inside the upstream repository.',
        '    upstream:',
        '      path: ${_yamlScalar(package.upstreamPath)}',
      ],
      '    # FlutterOH adaptation package release version.',
      '    version: ${_yamlScalar(package.version)}',
      '    # Upstream package version this adaptation targets.',
      '    upstreamVersion: ${_yamlScalar(package.upstreamVersion)}',
      if (package.status != null && package.status != 'compatible') ...[
        '    # Use experimental while porting; remove when compatible.',
        '    status: ${package.status}',
      ],
    ],
    '',
  ].join('\n');
}

String _manifestPath(String? path) {
  if (path == null || path.isEmpty || path == '.') {
    return '.';
  }
  return path;
}

PackageManifestPackage _readPackageManifest(
  String name,
  Map<String, Object?> package, {
  required String defaultRepositoryPath,
  required String defaultUpstreamPath,
}) {
  ensureAllowedKeys(package, 'fluoh.yaml packages.$name', {
    'repository',
    'upstream',
    'version',
    'upstreamVersion',
    'status',
  });
  final repository = optionalObjectMap(
    package['repository'],
    'fluoh.yaml packages.$name.repository',
  );
  final upstream = optionalObjectMap(
    package['upstream'],
    'fluoh.yaml packages.$name.upstream',
  );
  if (repository != null) {
    ensureAllowedKeys(repository, 'fluoh.yaml packages.$name.repository', {
      'path',
    });
  }
  if (upstream != null) {
    ensureAllowedKeys(upstream, 'fluoh.yaml packages.$name.upstream', {'path'});
  }
  final version = requiredString(package, 'version');
  validateReleaseVersion(version, label: 'fluoh.yaml packages.$name.version');
  return PackageManifestPackage(
    name: name,
    repositoryPath: _manifestPath(
      optionalString(repository ?? const {}, 'path') ?? defaultRepositoryPath,
    ),
    upstreamPath: _manifestPath(
      optionalString(upstream ?? const {}, 'path') ?? defaultUpstreamPath,
    ),
    upstreamVersion: requiredString(package, 'upstreamVersion'),
    version: version,
    status: _releaseStatus(optionalString(package, 'status')),
  );
}

String? _releaseStatus(String? status) {
  if (status == null) {
    return null;
  }
  if (const {'compatible', 'experimental', 'broken'}.contains(status)) {
    return status;
  }
  throw const FluohSchemaException(
    'fluoh.yaml status must be compatible, experimental, or broken.',
  );
}

void _ensurePackageManifestSchema(Map<String, Object?> yaml) {
  final schema = yaml['schema'];
  if (schema == null) {
    throw const FluohSchemaException('fluoh.yaml missing "schema".');
  }
  if (schema is! int) {
    throw const FluohSchemaException('fluoh.yaml schema must be an integer.');
  }
  if (schema > packageManifestSchema) {
    throw FluohSchemaException(
      'fluoh.yaml schema $schema requires a newer fluoh.',
    );
  }
  if (schema < packageManifestSchema) {
    throw FluohSchemaException(
      'fluoh.yaml schema $schema is not supported for package repositories. '
      'Expected schema $packageManifestSchema.',
    );
  }
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
  if (value.contains(RegExp(r'\s'))) {
    return true;
  }
  if (value.endsWith(':') || value.contains(': ')) {
    return true;
  }
  if (const {'true', 'false', 'null', '~'}.contains(value.toLowerCase())) {
    return true;
  }
  return false;
}
