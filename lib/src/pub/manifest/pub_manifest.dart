import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import 'pubspec_package.dart';

const pubManifestSchema = 1;

class PubManifest {
  const PubManifest({
    required this.sdkVersion,
    required this.branch,
    required this.upstreamUrl,
    required this.upstreamRef,
    required this.adapterUrl,
    required this.packages,
    this.upstreamDefaultBranch,
    this.dependencyPolicy = const {},
  });

  final String sdkVersion;
  final String branch;
  final String upstreamUrl;
  final String upstreamRef;
  final String? upstreamDefaultBranch;
  final String adapterUrl;
  final List<PubManifestPackage> packages;
  final Map<String, String> dependencyPolicy;

  String get dependencyUrl => dependencyUrlForAdapterRepository(adapterUrl);

  PubManifestPackage packageForName(String? packageName) {
    if (packageName != null && packageName.trim().isNotEmpty) {
      final name = packageName.trim();
      for (final package in packages) {
        if (package.name == name) {
          return package;
        }
      }
      throw UsageException(
        'Package $name is not registered in fluoh.yaml.',
        '',
      );
    }
    if (packages.length == 1) {
      return packages.single;
    }
    throw UsageException(
      'Multiple packages are registered in fluoh.yaml. Pass '
          '"--package <name>".',
      '',
    );
  }

  PubManifestPackage get primaryPackage => packageForName(null);

  String get packageName => primaryPackage.name;
  String get upstreamVersion => primaryPackage.upstreamVersion;
  String get releaseVersion => primaryPackage.releaseVersion;
  String get releaseTag => primaryPackage.releaseTag(sdkVersion);
  String? get upstreamPath => primaryPackage.upstreamPath;
  String? get dependencyPath => primaryPackage.dependencyPath;
  String? get status => primaryPackage.status;
}

class PubManifestPackage {
  const PubManifestPackage({
    required this.name,
    required this.upstreamVersion,
    required this.releaseVersion,
    this.dependencyPath,
    this.upstreamPath,
    this.status,
  });

  final String name;
  final String upstreamVersion;
  final String releaseVersion;
  final String? dependencyPath;
  final String? upstreamPath;
  final String? status;

  String releaseTag(String sdkVersion) {
    return pubReleaseTagForPackage(
      packageName: name,
      upstreamVersion: upstreamVersion,
      sdkVersion: sdkVersion,
      releaseVersion: releaseVersion,
    );
  }

  PubManifestPackage copyWith({
    String? upstreamVersion,
    String? releaseVersion,
    String? dependencyPath,
    String? upstreamPath,
    String? status,
  }) {
    return PubManifestPackage(
      name: name,
      upstreamVersion: upstreamVersion ?? this.upstreamVersion,
      releaseVersion: releaseVersion ?? this.releaseVersion,
      dependencyPath: dependencyPath ?? this.dependencyPath,
      upstreamPath: upstreamPath ?? this.upstreamPath,
      status: status ?? this.status,
    );
  }
}

String ohosBranchForSdk(String sdkVersion) =>
    'ohos/${sdkVersionSeriesFromSdkVersion(sdkVersion)}';

String pubReleaseTagForPackage({
  required String packageName,
  required String upstreamVersion,
  required String sdkVersion,
  required String releaseVersion,
}) {
  final flutterVersion = _flutterVersionFromSdkVersion(sdkVersion);
  return '$packageName-v$upstreamVersion-ohos-$flutterVersion-$releaseVersion';
}

String sdkVersionSeriesFromSdkVersion(String sdkVersion) {
  final match = RegExp(r'^(\d+)\.(\d+)\.').firstMatch(sdkVersion);
  if (match == null) {
    throw FormatException('Invalid Flutter OHOS SDK version: $sdkVersion');
  }
  return '${match.group(1)}.${match.group(2)}';
}

String dependencyUrlForAdapterRepository(String repository) {
  final trimmed = repository.trim();
  final match = RegExp(r'^git@([^:]+):(.+)$').firstMatch(trimmed);
  if (match == null) {
    return trimmed;
  }
  return 'https://${match.group(1)}/${match.group(2)}';
}

Future<void> writePubManifest({
  required Directory destination,
  required PubspecPackage package,
  required String upstream,
  required String upstreamRef,
  required String packagePath,
  required String sdkVersion,
  required String branch,
  required String adapterUrl,
  String? dependencyPath,
  String? upstreamPath,
  String? upstreamDefaultBranch,
  String releaseVersion = '0.1.0',
  String status = 'experimental',
}) async {
  final manifest = PubManifest(
    sdkVersion: sdkVersion,
    branch: branch,
    upstreamUrl: upstream,
    upstreamRef: upstreamRef,
    upstreamDefaultBranch: upstreamDefaultBranch,
    adapterUrl: adapterUrl,
    dependencyPolicy: const {},
    packages: [
      PubManifestPackage(
        name: package.name,
        upstreamVersion: package.version,
        releaseVersion: releaseVersion,
        dependencyPath: _manifestPath(dependencyPath ?? packagePath),
        upstreamPath: _manifestPath(upstreamPath ?? packagePath),
        status: status,
      ),
    ],
  );
  await writePubManifestFile(destination, manifest);
}

