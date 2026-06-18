part of 'dependency_plan_commands_test.dart';

void _registerDependencyPlanCommandPolicyTests() {
  test('reports malformed dependency policy', () async {
    final environment = await _preparedEnvironment();
    final configFile = File('${environment.workingDirectory.path}/fluoh.yaml');
    await configFile.writeAsString('''
schema: 1
kind: project
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
            .replaceAll('version: "0.0.0"', 'version: "9.0.0"')
            .replaceAll(
              'tag: camera-0.11.0-ohos-3.35-0.0.0',
              'tag: camera-0.11.0-ohos-3.35-9.0.0',
            )
            .replaceAll('version: "1.0.0"', 'version: "10.0.0"')
            .replaceAll(
              'tag: camera-0.11.0-ohos-3.35-1.0.0',
              'tag: camera-0.11.0-ohos-3.35-10.0.0',
            ),
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
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
        contains('  camera 0.11.0: override -> camera-0.11.0-ohos-3.35-10.0.0'),
      );
      expect(stderr, isEmpty);
    },
  );

  test(
    'stops when equal-priority sources disagree on a FlutterOH implementation',
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
        ['source', 'enable', 'first', firstSource.path, '--priority', '100'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      expect(
        await runFluoh(
          [
            'source',
            'enable',
            'second',
            secondSource.path,
            '--priority',
            '100',
          ],
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
      expect(
        stderr.join('\n'),
        contains('Conflicting FlutterOH implementation'),
      );
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
      ['source', 'enable', 'fixture', source.path],
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
      contains(
        '  camera 0.11.0: No known FlutterOH implementation is available.',
      ),
    );
    expect(stdout.join('\n'), isNot(contains('camera-v0.11.0-ohos')));

    expect(
      await runFluoh(
        ['deps', 'check', '--all-release-statuses', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    final brokenJson = jsonDecode(stdout.removeLast()) as Map<String, Object?>;
    expect(
      brokenJson,
      containsPair('releaseStatuses', ['compatible', 'experimental', 'broken']),
    );
    expect(
      brokenJson['dependencies'] as List<Object?>,
      contains(
        allOf(
          containsPair('name', 'camera'),
          containsPair('status', 'implemented'),
          containsPair('implementationStatus', 'broken'),
        ),
      ),
    );
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
        implementationRef: 'share_plus-10.0.0-ohos-3.35-1.0.0',
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'official', official.path, '--priority', '10'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        ['source', 'enable', 'team', supplemental.path, '--priority', '200'],
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
        contains('  camera 0.11.0: override -> camera-0.11.0-ohos-3.35-1.0.0'),
      );
      expect(
        stdout,
        contains(
          '  share_plus 10.0.0: override -> share_plus-10.0.0-ohos-3.35-1.0.0',
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
        contains('  camera 0.11.0: override -> camera-0.11.0-ohos-3.35-1.0.0'),
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
    expect(content, isNot(contains('camera-0.11.0-ohos-3.35-1.0.0')));
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
        implementationRef: 'camera-0.12.0-ohos-3.35-1.0.0',
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
        ['source', 'enable', 'official', official.path, '--priority', '200'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      await runFluoh(
        ['source', 'enable', 'team', team.path, '--priority', '10'],
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
      expect(pubspec, contains('ref: camera-0.12.0-ohos-3.35-1.0.0'));
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
