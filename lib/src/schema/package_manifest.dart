import 'pubspec.dart';
import 'version_rules.dart';
import 'yaml_utils.dart';

/// Current `fluoh.yaml` schema version for package support branches.
const packageManifestSchema = 1;

/// Initial FlutterOH support release version for newly created branches.
const initialPackageReleaseVersion = '0.1.0';

/// Package manifest kind.
const packageManifestKind = 'package';

/// Spec-first FlutterOH package origin.
const packageOriginCreated = 'created';

/// Upstream-first FlutterOH package origin.
const packageOriginPorted = 'ported';

/// Default upstream branch used when `fluoh.yaml` omits `upstream.git.branch`.
const defaultUpstreamBranch = 'main';

/// Default platform that a fluoh package support branch implements.
const defaultTargetPlatforms = ['ohos'];

/// Default publish targets tracked by package release gates.
const defaultPackagePublishTargets = ['pub.dev', 'flutteroh-source'];

/// Parsed `fluoh.yaml` manifest for one FlutterOH package support branch.
///
/// A package branch is the smallest support unit. Monorepo repositories use
/// one branch per package instead of registering multiple packages in one
/// manifest.
class PackageManifest {
  /// Creates an immutable package support manifest.
  const PackageManifest({
    required this.sdkVersion,
    required this.repositoryUrl,
    required this.repositoryBranch,
    required this.package,
    this.sdkKind = sdkKindFlutterOh,
    this.targetPlatforms = defaultTargetPlatforms,
    this.preservedPlatforms = const <String>[],
    this.publishTargets = defaultPackagePublishTargets,
    this.originKind = packageOriginPorted,
    this.upstreamUrl,
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
      'platforms',
      'publishTargets',
      'repository',
      'origin',
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
    final origin = objectMap(yaml['origin'], 'fluoh.yaml origin');
    final package = objectMap(yaml['package'], 'fluoh.yaml package');

    ensureAllowedKeys(sdk, 'fluoh.yaml sdk', {'kind', 'version'});
    ensureAllowedKeys(repository, 'fluoh.yaml repository', {'git'});
    ensureAllowedKeys(repositoryGit, 'fluoh.yaml repository.git', {
      'url',
      'branch',
    });
    ensureAllowedKeys(origin, 'fluoh.yaml origin', {'kind'});
    final originKind = _originKind(requiredString(origin, 'kind'));
    final upstream = optionalObjectMap(yaml['upstream'], 'fluoh.yaml upstream');
    Map<String, Object?>? upstreamGit;
    if (originKind == packageOriginPorted) {
      if (upstream == null) {
        throw const FluohSchemaException(
          'fluoh.yaml upstream is required for ported packages.',
        );
      }
      ensureAllowedKeys(upstream, 'fluoh.yaml upstream', {'git'});
      upstreamGit = objectMap(upstream['git'], 'fluoh.yaml upstream.git');
      ensureAllowedKeys(upstreamGit, 'fluoh.yaml upstream.git', {
        'url',
        'branch',
      });
    } else if (upstream != null) {
      throw const FluohSchemaException(
        'fluoh.yaml upstream must be omitted for created packages.',
      );
    }

    final sdkVersion = requiredString(sdk, 'version');
    final sdkKind = normalizeSdkKind(
      optionalString(sdk, 'kind'),
      label: 'fluoh.yaml sdk.kind',
    );
    if (!isFlutterOhSdkKind(sdkKind)) {
      throw const FluohSchemaException(
        'fluoh package manifests currently require sdk.kind: flutteroh.',
      );
    }
    flutterVersionFromSdkVersion(sdkVersion);
    final platforms = optionalObjectMap(
      yaml['platforms'],
      'fluoh.yaml platforms',
    );
    if (platforms != null) {
      ensureAllowedKeys(platforms, 'fluoh.yaml platforms', {
        'target',
        'preserved',
      });
    }
    final targetPlatforms = _platformList(
      platforms?['target'],
      label: 'fluoh.yaml platforms.target',
      fallback: defaultTargetPlatforms,
    );
    final preservedPlatforms = _platformList(
      platforms?['preserved'],
      label: 'fluoh.yaml platforms.preserved',
      fallback: const <String>[],
    );
    if (targetPlatforms.contains('ohos') && !isFlutterOhSdkKind(sdkKind)) {
      throw const FluohSchemaException(
        'fluoh.yaml packages targeting ohos require sdk.kind: flutteroh.',
      );
    }
    final publishTargets = _publishTargetList(yaml['publishTargets']);

    final manifestPackage = _readPackageManifest(
      package,
      originKind: originKind,
    );
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
    final upstreamBranch = upstreamGit == null
        ? defaultUpstreamBranch
        : requiredString(upstreamGit, 'branch');

    return PackageManifest(
      sdkVersion: sdkVersion,
      sdkKind: sdkKind,
      targetPlatforms: targetPlatforms,
      preservedPlatforms: preservedPlatforms,
      publishTargets: publishTargets,
      originKind: originKind,
      repositoryUrl: requiredString(repositoryGit, 'url'),
      repositoryBranch: normalizedRepositoryBranch,
      upstreamUrl: upstreamGit == null
          ? null
          : requiredString(upstreamGit, 'url'),
      upstreamBranch: normalizeGitRef(
        upstreamBranch,
        label: 'fluoh.yaml upstream.git.branch',
      ),
      package: manifestPackage,
    );
  }

  /// Human-readable FlutterOH support repository name.
  String get name => package.name;

  /// Full FlutterOH SDK tag used by this support branch.
  final String sdkVersion;

  /// SDK kind selected by this package branch.
  final String sdkKind;

  /// Platforms implemented or explicitly targeted by this branch.
  final List<String> targetPlatforms;

  /// Existing upstream platforms that must be preserved while adding support.
  final List<String> preservedPlatforms;

  /// Release/distribution targets tracked by package checks.
  final List<String> publishTargets;

  /// Package origin kind: `created` or `ported`.
  final String originKind;

  /// Whether this package was created from a local spec instead of upstream.
  bool get isCreated => originKind == packageOriginCreated;

  /// Whether this package was ported from an upstream package repository.
  bool get isPorted => originKind == packageOriginPorted;

  /// Git URL for the FlutterOH package implementation repository.
  final String repositoryUrl;

  /// Git branch that owns this package support manifest.
  final String repositoryBranch;

  /// Git URL for the upstream Flutter package repository.
  final String? upstreamUrl;

  /// Git URL for the upstream Flutter package repository, when ported.
  String get requiredUpstreamUrl {
    final upstreamUrl = this.upstreamUrl;
    if (upstreamUrl == null) {
      throw const FluohSchemaException(
        'Created packages do not have an upstream repository.',
      );
    }
    return upstreamUrl;
  }

  /// Upstream branch tracked by `fluoh package upstream sync`.
  final String upstreamBranch;

  /// Package targeted by this branch.
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
  String get upstreamVersion => package.sourceVersion;

  /// Primary package FlutterOH support release version.
  String get releaseVersion => package.version;

  /// Primary package release tag for [sdkVersion].
  String get releaseTag => package.releaseTag(sdkVersion);

  /// Primary package release status, or `null` when compatible.
  String? get status => package.status;
}

/// Release metadata for the package targeted by one branch.
class PackageManifestPackage {
  /// Creates an immutable package manifest entry.
  const PackageManifestPackage({
    required this.name,
    required this.version,
    String? path,
    this.upstreamVersion,
    this.upstreamCommit,
    this.upstreamRef,
    this.status,
  }) : path = path ?? '.';

