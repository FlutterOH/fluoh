import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';
import '../helpers/package_test_context.dart';

void main() {
  test('reports package handoff state as json', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final trace = File(
      '${packageRepository.path}/.fluoh/traces/camera/adaptation/trace.json',
    );
    await trace.parent.create(recursive: true);
    await trace.writeAsString(jsonEncode({'id': 'camera-adaptation'}));
    final unrelatedTrace = File(
      '${packageRepository.path}/.fluoh/traces/share_plus/adaptation/trace.json',
    );
    await unrelatedTrace.parent.create(recursive: true);
    await unrelatedTrace.writeAsString(jsonEncode({'id': 'share-plus'}));
    final reportFile = File(
      '${packageRepository.path}/.fluoh/reports/camera/ai-report-test.md',
    );
    await reportFile.parent.create(recursive: true);
    await reportFile.writeAsString('# camera report\n');
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'handoff', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final handoff = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(handoff, containsPair('schema', 1));
    expect(handoff, containsPair('command', 'package handoff'));
    expect(handoff, containsPair('ok', true));
    expect(handoff, containsPair('handoffSchema', 1));
    expect(handoff, containsPair('kind', 'fluoh.packageHandoff'));
    expect(handoff, containsPair('branchMatchesManifest', true));
    expect(handoff, containsPair('dirty', false));
    final package = handoff['package'] as Map<String, Object?>;
    expect(package, containsPair('name', 'camera'));
    expect(package, containsPair('upstreamVersion', '0.11.0'));
    final evidence = handoff['evidence'] as Map<String, Object?>;
    expect(evidence, containsPair('latestTrace', trace.path));
    expect(
      evidence,
      containsPair('traceDir', '.fluoh/traces/camera/adaptation'),
    );
    expect(evidence['reports'], contains(reportFile.path));
    final nextCommands = (handoff['nextCommands'] as List<Object?>)
        .cast<String>();
    expect(
      nextCommands,
      containsAllInOrder([
        'fluoh verify --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
        'fluoh drive all --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
        'fluoh package check --package camera --json',
      ]),
    );
    expect(nextCommands, isNot(contains('fluoh report create --scope camera')));
    expect(stderr, isEmpty);
  });

  test('package handoff defaults next commands to the adaptation trace', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'handoff', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final handoff = jsonDecode(stdout.single) as Map<String, Object?>;
    final evidence = handoff['evidence'] as Map<String, Object?>;
    expect(evidence, isNot(contains('latestTrace')));
    expect(
      evidence,
      containsPair('traceDir', '.fluoh/traces/camera/adaptation'),
    );
    final nextCommands = (handoff['nextCommands'] as List<Object?>)
        .cast<String>();
    expect(
      nextCommands,
      containsAllInOrder([
        'fluoh verify --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
        'fluoh drive all --package camera --json --trace-dir .fluoh/traces/camera/adaptation',
        'fluoh report create --scope camera --package camera --trace-dir .fluoh/traces/camera/adaptation --json',
        'fluoh package check --package camera --json',
      ]),
    );
    expect(stderr, isEmpty);
  });

  test(
    'package handoff reports real manifest branch when branch differs',
    () async {
      final environment = await createTestEnvironment();
      final packageRepository = await createPackageRepositoryFixture(
        environment,
      );
      await runGit(packageRepository, ['checkout', '-b', 'scratch-work']);
      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['package', 'handoff', '--json'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final handoff = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(handoff, containsPair('branch', 'scratch-work'));
      expect(handoff, containsPair('branchMatchesManifest', false));
      final manifestBranch = handoff['manifestBranch'] as String;
      expect(manifestBranch, isNotEmpty);
      expect((handoff['nextCommands'] as List<Object?>).cast<String>(), [
        'git switch $manifestBranch',
      ]);
      expect(stderr, isEmpty);
    },
  );

  test('reports package release readiness as json', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'status', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'package status'));
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('branchMatches', true));
    expect(report, containsPair('workingTreeClean', true));
    expect(report, containsPair('ready', false));
    final blockers = report['readinessBlockers'] as List<Object?>;
    expect(
      blockers,
      contains(
        allOf(
          containsPair('scope', 'package'),
          containsPair('package', 'camera'),
          containsPair('code', 'evidence.ohos_run_missing'),
          containsPair(
            'nextCommand',
            'fluoh run ohos --package camera --auto-emulator --json',
          ),
        ),
      ),
    );
    expect(
      blockers,
      contains(
        allOf(
          containsPair('scope', 'package'),
          containsPair('package', 'camera'),
          containsPair('code', 'evidence.interaction_missing'),
        ),
      ),
    );
    final packages = report['packages'] as List<Object?>;
    final package = packages.single as Map<String, Object?>;
    expect(package, containsPair('package', 'camera'));
    final packageBlockers = package['readinessBlockers'] as List<Object?>;
    expect(packageBlockers, isNotEmpty);
    final checks = package['checks'] as List<Object?>;
    expect(
      checks,
      contains(
        allOf(
          containsPair('name', 'release-status'),
          containsPair('status', 'warning'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('reports the current package branch by default', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await createUpstreamWorkspaceRepository(
      Directory('${environment.homeDirectory.path}/upstream_status_multi'),
      packagePath: 'packages/camera/camera',
      packageName: 'camera',
      version: '0.11.0',
    );
    await runGit(upstream, ['tag', 'camera-v0.11.0']);
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/package_status_multi',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    expect(
      await runFluoh(
        [
          'package',
          'create',
          upstream.path,
          '--repository-name',
          'package_status_multi',
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--package-path',
          'packages/camera/camera',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    await commitGeneratedPackageRepository(packageRepository);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    stdout.clear();

    expect(
      await runFluoh(
        ['package', 'status', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final packages = report['packages'] as List<Object?>;
    expect(
      packages.cast<Map<String, Object?>>().map(
        (package) => package['package'],
      ),
      containsAll(['camera']),
    );
    expect(packages, hasLength(1));
    expect(report['readinessBlockers'], isA<List<Object?>>());
    expect(stderr, isEmpty);
  });

  test('reports missing federated OHOS default package route', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await _createFederatedStatusWorkspace(
      Directory('${environment.homeDirectory.path}/upstream_status_federated'),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/path_provider_status',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    expect(
      await runFluoh(
        [
          'package',
          'create',
          upstream.path,
          '--repository-name',
          'path_provider',
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--package-path',
          'packages/path_provider/path_provider',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    await commitGeneratedPackageRepository(packageRepository);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['package', 'status', '--package', 'path_provider', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final blockers = report['readinessBlockers'] as List<Object?>;
    final routeBlockers = blockers.cast<Map<String, Object?>>().where((
      blocker,
    ) {
      return blocker['code'] == 'platform.ohos_default_package_missing';
    }).toList();
    expect(routeBlockers, hasLength(1));
    final blocker = routeBlockers.single;
    expect(blocker, containsPair('package', 'path_provider'));
    expect(
      blocker,
      containsPair(
        'message',
        allOf(
          contains('path_provider_ohos'),
          contains('packages/path_provider/path_provider_ohos'),
          contains('../path_provider_ohos'),
        ),
      ),
    );
    expect(blocker, isNot(containsPair('nextCommand', anything)));
    final details = blocker['details'] as Map<String, Object?>;
    expect(details, containsPair('kind', 'federated_platform_package'));
    expect(details, containsPair('platform', 'ohos'));
    expect(
      details,
      containsPair('implementationPackageName', 'path_provider_ohos'),
    );
    final packages = report['packages'] as List<Object?>;
    final package = packages.single as Map<String, Object?>;
    final checks = package['checks'] as List<Object?>;
    expect(
      checks,
      contains(
        allOf(
          containsPair('name', 'platform-structure'),
          containsPair('status', 'warning'),
          containsPair('message', contains('ohos.default_package')),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('reports incomplete federated OHOS default package route', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final upstream = await _createFederatedStatusWorkspace(
      Directory(
        '${environment.homeDirectory.path}/upstream_status_incomplete_ohos',
      ),
    );
    final packageRepository = Directory(
      '${environment.homeDirectory.path}/path_provider_status_incomplete',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    expect(
      await runFluoh(
        [
          'package',
          'create',
          upstream.path,
          '--repository-name',
          'path_provider',
          '--output',
          packageRepository.path,
          '--sdk',
          '3.35.8-ohos-0.0.3',
          '--package-path',
          'packages/path_provider/path_provider',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    await commitGeneratedPackageRepository(packageRepository);
    await _addOhosDefaultPackageOnly(packageRepository);
    await runGit(packageRepository, ['add', '.']);
    await runGit(packageRepository, [
      'commit',
      '-m',
      'Add incomplete OHOS route',
    ]);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['package', 'status', '--package', 'path_provider', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final incompleteReport = jsonDecode(stdout.single) as Map<String, Object?>;
    final incompleteBlockers =
        (incompleteReport['readinessBlockers'] as List<Object?>)
            .cast<Map<String, Object?>>();
    final blocker = incompleteBlockers.singleWhere(
      (blocker) =>
          blocker['code'] == 'platform.ohos_default_package_incomplete',
    );
    expect(
      blocker['message'],
      allOf(
        contains('dependency path_provider_ohos is missing'),
        contains('implementation package path_provider_ohos was not found'),
      ),
    );
    expect(blocker, isNot(containsPair('nextCommand', anything)));
    expect(
      blocker['details'],
      containsPair('defaultPackage', 'path_provider_ohos'),
    );
    expect(blocker['details'], containsPair('dependencyPresent', false));
    expect(
      blocker['details'],
      containsPair('implementationPackagePresent', false),
    );
    expect(stderr, isEmpty);

    await _addOhosImplementationPackage(packageRepository);
    await runGit(packageRepository, ['add', '.']);
    await runGit(packageRepository, ['commit', '-m', 'Complete OHOS route']);
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['package', 'status', '--package', 'path_provider', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final completeReport = jsonDecode(stdout.single) as Map<String, Object?>;
    final completeBlockers =
        (completeReport['readinessBlockers'] as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(
      completeBlockers.map((blocker) => blocker['code']),
      isNot(contains('platform.ohos_default_package_incomplete')),
    );
    expect(stderr, isEmpty);
  });

  test(
    'reports federated OHOS default package dependency path mismatch',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final upstream = await _createFederatedStatusWorkspace(
        Directory('${environment.homeDirectory.path}/upstream_status_bad_path'),
      );
      final packageRepository = Directory(
        '${environment.homeDirectory.path}/path_provider_status_bad_path',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      expect(
        await runFluoh(
          [
            'package',
            'create',
            upstream.path,
            '--repository-name',
            'path_provider',
            '--output',
            packageRepository.path,
            '--sdk',
            '3.35.8-ohos-0.0.3',
            '--package-path',
            'packages/path_provider/path_provider',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      await commitGeneratedPackageRepository(packageRepository);
      await _addOhosDefaultPackageOnly(packageRepository);
      await _addOhosImplementationPackage(packageRepository);
      await _setOhosImplementationDependencyPath(
        packageRepository,
        '../wrong_path_provider_ohos',
      );
      await runGit(packageRepository, ['add', '.']);
      await runGit(packageRepository, [
        'commit',
        '-m',
        'Add mismatched OHOS dependency route',
      ]);
      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: packageRepository,
      );
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          ['package', 'status', '--package', 'path_provider', '--json'],
          environment: packageEnvironment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      final blockers = (report['readinessBlockers'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final blocker = blockers.singleWhere(
        (blocker) =>
            blocker['code'] == 'platform.ohos_default_package_incomplete',
      );
      expect(
        blocker['message'],
        contains(
          'dependency path ../wrong_path_provider_ohos does not resolve to implementation package path_provider_ohos',
        ),
      );
      final details = blocker['details'] as Map<String, Object?>;
      expect(details, containsPair('dependencyPresent', true));
      expect(
        details,
        containsPair('dependencyPath', '../wrong_path_provider_ohos'),
      );
      expect(
        details,
        containsPair(
          'dependencyResolvedPath',
          'packages/path_provider/wrong_path_provider_ohos',
        ),
      );
      expect(details, containsPair('implementationPackagePresent', true));
      expect(
        details,
        containsPair('implementationPackageAtDependencyPathPresent', false),
      );
      final requiredEdits = (details['requiredEdits'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        requiredEdits,
        contains(
          allOf(
            containsPair('target', 'appFacingPubspec'),
            containsPair('action', 'update_dependency_path'),
            containsPair('package', 'path_provider_ohos'),
          ),
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test('reports release validation failures as readiness warnings', () async {
    final environment = await createTestEnvironment();
    final packageRepository = await createPackageRepositoryFixture(environment);
    await runGit(packageRepository, ['tag', 'camera-0.11.0-ohos-3.35-0.2.0']);
    final packageEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: packageRepository,
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['package', 'status', '--json'],
        environment: packageEnvironment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('ready', false));
    final packages = report['packages'] as List<Object?>;
    final package = packages.single as Map<String, Object?>;
    final checks = package['checks'] as List<Object?>;
    expect(
      checks,
      contains(
        allOf(
          containsPair('name', 'release-metadata'),
          containsPair('status', 'warning'),
          containsPair(
            'message',
            contains('must be greater than latest release version 0.2.0'),
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });
}

Future<Directory> _createFederatedStatusWorkspace(Directory repo) async {
  final upstream = await createUpstreamWorkspaceRepository(
    repo,
    packagePath: 'packages/path_provider/path_provider',
    packageName: 'path_provider',
    version: '2.1.0',
  );
  final packageDirectory = Directory(
    '${upstream.path}/packages/path_provider/path_provider',
  );
  await Directory('${packageDirectory.path}/lib').create(recursive: true);
  await File(
    '${packageDirectory.path}/lib/path_provider.dart',
  ).writeAsString('library path_provider;\n');
  await File('${packageDirectory.path}/pubspec.yaml').writeAsString('''
name: path_provider
version: 2.1.0

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter

flutter:
  plugin:
    platforms:
      android:
        default_package: path_provider_android
      ios:
        default_package: path_provider_foundation
''');
  await runGit(upstream, ['add', '.']);
  await runGit(upstream, ['commit', '-m', 'Add federated plugin metadata']);
  await runGit(upstream, ['tag', 'path_provider-v2.1.0']);
  return upstream;
}

Future<void> _addOhosDefaultPackageOnly(Directory packageRepository) async {
  final pubspec = File(
    '${packageRepository.path}/packages/path_provider/path_provider/pubspec.yaml',
  );
  final content = await pubspec.readAsString();
  await pubspec.writeAsString(
    content.replaceFirst(
      '''
      ios:
        default_package: path_provider_foundation
''',
      '''
      ios:
        default_package: path_provider_foundation
      ohos:
        default_package: path_provider_ohos
''',
    ),
  );
}

Future<void> _addOhosImplementationPackage(Directory packageRepository) async {
  final appPubspec = File(
    '${packageRepository.path}/packages/path_provider/path_provider/pubspec.yaml',
  );
  final content = await appPubspec.readAsString();
  await appPubspec.writeAsString(
    content.replaceFirst(
      '''
dependencies:
  flutter:
    sdk: flutter
''',
      '''
dependencies:
  path_provider_ohos:
    path: ../path_provider_ohos
  flutter:
    sdk: flutter
''',
    ),
  );
  final implementation = Directory(
    '${packageRepository.path}/packages/path_provider/path_provider_ohos',
  );
  await Directory('${implementation.path}/lib').create(recursive: true);
  await File(
    '${implementation.path}/lib/path_provider_ohos.dart',
  ).writeAsString('library path_provider_ohos;\n');
  await File('${implementation.path}/pubspec.yaml').writeAsString('''
name: path_provider_ohos
version: 2.1.0

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
  path_provider:
    path: ../path_provider

flutter:
  plugin:
    platforms:
      ohos:
        pluginClass: PathProviderPlugin
''');
}

Future<void> _setOhosImplementationDependencyPath(
  Directory packageRepository,
  String path,
) async {
  final appPubspec = File(
    '${packageRepository.path}/packages/path_provider/path_provider/pubspec.yaml',
  );
  final content = await appPubspec.readAsString();
  await appPubspec.writeAsString(
    content.replaceFirst(
      '  path_provider_ohos:\n    path: ../path_provider_ohos',
      '  path_provider_ohos:\n    path: $path',
    ),
  );
}
