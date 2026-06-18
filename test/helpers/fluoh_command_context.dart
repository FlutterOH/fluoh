import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

Future<FluohEnvironment> createTestEnvironment() async {
  final root = await Directory.systemTemp.createTemp('fluoh_cmd_');
  addTearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  final home = Directory('${root.path}/home');
  final project = Directory('${root.path}/project');
  await home.create(recursive: true);
  await project.create(recursive: true);

  return FluohEnvironment(
    homeDirectory: home,
    workingDirectory: project,
    processEnvironment: {
      'FLUOH_DEFAULT_SOURCE_URL': Uri.file(
        '${root.path}/missing_default_source',
      ).toString(),
    },
  );
}

Future<Directory> createPackageSourceFixture(Directory parent) async {
  final source = Directory('${parent.path}/package_source');
  await Directory('${source.path}/manifests/camera').create(recursive: true);
  await Directory(
    '${source.path}/manifests/share_plus',
  ).create(recursive: true);

  final sdkRepository = await createTaggedGitRepository(
    Directory('${parent.path}/flutter-ohos-sdk'),
    tag: '3.35.8-ohos-0.0.3',
    readme: '# Mock FlutterOH SDK\n',
  );

  await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: test-flutteroh-source
description: Test source fixture.
repository:
  git:
    url: file:${source.path}

sdk:
  git:
    url: ${sdkRepository.path}
  versions:
    - 3.35.8-ohos-0.0.3

manifests:
  - name: camera
  - name: share_plus
''');

  await File('${source.path}/manifests/camera/fluoh.yaml').writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: ${parent.path}/camera

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
        - version: "0.0.0"
          tag: camera-0.11.0-ohos-3.35-0.0.0
          upstream:
            version: "0.11.0"
            ref: camera-v0.11.0
            commit: "1111111111111111111111111111111111111111"
        - version: "1.0.0"
          tag: camera-0.11.0-ohos-3.35-1.0.0
          upstream:
            version: "0.11.0"
            ref: camera-v0.11.0
            commit: "1111111111111111111111111111111111111111"
''');

  await File('${source.path}/manifests/share_plus/fluoh.yaml').writeAsString('''
schema: 1
kind: manifest

repository:
  git:
    url: ${parent.path}/share_plus

origin:
  kind: ported

upstream:
  git:
    url: https://github.com/fluttercommunity/plus_plugins

package:
  name: share_plus
  path: packages/share_plus/share_plus
  sdks:
    "3.35":
      releases:
        - version: "1.0.0"
          tag: share_plus-9.0.0-ohos-3.35-1.0.0
          upstream:
            version: "9.0.0"
            ref: share_plus-v9.0.0
            commit: "9999999999999999999999999999999999999999"
''');

  return source;
}

Future<void> writeSdkSourceFixture(
  Directory source, {
  required String sdkRepository,
  required Map<String, String> releases,
}) async {
  await source.create(recursive: true);
  final buffer = StringBuffer()
    ..writeln('schema: 1')
    ..writeln('kind: source')
    ..writeln('name: test-flutteroh-source')
    ..writeln('description: Test source fixture.')
    ..writeln()
    ..writeln('repository:')
    ..writeln('  git:')
    ..writeln('    url: file:${source.path}')
    ..writeln()
    ..writeln('sdk:')
    ..writeln('  git:')
    ..writeln('    url: $sdkRepository')
    ..writeln('  versions:');

  for (final entry in releases.entries) {
    buffer.writeln('    - ${entry.key}');
  }

  await File('${source.path}/fluoh.yaml').writeAsString(buffer.toString());
}

Future<void> writeFlutterProjectWithImplementationOverrideFixture(
  Directory project,
) async {
  await writeFlutterProjectFixture(project);
  final pubspec = File('${project.path}/pubspec.yaml');
  await pubspec.writeAsString('''
${await pubspec.readAsString()}
dependency_overrides:
  camera:
    git:
      url: ${project.parent.path}/camera
      ref: camera-0.11.0-ohos-3.35-0
''');
}

Future<void> writeFlutterProjectFixture(Directory project) async {
  await File('${project.path}/pubspec.yaml').writeAsString('''
name: fixture_app

dependencies:
  flutter:
    sdk: flutter
  camera: 0.11.0
  share_plus: 10.0.0
  mystery_package: ^1.0.0

dev_dependencies:
  test: ^1.25.0
''');

  await File('${project.path}/pubspec.lock').writeAsString('''
packages:
  camera:
    dependency: "direct main"
    description:
      name: camera
    source: hosted
    version: "0.11.0"
    dependencies:
      camera_platform_interface: "2.9.0"
  camera_platform_interface:
    dependency: transitive
    description:
      name: camera_platform_interface
    source: hosted
    version: "2.9.0"
  share_plus:
    dependency: "direct main"
    description:
      name: share_plus
    source: hosted
    version: "10.0.0"
  mystery_package:
    dependency: "direct main"
    description:
      name: mystery_package
    source: hosted
    version: "1.0.0"
sdks:
  dart: ">=3.0.0 <4.0.0"
''');
}