  /// Package name from the upstream pubspec.
  final String name;

  /// Package path inside both the upstream and FlutterOH repositories.
  final String path;

  /// Upstream package version targeted by this port, or null for created packages.
  final String? upstreamVersion;

  /// Upstream Git ref that provided this package's source snapshot.
  final String? upstreamRef;

  /// Resolved upstream Git commit for [upstreamRef], or null for created packages.
  final String? upstreamCommit;

  /// FlutterOH support release version.
  final String version;

  /// Release status; `null` means compatible.
  final String? status;

  /// Alias for the support release version.
  String get releaseVersion => version;

  /// Version used by dependency/source matching.
  String get sourceVersion => upstreamVersion ?? version;

  /// Upstream package version, when this package is ported.
  String get requiredUpstreamVersion {
    final upstreamVersion = this.upstreamVersion;
    if (upstreamVersion == null) {
      throw const FluohSchemaException(
        'Created packages do not have an upstream package version.',
      );
    }
    return upstreamVersion;
  }

  /// Upstream commit, when this package is ported.
  String get requiredUpstreamCommit {
    final upstreamCommit = this.upstreamCommit;
    if (upstreamCommit == null) {
      throw const FluohSchemaException(
        'Created packages do not have an upstream commit.',
      );
    }
    return upstreamCommit;
  }

