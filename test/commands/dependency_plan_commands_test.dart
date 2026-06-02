import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

void main() {
  test('checks dependency compatibility and emits json', () async {
    final environment = await _preparedEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['deps', 'check'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['deps', 'check', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, contains('Ready to fix:'));
    expect(
      stdout,
      contains('  camera 0.11.0: override -> camera-0.11.0-ohos-3.35-1'),
    );
    expect(stdout, contains('Needs decision:'));
    expect(
      stdout,
      anyElement(
        contains(
          'share_plus 10.0.0: OHOS implementation targets upstream 9.0.0',
        ),
      ),
    );
    expect(stdout, contains('Unavailable:'));
    expect(
      stdout,
      contains(
        '  mystery_package 1.0.0: No known OHOS implementation is available.',
      ),
    );
    expect(stdout, contains('Transitive dependencies:'));
    _expectOutputContains(
      stdout,
      'camera_platform_interface 2.9.0: Transitive dependency; fluoh only rewrites direct dependencies.',
    );
    expect(
      stdout,
      contains('Next: run `fluoh deps fix`, then `fluoh deps get`'),
    );

    final jsonReport = jsonDecode(stdout.last) as Map<String, Object?>;
    expect(jsonReport, containsPair('schemaVersion', 1));
    expect(jsonReport, containsPair('command', 'deps check'));
    expect(jsonReport, containsPair('ok', false));
    expect(jsonReport, containsPair('exitCode', 0));
    final dependencies = jsonReport['dependencies'] as List<Object?>;
    expect(
      dependencies,
      contains(
        allOf(
          containsPair('name', 'camera'),
          containsPair('status', 'implemented'),
          containsPair('direct', true),
          containsPair('actionable', true),
          containsPair('recommendedAction', 'write-override'),
        ),
      ),
    );
    expect(
      dependencies,
      contains(
        allOf(
          containsPair('name', 'camera_platform_interface'),
          containsPair('dependencyChain', [
            'camera',
            'camera_platform_interface',
          ]),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'repairs invalid package route data in source locks during dependency checks',
    () async {
      final environment = await _preparedEnvironment();
      final lockFile = File(
        '${environment.homeDirectory.path}/sources.lock.json',
      );
      final lock =
          jsonDecode(lockFile.readAsStringSync()) as Map<String, Object?>;
      lock['packageRoutes'] = {'fixture': 'not a source manifest object'};
      await lockFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(lock)}\n',
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['deps', 'check'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(stdout, anyElement(contains('camera 0.11.0')));
      final repairedLock =
          jsonDecode(lockFile.readAsStringSync()) as Map<String, Object?>;
      final packageRoutes =
          repairedLock['packageRoutes'] as Map<String, Object?>;
      final fixtureManifests = packageRoutes['fixture'] as Map<String, Object?>;
      final cameraManifest = fixtureManifests['camera'] as Map<String, Object?>;
      expect(cameraManifest, containsPair('camera', ['3.35']));
      expect(stderr, isEmpty);
    },
  );

  test(
    'uses fresh package routes without validating unrelated manifests',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      await _writeCameraOnlyProjectFixture(environment.workingDirectory);
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
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
      final lockFile = File(
        '${environment.homeDirectory.path}/sources.lock.json',
      );
      final snapshotHash = _lockSourceSnapshotHash(lockFile, 'fixture');
      final cachedSource = Directory(
        '${environment.homeDirectory.path}/sources/fixture',
      );
      final unrelatedManifest = File(
        '${cachedSource.path}/manifests/share_plus/fluoh.yaml',
      );
      await unrelatedManifest.writeAsString(
        unrelatedManifest.readAsStringSync().replaceFirst(
          '        releases:\n',
          '        releases: []\n',
        ),
      );
      await _writeSnapshotStateForCurrentFingerprint(
        cachedSource,
        snapshotHash: snapshotHash,
      );
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          ['deps', 'check'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(
        stdout,
        contains('  camera 0.11.0: override -> camera-0.11.0-ohos-3.35-1'),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'plans and writes tag-based overrides only for direct implemented packages',
    () async {
      final environment = await _preparedEnvironment();
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['deps', 'fix', '--dry-run'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(
        File(
          '${environment.workingDirectory.path}/pubspec.yaml',
        ).readAsStringSync(),
        isNot(contains('dependency_overrides')),
      );

      expect(
        await runFluoh(
          ['deps', 'fix'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final pubspec = File(
        '${environment.workingDirectory.path}/pubspec.yaml',
      ).readAsStringSync();
      expect(
        stdout,
        contains('Would override camera -> camera-0.11.0-ohos-3.35-1'),
      );
      expect(stdout, contains('override camera -> camera-0.11.0-ohos-3.35-1'));
      expect(stdout, contains('Updated pubspec.yaml with 1 dependency change'));
      expect(stdout, contains('Next: run `fluoh deps get`'));
      expect(pubspec, contains('dependency_overrides:'));
      expect(pubspec, contains('camera-0.11.0-ohos-3.35-1'));
      expect(pubspec, contains('path: packages/camera/camera'));
      expect(pubspec, isNot(contains('camera_platform_interface:')));
      expect(pubspec, isNot(contains('share_plus-9.0.0-ohos-3.35-1')));
      expect(stderr, isEmpty);
    },
  );

  test('deps fix emits json with change summaries', () async {
    final environment = await _preparedEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['deps', 'fix', '--dry-run', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    // --json mode outputs only JSON on stdout, no human-readable text.
    expect(stdout, hasLength(1));
    final dryRunReport = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(dryRunReport, containsPair('schemaVersion', 1));
    expect(dryRunReport, containsPair('command', 'deps fix'));
    expect(dryRunReport, containsPair('ok', false));
    expect(dryRunReport, containsPair('exitCode', 0));
    expect(dryRunReport, containsPair('applied', 0));
    expect(dryRunReport, containsPair('dryRun', true));
    final dryRunChanges = dryRunReport['changes'] as List<Object?>;
    expect(dryRunChanges, isNotEmpty);
    final cameraChange = dryRunChanges.first as Map<String, Object?>;
    expect(cameraChange, containsPair('packageName', 'camera'));
    expect(cameraChange, containsPair('kind', 'writeOverride'));
    expect(cameraChange, containsPair('nextRef', 'camera-0.11.0-ohos-3.35-1'));
    expect(
      File(
        '${environment.workingDirectory.path}/pubspec.yaml',
      ).readAsStringSync(),
      isNot(contains('dependency_overrides')),
    );

    stdout.clear();
    expect(
      await runFluoh(
        ['deps', 'fix', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, hasLength(1));
    final fixReport = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(fixReport, containsPair('schemaVersion', 1));
    expect(fixReport, containsPair('command', 'deps fix'));
    expect(fixReport, containsPair('ok', true));
    expect(fixReport, containsPair('exitCode', 0));
    expect(fixReport, containsPair('applied', 1));
    expect(fixReport, containsPair('dryRun', false));
    final fixChanges = fixReport['changes'] as List<Object?>;
    expect(fixChanges, hasLength(1));
    final appliedChange = fixChanges.first as Map<String, Object?>;
    expect(appliedChange, containsPair('packageName', 'camera'));
    expect(appliedChange, containsPair('nextRef', 'camera-0.11.0-ohos-3.35-1'));
    final pubspec = File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    ).readAsStringSync();
    expect(pubspec, contains('dependency_overrides:'));
    expect(pubspec, contains('camera-0.11.0-ohos-3.35-1'));
    expect(stderr, isEmpty);
  });

  test('prints package advisories from source manifests', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final manifest = File('${source.path}/manifests/share_plus/fluoh.yaml');
    await manifest.writeAsString(
      manifest.readAsStringSync().replaceFirst('    sdks:', '''
    advisory:
      message: Prefer upstream share_plus when native OHOS support is enough.
      alternatives:
        - name: share_plus_ohos
          reason: Provides native OHOS support.
          url: https://pub.dev/packages/share_plus_ohos
    sdks:'''),
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
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

    expect(
      await runFluoh(
        ['deps', 'check'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(stdout, contains('Advisories:'));
    expect(
      stdout,
      contains(
        '  share_plus: Prefer upstream share_plus when native OHOS support is enough.',
      ),
    );
    _expectOutputContains(
      stdout,
      'share_plus: consider share_plus_ohos - Provides native OHOS support. https://pub.dev/packages/share_plus_ohos',
    );

    expect(
      await runFluoh(
        ['deps', 'check', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    final jsonReport = jsonDecode(stdout.last) as Map<String, Object?>;
    final dependencies = jsonReport['dependencies'] as List<Object?>;
    expect(
      dependencies,
      contains(
        allOf(
          containsPair('name', 'share_plus'),
          containsPair(
            'advisory',
            containsPair(
              'message',
              'Prefer upstream share_plus when native OHOS support is enough.',
            ),
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('reports existing dependency override conflicts', () async {
    final environment = await _preparedEnvironment();
    final pubspecFile = File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    );
    await pubspecFile.writeAsString('''
${pubspecFile.readAsStringSync()}
dependency_overrides:
  camera:
    path: ../camera
''');
    final checkStdout = <String>[];
    final fixStdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['deps', 'check'],
        environment: environment,
        stdout: checkStdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      await runFluoh(
        ['deps', 'fix'],
        environment: environment,
        stdout: fixStdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final pubspec = pubspecFile.readAsStringSync();
    expect(checkStdout, contains('Needs manual action:'));
    expect(
      checkStdout,
      contains(
        '  camera 0.11.0: dependency_overrides already contains this package.',
      ),
    );
    _expectOutputContains(
      checkStdout,
      'Summary: 0 ready, 1 needs decision, 1 manual, 1 unavailable, 0 already OK, 1 transitive',
    );
    expect(
      fixStdout,
      contains(
        'Skipped camera: dependency_overrides already contains this package.',
      ),
    );
    expect(pubspec, contains('path: ../camera'));
    expect(pubspec, isNot(contains('camera-0.11.0-ohos-3.35-1')));
    expect(stderr, isEmpty);
  });

  test('rewrites direct dependencies from project policy', () async {
    final environment = await _preparedEnvironment();
    final pubspecFile = File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    );
    final configFile = File('${environment.workingDirectory.path}/fluoh.yaml');
    await configFile.writeAsString(
      configFile.readAsStringSync().replaceFirst(
        'pubspecSection: dependency_overrides',
        'pubspecSection: dependencies',
      ),
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['deps', 'fix'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final pubspec = pubspecFile.readAsStringSync();
    expect(pubspec, contains('dependencies:'));
    expect(pubspec, contains('  camera:'));
    expect(pubspec, contains('    git:'));
    expect(pubspec, contains('camera-0.11.0-ohos-3.35-1'));
    expect(pubspec, contains('path: packages/camera/camera'));
    expect(pubspec, isNot(contains('dependency_overrides:')));
    expect(stderr, isEmpty);
  });

  test(
    'allows incompatible implementation versions from project policy',
    () async {
      final environment = await _preparedEnvironment();
      final pubspecFile = File(
        '${environment.workingDirectory.path}/pubspec.yaml',
      );
      final configFile = File(
        '${environment.workingDirectory.path}/fluoh.yaml',
      );
      await configFile.writeAsString(
        configFile.readAsStringSync().replaceFirst(
          'versionChanges: compatible',
          'versionChanges: any',
        ),
      );
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['deps', 'fix'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final pubspec = pubspecFile.readAsStringSync();
      expect(
        stdout,
        contains(
          'override share_plus -> share_plus-9.0.0-ohos-3.35-1 '
          '(upstream 10.0.0 -> 9.0.0)',
        ),
      );
      expect(pubspec, contains('camera-0.11.0-ohos-3.35-1'));
      expect(pubspec, contains('share_plus-9.0.0-ohos-3.35-1'));
      expect(stderr, isEmpty);
    },
  );

  test(
    'uses compatible implementation upgrades without version mismatch opt-in',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      await _appendImplementationVersion(
        source,
        packageName: 'share_plus',
        upstreamVersion: '10.1.0',
        upstreamRef: 'share_plus-v10.1.0',
        implementationRef: 'share_plus-10.1.0-ohos-3.35-1',
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
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

      expect(
        await runFluoh(
          ['deps', 'check', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      final jsonReport =
          jsonDecode(stdout.removeLast()) as Map<String, Object?>;
      final dependencies = jsonReport['dependencies'] as List<Object?>;
      expect(
        dependencies,
        contains(
          allOf(
            containsPair('name', 'share_plus'),
            containsPair('status', 'version-upgrade'),
            containsPair('actionable', true),
            containsPair('implementationUpstreamVersion', '10.1.0'),
          ),
        ),
      );

      expect(
        await runFluoh(
          ['deps', 'fix', '--dry-run'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      _expectOutputContains(
        stdout,
        'Would override share_plus -> share_plus-10.1.0-ohos-3.35-1 '
        '(upstream 10.0.0 -> 10.1.0)',
      );
      expect(
        stdout.join('\n'),
        isNot(
          contains(
            'Skipped share_plus: OHOS implementation targets upstream 10.1.0',
          ),
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'keeps incompatible 0.x minor implementation upgrades behind opt-in',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      await _addRepositoryPackage(
        source,
        packageName: 'zero_implementation',
        repositoryUrl: '${environment.homeDirectory.path}/zero_implementation',
        upstreamUrl: 'https://example.com/zero_implementation',
        packagePath: 'packages/zero_implementation',
        upstreamVersion: '0.12.0',
        upstreamRef: 'zero_implementation-v0.12.0',
        implementationRef: 'zero_implementation-0.12.0-ohos-3.35-1',
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
      await pubspec.writeAsString(
        pubspec.readAsStringSync().replaceFirst('  mystery_package: ^1.0.0', '''
  zero_implementation: 0.11.0
  mystery_package: ^1.0.0'''),
      );
      final lock = File('${environment.workingDirectory.path}/pubspec.lock');
      await lock.writeAsString(
        lock.readAsStringSync().replaceFirst('sdks:', '''
  zero_implementation:
    dependency: "direct main"
    description:
      name: zero_implementation
    source: hosted
    version: "0.11.0"
sdks:'''),
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
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

      expect(
        await runFluoh(
          ['deps', 'check', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      final jsonReport =
          jsonDecode(stdout.removeLast()) as Map<String, Object?>;
      final dependencies = jsonReport['dependencies'] as List<Object?>;
      expect(
        dependencies,
        contains(
          allOf(
            containsPair('name', 'zero_implementation'),
            containsPair('status', 'incompatible-version'),
            containsPair('actionable', false),
            containsPair('implementationUpstreamVersion', '0.12.0'),
          ),
        ),
      );

      expect(
        await runFluoh(
          ['deps', 'fix', '--dry-run'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(
        stdout.join('\n'),
        contains(
          'Skipped zero_implementation: OHOS implementation targets upstream 0.12.0',
        ),
      );
      expect(
        stdout.join('\n'),
        isNot(contains('Would override zero_implementation')),
      );
      expect(stderr, isEmpty);
    },
  );

  test('reports malformed dependency policy', () async {
    final environment = await _preparedEnvironment();
    final configFile = File('${environment.workingDirectory.path}/fluoh.yaml');
    await configFile.writeAsString('''
schema: 1
sdk:
  version: 3.35.8-ohos-0.0.3
dependencyPolicy: true
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['deps', 'check'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stdout, isEmpty);
    expect(
      stderr.join('\n'),
      contains('dependencyPolicy in fluoh.yaml must be a YAML map.'),
    );
  });

  test(
    'selects implementation version 10 over version 9 numerically',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final manifest = File('${source.path}/manifests/camera/fluoh.yaml');
      await manifest.writeAsString(
        manifest
            .readAsStringSync()
            .replaceAll('version: "0"', 'version: "9"')
            .replaceAll('version: "1"', 'version: "10"'),
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'fixture', source.path],
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

      expect(
        await runFluoh(
          ['deps', 'check'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(
        stdout,
        contains('  camera 0.11.0: override -> camera-0.11.0-ohos-3.35-10'),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'stops when equal-priority sources disagree on an OHOS implementation',
    () async {
      final environment = await createTestEnvironment();
      final firstSource = await createPackageSourceFixture(
        Directory('${environment.homeDirectory.path}/first'),
      );
      final secondSource = await createPackageSourceFixture(
        Directory('${environment.homeDirectory.path}/second'),
      );
      await _copySdkMetadata(from: firstSource, to: secondSource);
      final manifest = File('${secondSource.path}/manifests/camera/fluoh.yaml');
      await manifest.writeAsString(
        manifest.readAsStringSync().replaceAll(
          '${environment.homeDirectory.path}/second/camera',
          '${environment.homeDirectory.path}/different',
        ),
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'first', firstSource.path, '--priority', '100'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      expect(
        await runFluoh(
          ['source', 'add', 'second', secondSource.path, '--priority', '100'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(
        await runFluoh(
          ['sdk', 'use', '3.35.8-ohos-0.0.3'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          ['deps', 'check'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );
      expect(stderr.join('\n'), contains('Conflicting OHOS implementation'));
    },
  );

  test('does not select broken implementation releases', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    await _setImplementationStatus(
      source,
      packageName: 'camera',
      status: 'broken',
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
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

    expect(
      await runFluoh(
        ['deps', 'check'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      stdout,
      contains('  camera 0.11.0: No known OHOS implementation is available.'),
    );
    expect(stdout.join('\n'), isNot(contains('camera-v0.11.0-ohos')));
    expect(stderr, isEmpty);
  });

  test(
    'layers package metadata supplemental sources over the official source',
    () async {
      final environment = await createTestEnvironment();
      final official = await createPackageSourceFixture(
        Directory('${environment.homeDirectory.path}/official'),
      );
      final supplemental = Directory('${environment.homeDirectory.path}/team');
      await _writePackageOnlySource(
        supplemental,
        packageName: 'share_plus',
        repositoryUrl: '${environment.homeDirectory.path}/share_plus',
        upstreamUrl: 'https://github.com/fluttercommunity/plus_plugins',
        packagePath: 'packages/share_plus/share_plus',
        upstreamVersion: '10.0.0',
        upstreamRef: 'share_plus-v10.0.0',
        implementationRef: 'share_plus-10.0.0-ohos-3.35-1',
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'official', official.path, '--priority', '10'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        ['source', 'add', 'team', supplemental.path, '--priority', '200'],
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

      expect(
        await runFluoh(
          ['deps', 'check'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(
        stdout,
        contains('  camera 0.11.0: override -> camera-0.11.0-ohos-3.35-1'),
      );
      expect(
        stdout,
        contains(
          '  share_plus 10.0.0: override -> share_plus-10.0.0-ohos-3.35-1',
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'ignores invalid git source snapshots when another source is readable',
    () async {
      final environment = await createTestEnvironment();
      final validSource = await createPackageSourceFixture(
        Directory('${environment.homeDirectory.path}/valid'),
      );
      final brokenCache = Directory(
        '${environment.homeDirectory.path}/sources/broken',
      );
      await brokenCache.create(recursive: true);
      await File('${brokenCache.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: source
name: Broken source
description: Broken source.

repository:
  git:
    url: file:${brokenCache.path}

manifests:
  - name: missing
''');
      await File('${environment.homeDirectory.path}/config.json').writeAsString(
        jsonEncode({
          'sources': {
            'valid': {'path': validSource.path, 'priority': 10},
            'broken': {
              'path': brokenCache.path,
              'url': 'file://${environment.homeDirectory.path}/missing-source',
              'priority': 200,
            },
          },
        }),
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          ['sdk', 'use', '3.35.8-ohos-0.0.3'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(
        await runFluoh(
          ['deps', 'check'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      expect(
        stdout,
        contains('  camera 0.11.0: override -> camera-0.11.0-ohos-3.35-1'),
      );
      expect(stderr, isEmpty);
    },
  );

  test('restores pubspec.yaml when dependency rewrite fails', () async {
    final environment = await _preparedEnvironment();
    final pubspecFile = File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    );

    // Remove the dependencies section so the rewrite target cannot be found.
    await pubspecFile.writeAsString(
      pubspecFile.readAsStringSync().replaceFirst('dependencies:\n', ''),
    );
    final modifiedContent = pubspecFile.readAsStringSync();
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['deps', 'fix'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    // The file should be restored to the state before the failed fix attempt.
    final content = pubspecFile.readAsStringSync();
    expect(content, equals(modifiedContent));
    expect(content, isNot(contains('dependency_overrides')));
    expect(content, isNot(contains('camera-0.11.0-ohos-3.35-1')));
  });

  test(
    'preserves implementation repository URLs when reading the lock',
    () async {
      final environment = await createTestEnvironment();
      final official = await createPackageSourceFixture(
        Directory('${environment.homeDirectory.path}/official'),
      );
      final team = Directory('${environment.homeDirectory.path}/team');
      final teamRepository = '${environment.homeDirectory.path}/team_camera';
      await _writePackageOnlySource(
        team,
        packageName: 'camera',
        repositoryUrl: teamRepository,
        upstreamUrl: 'https://github.com/flutter/packages',
        packagePath: 'packages/camera/camera',
        upstreamVersion: '0.12.0',
        upstreamRef: 'camera-v0.12.0',
        implementationRef: 'camera-0.12.0-ohos-3.35-1',
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      final pubspecFile = File(
        '${environment.workingDirectory.path}/pubspec.yaml',
      );
      await pubspecFile.writeAsString(
        pubspecFile.readAsStringSync().replaceFirst(
          '  camera: 0.11.0',
          '  camera: 0.12.0',
        ),
      );
      final lockFile = File(
        '${environment.workingDirectory.path}/pubspec.lock',
      );
      await lockFile.writeAsString(
        lockFile.readAsStringSync().replaceFirst(
          'version: "0.11.0"',
          'version: "0.12.0"',
        ),
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'add', 'official', official.path, '--priority', '200'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        ['source', 'add', 'team', team.path, '--priority', '10'],
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
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          ['deps', 'fix'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final pubspec = pubspecFile.readAsStringSync();
      expect(pubspec, contains('url: $teamRepository'));
      expect(pubspec, contains('ref: camera-0.12.0-ohos-3.35-1'));
      expect(
        pubspec,
        isNot(
          contains('url: ${environment.homeDirectory.path}/official/camera'),
        ),
      );
      expect(stderr, isEmpty);
    },
  );
}

Future<FluohEnvironment> _preparedEnvironment() async {
  final environment = await createTestEnvironment();
  final source = await createPackageSourceFixture(environment.homeDirectory);
  await writeFlutterProjectFixture(environment.workingDirectory);
  final stdout = <String>[];
  final stderr = <String>[];

  await runFluoh(
    ['source', 'add', 'fixture', source.path],
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
        ? 'camera-0.11.0-ohos-3.35-1'
        : '$packageName-v1.0.0-ohos-3.35.8-1',
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
    content.replaceFirst(
      '        releases:\n',
      '        releases:\n'
          '          - version: $releaseVersion\n'
          '            upstreamVersion: $upstreamVersion\n',
    ),
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
  await root.writeAsString(
    root.readAsStringSync().replaceFirst(
      '\nmanifests:\n',
      '\nmanifests:\n  - name: $packageName\n',
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
name: Team source
description: Team source.

repository:
  git:
    url: file:${source.path}

environment:
  fluoh: ">=0.1.0"

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
      '1';
  await File('${repository.path}/fluoh.yaml').writeAsString('''
schema: 1
kind: manifest
name: $repositoryName

repository:
  git:
    url: $repositoryUrl

upstream:
  git:
    url: $upstreamUrl

packages:
  $packageName:
    repository:
      path: $packagePath
    upstream:
      path: $packagePath
    sdks:
      "3.35":
        releases:
          - version: $releaseVersion
            upstreamVersion: $upstreamVersion
${status == 'compatible' ? '' : '            status: $status\n'}
''');
}
