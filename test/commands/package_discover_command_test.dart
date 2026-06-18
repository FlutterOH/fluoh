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
    expect(discovery['recommendedCount'], 1);
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
    expect(camera['role'], 'flutter_plugin');
    final profile = camera['supportProfile'] as Map<String, Object?>;
    expect(profile['complexity'], 'high');
    expect(
      profile['categories'],
      containsAll(['media-capture', 'runtime-permission']),
    );
    expect(
      profile['riskReasons'],
      containsAll(['hardware-or-system-picker', 'runtime-permission-matrix']),
    );
    expect(
      profile['requiredEvidence'],
      containsAll([
        'capture-picker-success-cancel-error',
        'official-platform-docs-reviewed',
        'permission-grant-deny',
      ]),
    );
    expect(profile, containsPair('officialDocsRequired', true));
    expect(
      profile['officialDocTopics'],
      containsAll([contains('permission'), contains('camera')]),
    );
    final suggestedCoverage = (profile['suggestedCoverage'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      suggestedCoverage,
      contains(containsPair('category', 'media-capture')),
    );
    expect(
      suggestedCoverage,
      contains(containsPair('category', 'runtime-permission')),
    );
    expect(camera['missingPlatforms'], ['ohos']);
    expect(camera['recommended'], isTrue);
    expect(
      camera['portCommand'],
      'fluoh package port ${upstream.path} --repository-name camera '
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

  test('recommends implementation package for federated app package', () async {
    final environment = await createTestEnvironment();
    final upstream = await _createFederatedDiscoveryRepository(
      Directory('${environment.homeDirectory.path}/upstream_federated_plugins'),
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
    expect(discovery['candidateCount'], 4);
    expect(discovery['recommendedCount'], 1);
    expect(
      discovery['queueCommand'],
      'fluoh package queue packages/camera/camera --json',
    );
    final candidates = discovery['candidates'] as List<Object?>;
    final candidateMaps = candidates.cast<Map<String, Object?>>();
    final camera = candidateMaps.singleWhere(
      (candidate) => candidate['name'] == 'camera',
    );
    expect(camera['name'], 'camera');
    expect(camera['role'], 'app_facing_package');
    expect(camera['platformDefaultPackages'], {
      'android': 'camera_android',
      'ios': 'camera_ios',
    });

    final recommendation =
        camera['implementationRecommendation'] as Map<String, Object?>;
    expect(recommendation['kind'], 'federated_platform_package');
    expect(
      recommendation['reason'],
      'federated_plugin_missing_platform_package',
    );
    expect(recommendation['platform'], 'ohos');
    expect(
      recommendation['setupCommand'],
      'fluoh package port ${upstream.path} --repository-name camera '
      '--package-path packages/camera/camera',
    );
    expect(recommendation['sourceRoute'], {
      'packageName': 'camera',
      'packagePath': 'packages/camera/camera',
    });
    expect(recommendation['appFacingPackage'], 'camera');
    expect(recommendation['appFacingPath'], 'packages/camera/camera');
    expect(recommendation['implementationPackageName'], 'camera_ohos');
    expect(
      recommendation['implementationPackagePath'],
      'packages/camera/camera_ohos',
    );
    expect(recommendation['implementationDependency'], {
      'package': 'camera_ohos',
      'path': '../camera_ohos',
    });
    expect(recommendation['existingDefaultPackages'], {
      'android': 'camera_android',
      'ios': 'camera_ios',
    });
    final requiredEdits = recommendation['requiredEdits'] as List<Object?>;
    expect(
      requiredEdits,
      contains(containsPair('action', 'add_default_package')),
    );
    expect(
      requiredEdits,
      contains(containsPair('defaultPackage', 'camera_ohos')),
    );
    expect(requiredEdits, contains(containsPair('path', '../camera_ohos')));

    final android = candidateMaps.singleWhere(
      (candidate) => candidate['name'] == 'camera_android',
    );
    expect(android['role'], 'platform_specific_helper');
    expect(android['recommended'], isFalse);
    expect(android['reason'], 'covered_by_federated_app_facing_package');
    expect(android['missingPlatforms'], ['ohos']);
    final androidCoverage =
        android['coveredByImplementationRecommendations'] as List<Object?>;
    expect(androidCoverage.single, containsPair('kind', 'default_package'));
    expect(androidCoverage.single, containsPair('appFacingPackage', 'camera'));
    expect(
      androidCoverage.single,
      containsPair('referencedPlatforms', ['android']),
    );
    expect(
      androidCoverage.single,
      containsPair('recommendedImplementationPackage', 'camera_ohos'),
    );

    final ios = candidateMaps.singleWhere(
      (candidate) => candidate['name'] == 'camera_ios',
    );
    expect(ios['recommended'], isFalse);
    expect(ios['reason'], 'covered_by_federated_app_facing_package');
    expect(
      ios['coveredByImplementationRecommendations'],
      contains(containsPair('referencedPlatforms', ['ios'])),
    );

    final windows = candidateMaps.singleWhere(
      (candidate) => candidate['name'] == 'camera_windows',
    );
    expect(windows['role'], 'platform_specific_helper');
    expect(windows['recommended'], isFalse);
    expect(windows['reason'], 'covered_by_federated_app_facing_package');
    final windowsCoverage =
        windows['coveredByImplementationRecommendations'] as List<Object?>;
    expect(
      windowsCoverage.single,
      containsPair('kind', 'federated_family_sibling'),
    );
    expect(
      windowsCoverage.single,
      containsPair('candidatePlatforms', ['windows']),
    );
    expect(
      windowsCoverage.single,
      containsPair('recommendedImplementationPackage', 'camera_ohos'),
    );
  });

  test('does not recommend test fixtures or platform helper plugins', () async {
    final environment = await createTestEnvironment();
    final upstream = await _createDiscoveryRoleRepository(
      Directory('${environment.homeDirectory.path}/upstream_role_plugins'),
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
    expect(discovery['candidateCount'], 3);
    expect(discovery['recommendedCount'], 1);
    expect(
      discovery['queueCommand'],
      'fluoh package queue packages/camera/camera --json',
    );

    final candidates = (discovery['candidates'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final camera = candidates.singleWhere(
      (candidate) => candidate['name'] == 'camera',
    );
    expect(camera['role'], 'flutter_plugin');
    expect(camera['recommended'], isTrue);

    final lifecycle = candidates.singleWhere(
      (candidate) => candidate['name'] == 'flutter_plugin_android_lifecycle',
    );
    expect(lifecycle['role'], 'platform_specific_helper');
    expect(lifecycle['recommended'], isFalse);
    expect(lifecycle['reason'], 'platform_specific_helper_package');

    final testPlugin = candidates.singleWhere(
      (candidate) => candidate['name'] == 'test_plugin',
    );
    expect(testPlugin['role'], 'test_fixture');
    expect(testPlugin['recommended'], isFalse);
    expect(testPlugin['reason'], 'test_fixture');
  });

  test('profiles external service plugin blockers as JSON', () async {
    final environment = await createTestEnvironment();
    final upstream = await _createExternalServiceDiscoveryRepository(
      Directory('${environment.homeDirectory.path}/upstream_external_plugins'),
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
    final candidates = (discovery['candidates'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final firebase = candidates.singleWhere(
      (candidate) => candidate['name'] == 'firebase_core',
    );
    final profile = firebase['supportProfile'] as Map<String, Object?>;
    expect(profile['complexity'], 'external');
    expect(
      profile['categories'],
      containsAll(['external-service', 'firebase-service']),
    );
    expect(profile['riskReasons'], contains('external-service-sdk'));
    expect(
      profile['requiredEvidence'],
      contains('sdk-availability-and-credential-blocker'),
    );
    expect(profile, containsPair('officialDocsRequired', true));
    expect(
      profile['officialDocTopics'],
      contains(contains('Official vendor SDK documentation')),
    );
    expect(profile['blockerPolicy'], isA<Map<String, Object?>>());
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
    expect(output, contains('fluoh package port ${upstream.path}'));
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
      candidate['portCommand'],
      "fluoh package port '${upstream.path}' --repository-name "
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

Future<Directory> _createFederatedDiscoveryRepository(Directory repo) async {
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
    defaultPackages: const {'android': 'camera_android', 'ios': 'camera_ios'},
  );
  await _writePackage(
    repo,
    path: 'packages/camera/camera_android',
    name: 'camera_android',
    version: '0.11.0',
    pluginPlatforms: const ['android'],
  );
  await _writePackage(
    repo,
    path: 'packages/camera/camera_ios',
    name: 'camera_ios',
    version: '0.11.0',
    pluginPlatforms: const ['ios'],
  );
  await _writePackage(
    repo,
    path: 'packages/camera/camera_windows',
    name: 'camera_windows',
    version: '0.11.0',
    pluginPlatforms: const ['windows'],
  );
  await File('${repo.path}/README.md').writeAsString('# federated plugins\n');
  await _runProcess('git', ['add', '.'], repo);
  await _runProcess('git', ['commit', '-m', 'Initial federated plugin'], repo);
  return repo;
}

Future<Directory> _createDiscoveryRoleRepository(Directory repo) async {
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
    path: 'packages/flutter_plugin_android_lifecycle',
    name: 'flutter_plugin_android_lifecycle',
    version: '2.0.0',
    pluginPlatforms: const ['android'],
  );
  await _writePackage(
    repo,
    path: 'packages/pigeon/platform_tests/test_plugin',
    name: 'test_plugin',
    version: '1.0.0',
    pluginPlatforms: const ['android', 'ios'],
  );
  await File('${repo.path}/README.md').writeAsString('# role plugins\n');
  await _runProcess('git', ['add', '.'], repo);
  await _runProcess('git', ['commit', '-m', 'Initial role plugins'], repo);
  return repo;
}

Future<Directory> _createExternalServiceDiscoveryRepository(
  Directory repo,
) async {
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
    path: 'packages/firebase_core/firebase_core',
    name: 'firebase_core',
    version: '4.0.0',
    pluginPlatforms: const ['android', 'ios'],
  );
  await File('${repo.path}/README.md').writeAsString('# firebase plugins\n');
  await _runProcess('git', ['add', '.'], repo);
  await _runProcess('git', ['commit', '-m', 'Initial firebase plugin'], repo);
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
  Map<String, String> defaultPackages = const {},
}) async {
  final directory = Directory('${repo.path}/$path');
  await Directory('${directory.path}/lib').create(recursive: true);
  final flutterBlock = pluginPlatforms == null
      ? ''
      : '''

flutter:
  plugin:
${_platformsBlock(pluginPlatforms, defaultPackages: defaultPackages)}
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

String _platformsBlock(
  List<String> platforms, {
  Map<String, String> defaultPackages = const {},
}) {
  final buffer = StringBuffer('    platforms:\n');
  for (final platform in platforms) {
    buffer.writeln('      $platform:');
    final defaultPackage = defaultPackages[platform];
    if (defaultPackage == null) {
      buffer.writeln('        pluginClass: ${platform}Plugin');
    } else {
      buffer.writeln('        default_package: $defaultPackage');
    }
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
