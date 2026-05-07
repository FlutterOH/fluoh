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
  String releaseVersion = '0.1.0',
  String status = 'experimental',
}) async {
  final path = packagePath == '.' || packagePath.isEmpty ? null : packagePath;
  await File('${destination.path}/fluoh.yaml').writeAsString(
    [
      'schema: 1',
      'name: ${package.name}',
      '',
      'upstream:',
      '  url: $upstream',
      if (path != null) '  path: $path',
      '  ref: $upstreamRef',
      '  version: ${package.version}',
      '',
      'fluoh:',
      '  url: $adapterUrl',
      '  sdkVersion: $sdkVersion',
      '  status: $status',
      '  release:',
      '    version: $releaseVersion',
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

  _ensureAllowedKeys(yaml, 'fluoh.yaml', {
    'schema',
    'name',
    'upstream',
    'fluoh',
  });
  final upstream = _requiredMap(yaml, 'upstream');
  final fluoh = _requiredMap(yaml, 'fluoh');
  final release = _requiredMap(fluoh, 'release');
  _ensureAllowedKeys(upstream, 'fluoh.yaml upstream', {
    'url',
    'path',
    'ref',
    'version',
  });
  _ensureAllowedKeys(fluoh, 'fluoh.yaml fluoh', {
    'url',
    'sdkVersion',
    'status',
    'release',
  });
  _ensureAllowedKeys(release, 'fluoh.yaml fluoh.release', {'version'});
  final upstreamPath = _optionalString(upstream, 'path');
  final adapterUrl = _requiredString(fluoh, 'url');
  final sdkVersion = _requiredString(fluoh, 'sdkVersion');
  final upstreamVersion = _requiredString(upstream, 'version');
  final releaseVersion = _requiredString(release, 'version');
  final packageName = _requiredString(yaml, 'name');

  return PubManifest(
    packageName: packageName,
    upstreamVersion: upstreamVersion,
    sdkVersion: sdkVersion,
    releaseVersion: releaseVersion,
    branch: ohosBranchForSdk(sdkVersion),
    releaseTag: pubReleaseTagForPackage(
      packageName: packageName,
      upstreamVersion: upstreamVersion,
      sdkVersion: sdkVersion,
      releaseVersion: releaseVersion,
    ),
    upstreamUrl: _requiredString(upstream, 'url'),
    upstreamPath: upstreamPath,
    upstreamRef: _requiredString(upstream, 'ref'),
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

void _ensureAllowedKeys(YamlMap map, String label, Set<String> allowed) {
  for (final key in map.keys) {
    if (key is! String || !allowed.contains(key)) {
      throw UsageException('$label must not contain "$key".', '');
    }
  }
}
