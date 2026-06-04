import 'pubspec.dart';
import 'version_rules.dart';
import 'yaml_utils.dart';

/// Current `fluoh.yaml` schema version for package adaptation branches.
const packageManifestSchema = 1;

/// Initial FlutterOH adaptation release version for newly created branches.
const initialPackageReleaseVersion = '0.1.0';

/// Package manifest kind.
const packageManifestKind = 'package';

/// Default upstream branch used when `fluoh.yaml` omits `upstream.git.branch`.
const defaultUpstreamBranch = 'main';

/// Parsed `fluoh.yaml` manifest for one FlutterOH package adaptation branch.
///
/// A package branch is the smallest adaptation unit. Monorepo repositories use
/// one branch per package instead of registering multiple packages in one
/// manifest.
class PackageManifest {
  /// Creates an immutable package adaptation manifest.
  const PackageManifest({
    required this.sdkVersion,
    required this.repositoryUrl,
    required this.repositoryBranch,
    required this.upstreamUrl,
    required this.package,
    this.upstreamBranch = defaultUpstreamBranch,
  });

  /// Parses and validates `fluoh.yaml` content.
  factory PackageManifest.parse(String content) {
    final yaml = parseYamlMap(content, label: 'fluoh.yaml');
    _ensurePackageManifestSchema(yaml);

    ensureAllowedKeys(yaml, 'fluoh.yaml', {
      'schema',
      'kind',
      'sdk',
      'repository',
      'upstream',
      'package',
    });
    final kind = requiredString(yaml, 'kind');
    if (kind != packageManifestKind) {
      throw FluohSchemaException(
        'fluoh.yaml kind must be $packageManifestKind.',
      );
    }

    final sdk = objectMap(yaml['sdk'], 'fluoh.yaml sdk');
    final repository = objectMap(yaml['repository'], 'fluoh.yaml repository');
    final repositoryGit = objectMap(
      repository['git'],
      'fluoh.yaml repository.git',
    );
    final upstream = objectMap(yaml['upstream'], 'fluoh.yaml upstream');
    final upstreamGit = objectMap(upstream['git'], 'fluoh.yaml upstream.git');
    final package = objectMap(yaml['package'], 'fluoh.yaml package');

    ensureAllowedKeys(sdk, 'fluoh.yaml sdk', {'version'});
    ensureAllowedKeys(repository, 'fluoh.yaml repository', {'git'});
    ensureAllowedKeys(repositoryGit, 'fluoh.yaml repository.git', {
      'url',
      'branch',
    });
    ensureAllowedKeys(upstream, 'fluoh.yaml upstream', {'git'});
    ensureAllowedKeys(upstreamGit, 'fluoh.yaml upstream.git', {
      'url',
      'branch',
    });

    final sdkVersion = requiredString(sdk, 'version');
    flutterVersionFromSdkVersion(sdkVersion);

    final manifestPackage = _readPackageManifest(package);
    final repositoryBranch = requiredString(repositoryGit, 'branch');
    final normalizedRepositoryBranch = normalizeGitRef(
      repositoryBranch,
      label: 'fluoh.yaml repository.git.branch',
    );
    _validatePackageBranch(
      normalizedRepositoryBranch,
      sdkVersion: sdkVersion,
      packageName: manifestPackage.name,
    );
    final upstreamBranch = requiredString(upstreamGit, 'branch');

    return PackageManifest(
      sdkVersion: sdkVersion,
      repositoryUrl: requiredString(repositoryGit, 'url'),
      repositoryBranch: normalizedRepositoryBranch,
      upstreamUrl: requiredString(upstreamGit, 'url'),
      upstreamBranch: normalizeGitRef(
        upstreamBranch,
        label: 'fluoh.yaml upstream.git.branch',
      ),
      package: manifestPackage,
    );
  }

  /// Human-readable FlutterOH adaptation repository name.
  String get name => package.name;

  /// Full FlutterOH SDK tag used by this adaptation branch.
  final String sdkVersion;

