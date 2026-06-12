part of 'dependency_plan_commands_test.dart';

void _registerDependencyPlanCommandCoreTests() {
  test('reports missing project files before SDK selection', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['deps', 'check', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    expect(stdout, hasLength(1));
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'deps check'));
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 64));
    expect(
      report['error'],
      containsPair('message', 'Missing pubspec.yaml in the current project.'),
    );
    expect(stderr, isEmpty);
  });

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
      contains('  camera 0.11.0: override -> camera-0.11.0-ohos-3.35-1.0.0'),
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
    expect(jsonReport, containsPair('schema', 1));
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
      final fixturePackages = packageRoutes['fixture'] as Map<String, Object?>;
      expect(fixturePackages, containsPair('camera', ['3.35']));
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
        contains('  camera 0.11.0: override -> camera-0.11.0-ohos-3.35-1.0.0'),
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
        contains('Would override camera -> camera-0.11.0-ohos-3.35-1.0.0'),
      );
      expect(
        stdout,
        contains('override camera -> camera-0.11.0-ohos-3.35-1.0.0'),
      );
      expect(stdout, contains('Updated pubspec.yaml with 1 dependency change'));
      expect(stdout, contains('Next: run `fluoh deps get`'));
      expect(pubspec, contains('dependency_overrides:'));
      expect(pubspec, contains('camera-0.11.0-ohos-3.35-1.0.0'));
      expect(pubspec, contains('path: packages/camera/camera'));
      expect(pubspec, isNot(contains('camera_platform_interface:')));
      expect(pubspec, isNot(contains('share_plus-9.0.0-ohos-3.35-1.0.0')));
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
    expect(dryRunReport, containsPair('schema', 1));
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
    expect(
      cameraChange,
      containsPair('nextRef', 'camera-0.11.0-ohos-3.35-1.0.0'),
    );
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
    expect(fixReport, containsPair('schema', 1));
    expect(fixReport, containsPair('command', 'deps fix'));
    expect(fixReport, containsPair('ok', true));
    expect(fixReport, containsPair('exitCode', 0));
    expect(fixReport, containsPair('applied', 1));
    expect(fixReport, containsPair('dryRun', false));
    final fixChanges = fixReport['changes'] as List<Object?>;
    expect(fixChanges, hasLength(1));
    final appliedChange = fixChanges.first as Map<String, Object?>;
    expect(appliedChange, containsPair('packageName', 'camera'));
    expect(
      appliedChange,
      containsPair('nextRef', 'camera-0.11.0-ohos-3.35-1.0.0'),
    );
    final pubspec = File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    ).readAsStringSync();
    expect(pubspec, contains('dependency_overrides:'));
    expect(pubspec, contains('camera-0.11.0-ohos-3.35-1.0.0'));
    expect(stderr, isEmpty);
  });

  test('prints package advisories from source manifests', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    final manifest = File('${source.path}/manifests/share_plus/fluoh.yaml');
    await manifest.writeAsString(
      manifest.readAsStringSync().replaceFirst('  sdks:', '''
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
    expect(pubspec, isNot(contains('camera-0.11.0-ohos-3.35-1.0.0')));
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
    expect(pubspec, contains('camera-0.11.0-ohos-3.35-1.0.0'));
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
          'override share_plus -> share_plus-9.0.0-ohos-3.35-1.0.0 '
          '(upstream 10.0.0 -> 9.0.0)',
        ),
      );
      expect(pubspec, contains('camera-0.11.0-ohos-3.35-1.0.0'));
      expect(pubspec, contains('share_plus-9.0.0-ohos-3.35-1.0.0'));
      expect(stderr, isEmpty);
    },
  );

  test(
    'uses non-compatible implementation statuses only with command opt-in',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      await _setImplementationStatus(
        source,
        packageName: 'camera',
        status: 'experimental',
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
      final defaultJson =
          jsonDecode(stdout.removeLast()) as Map<String, Object?>;
      final defaultDependencies = defaultJson['dependencies'] as List<Object?>;
      expect(
        defaultDependencies,
        contains(
          allOf(
            containsPair('name', 'camera'),
            containsPair('status', 'unknown'),
            containsPair('actionable', false),
            isNot(containsPair('implementationStatus', 'experimental')),
          ),
        ),
      );

      expect(
        await runFluoh(
          ['deps', 'check', '--all-release-statuses', '--json'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      final allStatusesJson =
          jsonDecode(stdout.removeLast()) as Map<String, Object?>;
      final allStatusesDependencies =
          allStatusesJson['dependencies'] as List<Object?>;
      expect(
        allStatusesJson,
        containsPair('releaseStatuses', [
          'compatible',
          'experimental',
          'broken',
        ]),
      );
      expect(
        allStatusesDependencies,
        contains(
          allOf(
            containsPair('name', 'camera'),
            containsPair('status', 'implemented'),
            containsPair('actionable', true),
            containsPair('implementationStatus', 'experimental'),
          ),
        ),
      );
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
        implementationRef: 'share_plus-10.1.0-ohos-3.35-1.0.0',
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
        'Would override share_plus -> share_plus-10.1.0-ohos-3.35-1.0.0 '
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
        implementationRef: 'zero_implementation-0.12.0-ohos-3.35-1.0.0',
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
}
