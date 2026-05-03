import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

class PackageInfo {
  const PackageInfo({required this.name, required this.version});

  final String name;
  final String version;
}

class AdapterManifest {
  const AdapterManifest({
    required this.packageName,
    required this.upstreamVersion,
    required this.sdkVersion,
    required this.adapterVersion,
    required this.branch,
    required this.releaseTag,
    required this.upstreamUrl,
    required this.flutterOhUrl,
    required this.replacementUrl,
    this.upstreamPath,
    this.upstreamRef,
    this.replacementPath,
    this.status,
  });

  final String packageName;
  final String upstreamVersion;
  final String sdkVersion;
  final String adapterVersion;
  final String branch;
  final String releaseTag;
  final String upstreamUrl;
  final String? upstreamPath;
  final String? upstreamRef;
  final String flutterOhUrl;
  final String replacementUrl;
  final String? replacementPath;
  final String? status;
}

String adapterBranchForSdk(String sdkVersion) => 'ohos/$sdkVersion';

String releaseTagForAdapter({
  required String packageName,
  required String upstreamVersion,
  required String sdkVersion,
  required String adapterVersion,
}) {
  return '$packageName-v$upstreamVersion-ohos-$sdkVersion-$adapterVersion';
}

Directory packageDirectory(Directory repository, String packagePath) {
  if (packagePath == '.' || packagePath.isEmpty) {
    return repository;
  }
  return Directory('${repository.path}/$packagePath');
}

Future<PackageInfo> readPackageInfo(Directory repository) async {
  final pubspec = File('${repository.path}/pubspec.yaml');
  if (!await pubspec.exists()) {
    throw UsageException('Missing pubspec.yaml in upstream repository.', '');
  }
  final yaml = loadYaml(await pubspec.readAsString());
  if (yaml is! YamlMap) {
    throw UsageException('pubspec.yaml must contain a YAML map.', '');
  }
  final name = yaml['name'];
  final version = yaml['version'];
  if (name is! String || version is! String) {
    throw UsageException('pubspec.yaml must contain name and version.', '');
  }
  return PackageInfo(name: name, version: version);
}

Future<String> findPackagePath(Directory repository, String packageName) async {
  await for (final entity in repository.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('/pubspec.yaml')) {
      continue;
    }
    if (entity.path.contains('/.git/')) {
      continue;
    }
    final package = await readPackageInfo(entity.parent);
    if (package.name == packageName) {
      final relative = entity.parent.path.substring(repository.path.length);
      final normalized = relative.startsWith('/')
          ? relative.substring(1)
          : relative;
      return normalized.isEmpty ? '.' : normalized;
    }
  }
  throw UsageException(
    'Package $packageName was not found in upstream repository.',
    '',
  );
}

Future<void> writeAdapterManifest({
  required Directory destination,
  required PackageInfo package,
  required String upstream,
  required String upstreamRef,
  required String packagePath,
  required String sdkVersion,
  required String branch,
  required String flutterOhUrl,
  String adapterVersion = '0.1.0',
  String status = 'experimental',
}) async {
  final tag = releaseTagForAdapter(
    packageName: package.name,
    upstreamVersion: package.version,
    sdkVersion: sdkVersion,
    adapterVersion: adapterVersion,
  );
  final path = packagePath == '.' || packagePath.isEmpty ? null : packagePath;
  await File('${destination.path}/fluoh.yaml').writeAsString(
    [
      'schema: 1',
      '',
      'package:',
      '  name: ${package.name}',
      '  upstream:',
      '    type: git',
      '    url: $upstream',
      if (path != null) '    path: $path',
      '    ref: $upstreamRef',
      '    version: ${package.version}',
      '',
      'flutteroh:',
      '  url: $flutterOhUrl',
      '  branch: $branch',
      '  release:',
      '    version: $adapterVersion',
      '    tag: $tag',
      '',
      'sdk:',
      '  version: $sdkVersion',
      '',
      'status: $status',
      '',
      'replacement:',
      '  source: git',
      '  url: $flutterOhUrl',
      '  ref: $tag',
      if (path != null) '  path: $path',
      '',
      'notes:',
      '  summary: Adds OpenHarmony platform implementation.',
      '',
    ].join('\n'),
  );
}

Future<AdapterManifest> readAdapterManifest(Directory repository) async {
  final manifest = File('${repository.path}/fluoh.yaml');
  if (!await manifest.exists()) {
    throw UsageException('Missing fluoh.yaml.', '');
  }
  final yaml = loadYaml(await manifest.readAsString());
  if (yaml is! YamlMap) {
    throw UsageException('fluoh.yaml must contain a YAML map.', '');
  }

  final package = _requiredMap(yaml, 'package');
  final upstream = _requiredMap(package, 'upstream');
  final sdk = _requiredMap(yaml, 'sdk');
  final flutteroh = _requiredMap(yaml, 'flutteroh');
  final release = _requiredMap(flutteroh, 'release');
  final replacement = _requiredMap(yaml, 'replacement');

  return AdapterManifest(
    packageName: _requiredString(package, 'name'),
    upstreamVersion: _requiredString(upstream, 'version'),
    sdkVersion: _requiredString(sdk, 'version'),
    adapterVersion: _requiredString(release, 'version'),
    branch: _requiredString(flutteroh, 'branch'),
    releaseTag: _requiredString(release, 'tag'),
    upstreamUrl: _requiredString(upstream, 'url'),
    upstreamPath: _optionalString(upstream, 'path'),
    upstreamRef: _optionalString(upstream, 'ref'),
    flutterOhUrl: _requiredString(flutteroh, 'url'),
    replacementUrl: _requiredString(replacement, 'url'),
    replacementPath: _optionalString(replacement, 'path'),
    status: _optionalString(yaml, 'status'),
  );
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
