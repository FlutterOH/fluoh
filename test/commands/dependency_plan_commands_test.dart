import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:fluoh/src/schema/source_index.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

part 'dependency_plan_commands_core_part.dart';
part 'dependency_plan_commands_policy_part.dart';

void main() {
  _registerDependencyPlanCommandCoreTests();
  _registerDependencyPlanCommandPolicyTests();
}

Future<FluohEnvironment> _preparedEnvironment() async {
  final environment = await createTestEnvironment();
  final source = await createPackageSourceFixture(environment.homeDirectory);
  await writeFlutterProjectFixture(environment.workingDirectory);
  final stdout = <String>[];
  final stderr = <String>[];

  await runFluoh(
    ['source', 'enable', 'fixture', source.path],
    environment: environment,
    stdout: stdout.add,
    stderr: stderr.add,
  );
  await runFluoh(
    ['sdk', 'use', '3.35.8-ohos-0.0.3'],
    environment: environment,
    stdout: stdout.add,
    stderr: stderr.add,
  );

  return environment;
}

void _expectOutputContains(List<String> output, String expected) {
  expect(
    _normalizeOutput(output.join('\n')),
    contains(_normalizeOutput(expected)),
  );
}

String _normalizeOutput(String value) {
  return value
      .replaceAll(RegExp(r'(?<=[/-])\s+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Future<void> _writeCameraOnlyProjectFixture(Directory project) async {
  await File('${project.path}/pubspec.yaml').writeAsString('''
name: fixture_app

dependencies:
  flutter:
    sdk: flutter
  camera: 0.11.0
''');

  await File('${project.path}/pubspec.lock').writeAsString('''
packages:
  camera:
    dependency: "direct main"
    description:
      name: camera
    source: hosted
    version: "0.11.0"
sdks:
  dart: ">=3.0.0 <4.0.0"
''');
}

String _lockSourceSnapshotHash(File lockFile, String sourceName) {
  final lock = jsonDecode(lockFile.readAsStringSync()) as Map<String, Object?>;
  final fingerprint = lock['fingerprint'] as Map<String, Object?>;
  final sources = fingerprint['sources'] as List<Object?>;
  final source = sources.cast<Map<String, Object?>>().singleWhere(
    (source) => source['name'] == sourceName,
  );
  return source['snapshotHash'] as String;
}

Future<void> _writeSnapshotStateForCurrentFingerprint(
  Directory root, {
  required String snapshotHash,
}) async {
  final state = {
    'stateVersion': 1,
    'generatedBy': 'fixture',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'fingerprint': await _snapshotFingerprint(root),
    'snapshotHash': snapshotHash,
  };
  await File(
    '${root.path}/.fluoh-source-state.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(state)}\n');
}

Future<Map<String, Object?>> _snapshotFingerprint(Directory root) async {
  final entries = <Map<String, Object?>>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final relative = _relativePath(root, entity);
    if (relative == '.fluoh-source-state.json') {
      continue;
    }
    final stat = await entity.stat();
    entries.add({
      'path': relative,
      'size': stat.size,
      'modified': stat.modified.toUtc().microsecondsSinceEpoch,
    });
  }
  entries.sort((a, b) => '${a['path']}'.compareTo('${b['path']}'));
  return {'files': entries};
}

String _relativePath(Directory root, FileSystemEntity entity) {
  final rootPath = root.absolute.path;
  final entityPath = entity.absolute.path;
  if (entityPath == rootPath) {
    return '';
  }
  return entityPath.substring(rootPath.length + 1);
}

Future<void> _setImplementationStatus(
  Directory source, {
  required String packageName,
  required String status,
}) async {
  await _writeImplementationManifest(
    source,
    repositoryName: packageName,
    packageName: packageName,
    repositoryUrl: '${source.parent.path}/$packageName',
    upstreamUrl: 'https://github.com/flutter/packages',
    packagePath: 'packages/$packageName/$packageName',
    upstreamVersion: packageName == 'camera' ? '0.11.0' : '1.0.0',
    upstreamRef: packageName == 'camera' ? 'camera-v0.11.0' : 'v1.0.0',
    implementationRef: packageName == 'camera'
        ? 'camera-0.11.0-ohos-3.35-1.0.0'
        : '$packageName-1.0.0-ohos-3.35-1.0.0',
    status: status,
  );
}

Future<void> _appendImplementationVersion(
  Directory source, {
  required String packageName,
  required String upstreamVersion,
  required String upstreamRef,
  required String implementationRef,
}) async {
  final manifest = File('${source.path}/manifests/$packageName/fluoh.yaml');
  final releaseVersion =
      RegExp(
        r'-([0-9]+(?:\.[0-9]+)*)$',
      ).firstMatch(implementationRef)?.group(1) ??
      '1';
  final content = manifest.readAsStringSync();
  await manifest.writeAsString(
    '$content'
    '        - version: $releaseVersion\n'
    '          tag: $implementationRef\n'
    '          upstream:\n'
    '            version: $upstreamVersion\n'
    '            ref: $upstreamRef\n'
    '            commit: "1111111111111111111111111111111111111111"\n',
  );
}

Future<void> _copySdkMetadata({
  required Directory from,
  required Directory to,
}) async {
  final fromContent = File('${from.path}/fluoh.yaml').readAsStringSync();
  final toFile = File('${to.path}/fluoh.yaml');
  final toContent = toFile.readAsStringSync();
  final sdkPattern = RegExp(r'\nsdk:\n[\s\S]*?\n\nmanifests:');
  final sdk = sdkPattern.firstMatch(fromContent)!.group(0)!;
  await toFile.writeAsString(toContent.replaceFirst(sdkPattern, sdk));
}

Future<void> _addRepositoryPackage(
  Directory source, {
  required String packageName,
  required String repositoryUrl,
  required String upstreamUrl,
  required String packagePath,
  required String upstreamVersion,
  required String upstreamRef,
  required String implementationRef,
}) async {
  final root = File('${source.path}/fluoh.yaml');
  final manifest = parseSourceRootManifest(root.readAsStringSync());
  await root.writeAsString(
    sourceRootManifestContent(
      SourceRootManifestTemplate(
        name: manifest.name,
        description: manifest.description,
        repositoryGitUrl: manifest.repositoryGitUrl,
        sdkRepository: manifest.sdkRepository,
        sdkReleases: manifest.sdkReleases,
        manifests: [
          ...manifest.manifests,
          SourceManifestRoute(name: packageName),
        ],
      ),
    ),
  );
  await _writeImplementationManifest(
    source,
    repositoryName: packageName,
    packageName: packageName,
    repositoryUrl: repositoryUrl,
    upstreamUrl: upstreamUrl,
    packagePath: packagePath,
    upstreamVersion: upstreamVersion,
    upstreamRef: upstreamRef,
    implementationRef: implementationRef,
    status: 'compatible',
  );
}

Future<void> _writePackageOnlySource(
  Directory source, {
  required String packageName,
  required String repositoryUrl,
  required String upstreamUrl,
  required String packagePath,
  required String upstreamVersion,
  required String upstreamRef,
  required String implementationRef,
}) async {
  await source.create(recursive: true);
  await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: team-source
description: Team source.

repository:
  git:
    url: file:${source.path}

manifests:
  - name: $packageName
''');
  await _writeImplementationManifest(
    source,
    repositoryName: packageName,
    packageName: packageName,
    repositoryUrl: repositoryUrl,
    upstreamUrl: upstreamUrl,
    packagePath: packagePath,
    upstreamVersion: upstreamVersion,
    upstreamRef: upstreamRef,
    implementationRef: implementationRef,
    status: 'compatible',
  );
}

Future<void> _writeImplementationManifest(
  Directory source, {
  required String repositoryName,
  required String packageName,
  required String repositoryUrl,
  required String upstreamUrl,
  required String packagePath,
  required String upstreamVersion,
  required String upstreamRef,
  required String implementationRef,
  required String status,
}) async {
  final repository = Directory('${source.path}/manifests/$repositoryName');
  await repository.create(recursive: true);
  final releaseVersion =
      RegExp(
        r'-([0-9]+(?:\.[0-9]+)*)$',
      ).firstMatch(implementationRef)?.group(1) ??
      '1.0.0';
  await File('${repository.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: $repositoryUrl

origin:
  kind: ported

upstream:
  git:
    url: $upstreamUrl

package:
  name: $packageName
  path: $packagePath
  sdks:
    "3.35":
      releases:
        - version: $releaseVersion
          tag: $implementationRef
          upstream:
            version: $upstreamVersion
            ref: $upstreamRef
            commit: "1111111111111111111111111111111111111111"
${status == 'compatible' ? '' : '          status: $status\n'}
''');
}
