import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import 'pubspec_package.dart';

class PubManifest {
  const PubManifest({
    required this.packageName,
    required this.upstreamVersion,
    required this.sdkVersion,
    required this.releaseVersion,
    required this.branch,
    required this.releaseTag,
    required this.upstreamUrl,
    required this.adapterUrl,
    required this.dependencyUrl,
    this.upstreamPath,
    this.upstreamRef,
    this.dependencyPath,
    this.status,
  });

  final String packageName;
  final String upstreamVersion;
  final String sdkVersion;
  final String releaseVersion;
  final String branch;
  final String releaseTag;
  final String upstreamUrl;
  final String? upstreamPath;
  final String? upstreamRef;
  final String adapterUrl;
  final String dependencyUrl;
  final String? dependencyPath;
  final String? status;
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
  return '${_flutterVersionFromSdkVersion(sdkVersion)}-ohos';
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
  String releaseVersion = '0.1.0',
  String status = 'experimental',
}) async {
  final tag = pubReleaseTagForPackage(
    packageName: package.name,
    upstreamVersion: package.version,
    sdkVersion: sdkVersion,
    releaseVersion: releaseVersion,
  );
  final path = packagePath == '.' || packagePath.isEmpty ? null : packagePath;
  await File('${destination.path}/fluoh.yaml').writeAsString(
    [
      'schema: 1',
      'name: ${package.name}',
      '',
      'upstream:',
      '  type: git',
      '  url: $upstream',
      if (path != null) '  path: $path',
      '  ref: $upstreamRef',
      '  version: ${package.version}',
      '',
      'fluoh:',
      '  type: git',
      '  url: $adapterUrl',
      '  branch: $branch',
      '  sdkVersion: $sdkVersion',
      '  status: $status',
      '  release:',
      '    version: $releaseVersion',
      '    tag: $tag',
      '',
    ].join('\n'),
  );
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

  final upstream = _requiredMap(yaml, 'upstream');
  final fluoh = _requiredMap(yaml, 'fluoh');
  if (yaml.containsKey('dependency')) {
    throw UsageException('fluoh.yaml must not contain "dependency".', '');
  }
  final release = _requiredMap(fluoh, 'release');
  final upstreamPath = _optionalString(upstream, 'path');
  final adapterUrl = _requiredString(fluoh, 'url');

  return PubManifest(
    packageName: _requiredString(yaml, 'name'),
    upstreamVersion: _requiredString(upstream, 'version'),
    sdkVersion: _requiredString(fluoh, 'sdkVersion'),
    releaseVersion: _requiredString(release, 'version'),
    branch: _requiredString(fluoh, 'branch'),
    releaseTag: _requiredString(release, 'tag'),
    upstreamUrl: _requiredString(upstream, 'url'),
    upstreamPath: upstreamPath,
    upstreamRef: _optionalString(upstream, 'ref'),
    adapterUrl: adapterUrl,
    dependencyUrl: dependencyUrlForAdapterRepository(adapterUrl),
    dependencyPath: upstreamPath,
    status: _optionalString(fluoh, 'status'),
  );
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
