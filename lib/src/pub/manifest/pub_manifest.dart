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
  final String releaseVersion;
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

String ohosBranchForSdk(String sdkVersion) => 'ohos/$sdkVersion';

String pubReleaseTagForPackage({
  required String packageName,
  required String upstreamVersion,
  required String sdkVersion,
  required String releaseVersion,
}) {
  return '$packageName-v$upstreamVersion-ohos-$sdkVersion-$releaseVersion';
}

Future<void> writePubManifest({
  required Directory destination,
  required PubspecPackage package,
  required String upstream,
  required String upstreamRef,
  required String packagePath,
  required String sdkVersion,
  required String branch,
  required String flutterOhUrl,
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
      '    version: $releaseVersion',
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

Future<PubManifest> readPubManifest(Directory repository) async {
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

  return PubManifest(
    packageName: _requiredString(package, 'name'),
    upstreamVersion: _requiredString(upstream, 'version'),
    sdkVersion: _requiredString(sdk, 'version'),
    releaseVersion: _requiredString(release, 'version'),
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