Future<void> writePubManifestFile(
  Directory destination,
  PubManifest manifest,
) async {
  await File(
    '${destination.path}/fluoh.yaml',
  ).writeAsString(_pubManifestContent(manifest));
}

Future<void> addPubManifestPackage({
  required Directory destination,
  required PubspecPackage package,
  required String packagePath,
  String releaseVersion = '0.1.0',
  String status = 'experimental',
}) async {
  final manifest = await readPubManifest(destination);
  if (manifest.packages.any((existing) => existing.name == package.name)) {
    throw UsageException(
      'Package ${package.name} is already registered in fluoh.yaml.',
      '',
    );
  }
  await writePubManifestFile(
    destination,
    PubManifest(
      sdkVersion: manifest.sdkVersion,
      branch: manifest.branch,
      upstreamUrl: manifest.upstreamUrl,
      upstreamRef: manifest.upstreamRef,
      upstreamDefaultBranch: manifest.upstreamDefaultBranch,
      adapterUrl: manifest.adapterUrl,
      dependencyPolicy: manifest.dependencyPolicy,
      packages: [
        ...manifest.packages,
        PubManifestPackage(
          name: package.name,
          upstreamVersion: package.version,
          releaseVersion: releaseVersion,
          dependencyPath: _manifestPath(packagePath),
          upstreamPath: _manifestPath(packagePath),
          status: status,
        ),
      ],
    ),
  );
}

Future<void> updatePubManifestUpstream({
  required Directory destination,
  required String upstreamRef,
  required Map<String, String> packageVersions,
}) async {
  final manifest = await readPubManifest(destination);
  for (final package in manifest.packages) {
    if (!packageVersions.containsKey(package.name)) {
      throw UsageException('Missing upstream version for ${package.name}.', '');
    }
  }
  await writePubManifestFile(
    destination,
    PubManifest(
      sdkVersion: manifest.sdkVersion,
      branch: manifest.branch,
      upstreamUrl: manifest.upstreamUrl,
      upstreamRef: upstreamRef,
      upstreamDefaultBranch: manifest.upstreamDefaultBranch,
      adapterUrl: manifest.adapterUrl,
      dependencyPolicy: manifest.dependencyPolicy,
      packages: [
        for (final package in manifest.packages)
          package.copyWith(upstreamVersion: packageVersions[package.name]),
      ],
    ),
  );
}

String _pubManifestContent(PubManifest manifest) {
  return [
    'schema: $pubManifestSchema',
    '',
    'sdk:',
    '  version: ${manifest.sdkVersion}',
    '',
    if (manifest.dependencyPolicy.isNotEmpty) ...[
      'dependencyPolicy:',
      for (final entry in manifest.dependencyPolicy.entries)
        '  ${entry.key}: ${entry.value}',
      '',
    ],
    'repository:',
    '  url: ${manifest.adapterUrl}',
    '  ref: ${manifest.branch}',
    '',
    'upstream:',
    '  url: ${manifest.upstreamUrl}',
    '  ref: ${manifest.upstreamRef}',
    if (manifest.upstreamDefaultBranch != null)
      '  defaultBranch: ${manifest.upstreamDefaultBranch}',
    '',
    'packages:',
    for (final package in manifest.packages) ...[
      '  ${package.name}:',
      if (package.dependencyPath != null) '    path: ${package.dependencyPath}',
      '    upstream:',
      '      version: ${package.upstreamVersion}',
      if (package.upstreamPath != null) '      path: ${package.upstreamPath}',
      '    release:',
      '      version: ${package.releaseVersion}',
      '      status: ${package.status ?? 'experimental'}',
    ],
    '',
  ].join('\n');
}

String? _manifestPath(String? path) {
  if (path == null || path.isEmpty || path == '.') {
    return null;
  }
  return path;
}

