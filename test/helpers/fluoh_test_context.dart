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
  await Directory('${source.path}/sdk').create(recursive: true);
  await Directory('${source.path}/packages/manifests').create(recursive: true);

  final sdkRepository = await createTaggedGitRepository(
    Directory('${parent.path}/flutter-ohos-sdk'),
    tag: '3.35.8-ohos-0.0.3',
    readme: '# Mock Flutter OHOS SDK\n',
  );

  await File('${source.path}/sdk/index.yaml').writeAsString('''
schema: 1
repositoryUrl: ${sdkRepository.path}
versions:
  - version: 3.35.8-ohos-0.0.3
    tag: 3.35.8-ohos-0.0.3
    versionSeries: "3.35"
    status: stable
''');

  await File('${source.path}/packages/registry.yaml').writeAsString('''
schema: 1
packages:
  - name: camera
    repositoryUrl: ${parent.path}/camera
    upstreamUrl: https://github.com/flutter/packages/tree/main/packages/camera/camera
    packagePath: packages/camera/camera
    status: compatible
  - name: share_plus
    repositoryUrl: ${parent.path}/share_plus
    upstreamUrl: https://github.com/fluttercommunity/plus_plugins/tree/main/packages/share_plus/share_plus
    packagePath: packages/share_plus/share_plus
    status: compatible
''');

  await File('${source.path}/packages/manifests/camera.yaml').writeAsString('''
schema: 1
package:
  name: camera
  repositoryUrl: ${parent.path}/camera
  upstreamUrl: https://github.com/flutter/packages/tree/main/packages/camera/camera
  packagePath: packages/camera/camera
releases:
  - version: 0.11.0
    upstreamRef: camera-v0.11.0
    sdk:
      versionSeries: "3.35"
      versionRange: ">=3.35.8 <3.36.0"
      versions:
        - 3.35.8-ohos-0.0.3
    status: compatible
    sourceBranch: ohos-3.35
    release:
      version: "0"
      tag: camera-v0.11.0-ohos-3.35.8-0
    replacement:
      type: git
      url: ${parent.path}/camera
      ref: camera-v0.11.0-ohos-3.35.8-0
      path: packages/camera/camera
  - version: 0.11.0
    upstreamRef: camera-v0.11.0
    sdk:
      versionSeries: "3.35"
      versionRange: ">=3.35.8 <3.36.0"
      versions:
        - 3.35.8-ohos-0.0.3
    status: compatible
    sourceBranch: ohos-3.35
    release:
      version: "1"
      tag: camera-v0.11.0-ohos-3.35.8-1
    replacement:
      type: git
      url: ${parent.path}/camera
      ref: camera-v0.11.0-ohos-3.35.8-1
      path: packages/camera/camera
''');

  await File('${source.path}/packages/manifests/share_plus.yaml').writeAsString(
    '''
schema: 1
package:
  name: share_plus
  repositoryUrl: ${parent.path}/share_plus
  upstreamUrl: https://github.com/fluttercommunity/plus_plugins/tree/main/packages/share_plus/share_plus
  packagePath: packages/share_plus/share_plus
releases:
  - version: 9.0.0
    upstreamRef: share_plus-v9.0.0
    sdk:
      versionSeries: "3.35"
      versionRange: ">=3.35.8 <3.36.0"
      versions:
        - 3.35.8-ohos-0.0.3
    status: compatible
    sourceBranch: ohos-3.35
    release:
      version: "1"
      tag: share_plus-v9.0.0-ohos-3.35.8-1
    replacement:
      type: git
      url: ${parent.path}/share_plus
      ref: share_plus-v9.0.0-ohos-3.35.8-1
      path: packages/share_plus/share_plus
''',
  );

  return source;
}

Future<void> writeFlutterProjectWithAdapterOverrideFixture(
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
      ref: camera-v0.11.0-ohos-3.35.8-0
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
  await _git(repo, ['add', 'pubspec.yaml', 'README.md']);
  await _git(repo, ['commit', '-m', 'Initial package fixture']);

  return repo;
}

Future<Directory> createUpstreamMonorepoRepository(
  Directory repo, {
  String packagePath = 'packages/camera/camera',
  String packageName = 'camera',
  String version = '0.11.0',
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
  await _git(repo, ['add', '.']);
  await _git(repo, ['commit', '-m', 'Initial monorepo fixture']);

  return repo;
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
