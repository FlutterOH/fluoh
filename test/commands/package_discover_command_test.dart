import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

void main() {
  test('discovers plugin packages missing ohos as JSON', () async {
    final environment = await createTestEnvironment();
    final upstream = await _createDiscoveryRepository(
      Directory('${environment.homeDirectory.path}/upstream_plugins'),
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'discover', upstream.path, '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stderr, isEmpty);
    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(payload['command'], 'package discover');
    expect(payload['ok'], isTrue);
    expect(payload['changed'], isFalse);
    final discovery = payload['discovery'] as Map<String, Object?>;
    expect(discovery['pubspecCount'], 4);
    expect(discovery['pluginPackageCount'], 2);
    expect(discovery['candidateCount'], 1);
    expect(
      discovery['queueCommand'],
      'fluoh package queue packages/camera/camera --json',
    );

    final candidates = discovery['candidates'] as List<Object?>;
    final candidatePaths = [
      for (final candidate in candidates)
        (candidate as Map<String, Object?>)['path'],
    ];
    expect(candidatePaths, ['packages/camera/camera']);

    final camera = candidates.first as Map<String, Object?>;
    expect(camera['name'], 'camera');
    expect(camera['version'], '0.11.0');
    expect(camera['sdkConstraint'], '^3.0.0');
    expect(camera['platforms'], ['android', 'ios']);
    expect(camera['missingPlatforms'], ['ohos']);
    expect(camera['recommended'], isTrue);
    expect(
      camera['createCommand'],
      'fluoh package create ${upstream.path} --repository-name camera '
      '--package-path packages/camera/camera',
    );

    final issues = discovery['issues'] as List<Object?>;
    expect(issues, hasLength(1));
    expect(
      issues.single,
      containsPair('path', 'packages/broken_plugin/pubspec.yaml'),
    );
    expect(
      issues.single,
      containsPair('code', 'pubspec.package_identity_missing'),
    );
  });

  test('can include plugin packages that already declare ohos', () async {
    final environment = await createTestEnvironment();
    final upstream = await _createDiscoveryRepository(
      Directory('${environment.homeDirectory.path}/upstream_all_plugins'),
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'package',
          'discover',
          upstream.path,
          '--include-existing-platform',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stderr, isEmpty);
    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    final discovery = payload['discovery'] as Map<String, Object?>;
    expect(discovery['candidateCount'], 2);
    final candidates = discovery['candidates'] as List<Object?>;
    final share = candidates.cast<Map<String, Object?>>().singleWhere(
      (candidate) => candidate['name'] == 'share_plus',
    );
    expect(share['platforms'], ['android', 'ios', 'ohos']);
    expect(share['missingPlatforms'], isEmpty);
    expect(share['recommended'], isFalse);
  });

  test('prints human-readable discovery results and next commands', () async {
    final environment = await createTestEnvironment();
    final upstream = await _createDiscoveryRepository(
      Directory('${environment.homeDirectory.path}/upstream_human_plugins'),
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'discover', upstream.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stderr, isEmpty);
    final output = stdout.join('\n');
    expect(output, contains('Package candidates discovered'));
    expect(output, contains('Flutter plugins missing ohos'));
    expect(output, contains('camera'));
    expect(output, contains('packages/camera/camera'));
    expect(output, isNot(contains('share_plus')));
    expect(output, contains('fluoh package create ${upstream.path}'));
  });

  test('prints discovery issues when no human candidates match', () async {
    final environment = await createTestEnvironment();
    final upstream = await _createBrokenDiscoveryRepository(
      Directory('${environment.homeDirectory.path}/upstream_broken_plugins'),
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'discover', upstream.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stderr, isEmpty);
    final output = stdout.join('\n');
    expect(output, contains('No matching package candidates found.'));
    expect(output, contains('packages/broken_plugin/pubspec.yaml'));
    expect(
      output,
      contains('Flutter plugin pubspec must contain name and version.'),
    );
  });

  test('quotes generated commands for paths with spaces', () async {
    final environment = await createTestEnvironment();
    final upstream = await _createSpacedPathDiscoveryRepository(
      Directory('${environment.homeDirectory.path}/upstream plugins'),
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'discover', upstream.path, '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stderr, isEmpty);
    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    final discovery = payload['discovery'] as Map<String, Object?>;
    expect(
      discovery['queueCommand'],
      "fluoh package queue 'packages/fancy plugin' --json",
    );
    final candidates = discovery['candidates'] as List<Object?>;
    final candidate = candidates.single as Map<String, Object?>;
    expect(
      candidate['createCommand'],
      "fluoh package create '${upstream.path}' --repository-name "
      "fancy_plugin --package-path 'packages/fancy plugin'",
    );
  });
}

Future<Directory> _createDiscoveryRepository(Directory repo) async {
  await repo.create(recursive: true);
  await _runProcess('git', ['init', '--initial-branch=main'], repo);
  await _runProcess('git', [
    'config',
    'user.email',
    'fixture@example.com',
  ], repo);
  await _runProcess('git', ['config', 'user.name', 'Fixture'], repo);

  await _writePackage(
    repo,
    path: 'packages/camera/camera',
    name: 'camera',
    version: '0.11.0',
    pluginPlatforms: const ['android', 'ios'],
  );
  await _writePackage(
    repo,
    path: 'packages/share_plus/share_plus',
    name: 'share_plus',
    version: '9.0.0',
    pluginPlatforms: const ['android', 'ios', 'ohos'],
  );
  await _writePackage(
    repo,
    path: 'packages/path_provider_platform_interface',
    name: 'path_provider_platform_interface',
    version: '2.1.0',
    pluginPlatforms: null,
  );
  await _writeBrokenPlugin(repo, path: 'packages/broken_plugin');
  await _writePackage(
    repo,
    path: 'packages/camera/camera/example',
    name: 'camera_example',
    version: '0.1.0',
    pluginPlatforms: const ['android'],
  );
  await File('${repo.path}/README.md').writeAsString('# plugins\n');
  await _runProcess('git', ['add', '.'], repo);
  await _runProcess('git', ['commit', '-m', 'Initial plugin workspace'], repo);
  return repo;
}

Future<Directory> _createBrokenDiscoveryRepository(Directory repo) async {
  await repo.create(recursive: true);
  await _runProcess('git', ['init', '--initial-branch=main'], repo);
  await _runProcess('git', [
    'config',
    'user.email',
    'fixture@example.com',
  ], repo);
  await _runProcess('git', ['config', 'user.name', 'Fixture'], repo);
  await _writeBrokenPlugin(repo, path: 'packages/broken_plugin');
  await File('${repo.path}/README.md').writeAsString('# broken plugins\n');
  await _runProcess('git', ['add', '.'], repo);
  await _runProcess('git', ['commit', '-m', 'Initial broken plugin'], repo);
  return repo;
}

Future<Directory> _createSpacedPathDiscoveryRepository(Directory repo) async {
  await repo.create(recursive: true);
  await _runProcess('git', ['init', '--initial-branch=main'], repo);
  await _runProcess('git', [
    'config',
    'user.email',
    'fixture@example.com',
  ], repo);
  await _runProcess('git', ['config', 'user.name', 'Fixture'], repo);
  await _writePackage(
    repo,
    path: 'packages/fancy plugin',
    name: 'fancy_plugin',
    version: '1.0.0',
    pluginPlatforms: const ['android'],
  );
  await File('${repo.path}/README.md').writeAsString('# spaced plugins\n');
  await _runProcess('git', ['add', '.'], repo);
  await _runProcess('git', ['commit', '-m', 'Initial spaced plugin'], repo);
  return repo;
}

Future<void> _writePackage(
  Directory repo, {
  required String path,
  required String name,
  required String version,
  required List<String>? pluginPlatforms,
}) async {
  final directory = Directory('${repo.path}/$path');
  await Directory('${directory.path}/lib').create(recursive: true);
  final flutterBlock = pluginPlatforms == null
      ? ''
      : '''

flutter:
  plugin:
${_platformsBlock(pluginPlatforms)}
''';
  await File('${directory.path}/pubspec.yaml').writeAsString('''
name: $name
version: $version

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
$flutterBlock''');
  await File(
    '${directory.path}/lib/$name.dart',
  ).writeAsString('library $name;\n');
}

Future<void> _writeBrokenPlugin(Directory repo, {required String path}) async {
  final directory = Directory('${repo.path}/$path');
  await directory.create(recursive: true);
  await File('${directory.path}/pubspec.yaml').writeAsString('''
name: broken_plugin

flutter:
  plugin:
    platforms:
      android:
        pluginClass: BrokenPlugin
''');
}

String _platformsBlock(List<String> platforms) {
  final buffer = StringBuffer('    platforms:\n');
  for (final platform in platforms) {
    buffer
      ..writeln('      $platform:')
      ..writeln('        pluginClass: ${platform}Plugin');
  }
  return buffer.toString();
}

Future<void> _runProcess(
  String executable,
  List<String> arguments,
  Directory workingDirectory,
) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
  );
  if (result.exitCode != 0) {
    fail('$executable ${arguments.join(' ')} failed:\n${result.stderr}');
  }
}
