import 'dart:convert';
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
  final generated = Directory('${source.path}/generated');
  await generated.create(recursive: true);

  final sdkRepository = await createTaggedGitRepository(
    Directory('${parent.path}/flutter-ohos-sdk'),
    tag: '3.35.8-ohos-0.0.3',
    readme: '# Mock Flutter OHOS SDK\n',
  );

  await File('${generated.path}/sdk-index.json').writeAsString(
    jsonEncode({
      'schemaVersion': 1,
      'releases': [
        {
          'version': '3.35.8-ohos-0.0.3',
          'flutterVersion': '3.35.8',
          'channel': 'stable',
          'repository': sdkRepository.path,
          'tag': '3.35.8-ohos-0.0.3',
          'publishedAt': '2026-04-29T00:00:00Z',
        },
      ],
    }),
  );

  await File('${generated.path}/package-index.json').writeAsString(
    jsonEncode({
      'schemaVersion': 1,
      'packages': {
        'camera': {
          'upstream':
              'https://github.com/flutter/packages/tree/main/packages/camera/camera',
          'adapters': [
            {
              'sdkLine': '3.35',
              'upstreamVersion': '0.11.0',
              'repository': '${parent.path}/camera',
              'tag': 'camera-v0.11.0-ohos-3.35.8-0',
              'path': 'packages/camera/camera',
            },
            {
              'sdkLine': '3.35',
              'upstreamVersion': '0.11.0',
              'repository': '${parent.path}/camera',
              'tag': 'camera-v0.11.0-ohos-3.35.8-1',
              'path': 'packages/camera/camera',
            },
          ],
        },
        'share_plus': {
          'upstream':
              'https://github.com/fluttercommunity/plus_plugins/tree/main/packages/share_plus/share_plus',
          'adapters': [
            {
              'sdkLine': '3.35',
              'upstreamVersion': '9.0.0',
              'repository': '${parent.path}/share_plus',
              'tag': 'share_plus-v9.0.0-ohos-3.35.8-1',
            },
          ],
        },
      },
    }),
  );

  await File('${generated.path}/compatibility-matrix.json').writeAsString(
    jsonEncode({
      'schemaVersion': 1,
      'sdkLines': {
        '3.35': {
          'native': ['path_provider'],
          'adapted': ['camera'],
          'blocked': ['legacy_camera'],
        },
      },
    }),
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
