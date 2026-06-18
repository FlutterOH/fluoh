import 'dart:io';
import 'dart:convert';

import 'package:fluoh/fluoh.dart';
import 'package:fluoh/src/schema/schema.dart' show sdkLineFromSdkVersion;
import 'package:fluoh/src/source/source_runtime.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

part 'source_command_config_part.dart';
part 'source_command_sync_part.dart';
part 'source_command_check_part.dart';
part 'source_command_update_part.dart';
part 'source_command_cache_part.dart';

void main() {
  _registerSourceCommandConfigTests();
  _registerSourceCommandSyncTests();
  _registerSourceCommandCheckTests();
  _registerSourceCommandUpdateTests();
  _registerSourceCommandCacheTests();
}

Future<void> _writeCameraSourceManifest(
  Directory source,
  Directory packageRepository, {
  required List<(String, String)> releases,
  String? advisory,
  String packagePath = 'packages/camera/camera',
}) async {
  await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

manifests:
  - name: camera
''');
  final manifest = File('${source.path}/manifests/camera/fluoh.yaml');
  await manifest.parent.create(recursive: true);
  await manifest.writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: ${packageRepository.path}

origin:
  kind: ported

upstream:
  git:
    url: https://github.com/flutter/packages

package:
  name: camera
  path: $packagePath
${advisory == null ? '' : '  advisory:\n    message: "$advisory"\n'}  sdks:
    "3.35":
      releases:
${releases.map((release) => '        - version: "${release.$1}"\n          tag: camera-${release.$2}-ohos-3.35-${release.$1}\n          upstream:\n            version: "${release.$2}"\n            ref: "1111111111111111111111111111111111111111"\n            commit: "1111111111111111111111111111111111111111"').join('\n')}
''');
}

Future<void> _writeCameraSourceManifestRaw(
  Directory source,
  Directory packageRepository, {
  required String releaseYaml,
  String packagePath = 'packages/camera/camera',
}) async {
  await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-source

manifests:
  - name: camera
''');
  final manifest = File('${source.path}/manifests/camera/fluoh.yaml');
  await manifest.parent.create(recursive: true);
  await manifest.writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: ${packageRepository.path}

origin:
  kind: ported

upstream:
  git:
    url: https://github.com/flutter/packages

package:
  name: camera
  path: $packagePath
  sdks:
    "3.35":
      releases:
$releaseYaml
''');
}

Future<void> _writeSimpleSourceManifest(
  Directory source,
  String manifestName,
) async {
  final manifest = File('${source.path}/manifests/$manifestName/fluoh.yaml');
  await manifest.parent.create(recursive: true);
  await manifest.writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: file:${source.path}/../${manifestName}_repo

origin:
  kind: ported

upstream:
  git:
    url: https://github.com/flutter/packages

package:
  name: $manifestName
  path: packages/$manifestName/$manifestName
  sdks:
    "3.35":
      releases:
        - version: "1.0.0"
          tag: $manifestName-1.0.0-ohos-3.35-1.0.0
          upstream:
            version: "1.0.0"
            ref: $manifestName-v1.0.0
            commit: "1111111111111111111111111111111111111111"
''');
}

Future<void> _writePackageManifest(
  Directory repository, {
  String? repositoryUrl,
  String name = 'packages',
  String packageName = 'camera',
  String packagePath = 'packages/camera/camera',
  String sdkVersion = '3.35.8-ohos-0.0.3',
  String releaseVersion = '0.2.0',
  String upstreamVersion = '0.11.0',
  String? upstreamRef,
  String upstreamCommit = '1111111111111111111111111111111111111111',
  String upstreamBranch = 'main',
}) async {
  repositoryUrl ??= 'file:${repository.path}';
  final sdkLine = sdkLineFromSdkVersion(sdkVersion);
  await repository.create(recursive: true);
  final upstreamRefLine = upstreamRef == null
      ? ''
      : '      ref: "$upstreamRef"\n';
  await File('${repository.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: package

sdk:
  version: $sdkVersion

repository:
  git:
    url: "$repositoryUrl"
    branch: ohos/$sdkLine/$packageName

origin:
  kind: ported

upstream:
  git:
    url: https://github.com/flutter/packages
    branch: $upstreamBranch

package:
  name: $packageName
  path: $packagePath
  release:
    version: "$releaseVersion"
    upstream:
      version: "$upstreamVersion"
$upstreamRefLine      commit: "$upstreamCommit"
''');
}

Future<void> _writeSourceSyncManifest(
  Directory source,
  Directory repository, {
  String? repositoryUrl,
  String manifestName = 'camera',
  List<String>? sdkVersions,
}) async {
  repositoryUrl ??= 'file:${repository.path}';
  final sdkLines = sdkVersions == null
      ? ''
      : '''

sdk:
  git:
    url: /tmp/flutter-ohos-sdk
  versions:
${sdkVersions.map((version) => '    - $version').join('\n')}
''';
  await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: local-flutteroh-source

repository:
  git:
    url: "file:${source.path}"
$sdkLines

manifests:
  - name: $manifestName
''');
  final manifest = File('${source.path}/manifests/$manifestName/fluoh.yaml');
  await manifest.parent.create(recursive: true);
  await manifest.writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: "$repositoryUrl"

origin:
  kind: ported

upstream:
  git:
    url: https://github.com/flutter/packages

package:
  name: camera
  path: packages/camera/camera
  sdks:
    "3.35":
      releases:
        - version: 0.1.0
          tag: camera-0.10.0-ohos-3.35-0.1.0
          upstream:
            version: 0.10.0
            ref: camera-v0.10.0
            commit: "1111111111111111111111111111111111111111"
''');
}

Future<File> _writeFakeSourceCheckFluoh(Directory root) async {
  final tool = File('${root.path}/fluoh-source-check');
  await tool.writeAsString(r'''
#!/bin/sh
if [ "$1" = "package" ] && [ "$2" = "check" ] && [ "$3" = "--package" ] && [ "$5" = "--json" ]; then
  printf '{"schema":1,"command":"package check","ok":true,"exitCode":0,"tags":["%s-0.11.0-ohos-3.35-1.0.0"]}\n' "$4"
  exit 0
fi
echo "unexpected args: $@" >&2
exit 64
''');
  final chmod = await Process.run('chmod', ['+x', tool.path]);
  expect(chmod.exitCode, 0, reason: chmod.stderr.toString());
  return tool;
}

Map<String, Object?> _readJsonObject(File file) {
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

String _lockSourceSnapshotHash(File lockFile, String sourceName) {
  final lock = _readJsonObject(lockFile);
  final fingerprint = lock['fingerprint'] as Map<String, Object?>;
  final sources = fingerprint['sources'] as List<Object?>;
  final source = sources.cast<Map<String, Object?>>().singleWhere(
    (source) => source['name'] == sourceName,
  );
  return source['snapshotHash'] as String;
}

Future<ProcessResult> _runGit(Directory repo, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: repo.path,
  );
  if (result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed:\n${result.stderr}');
  }
  return result;
}