  /// Computes the release tag for this package and SDK version.
  String releaseTag(String sdkVersion) {
    validateReleaseVersion(version);
    final upstreamVersion = this.upstreamVersion;
    if (upstreamVersion == null) {
      return createdPackageReleaseTagForPackage(
        packageName: name,
        sdkVersion: sdkVersion,
        releaseVersion: version,
      );
    }
    return portedPackageReleaseTagForPackage(
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
    final upstreamVersion = this.upstreamVersion;
    if (upstreamVersion == null) {
      return {
        createdPackageReleaseTagForPackage(
          packageName: name,
          sdkVersion: sdkVersion,
          releaseVersion: version,
        ),
      };
    }
    return {
      portedPackageReleaseTagForPackage(
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
    sdkKind: sdkKindFlutterOh,
    targetPlatforms: defaultTargetPlatforms,
    publishTargets: defaultPackagePublishTargets,
    originKind: packageOriginPorted,
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

/// Creates the initial `fluoh.yaml` manifest for a spec-created package branch.
PackageManifest createSpecPackageManifest({
  required PubspecPackage package,
  required String packagePath,
  required String sdkVersion,
  required String branch,
  required String repositoryUrl,
  String releaseVersion = initialPackageReleaseVersion,
  String status = 'experimental',
}) {
  return PackageManifest(
    sdkVersion: sdkVersion,
    sdkKind: sdkKindFlutterOh,
    targetPlatforms: defaultTargetPlatforms,
    publishTargets: defaultPackagePublishTargets,
    originKind: packageOriginCreated,
    repositoryBranch: branch,
    repositoryUrl: repositoryUrl,
    package: PackageManifestPackage(
      name: package.name,
      path: _manifestPath(packagePath),
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
  String? upstreamRef,
  String? upstreamCommit,
  bool clearUpstreamRef = true,
}) {
  final version = packageVersions[manifest.package.name];
  if (version == null) {
    throw FluohSchemaException(
      'Missing upstream version for ${manifest.package.name}.',
    );
  }
  if (!manifest.isPorted) {
    throw const FluohSchemaException(
      'Created packages do not have upstream version metadata.',
    );
  }
  return PackageManifest(
    sdkVersion: manifest.sdkVersion,
    sdkKind: manifest.sdkKind,
    targetPlatforms: manifest.targetPlatforms,
    preservedPlatforms: manifest.preservedPlatforms,
    publishTargets: manifest.publishTargets,
    originKind: manifest.originKind,
    repositoryBranch: manifest.repositoryBranch,
    repositoryUrl: manifest.repositoryUrl,
    upstreamUrl: manifest.upstreamUrl,
    upstreamBranch: manifest.upstreamBranch,
    package: manifest.package.copyWith(
      upstreamVersion: version,
      upstreamRef: upstreamRef,
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
    sdkKind: manifest.sdkKind,
    targetPlatforms: manifest.targetPlatforms,
    preservedPlatforms: manifest.preservedPlatforms,
    publishTargets: manifest.publishTargets,
    originKind: manifest.originKind,
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
  final originKind = _originKind(manifest.originKind);
  final isPorted = originKind == packageOriginPorted;
  if (isPorted &&
      (manifest.upstreamUrl == null ||
          manifest.package.upstreamVersion == null ||
          manifest.package.upstreamCommit == null)) {
    throw const FluohSchemaException(
      'fluoh.yaml upstream metadata is required for ported packages.',
    );
  }
  if (!isPorted &&
      (manifest.upstreamUrl != null ||
          manifest.package.upstreamVersion != null ||
          manifest.package.upstreamCommit != null ||
          manifest.package.upstreamRef != null)) {
    throw const FluohSchemaException(
      'fluoh.yaml upstream must be omitted for created packages.',
    );
  }
  final upstreamVersion = isPorted
      ? _manifestVersion(
          manifest.package.upstreamVersion!,
          label: 'fluoh.yaml package.release.upstream.version',
        )
      : null;
  final upstreamRef = !isPorted || manifest.package.upstreamRef == null
      ? null
      : normalizeGitRef(
          manifest.package.upstreamRef!,
          label: 'fluoh.yaml package.release.upstream.ref',
        );
  final upstreamCommit = isPorted
      ? normalizeGitCommitHash(
          manifest.package.upstreamCommit!,
          label: 'fluoh.yaml package.release.upstream.commit',
        )
      : null;
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
  final upstreamBranch = isPorted
      ? normalizeGitRef(
          manifest.upstreamBranch,
          label: 'fluoh.yaml upstream.git.branch',
        )
      : null;
  return [
    'schema: $packageManifestSchema',
    'kind: $packageManifestKind',
    '',
    '# SDK used by this support branch. OHOS targets require flutteroh.',
    'sdk:',
    '  kind: ${manifest.sdkKind}',
    '  version: ${manifest.sdkVersion}',
    '',
    '# Platform scope owned by this support branch.',
    'platforms:',
    '  target:',
    ..._yamlListItems(manifest.targetPlatforms, indent: '    '),
    if (manifest.preservedPlatforms.isNotEmpty) ...[
      '  preserved:',
      ..._yamlListItems(manifest.preservedPlatforms, indent: '    '),
    ],
    '',
    '# Distribution targets checked before release readiness.',
    'publishTargets:',
    ..._yamlListItems(manifest.publishTargets, indent: '  '),
    '',
    '# FlutterOH support repository and current package branch.',
    'repository:',
    '  git:',
    '    url: ${_yamlScalar(manifest.repositoryUrl)}',
    '    branch: ${_yamlScalar(repositoryBranch)}',
    '',
    '# Package source model used by fluoh package workflows.',
    'origin:',
    '  kind: $originKind',
    '',
    if (isPorted) ...[
      '# Upstream package repository tracked by fluoh package upstream sync.',
      'upstream:',
      '  git:',
      '    url: ${_yamlScalar(manifest.upstreamUrl!)}',
      '    branch: ${_yamlScalar(upstreamBranch!)}',
      '',
    ],
    '# Package targeted by this branch.',
    'package:',
    '  name: ${_yamlScalar(manifest.package.name)}',
    if (packagePath != '.') '  path: ${_yamlScalar(packagePath)}',
    '  release:',
    '    version: ${_yamlScalar(manifest.package.version)}',
    if (isPorted) ...[
      '    upstream:',
      '      version: ${_yamlScalar(upstreamVersion!)}',
      if (upstreamRef != null) '      ref: ${_yamlScalar(upstreamRef)}',
      '      commit: ${_yamlScalar(upstreamCommit!)}',
    ],
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

List<String> _platformList(
  Object? value, {
  required String label,
  required List<String> fallback,
}) {
  if (value == null) {
    return List<String>.unmodifiable(fallback);
  }
  if (value is! List<Object?>) {
    throw FluohSchemaException('$label must be a YAML list.');
  }
  final result = <String>[];
  for (final item in value) {
    if (item is! String || item.trim().isEmpty) {
      throw FluohSchemaException('$label entries must be non-empty strings.');
    }
    final platform = item.trim();
    _validatePlatformName(platform, label: '$label entry');
    if (!result.contains(platform)) {
      result.add(platform);
    }
  }
  if (result.isEmpty) {
    throw FluohSchemaException('$label must not be empty.');
  }
  return List<String>.unmodifiable(result);
}

List<String> _publishTargetList(Object? value) {
  if (value == null) {
    return List<String>.unmodifiable(defaultPackagePublishTargets);
  }
  if (value is! List<Object?>) {
    throw const FluohSchemaException(
      'fluoh.yaml publishTargets must be a YAML list.',
    );
  }
  final result = <String>[];
  for (final item in value) {
    if (item is! String || item.trim().isEmpty) {
      throw const FluohSchemaException(
        'fluoh.yaml publishTargets entries must be non-empty strings.',
      );
    }
    final target = item.trim();
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]*$').hasMatch(target)) {
      throw FluohSchemaException(
        'fluoh.yaml publishTargets entry "$target" is not valid.',
      );
    }
    if (!result.contains(target)) {
      result.add(target);
    }
  }
  if (result.isEmpty) {
    throw const FluohSchemaException(
      'fluoh.yaml publishTargets must not be empty.',
    );
  }
  return List<String>.unmodifiable(result);
}

void _validatePlatformName(String platform, {required String label}) {
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(platform)) {
    throw FluohSchemaException('$label "$platform" is not a valid platform.');
  }
}

List<String> _yamlListItems(List<String> values, {required String indent}) {
  return [for (final value in values) '$indent- ${_yamlScalar(value)}'];
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

PackageManifestPackage _readPackageManifest(
  Map<String, Object?> package, {
  required String originKind,
}) {
  ensureAllowedKeys(package, 'fluoh.yaml package', {'name', 'path', 'release'});
  final release = objectMap(package['release'], 'fluoh.yaml package.release');
  ensureAllowedKeys(release, 'fluoh.yaml package.release', {
    'version',
    'upstream',
    'status',
  });
  final upstream = optionalObjectMap(
    release['upstream'],
    'fluoh.yaml package.release.upstream',
  );
  if (originKind == packageOriginPorted && upstream == null) {
    throw const FluohSchemaException(
      'fluoh.yaml package.release.upstream is required for ported packages.',
    );
  }
  if (originKind == packageOriginCreated && upstream != null) {
    throw const FluohSchemaException(
      'fluoh.yaml package.release.upstream must be omitted for created packages.',
    );
  }
  if (upstream != null) {
    ensureAllowedKeys(upstream, 'fluoh.yaml package.release.upstream', {
      'version',
      'ref',
      'commit',
    });
  }
  final version = requiredString(release, 'version');
  validateReleaseVersion(version, label: 'fluoh.yaml package.release.version');
  final packageName = requiredString(package, 'name');
  validateDartPackageName(packageName, label: 'fluoh.yaml package.name');
  return PackageManifestPackage(
    name: packageName,
    path: _manifestPath(optionalString(package, 'path')),
    upstreamVersion: upstream == null
        ? null
        : _manifestVersion(
            requiredString(upstream, 'version'),
            label: 'fluoh.yaml package.release.upstream.version',
          ),
    upstreamRef: upstream == null
        ? null
        : _manifestRef(optionalString(upstream, 'ref')),
    upstreamCommit: upstream == null
        ? null
        : _manifestCommit(requiredString(upstream, 'commit')),
    version: version,
    status: _releaseStatus(optionalString(release, 'status')),
  );
}

String _originKind(String kind) {
  if (const {packageOriginCreated, packageOriginPorted}.contains(kind)) {
    return kind;
  }
  throw const FluohSchemaException(
    'fluoh.yaml origin.kind must be created or ported.',
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