  /// Git URL for the FlutterOH package implementation repository.
  final String repositoryUrl;

  /// Git branch that owns this package adaptation manifest.
  final String repositoryBranch;

  /// Git URL for the upstream Flutter package repository.
  final String upstreamUrl;

  /// Upstream branch tracked by `fluoh package sync`.
  final String upstreamBranch;

  /// Package adapted by this branch.
  final PackageManifestPackage package;

  /// Dependency URL used when rewriting consumer pubspec files.
  String get dependencyUrl =>
      dependencyUrlForImplementationRepository(repositoryUrl);

  /// Branch alias used by package repository commands.
  String get branch => repositoryBranch;

  /// Resolves the branch package, optionally validating its name.
  PackageManifestPackage packageForName(String? packageName) {
    final requested = packageName?.trim();
    if (requested == null || requested.isEmpty || requested == package.name) {
      return package;
    }
    throw FluohSchemaException(
      'Package $requested is not registered in this package branch.',
    );
  }

  /// Primary package for command helpers.
  PackageManifestPackage get primaryPackage => package;

  /// Primary package name.
  String get packageName => package.name;

  /// Primary package upstream version.
  String get upstreamVersion => package.upstreamVersion;

  /// Primary package FlutterOH adaptation release version.
  String get releaseVersion => package.version;

  /// Primary package release tag for [sdkVersion].
  String get releaseTag => package.releaseTag(sdkVersion);

  /// Primary package release status, or `null` when compatible.
  String? get status => package.status;
}

/// Release metadata for the package adapted by one branch.
class PackageManifestPackage {
  /// Creates an immutable package manifest entry.
  const PackageManifestPackage({
    required this.name,
    required this.upstreamVersion,
    required this.upstreamCommit,
    required this.version,
    String? path,
    this.upstreamRef,
    this.status,
  }) : path = path ?? '.';

  /// Package name from the upstream pubspec.
  final String name;

  /// Package path inside both the upstream and FlutterOH repositories.
  final String path;

  /// Upstream package version targeted by this adaptation.
  final String upstreamVersion;

  /// Upstream Git ref that provided this package's source snapshot.
  final String? upstreamRef;

  /// Resolved upstream Git commit for [upstreamRef].
  final String upstreamCommit;

  /// FlutterOH adaptation release version.
  final String version;

  /// Release status; `null` means compatible.
  final String? status;

  /// Alias for the adaptation release version.
  String get releaseVersion => version;

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

  /// Creates a copy with selected metadata fields changed.
  PackageManifestPackage copyWith({
    String? path,
    String? upstreamVersion,
    String? upstreamRef,
    bool clearUpstreamRef = false,
    String? upstreamCommit,
    String? version,
    String? status,
    bool clearStatus = false,
  }) {
    return PackageManifestPackage(
      name: name,
      path: path ?? this.path,
      upstreamVersion: upstreamVersion ?? this.upstreamVersion,
      upstreamRef: clearUpstreamRef ? null : upstreamRef ?? this.upstreamRef,
      upstreamCommit: upstreamCommit ?? this.upstreamCommit,
      version: version ?? this.version,
      status: clearStatus ? null : status ?? this.status,
    );
  }
}

/// Creates the initial `fluoh.yaml` manifest for a package branch.
PackageManifest createPackageManifest({
  required PubspecPackage package,
  required String upstream,
  required String packagePath,
  required String sdkVersion,
  required String branch,
  required String repositoryUrl,
  required String upstreamCommit,
  String upstreamBranch = defaultUpstreamBranch,
  String? upstreamRef,
  String releaseVersion = initialPackageReleaseVersion,
  String status = 'experimental',
}) {
  return PackageManifest(
    sdkVersion: sdkVersion,
    repositoryBranch: branch,
    upstreamUrl: upstream,
    upstreamBranch: upstreamBranch,
    repositoryUrl: repositoryUrl,
    package: PackageManifestPackage(
      name: package.name,
      path: _manifestPath(packagePath),
      upstreamVersion: _manifestVersion(
        package.version,
        label: 'fluoh.yaml package.release.upstream.version',
      ),
      upstreamRef: _manifestRef(upstreamRef),
      upstreamCommit: _manifestCommit(upstreamCommit),
      version: _manifestVersion(
        releaseVersion,
        label: 'fluoh.yaml package.release.version',
      ),
      status: status,
    ),
  );
}

