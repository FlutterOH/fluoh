import 'pubspec.dart';
import 'version_rules.dart';
import 'yaml_utils.dart';

const pubManifestSchema = 1;
const initialPubReleaseVersion = '0.1.0';
const defaultUpstreamBranch = 'main';

class PubRepositoryManifest {
  const PubRepositoryManifest({
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

  factory PubRepositoryManifest.parse(String content) {
    final yaml = parseYamlMap(content, label: 'fluoh.yaml');
    _ensurePubManifestSchema(yaml);

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

    final packages = <PubRepositoryManifestPackage>[];
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

    return PubRepositoryManifest(
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

  final String name;
  final String sdkVersion;
  final String repositoryUrl;
  final String repositoryBranch;
  final String repositoryPath;
  final String upstreamUrl;
  final String upstreamBranch;
  final String upstreamPath;
  final List<PubRepositoryManifestPackage> packages;

  String get dependencyUrl =>
      dependencyUrlForImplementationRepository(repositoryUrl);

  String get branch => repositoryBranch;

  PubRepositoryManifestPackage packageForName(String? packageName) {
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

  PubRepositoryManifestPackage get primaryPackage => packageForName(null);

  String get packageName => primaryPackage.name;
  String get upstreamVersion => primaryPackage.upstreamVersion;
  String get releaseVersion => primaryPackage.version;
  String get releaseTag => primaryPackage.releaseTag(sdkVersion);
  String get upstreamPackagePath => primaryPackage.upstreamPath;
  String get repositoryPackagePath => primaryPackage.repositoryPath;
  String get dependencyPath => primaryPackage.repositoryPath;
  String? get status => primaryPackage.status;
}

typedef PubManifest = PubRepositoryManifest;

class PubRepositoryManifestPackage {
  const PubRepositoryManifestPackage({
    required this.name,
    required this.upstreamVersion,
    required this.version,
    this.repositoryPath = '.',
    this.upstreamPath = '.',
    this.status,
  });

  final String name;
  final String upstreamVersion;
  final String version;
  final String repositoryPath;
  final String upstreamPath;
  final String? status;

  String get releaseVersion => version;
  String get dependencyPath => repositoryPath;

  String releaseTag(String sdkVersion) {
    validateReleaseVersion(version);
    return pubReleaseTagForPackage(
      packageName: name,
      upstreamVersion: upstreamVersion,
      sdkVersion: sdkVersion,
      releaseVersion: version,
    );
  }

  PubRepositoryManifestPackage copyWith({
    String? upstreamVersion,
    String? version,
    String? repositoryPath,
    String? upstreamPath,
    String? status,
  }) {
    return PubRepositoryManifestPackage(
      name: name,
      upstreamVersion: upstreamVersion ?? this.upstreamVersion,
      version: version ?? this.version,
      repositoryPath: repositoryPath ?? this.repositoryPath,
      upstreamPath: upstreamPath ?? this.upstreamPath,
      status: status ?? this.status,
    );
  }
}

typedef PubManifestPackage = PubRepositoryManifestPackage;

PubRepositoryManifest createPubRepositoryManifest({
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
  String releaseVersion = initialPubReleaseVersion,
  String status = 'experimental',
}) {
  return PubRepositoryManifest(
    name: name ?? package.name,
    sdkVersion: sdkVersion,
    repositoryBranch: branch,
    upstreamUrl: upstream,
    upstreamBranch: upstreamBranch,
    repositoryUrl: repositoryUrl,
    packages: [
      PubRepositoryManifestPackage(
        name: package.name,
        upstreamVersion: package.version,
        version: releaseVersion,
        repositoryPath: _manifestPath(repositoryPath ?? packagePath),
        upstreamPath: _manifestPath(upstreamPath ?? packagePath),
        status: status,
      ),
    ],
  );
}

PubRepositoryManifest addPubRepositoryManifestPackage({
  required PubRepositoryManifest manifest,
  required PubspecPackage package,
  required String packagePath,
  String releaseVersion = initialPubReleaseVersion,
  String status = 'experimental',
}) {
  if (manifest.packages.any((existing) => existing.name == package.name)) {
    throw FluohSchemaException(
      'Package ${package.name} is already registered in fluoh.yaml.',
    );
  }
  return PubRepositoryManifest(
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
      PubRepositoryManifestPackage(
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

PubRepositoryManifest updatePubRepositoryManifestUpstream({
  required PubRepositoryManifest manifest,
  required Map<String, String> packageVersions,
}) {
  for (final package in manifest.packages) {
    if (!packageVersions.containsKey(package.name)) {
      throw FluohSchemaException(
        'Missing upstream version for ${package.name}.',
      );
    }
  }
  return PubRepositoryManifest(
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

String pubRepositoryManifestContent(PubRepositoryManifest manifest) {
  for (final package in manifest.packages) {
    validateReleaseVersion(
      package.version,
      label: 'fluoh.yaml packages.${package.name}.version',
    );
  }
  return [
    'schema: $pubManifestSchema',
    'name: ${_yamlScalar(manifest.name)}',
    '',
    'sdk:',
    '  version: ${manifest.sdkVersion}',
    '',
    'repository:',
    '  git:',
    '    url: ${_yamlScalar(manifest.repositoryUrl)}',
    '    branch: ${_yamlScalar(manifest.repositoryBranch)}',
    if (manifest.repositoryPath != '.')
      '    path: ${_yamlScalar(manifest.repositoryPath)}',
    '',
    'upstream:',
    '  git:',
    '    url: ${_yamlScalar(manifest.upstreamUrl)}',
    if (manifest.upstreamBranch != defaultUpstreamBranch)
      '    branch: ${_yamlScalar(manifest.upstreamBranch)}',
    if (manifest.upstreamPath != '.')
      '    path: ${_yamlScalar(manifest.upstreamPath)}',
    '',
    'packages:',
    for (final package in manifest.packages) ...[
      '  ${package.name}:',
      if (package.repositoryPath != manifest.repositoryPath) ...[
        '    repository:',
        '      path: ${_yamlScalar(package.repositoryPath)}',
      ],
      if (package.upstreamPath != manifest.upstreamPath) ...[
        '    upstream:',
        '      path: ${_yamlScalar(package.upstreamPath)}',
      ],
      '    version: ${_yamlScalar(package.version)}',
      '    upstreamVersion: ${_yamlScalar(package.upstreamVersion)}',
      if (package.status != null && package.status != 'compatible')
        '    status: ${package.status}',
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

PubRepositoryManifestPackage _readPackageManifest(
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
  return PubRepositoryManifestPackage(
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

void _ensurePubManifestSchema(Map<String, Object?> yaml) {
  final schema = yaml['schema'];
  if (schema == null) {
    throw const FluohSchemaException('fluoh.yaml missing "schema".');
  }
  if (schema is! int) {
    throw const FluohSchemaException('fluoh.yaml schema must be an integer.');
  }
  if (schema != pubManifestSchema) {
    throw FluohSchemaException(
      'fluoh.yaml schema $schema is not supported for pub repositories. '
      'Expected schema $pubManifestSchema.',
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
  if (value.contains(RegExp(r'[\s:]'))) {
    return true;
  }
  if (const {'true', 'false', 'null', '~'}.contains(value.toLowerCase())) {
    return true;
  }
  return false;
}
