import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

Future<FluohEnvironment> createTestEnvironment() async {
  final root = await Directory.systemTemp.createTemp('fluoh_test_');
  addTearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  final home = Directory('${root.path}/home');
  final project = Directory('${root.path}/project');
  await home.create(recursive: true);
  await project.create(recursive: true);

  return FluohEnvironment(homeDirectory: home, workingDirectory: project);
}

Future<Directory> createPubSourceFixture(Directory parent) async {
  final source = Directory('${parent.path}/pub_source');
  await Directory('${source.path}/manifests/camera').create(recursive: true);
  await Directory(
    '${source.path}/manifests/share_plus',
  ).create(recursive: true);

  final sdkRepository = await createTaggedGitRepository(
    Directory('${parent.path}/flutter-ohos-sdk'),
    tag: '3.35.8-ohos-0.0.3',
    readme: '# Mock Flutter OHOS SDK\n',
  );

  await File('${source.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: Test FlutterOH source
description: Test source fixture.
repository:
  git:
    url: file:${source.path}

environment:
  fluoh: ">=0.1.0"

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
name: camera

repository:
  git:
    url: ${parent.path}/camera

upstream:
  git:
    url: https://github.com/flutter/packages
    branch: main

packages:
  camera:
    repository:
      path: packages/camera/camera
    upstream:
      path: packages/camera/camera
    sdks:
      "3.35":
        releases:
          - version: "0"
            upstreamVersion: "0.11.0"
          - version: "1"
            upstreamVersion: "0.11.0"
''');

  await File('${source.path}/manifests/share_plus/fluoh.yaml').writeAsString('''
schema: 1
kind: manifest
name: share_plus

repository:
  git:
    url: ${parent.path}/share_plus

upstream:
  git:
    url: https://github.com/fluttercommunity/plus_plugins
    branch: main

packages:
  share_plus:
    repository:
      path: packages/share_plus/share_plus
    upstream:
      path: packages/share_plus/share_plus
    sdks:
      "3.35":
        releases:
          - version: "1"
            upstreamVersion: "9.0.0"
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
    ..writeln('name: Test FlutterOH source')
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
  await _git(repo, ['add', 'README.md']);
  await _git(repo, ['commit', '-m', 'Initial fixture']);
  await _git(repo, ['tag', tag]);

  return repo;
}

Future<Directory> createUpstreamPackageRepository(
  Directory repo, {
  String packageName = 'camera',
  String version = '0.11.0',
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
  sdk: ^3.0.0
''');
  await File('${repo.path}/README.md').writeAsString('# $packageName\n');
  if (licenseContent != null) {
    await File('${repo.path}/LICENSE').writeAsString(licenseContent);
  }
  await _git(repo, ['add', '.']);
  await _git(repo, ['commit', '-m', 'Initial package fixture']);

  return repo;
}

Future<Directory> createUpstreamMonorepoRepository(
  Directory repo, {
  String packagePath = 'packages/camera/camera',
  String packageName = 'camera',
  String version = '0.11.0',
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
  sdk: ^3.0.0
''');
  await File('${repo.path}/README.md').writeAsString('# monorepo\n');
  if (licenseContent != null) {
    await File('${repo.path}/LICENSE').writeAsString(licenseContent);
  }
  await _git(repo, ['add', '.']);
  await _git(repo, ['commit', '-m', 'Initial monorepo fixture']);

  return repo;
}

Future<void> bumpUpstreamPackageVersion(
  Directory repo, {
  required String version,
  String packagePath = '.',
}) async {
  final packageDirectory = packagePath == '.'
      ? repo
      : Directory('${repo.path}/$packagePath');
  final pubspec = File('${packageDirectory.path}/pubspec.yaml');
  final content = await pubspec.readAsString();
  await pubspec.writeAsString(
    content.replaceFirst(
      RegExp(r'^version:\s+.*$', multiLine: true),
      'version: $version',
    ),
  );
  await _git(repo, ['add', '.']);
  await _git(repo, ['commit', '-m', 'Release $version']);
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