/// Updates upstream version metadata for the branch package.
PackageManifest updatePackageManifestUpstreamVersions({
  required PackageManifest manifest,
  required Map<String, String> packageVersions,
  String? upstreamCommit,
  bool clearUpstreamRef = true,
}) {
  final version = packageVersions[manifest.package.name];
  if (version == null) {
    throw FluohSchemaException(
      'Missing upstream version for ${manifest.package.name}.',
    );
  }
  return PackageManifest(
    sdkVersion: manifest.sdkVersion,
    repositoryBranch: manifest.repositoryBranch,
    repositoryUrl: manifest.repositoryUrl,
    upstreamUrl: manifest.upstreamUrl,
    upstreamBranch: manifest.upstreamBranch,
    package: manifest.package.copyWith(
      upstreamVersion: version,
      upstreamCommit: upstreamCommit,
      clearUpstreamRef: clearUpstreamRef,
    ),
  );
}

/// Updates release version or status metadata for the branch package.
///
/// Passing `status: 'compatible'` clears the status field because compatible is
/// represented by omission in generated `fluoh.yaml` files.
PackageManifest updatePackageManifestRelease({
  required PackageManifest manifest,
  required String packageName,
  String? version,
  String? status,
}) {
  if (manifest.package.name != packageName) {
    throw FluohSchemaException(
      'Package $packageName is not registered in this package branch.',
    );
  }
  if (version != null) {
    validateReleaseVersion(
      version,
      label: 'fluoh.yaml package.release.version',
    );
  }
  if (status != null) {
    _releaseStatus(status);
  }
  return PackageManifest(
    sdkVersion: manifest.sdkVersion,
    repositoryBranch: manifest.repositoryBranch,
    repositoryUrl: manifest.repositoryUrl,
    upstreamUrl: manifest.upstreamUrl,
    upstreamBranch: manifest.upstreamBranch,
    package: manifest.package.copyWith(
      version: version,
      status: status == 'compatible' ? null : status,
      clearStatus: status == 'compatible',
    ),
  );
}

/// Renders a package branch manifest to canonical `fluoh.yaml` content.
String packageManifestContent(PackageManifest manifest) {
  validateDartPackageName(
    manifest.package.name,
    label: 'fluoh.yaml package.name',
  );
  final packagePath = normalizeManifestPath(
    manifest.package.path,
    label: 'fluoh.yaml package.path',
  );
  final upstreamVersion = _manifestVersion(
    manifest.package.upstreamVersion,
    label: 'fluoh.yaml package.release.upstream.version',
  );
  final upstreamRef = manifest.package.upstreamRef == null
      ? null
      : normalizeGitRef(
          manifest.package.upstreamRef!,
          label: 'fluoh.yaml package.release.upstream.ref',
        );
  final upstreamCommit = normalizeGitCommitHash(
    manifest.package.upstreamCommit,
    label: 'fluoh.yaml package.release.upstream.commit',
  );
  validateReleaseVersion(
    manifest.package.version,
    label: 'fluoh.yaml package.release.version',
  );
  _releaseStatus(manifest.package.status);
  final repositoryBranch = normalizeGitRef(
    manifest.repositoryBranch,
    label: 'fluoh.yaml repository.git.branch',
  );
  _validatePackageBranch(
    repositoryBranch,
    sdkVersion: manifest.sdkVersion,
    packageName: manifest.package.name,
  );
  final upstreamBranch = normalizeGitRef(
    manifest.upstreamBranch,
    label: 'fluoh.yaml upstream.git.branch',
  );
  return [
    'schema: $packageManifestSchema',
    'kind: $packageManifestKind',
    '',
    '# Complete Flutter OHOS SDK tag used by this adaptation branch.',
    'sdk:',
    '  version: ${manifest.sdkVersion}',
    '',
    '# FlutterOH adaptation repository and current package branch.',
    'repository:',
    '  git:',
    '    url: ${_yamlScalar(manifest.repositoryUrl)}',
    '    branch: ${_yamlScalar(repositoryBranch)}',
    '',
    '# Upstream package repository tracked by fluoh package sync.',
    'upstream:',
    '  git:',
    '    url: ${_yamlScalar(manifest.upstreamUrl)}',
    '    branch: ${_yamlScalar(upstreamBranch)}',
    '',
    '# Package adapted by this branch.',
    'package:',
    '  name: ${_yamlScalar(manifest.package.name)}',
    if (packagePath != '.') '  path: ${_yamlScalar(packagePath)}',
    '  release:',
    '    version: ${_yamlScalar(manifest.package.version)}',
    '    upstream:',
    '      version: ${_yamlScalar(upstreamVersion)}',
    if (upstreamRef != null) '      ref: ${_yamlScalar(upstreamRef)}',
    '      commit: ${_yamlScalar(upstreamCommit)}',
    if (manifest.package.status != null &&
        manifest.package.status != 'compatible') ...[
      '    status: ${manifest.package.status}',
    ],
    '',
  ].join('\n');
}