Future<PubManifest> readPubManifest(Directory repository) async {
  final manifest = File('${repository.path}/fluoh.yaml');
  if (!await manifest.exists()) {
    throw UsageException('Missing fluoh.yaml.', '');
  }
  final yaml = loadYaml(await manifest.readAsString());
  if (yaml is! YamlMap) {
    throw UsageException('fluoh.yaml must contain a YAML map.', '');
  }
  _ensurePubManifestSchema(yaml);

  _ensureAllowedKeys(yaml, 'fluoh.yaml', {
    'schema',
    'sdk',
    'dependencyPolicy',
    'repository',
    'upstream',
    'packages',
  });
  final sdk = _requiredMap(yaml, 'sdk');
  final repositoryMap = _requiredMap(yaml, 'repository');
  final upstream = _requiredMap(yaml, 'upstream');
  final packagesMap = _requiredMap(yaml, 'packages');
  _ensureAllowedKeys(sdk, 'fluoh.yaml sdk', {'version'});
  _ensureAllowedKeys(repositoryMap, 'fluoh.yaml repository', {'url', 'ref'});
  _ensureAllowedKeys(upstream, 'fluoh.yaml upstream', {
    'url',
    'ref',
    'defaultBranch',
  });

  final packages = <PubManifestPackage>[];
  for (final entry in packagesMap.entries) {
    final name = entry.key;
    final value = entry.value;
    if (name is! String || name.trim().isEmpty || value is! YamlMap) {
      throw UsageException('fluoh.yaml packages must map names to maps.', '');
    }
    packages.add(_readPackageManifest(name, value));
  }
  if (packages.isEmpty) {
    throw UsageException('fluoh.yaml must register at least one package.', '');
  }

  return PubManifest(
    sdkVersion: _requiredString(sdk, 'version'),
    branch: _requiredString(repositoryMap, 'ref'),
    adapterUrl: _requiredString(repositoryMap, 'url'),
    upstreamUrl: _requiredString(upstream, 'url'),
    upstreamRef: _requiredString(upstream, 'ref'),
    upstreamDefaultBranch: _optionalString(upstream, 'defaultBranch'),
    dependencyPolicy: _optionalStringMap(yaml, 'dependencyPolicy'),
    packages: packages,
  );
}

PubManifestPackage _readPackageManifest(String name, YamlMap package) {
  _ensureAllowedKeys(package, 'fluoh.yaml packages.$name', {
    'path',
    'upstream',
    'release',
  });
  final upstream = _requiredMap(package, 'upstream');
  final release = _requiredMap(package, 'release');
  _ensureAllowedKeys(upstream, 'fluoh.yaml packages.$name.upstream', {
    'version',
    'path',
  });
  _ensureAllowedKeys(release, 'fluoh.yaml packages.$name.release', {
    'version',
    'status',
  });
  return PubManifestPackage(
    name: name,
    dependencyPath: _optionalString(package, 'path'),
    upstreamPath: _optionalString(upstream, 'path'),
    upstreamVersion: _requiredString(upstream, 'version'),
    releaseVersion: _requiredString(release, 'version'),
    status: _optionalString(release, 'status'),
  );
}

void _ensurePubManifestSchema(YamlMap yaml) {
  final schema = yaml['schema'];
  if (schema == null) {
    throw UsageException('fluoh.yaml missing "schema".', '');
  }
  if (schema is! int) {
    throw UsageException('fluoh.yaml schema must be an integer.', '');
  }
  if (schema != pubManifestSchema) {
    throw UsageException(
      'fluoh.yaml schema $schema is not supported for pub repositories. '
          'Expected schema $pubManifestSchema.',
      '',
    );
  }
}

String _flutterVersionFromSdkVersion(String version) {
  final match = RegExp(r'^(.+)-ohos-.+$').firstMatch(version);
  if (match == null) {
    throw FormatException('Invalid Flutter OHOS SDK version: $version');
  }
  return match.group(1)!;
}

YamlMap _requiredMap(YamlMap map, String key) {
  final value = map[key];
  if (value is! YamlMap) {
    throw UsageException('fluoh.yaml missing "$key".', '');
  }
  return value;
}

String _requiredString(YamlMap map, String key) {
  final value = map[key];
  if (value == null || '$value'.isEmpty) {
    throw UsageException('fluoh.yaml missing "$key".', '');
  }
  return '$value';
}

String? _optionalString(YamlMap map, String key) {
  final value = map[key];
  if (value == null || '$value'.isEmpty) {
    return null;
  }
  return '$value';
}

Map<String, String> _optionalStringMap(YamlMap map, String key) {
  final value = map[key];
  if (value == null) {
    return const {};
  }
  if (value is! YamlMap) {
    throw UsageException('$key in fluoh.yaml must be a YAML map.', '');
  }
  return {
    for (final entry in value.entries)
      if (entry.key is String && entry.value != null)
        entry.key as String: '${entry.value}',
  };
}

void _ensureAllowedKeys(YamlMap map, String label, Set<String> allowed) {
  for (final key in map.keys) {
    if (key is! String || !allowed.contains(key)) {
      throw UsageException('$label must not contain "$key".', '');
    }
  }
}