Future<Directory> createTaggedGitRepository(
  Directory repo, {
  required String tag,
  required String readme,
}) async {
  await repo.create(recursive: true);
  await _git(repo, ['init', '--initial-branch=main']);
  await _git(repo, ['config', 'user.email', 'fixture@example.com']);
  await _git(repo, ['config', 'user.name', 'Fixture']);
  await File('${repo.path}/README.md').writeAsString(readme);
  await Directory('${repo.path}/bin').create(recursive: true);
  await _writeSdkTool(File('${repo.path}/bin/flutter'));
  await _writeSdkTool(File('${repo.path}/bin/dart'));
  await _git(repo, ['add', '.']);
  await _git(repo, ['commit', '-m', 'Initial fixture']);
  await _git(repo, ['tag', tag]);

  return repo;
}

Future<void> _writeSdkTool(File tool) async {
  final name = tool.uri.pathSegments.last;
  await tool.writeAsString('''
#!/bin/sh
if [ "\$1" = "--version" ]; then
  if [ "$name" = "dart" ]; then
    echo "Dart SDK version: 3.9.2 (stable) (fixture)" >&2
  else
    echo "Flutter 3.35.8-ohos-0.0.3 • fixture"
  fi
  exit 0
fi
if [ "\$1" = "create" ]; then
  mkdir -p ohos
  exit 0
fi
exit 0
''');
  final result = await Process.run('chmod', ['+x', tool.path]);
  if (result.exitCode != 0) {
    fail('chmod +x ${tool.path} failed:\n${result.stderr}');
  }
}

Future<Directory> createUpstreamPackageRepository(
  Directory repo, {
  String packageName = 'camera',
  String version = '0.11.0',
  String sdkConstraint = '^3.0.0',
  String initialBranch = 'main',
  String? licenseContent = _mitLicenseContent,
}) async {
  await repo.create(recursive: true);
  await _git(repo, ['init', '--initial-branch=$initialBranch']);
  await _git(repo, ['config', 'user.email', 'fixture@example.com']);
  await _git(repo, ['config', 'user.name', 'Fixture']);
  await File('${repo.path}/pubspec.yaml').writeAsString('''
name: $packageName
version: $version

environment:
  sdk: "$sdkConstraint"
''');
  await File('${repo.path}/README.md').writeAsString('# $packageName\n');
  if (licenseContent != null) {
    await File('${repo.path}/LICENSE').writeAsString(licenseContent);
  }
  await _git(repo, ['add', '.']);
  await _git(repo, ['commit', '-m', 'Initial package fixture']);

  return repo;
}

Future<Directory> createUpstreamWorkspaceRepository(
  Directory repo, {
  String packagePath = 'packages/camera/camera',
  String packageName = 'camera',
  String version = '0.11.0',
  String sdkConstraint = '^3.0.0',
  String? licenseContent = _mitLicenseContent,
}) async {
  await repo.create(recursive: true);
  await _git(repo, ['init', '--initial-branch=main']);
  await _git(repo, ['config', 'user.email', 'fixture@example.com']);
  await _git(repo, ['config', 'user.name', 'Fixture']);
  final packageDirectory = Directory('${repo.path}/$packagePath');
  await packageDirectory.create(recursive: true);
  await File('${packageDirectory.path}/pubspec.yaml').writeAsString('''
name: $packageName
version: $version

environment:
  sdk: "$sdkConstraint"
''');
  await File('${repo.path}/README.md').writeAsString('# workspace\n');
  if (licenseContent != null) {
    await File('${repo.path}/LICENSE').writeAsString(licenseContent);
  }
  await _git(repo, ['add', '.']);
  await _git(repo, ['commit', '-m', 'Initial workspace fixture']);

  return repo;
}

Future<void> bumpUpstreamPackageVersion(
  Directory repo, {
  required String version,
  String packagePath = '.',
  String? sdkConstraint,
}) async {
  final packageDirectory = packagePath == '.'
      ? repo
      : Directory('${repo.path}/$packagePath');
  final pubspec = File('${packageDirectory.path}/pubspec.yaml');
  final content = await pubspec.readAsString();
  await pubspec.writeAsString(
    _replacePubspecVersionAndSdkConstraint(
      content,
      version: version,
      sdkConstraint: sdkConstraint,
    ),
  );
  await _git(repo, ['add', '.']);
  await _git(repo, ['commit', '-m', 'Release $version']);
}

String _replacePubspecVersionAndSdkConstraint(
  String content, {
  required String version,
  required String? sdkConstraint,
}) {
  var updated = content.replaceFirst(
    RegExp(r'^version:\s+.*$', multiLine: true),
    'version: $version',
  );
  if (sdkConstraint == null) {
    return updated;
  }
  return updated.replaceFirst(
    RegExp(r'^  sdk:\s+.*$', multiLine: true),
    '  sdk: "$sdkConstraint"',
  );
}

Future<void> initializeGitRepository(Directory repo) async {
  await _git(repo, ['init', '--initial-branch=main']);
  await _git(repo, ['config', 'user.email', 'fixture@example.com']);
  await _git(repo, ['config', 'user.name', 'Fixture']);
  await _git(repo, ['add', '.']);
  await _git(repo, ['commit', '-m', 'Initial source fixture']);
}

Future<void> commitAll(Directory repo, {required String message}) async {
  await _git(repo, ['add', '.']);
  await _git(repo, ['commit', '-m', message]);
}

Future<ProcessResult> _git(Directory repo, List<String> arguments) async {
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

const _mitLicenseContent = '''
MIT License

Copyright (c) 2026 Fixture

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software.
''';