String _manifestPath(String? path) {
  return normalizeManifestPath(path, label: 'fluoh.yaml package.path');
}

String _manifestVersion(String version, {required String label}) {
  validatePubVersion(version, label: label);
  return version;
}

String? _manifestRef(String? ref) {
  final trimmed = ref?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return normalizeGitRef(
    trimmed,
    label: 'fluoh.yaml package.release.upstream.ref',
  );
}

String _manifestCommit(String commit) {
  return normalizeGitCommitHash(
    commit,
    label: 'fluoh.yaml package.release.upstream.commit',
  );
}

void _validatePackageBranch(
  String branch, {
  required String sdkVersion,
  required String packageName,
}) {
  final expected = flutterOhosPackageBranchForSdk(
    sdkVersion: sdkVersion,
    packageName: packageName,
  );
  if (branch == expected) {
    return;
  }
  throw FluohSchemaException(
    'fluoh.yaml repository.git.branch must be $expected for package '
    '$packageName and SDK ${sdkLineFromSdkVersion(sdkVersion)}.',
  );
}

PackageManifestPackage _readPackageManifest(Map<String, Object?> package) {
  ensureAllowedKeys(package, 'fluoh.yaml package', {'name', 'path', 'release'});
  final release = objectMap(package['release'], 'fluoh.yaml package.release');
  ensureAllowedKeys(release, 'fluoh.yaml package.release', {
    'version',
    'upstream',
    'status',
  });
  final upstream = objectMap(
    release['upstream'],
    'fluoh.yaml package.release.upstream',
  );
  ensureAllowedKeys(upstream, 'fluoh.yaml package.release.upstream', {
    'version',
    'ref',
    'commit',
  });
  final version = requiredString(release, 'version');
  validateReleaseVersion(version, label: 'fluoh.yaml package.release.version');
  final packageName = requiredString(package, 'name');
  validateDartPackageName(packageName, label: 'fluoh.yaml package.name');
  return PackageManifestPackage(
    name: packageName,
    path: _manifestPath(optionalString(package, 'path')),
    upstreamVersion: _manifestVersion(
      requiredString(upstream, 'version'),
      label: 'fluoh.yaml package.release.upstream.version',
    ),
    upstreamRef: _manifestRef(optionalString(upstream, 'ref')),
    upstreamCommit: _manifestCommit(requiredString(upstream, 'commit')),
    version: version,
    status: _releaseStatus(optionalString(release, 'status')),
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
  if (RegExp(
    r'^[+-]?(?:\d+|\d+\.\d+|\.\d+)(?:[eE][+-]?\d+)?$',
  ).hasMatch(value)) {
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
